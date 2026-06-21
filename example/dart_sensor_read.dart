// Make sure to compile and upload the provided sketch.ino to the MCU first.
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
