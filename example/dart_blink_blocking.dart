// Make sure to compile and upload the provided sketch.ino to the MCU first.
import 'dart:io';
import 'arduino_bridge.dart';

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
