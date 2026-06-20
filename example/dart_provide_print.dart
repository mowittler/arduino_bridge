// Make sure to compile and upload the provided sketch.ino to the MCU first.
import 'dart:async';
import 'arduino_bridge.dart';

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
