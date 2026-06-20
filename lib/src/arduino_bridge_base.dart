//
// Author: mowittler
// Date: 2026-06-19
// License: MIT

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:message_pack_dart/message_pack_dart.dart';

/// A client for communicating with an Arduino router over a Unix domain socket
/// using the MessagePack-RPC protocol.
///
/// Connect to the router, then use [call] for request/response interactions,
/// [notify] for fire-and-forget messages, [provide] to expose a Dart function
/// that the router can invoke, or [register] to declare a method name without
/// attaching a handler.
class ArduinoBridge {
  /// The file-system path of the Unix domain socket to connect to.
  final String socketPath;

  Socket? _socket;
  int _msgCounter = 0;
  final Map<int, Completer<dynamic>> _pendingResponses = {};
  final List<int> _buffer = [];
  final Map<String, Function> _handlers = {};

  /// Creates an [ArduinoBridge] that connects to [socketPath].
  ///
  /// [socketPath] defaults to `/var/run/arduino-router.sock`.
  ArduinoBridge({this.socketPath = '/var/run/arduino-router.sock'});

  /// Opens the Unix socket connection and starts listening for incoming data.
  ///
  /// Returns `true` on success, or `false` if the connection attempt fails
  /// (e.g. the router is not running or the socket path does not exist).
  Future<bool> connect() async {
    try {
      _socket = await Socket.connect(
        InternetAddress(socketPath, type: InternetAddressType.unix),
        0,
      );
      _socket!.listen(
        _onData,
        onError: _onError,
        onDone: _onDone,
        cancelOnError: false,
      );
      return true;
    } catch (e) {
      print('Connection failed: $e');
      return false;
    }
  }

  /// Sends a MessagePack-RPC *request* and waits for the matching response.
  ///
  /// [method] is the RPC method name; [args] are its positional arguments.
  /// [timeout] controls how long to wait before throwing a [TimeoutException].
  ///
  /// Throws a [StateError] if not connected, a [TimeoutException] if the
  /// router does not reply within [timeout], or an [Exception] if the router
  /// returns an error payload.
  Future<dynamic> call(
    String method,
    List<dynamic> args, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (_socket == null) throw StateError('Not connected');

    _msgCounter++;
    final msgid = _msgCounter;

    final completer = Completer<dynamic>();
    _pendingResponses[msgid] = completer;

    _socket!.add(serialize([0, msgid, method, args]));

    try {
      return await completer.future.timeout(timeout);
    } on TimeoutException {
      _pendingResponses.remove(msgid);
      throw TimeoutException('Timeout waiting for $method', timeout);
    }
  }

  /// Sends a MessagePack-RPC *notification* — a one-way message with no reply.
  ///
  /// [method] is the RPC method name; [args] are its positional arguments.
  ///
  /// Throws a [StateError] if not connected.
  void notify(String method, List<dynamic> args) {
    if (_socket == null) throw StateError('Not connected');
    _socket!.add(serialize([2, method, args]));
  }

  /// Registers [methodName] with the router so it can dispatch calls to this
  /// client.
  ///
  /// This is a low-level wrapper around [call] using the built-in
  /// `$/register` method. Prefer [provide] when you also want incoming
  /// requests for [methodName] to be dispatched to a Dart handler.
  Future<void> register(String methodName) => call('\$/register', [methodName]);

  /// Sends a `$/reset` request to the router, instructing it to reset its
  /// state for this connection.
  Future<void> reset() => call('\$/reset', []);

  /// Registers [handler] under [method] so that incoming requests from the
  /// router for that method name are dispatched to [handler].
  ///
  /// Also calls [register] to inform the router that this client handles
  /// [method]. The handler may be synchronous or return a [Future].
  Future<void> provide(String method, Function handler) async {
    _handlers[method] = handler;
    await register(method);
  }

  /// Closes the socket connection and rejects all pending [call] futures with
  /// a [StateError].
  Future<void> disconnect() async {
    _failPending(StateError('Disconnected'));
    await _socket?.close();
    _socket = null;
  }

  // Appends incoming socket bytes to the buffer and attempts to deserialize a
  // complete MessagePack frame. Leaves partial data in the buffer until the
  // next chunk arrives.
  void _onData(List<int> data) {
    _buffer.addAll(data);
    try {
      _handleMessage(deserialize(Uint8List.fromList(_buffer)));
      _buffer.clear();
    } catch (_) {
      // incomplete frame, wait for more data
    }
  }

  // Dispatches an incoming MessagePack-RPC message by type:
  // type 0 (request) → invokes a registered handler and sends a response;
  // type 1 (response) → resolves or rejects the matching [Completer].
  void _handleMessage(dynamic msg) {
    if (msg is! List || msg.length < 3 || msg[0] is! int) return;

    final type = msg[0] as int;

    if (type == 0 && msg.length >= 4) {
      final msgid = msg[1] as int;
      final method = msg[2] as String;
      final args = msg[3] is List
          ? List<dynamic>.from(msg[3] as List)
          : <dynamic>[];
      _dispatchRequest(msgid, method, args);
    } else if (type == 1 && msg.length >= 4) {
      final msgid = msg[1] as int;
      final error = msg[2];
      final result = msg[3];

      final completer = _pendingResponses.remove(msgid);
      if (completer == null || completer.isCompleted) return;

      if (error != null) {
        completer.completeError(Exception(error));
      } else {
        completer.complete(result);
      }
    }
  }

  // Looks up [method] in [_handlers], invokes it with [args], and sends a
  // type-1 response back to the router. Handles both sync and async handlers.
  Future<void> _dispatchRequest(
    int msgid,
    String method,
    List<dynamic> args,
  ) async {
    final handler = _handlers[method];
    if (handler == null) {
      _socket?.add(serialize([1, msgid, 'method not found: $method', null]));
      return;
    }
    try {
      final result = await Function.apply(handler, args);
      _socket?.add(serialize([1, msgid, null, result]));
    } catch (e) {
      _socket?.add(serialize([1, msgid, e.toString(), null]));
    }
  }

  // Handles a socket-level error by logging it, failing all pending requests,
  // and clearing the socket reference.
  void _onError(Object error) {
    print('Socket error: $error');
    _failPending(StateError('Socket error: $error'));
    _socket = null;
  }

  // Called when the remote end closes the connection; fails pending requests
  // and clears the socket reference.
  void _onDone() {
    _failPending(StateError('Connection closed'));
    _socket = null;
  }

  // Rejects every outstanding [Completer] in [_pendingResponses] with [error]
  // and empties the map.
  void _failPending(Object error) {
    for (final completer in _pendingResponses.values) {
      if (!completer.isCompleted) completer.completeError(error);
    }
    _pendingResponses.clear();
  }
}
