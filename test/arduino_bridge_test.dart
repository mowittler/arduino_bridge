//
// Author: mowittler
// Date: 2026-06-19
// License: MIT

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:arduino_bridge/arduino_bridge.dart';
import 'package:message_pack_dart/message_pack_dart.dart';
import 'package:test/test.dart';

// A minimal fake router that speaks MessagePack-RPC over a Unix domain socket.
// It binds a real server socket so the full serialization path is exercised.
class FakeRouter {
  final ServerSocket _server;
  Socket? _client;
  final _buffer = <int>[];

  // Called with every complete MessagePack frame received from the client.
  void Function(List<dynamic>)? onMessage;

  FakeRouter._(this._server);

  static Future<FakeRouter> start(String path) async {
    final server = await ServerSocket.bind(
      InternetAddress(path, type: InternetAddressType.unix),
      0,
    );
    final router = FakeRouter._(server);
    server.listen(router._acceptClient);
    return router;
  }

  String get path => _server.address.address;

  void _acceptClient(Socket client) {
    _client = client;
    client.listen((data) {
      _buffer.addAll(data);
      try {
        final msg = deserialize(Uint8List.fromList(_buffer)) as List;
        _buffer.clear();
        onMessage?.call(msg);
      } catch (_) {}
    });
  }

  // Sends a type-1 (response) frame back to the connected client.
  void reply(int msgid, {dynamic error, dynamic result}) {
    _client?.add(serialize([1, msgid, error, result]));
  }

  // Sends a type-0 (request) frame to the connected client.
  void request(int msgid, String method, List<dynamic> args) {
    _client?.add(serialize([0, msgid, method, args]));
  }

  // Closes only the accepted client socket, leaving the server socket open.
  Future<void> closeClient() => _client?.close() ?? Future.value();

  Future<void> close() async {
    await _client?.close();
    await _server.close();
    try {
      File(path).deleteSync();
    } catch (_) {}
  }
}

// Each test gets a unique path so concurrent runs don't collide.
String _tempSocketPath() {
  final id = DateTime.now().microsecondsSinceEpoch;
  return '/tmp/ab_$id.sock';
}

