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
            const Text('Click to control boards LED 👆'),
          ],
        ),
      ),
    );
  }
}
