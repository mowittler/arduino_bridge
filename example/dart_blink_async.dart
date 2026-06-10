/*
 * Author: Maik Oberwittler
 * Date: 2026-06-10
 * License: MIT
 */

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
