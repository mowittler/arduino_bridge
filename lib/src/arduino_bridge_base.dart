import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:message_pack_dart/message_pack_dart.dart';

/// A client for communicating with an Arduino router over a Unix domain socket
/// using the MessagePack-RPC protocol.
///
/// Connect to the router, then use [call] for request/response interactions,
/// [notify] for fire-and-forget messages, and [register] to expose a method
/// name that this client can handle.
class ArduinoBridge {
  /// The file-system path of the Unix domain socket to connect to.
  final String socketPath;

  Socket? _socket;
  int _msgCounter = 0;
  final Map<int, Completer<dynamic>> _pendingResponses = {};
  final List<int> _buffer = [];

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
  /// This is a convenience wrapper around [call] using the built-in
  /// `$/register` method.
  Future<void> register(String methodName) => call('\$/register', [methodName]);

  /// Sends a `$/reset` request to the router, instructing it to reset its
  /// state for this connection.
  Future<void> reset() => call('\$/reset', []);

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
      _handleResponse(deserialize(Uint8List.fromList(_buffer)));
      _buffer.clear();
    } catch (_) {
      // incomplete frame, wait for more data
    }
  }

  // Validates a MessagePack-RPC type-1 (response) message and resolves or
  // rejects the matching [Completer] in [_pendingResponses].
  void _handleResponse(dynamic msg) {
    if (msg is! List || msg.length < 4 || msg[0] != 1) return;

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
