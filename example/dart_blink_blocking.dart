import 'dart:io';
import 'package:arduino_bridge/arduino_bridge.dart';

void main() {
  bool led_state = false;

  final bridge = ArduinoBridge();
  bridge.connect().then((connected) {
    for (var i = 0; i < 10; i++) {
      led_state = !led_state;
      print('LED is ${led_state ? 'ON' : 'OFF'}');
      bridge.notify('set_led_state', [led_state]);
      sleep(const Duration(seconds: 1));
    }

    bridge.disconnect();
  });
}
