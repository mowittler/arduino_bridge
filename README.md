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
that socket and communicates using MessagePack-RPC, a compact binary RPC
protocol built on top of [MessagePack](https://msgpack.org/) serialization.

Three message types are used:

| Type | Direction | Description |
|------|-----------|-------------|
| Request (0) | host <-> router | Call a method and wait for a response |
| Response (1) | host <-> router | Result or error for a previous request |
| Notification (2) | host -> router | Fire-and-forget message, no response |

---

## Requirements

- [Arduino Uno Q](https://www.arduino.cc/product-uno-q/) or [Ventuno Q](https://www.arduino.cc/product-ventuno-q/) with the Arduino router daemon running
- The `sketch.ino` from the `example/sketch/` directory compiled and flashed to the MCU in order to run the examples


---

## Flutter compatibility

This package is compatible with **Flutter for Linux desktop** only. No additional
setup is needed beyond targeting the Linux platform in your Flutter project. It also works in a dart-only environment.

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
final result = await bridge.call('sensor_read', [0]);
```

The default timeout is 5 seconds. 

A `TimeoutException` is thrown if no response arrives in time. An
`Exception` is thrown if the router returns an error payload.

### Sending a notification

`notify()` sends a fire-and-forget message with no response:

```dart
bridge.notify('set_led_state', [true]);
```

### Providing a method

`provide()` exposes a Dart function so the router can call it from the MCU
side. It registers the method name with the router and dispatches incoming
requests to your handler automatically. The handler can be synchronous or
`async`:

```dart
await bridge.provide('sensor_calibrate', (int channel) async {
  return 'done';
});
```

If the router calls a method that was never provided, the bridge replies with
an error payload automatically.

### Disconnecting

`disconnect()` closes the socket and rejects all pending `call()` futures
with a `StateError`:

```dart
await bridge.disconnect();
```

---

## Examples

### Flashing the MCU

Before running any of the examples below, compile and upload `example/sketch/sketch.ino` to your board using [arduino-cli](https://arduino.github.io/arduino-cli/). For the Arduino Uno Q use this:

```sh
arduino-cli compile --fqbn arduino:zephyr:unoq example/sketch/sketch.ino
arduino-cli upload -p /dev/ttyHS1 --fqbn arduino:zephyr:unoq example/sketch/sketch.ino
```

The sketch exposes two methods the host can call (`set_led_state`, `read_sensor`) and periodically calls `mcuCall` back on the host side:

```cpp
#include "Arduino_RouterBridge.h"

void setup() {
    pinMode(LED_BUILTIN, OUTPUT);
    
    Bridge.begin();
    Bridge.provide("set_led_state", set_led_state);
    Bridge.provide("read_sensor", read_sensor);
}

void loop() {
    Bridge.call("mcuCall", "Hello from MCU!");
    delay(1000);
}

void set_led_state(bool state) {
    digitalWrite(LED_BUILTIN, state ? LOW : HIGH);
}

// connect a potentiometer to VCC (3.3V) and GND, and the wiper to A0
int read_sensor() {
    return analogRead(A0);
}
```

> **Note:** All examples run without a potentiometer connected. However, without one the `read_sensor` example will always return the same floating pin value rather than a varying reading.

> **Note:** The `main.py` file in the `example/python/` directory is only required for the `flutter_advanced` example. All other examples are pure Dart/Flutter and do not depend on it (but on the `sketch.ino`).

---

### Blink (blocking)

Toggles the built-in LED 10 times using `notify()`.

```dart
import 'dart:io';
import 'package:arduino_bridge/arduino_bridge.dart';

void main() {
  bool ledState = false;

  final bridge = ArduinoBridge();
  bridge.connect().then((connected) {
    for (var i = 0; i < 10; i++) {
      ledState = !ledState;
      print('LED is ${ledState ? 'ON' : 'OFF'}');
      bridge.notify('set_led_state', [ledState]);
      sleep(const Duration(seconds: 1));
    }

    bridge.disconnect();
  });
}
```

---

### Blink (async)

The same LED blink loop rewritten with `async`/`await` and `Future.delayed`, keeping the event loop free between toggles.

```dart
import 'package:arduino_bridge/arduino_bridge.dart';

Future<void> main() async {
  final bridge = ArduinoBridge();

  final connected = await bridge.connect();
  if (!connected) {
    print('Failed to connect to Arduino Bridge');
    return;
  }
  print('Connected to Arduino Bridge');

  bool ledState = false;
  for (var i = 0; i < 10; i++) {
    ledState = !ledState;
    print('LED is ${ledState ? 'ON' : 'OFF'}');
    bridge.notify('set_led_state', [ledState]);
    await Future.delayed(const Duration(seconds: 1));
  }

  await bridge.disconnect();
  print('Disconnected from Arduino Bridge');
}
```

---

### Sensor read

Reads an analog value from the potentiometer wired to pin A0 ten times, once per second, using `call()`. Connect the potentiometer wiper to A0, one end to 3.3 V, and the other to GND.

```dart
// Connect a potentiometer to VCC (3.3V) and GND, and the wiper to A0 for this example.
import 'dart:async';
import 'package:arduino_bridge/arduino_bridge.dart';

Future<void> main() async {
  final bridge = ArduinoBridge();

  final connected = await bridge.connect();
  if (!connected) {
    print('Failed to connect to Arduino Bridge');
    return;
  }
  print('Connected to Arduino Bridge');

  for (var i = 0; i < 10; i++) {
    try {
      final value = await bridge.call('read_sensor', []);
      print('Sensor value: $value');
    } catch (e) {
      print('Error: $e');
    }
    await Future.delayed(const Duration(seconds: 1));
  }

  await bridge.disconnect();
  print('Disconnected from Arduino Bridge');
}
```

---

### Provide print

Exposes a `mcuCall` method so the MCU can push data to the host. The sketch calls it every second; the handler simply prints whatever it receives. After 10 seconds the bridge disconnects.

```dart
import 'dart:async';
import 'package:arduino_bridge/arduino_bridge.dart';

void mcuCall(dynamic data) {
  print(data);
}

Future<void> main() async {
  final bridge = ArduinoBridge();

  final connected = await bridge.connect();
  if (!connected) {
    print('Failed to connect to Arduino Bridge');
    return;
  }
  print('Connected to Arduino Bridge');

  await bridge.provide('mcuCall', mcuCall);

  await Future.delayed(const Duration(seconds: 10));
  await bridge.disconnect();
  print('Disconnected from Arduino Bridge');
}
```

---

### Flutter UI (main.dart)

A minimal Flutter Linux desktop app with a tap-to-toggle LED button. Connecting to the bridge happens in `initState`; toggling the LED sends a `notify` call; disconnecting is handled in `dispose`.

```dart
// Flutter Blink UI (inspired by App Lab example 'Blink with UI')
import 'package:flutter/material.dart';
import 'package:arduino_bridge/arduino_bridge.dart';

void main() {
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: BlinkPage(),
    );
  }
}

