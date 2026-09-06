import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'text_input_dialog.dart';

/// Camera screen for the QR cards. Returns the scanned raw value.
class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );

  /// Keeps two quick hits from popping the route twice.
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit(String code) {
    if (_handled || !mounted) return;
    _handled = true;
    Navigator.of(context).pop(code);
  }

  void _onDetect(BarcodeCapture capture) {
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value != null && value.trim().isNotEmpty) {
        _submit(value.trim());
        return;
      }
    }
  }

  Future<void> _enterManually() async {
    final code = await showDialog<String>(
      context: context,
      builder: (_) => const TextInputDialog(
        title: 'Enter code',
        confirmLabel: 'Continue',
        hintText: 'Link from the card, or a year',
      ),
    );
    if (code != null && code.isNotEmpty) _submit(code);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Scan QR code'),
        actions: [
          ValueListenableBuilder<MobileScannerState>(
            valueListenable: _controller,
            builder: (context, state, _) => IconButton(
              tooltip: 'Torch',
              icon: Icon(
                state.torchState == TorchState.on
                    ? Icons.flashlight_on
                    : Icons.flashlight_off,
              ),
              onPressed: state.isInitialized ? _controller.toggleTorch : null,
            ),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => _ScannerError(
              message: error.errorDetails?.message ?? error.errorCode.name,
              onManual: _enterManually,
            ),
          ),
          const _ScanFrame(),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: TextButton.icon(
                onPressed: _enterManually,
                icon: const Icon(Icons.keyboard),
                label: const Text('Enter the code by hand'),
                style: TextButton.styleFrom(foregroundColor: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanFrame extends StatelessWidget {
  const _ScanFrame();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 240,
        height: 240,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white70, width: 3),
          borderRadius: BorderRadius.circular(24),
        ),
      ),
    );
  }
}

class _ScannerError extends StatelessWidget {
  const _ScannerError({required this.message, required this.onManual});

  final String message;
  final VoidCallback onManual;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_photography, size: 48, color: Colors.white54),
              const SizedBox(height: 16),
              Text(
                'Camera unavailable\n$message',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onManual,
                icon: const Icon(Icons.keyboard),
                label: const Text('Enter the code by hand'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
