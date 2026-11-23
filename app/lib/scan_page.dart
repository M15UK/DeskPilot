import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Opens the camera and returns the text of the first QR code it sees.
class ScanPage extends StatefulWidget {
  const ScanPage({super.key});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  bool _done = false;

  void _onDetect(BarcodeCapture capture) {
    final text = capture.barcodes.firstOrNull?.rawValue;
    if (_done || text == null) return;
    _done = true;
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Scan the QR code')),
    body: MobileScanner(
      onDetect: _onDetect,
      errorBuilder: (context, error) => const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            "The camera didn't start. Allow DeskPilot to use the camera in "
            "your phone's settings, then try again.",
            textAlign: TextAlign.center,
          ),
        ),
      ),
    ),
  );
}