class BlinkPage extends StatefulWidget {
  const BlinkPage({super.key});

  @override
  State<BlinkPage> createState() => _BlinkPageState();
}

class _BlinkPageState extends State<BlinkPage> {
  bool _ledOn = false;
  final ArduinoBridge _bridge = ArduinoBridge();

  @override
  void initState() {
    super.initState();
    _bridge.connect().then((connected) {
      if (connected) {
        print('Connected to Arduino Bridge');
      }
    });
  }

  void _toggleLed() {
    setState(() => _ledOn = !_ledOn);
    _bridge.notify('set_led_state', [_ledOn]);
  }

  @override
  void dispose() {
    _bridge.notify('set_led_state', [false]);
    _bridge.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        backgroundColor: Colors.blue,
        title: const Text('Flutter Blink'),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 16),
            child: Icon(Icons.flutter_dash, size: 28),
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: _toggleLed,
              child: Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _ledOn
                      ? Colors.blue.withValues(alpha: 0.5)
                      : Colors.grey,
                  boxShadow: _ledOn
                      ? [
                          BoxShadow(
                            color: Colors.blue.withValues(alpha: 0.5),
                            blurRadius: 48,
                            spreadRadius: 12,
                          ),
                        ]
                      : [],
                ),
                child: Center(child: Text(_ledOn ? 'LED IS ON' : 'LED IS OFF')),
              ),
            ),
            const SizedBox(height: 32),
            const Text('Click to control boards LED'),
          ],
        ),
      ),
    );
  }
}
```

---

### Flutter Blink Advanced (main.py + flutter_blink_advanced.dart)

A two-part example that separates the blink loop from the UI. `main.py` runs on the MPU (Linux side) and drives the LED autonomously, toggling it at a configurable interval. The Flutter app exposes a slider that sends a `set_interval` notification whenever the user changes the value — no polling, no blocking. This example better reflects a real-life scenario.

**`main.py`** (runs on the MPU):

```python
from arduino.app_utils import *
import time

led_state = False

interval = 1.0

def set_interval(new_interval):
    global interval
    interval = new_interval

Bridge.provide("set_interval", set_interval)

def loop():
    global led_state
    interval
    time.sleep(interval)
    led_state = not led_state
    Bridge.call("set_led_state", led_state)

App.run(user_loop=loop)
```

**`flutter_blink_advanced.dart`** (Flutter Linux desktop app):

```dart
// Make sure to compile and upload the provided sketch.ino to the MCU first.
// Make sure that the provided main.py is running on the MPU.
import 'package:flutter/material.dart';
import 'package:arduino_bridge/arduino_bridge.dart';

void main() {
  runApp(const MainApp());
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  static const _intervals = [0.25, 0.5, 1.0, 1.5, 2.0];
  int _index = 2;
  final ArduinoBridge _bridge = ArduinoBridge();

  @override
  void initState() {
    super.initState();
    _bridge.connect().then((connected) {
      if (connected) {
        print('Connected to Arduino Bridge');
      }
    });
  }

  void _onIntervalChanged(double interval) {
    setState(() => _index = interval.round());
    _bridge.notify('set_interval', [_intervals[_index]]);
  }

  @override
  void dispose() {
    _bridge.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Please select the blinking interval of the LED in seconds:',
              ),
              Slider(
                min: 0,
                max: 4.0,
                divisions: 4,
                value: _index.toDouble(),
                label: '${_intervals[_index]}',
                onChanged: _onIntervalChanged,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: _intervals
                      .map(
                        (interval) => Text(
                          interval == interval.truncate()
                              ? '${interval.toInt()}'
                              : '$interval',
                          style: const TextStyle(fontSize: 12),
                        ),
                      )
                      .toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

---

## API reference

| Method | Returns | Description |
|--------|---------|-------------|
| `connect()` | `Future<bool>` | Opens the socket connection |
| `call(method, args, {timeout})` | `Future<dynamic>` | Sends a request and awaits the response |
| `notify(method, args)` | `void` | Sends a fire-and-forget notification |
| `provide(method, handler)` | `Future<void>` | Exposes a Dart function for the router to call |
| `disconnect()` | `Future<void>` | Closes the connection |

Full API documentation is available on
[pub.dev](https://pub.dev/documentation/arduino_bridge/latest/).

---

## License

This package is licensed under the MIT License.
