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
