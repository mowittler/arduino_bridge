# arduino_bridge
**Flutter gets physical**

A Dart/Flutter package for communicating with the [Arduino Router](https://github.com/arduino/arduino-router) using the 
[MessagePack-RPC](https://github.com/msgpack-rpc/msgpack-rpc) protocol. 
It is designed to run on Linux only and targets the **Arduino Uno Q** and 
the **Ventuno Q**.

---

## How it works

The Arduino router daemon listens on a Unix domain socket and acts as a
broker between the host application and the MCU. This package connects to
that socket and communicates using MessagePack-RPC — a compact binary RPC
protocol built on top of
[MessagePack](https://msgpack.org/) serialization.

Three message types are used:

| Type | Direction | Description |
|------|-----------|-------------|
| Request (0) | host → router | Call a method and wait for a response |
| Response (1) | router → host | Result or error for a previous request |
| Notification (2) | host → router | Fire-and-forget message, no response |

---

## Requirements

- [Arduino Uno Q](https://www.arduino.cc/product-uno-q/) or [Ventuno Q](https://www.arduino.cc/product-ventuno-q/) with the Arduino router daemon running

---

## Flutter compatibility

This package is compatible with **Flutter for Linux desktop** only. No additional
setup is needed beyond targeting the Linux platform in your Flutter project.

---

## Installation

```yaml
dependencies:
  arduino_bridge: ^0.9.0
```

```sh
dart pub get
```

---

## Usage

### Connecting

```dart
final bridge = ArduinoBridge();
final connected = await bridge.connect();
```

`connect()` returns `true` on success and `false` if the router is not
reachable.

### Calling a method

`call()` sends a request and waits for the router to reply:

```dart
final result = await bridge.call('sensor/read', [0]);
```

The default timeout is 5 seconds. 

A `TimeoutException` is thrown if no response arrives in time. An
`Exception` is thrown if the router returns an error payload.

### Sending a notification

`notify()` sends a fire-and-forget message with no response:

```dart
bridge.notify('set_led_state', [true]);
```

### Disconnecting

`disconnect()` closes the socket and rejects all pending `call()` futures
with a `StateError`:

```dart
await bridge.disconnect();
```

---

## API reference

| Method | Returns | Description |
|--------|---------|-------------|
| `connect()` | `Future<bool>` | Opens the socket connection |
| `call(method, args, {timeout})` | `Future<dynamic>` | Sends a request and awaits the response |
| `notify(method, args)` | `void` | Sends a fire-and-forget notification |
| `register(methodName)` | `Future<void>` | Registers a method name with the router |
| `reset()` | `Future<void>` | Resets the router connection state |
| `disconnect()` | `Future<void>` | Closes the connection |

Full API documentation is available on
[pub.dev](https://pub.dev/documentation/arduino_bridge/latest/).

---

## License

This package is licensed under the MIT License.