void main() {
  group('ArduinoBridge', () {
    late FakeRouter router;
    late ArduinoBridge bridge;

    // Start a fresh router and bridge before every test.
    setUp(() async {
      router = await FakeRouter.start(_tempSocketPath());
      bridge = ArduinoBridge(socketPath: router.path);
    });

    // Always disconnect and tear down the router, even if the test fails.
    tearDown(() async {
      await bridge.disconnect();
      await router.close();
    });

    // -- connect ----------------------------------------------

    test('connect() returns true when router is available', () async {
      expect(await bridge.connect(), isTrue);
    });

    // No server is listening at this path, so the OS returns an error.
    test('connect() returns false when no router is listening', () async {
      final absent = ArduinoBridge(socketPath: '/tmp/no_such_socket.sock');
      expect(await absent.connect(), isFalse);
    });

    // -- call ------------------------------------------------------

    test('call() sends a type-0 request and returns the result', () async {
      await bridge.connect();

      router.onMessage = (msg) {
        // MessagePack-RPC request format: [type, msgid, method, args]
        expect(msg[0], 0); // type = request
        expect(msg[2], 'led/set');
        expect(msg[3], [1, true]);
        router.reply(msg[1] as int, result: 'ok');
      };

      expect(await bridge.call('led/set', [1, true]), 'ok');
    });

    test(
      'call() throws Exception when router returns an error payload',
      () async {
        await bridge.connect();

        // Reply with a non-null error field to simulate a router-side failure.
        router.onMessage = (msg) =>
            router.reply(msg[1] as int, error: 'bad input');

        await expectLater(
          bridge.call('led/set', []),
          throwsA(isA<Exception>()),
        );
      },
    );

    test('call() throws TimeoutException when no response arrives', () async {
      await bridge.connect();
      // router.onMessage left null — no reply will be sent

      await expectLater(
        bridge.call('slow', [], timeout: const Duration(milliseconds: 100)),
        throwsA(isA<TimeoutException>()),
      );
    });

    // Calling before connect() must fail without touching the socket.
    test('call() throws StateError when not connected', () async {
      await expectLater(bridge.call('any', []), throwsA(isA<StateError>()));
    });

    // Each request must carry a strictly increasing msgid so responses
    // can be matched back to the correct completer.
    test('call() increments msgid across multiple requests', () async {
      await bridge.connect();

      final ids = <int>[];
      router.onMessage = (msg) {
        ids.add(msg[1] as int);
        router.reply(msg[1] as int, result: null);
      };

      await bridge.call('a', []);
      await bridge.call('b', []);

      expect(ids.length, 2);
      expect(ids[1], greaterThan(ids[0]));
    });

    // -- notify ----------------------------------------------------

    test('notify() sends a type-2 notification frame', () async {
      await bridge.connect();

      // Use a Completer so we can await the async socket delivery.
      final received = Completer<List<dynamic>>();
      router.onMessage = received.complete;

      bridge.notify('event/ping', ['hello']);

      final msg = await received.future.timeout(const Duration(seconds: 2));
      // MessagePack-RPC notification format: [type, method, args]
      expect(msg[0], 2); // type = notification
      expect(msg[1], 'event/ping');
      expect(msg[2], ['hello']);
    });

    // notify() is synchronous — StateError must be thrown, not returned.
    test('notify() throws StateError when not connected', () {
      expect(() => bridge.notify('x', []), throwsA(isA<StateError>()));
    });

    // -- register --------------------------------------------------

    // register() is a thin wrapper; verify it uses the correct built-in name.
    test('register() sends \$/register with the method name', () async {
      await bridge.connect();

      router.onMessage = (msg) {
        expect(msg[2], '\$/register');
        expect(msg[3], ['my/method']);
        router.reply(msg[1] as int, result: null);
      };

      await bridge.register('my/method'); // must not throw
    });

    // -- reset -----------------------------------------------------

    // reset() is a thin wrapper — verify it uses the correct built-in name.
    test('reset() sends \$/reset with empty args', () async {
      await bridge.connect();

      router.onMessage = (msg) {
        expect(msg[2], '\$/reset');
        expect(msg[3], isEmpty);
        router.reply(msg[1] as int, result: null);
      };

      await bridge.reset(); // must not throw
    });

    // -- provide ---------------------------------------------------

    test('provide() sends \$/register for the method name', () async {
      await bridge.connect();

      String? registeredName;
      router.onMessage = (msg) {
        registeredName = msg[3][0] as String;
        router.reply(msg[1] as int, result: null);
      };

      await bridge.provide('sensor/read', (_) => 42);

      expect(registeredName, 'sensor/read');
    });

    test(
      'provide() dispatches incoming request to handler and sends response',
      () async {
        await bridge.connect();

        // Reply to the $/register call that provide() triggers internally.
        router.onMessage = (msg) => router.reply(msg[1] as int, result: null);
        await bridge.provide('greet', (String name) => 'hello $name');

        // Capture the bridge's reply to our incoming request.
        final replyReceived = Completer<List<dynamic>>();
        router.onMessage = replyReceived.complete;

        router.request(42, 'greet', ['world']);

        final response = await replyReceived.future.timeout(
          const Duration(seconds: 2),
        );
        expect(response[0], 1); // type = response
        expect(response[1], 42); // msgid echoed back
        expect(response[2], isNull); // no error
        expect(response[3], 'hello world'); // handler return value
      },
    );

    test('provide() sends error response when handler throws', () async {
      await bridge.connect();

      router.onMessage = (msg) => router.reply(msg[1] as int, result: null);
      await bridge.provide('boom', (_) => throw Exception('oops'));

      final replyReceived = Completer<List<dynamic>>();
      router.onMessage = replyReceived.complete;

      router.request(7, 'boom', []);

      final response = await replyReceived.future.timeout(
        const Duration(seconds: 2),
      );
      expect(response[0], 1); // type = response
      expect(response[1], 7); // msgid echoed back
      expect(response[2], isNotNull); // error payload present
      expect(response[3], isNull); // no result
    });

    test(
      'provide() sends error response when method is not registered',
      () async {
        await bridge.connect();

        final replyReceived = Completer<List<dynamic>>();
        router.onMessage = replyReceived.complete;

        // Send a request for a method that was never provided.
        router.request(99, 'unknown/method', []);

        final response = await replyReceived.future.timeout(
          const Duration(seconds: 2),
        );
        expect(response[0], 1); // type = response
        expect(response[1], 99); // msgid echoed back
        expect(response[2], isNotNull); // error: method not found
        expect(response[3], isNull); // no result
      },
    );

    // -- disconnect -------------------------------------------------

    test('disconnect() rejects pending call() with StateError', () async {
      await bridge.connect();

      final callFuture = bridge.call(
        'slow',
        [],
        timeout: const Duration(seconds: 10),
      );

      // Register the listener before disconnecting — _failPending completes
      // the completer synchronously, so the error lands on callFuture before
      // expectLater is reached if we await disconnect() first.
      final expectation = expectLater(callFuture, throwsA(isA<StateError>()));
      await bridge.disconnect();
      await expectation;
    });

    // -- server-side close ------------------------------------------

    // Simulates the router process dying while a request is in flight.
    test(
      'pending call() throws StateError when the server closes the connection',
      () async {
        await bridge.connect();

        final callFuture = bridge.call(
          'slow',
          [],
          timeout: const Duration(seconds: 10),
        );

        // Close the server-side socket; client detects EOF via _onDone.
        await router.closeClient();

        await expectLater(callFuture, throwsA(isA<StateError>()));
      },
    );
  });
}
