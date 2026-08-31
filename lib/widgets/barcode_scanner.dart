import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class BarcodeScannerScreen extends StatefulWidget {
  const BarcodeScannerScreen({super.key});

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  bool _done = false;
  String _scannedCode = '';
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    torchEnabled: false,
  );

  bool _torchOn = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Scan Barcode'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(
              _torchOn ? Icons.flash_on : Icons.flash_off,
              color: _torchOn ? Colors.yellow : Colors.white,
            ),
            onPressed: () {
              _controller.toggleTorch();
              setState(() => _torchOn = !_torchOn);
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          // Full screen camera
          MobileScanner(
            controller: _controller,
            onDetect: (capture) {
              if (_done) return;
              final barcode = capture.barcodes.firstOrNull?.rawValue;
              if (barcode != null && mounted) {
                setState(() {
                  _done = true;
                  _scannedCode = barcode;
                });
                // Show barcode on top briefly, then return result
                Future.delayed(const Duration(milliseconds: 600), () {
                  if (mounted) Navigator.pop(context, barcode);
                });
              }
            },
          ),

          // Scan overlay - large frame
          Center(
            child: Container(
              width: MediaQuery.of(context).size.width * 0.85,
              height: MediaQuery.of(context).size.width * 0.55,
              decoration: BoxDecoration(
                border: Border.all(
                  color: _done ? Colors.green : Colors.white,
                  width: 3,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Stack(
                children: [
                  // Animated scan line
                  if (!_done)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: _ScanLine(),
                    ),
                  // Corner accents
                  _CornerAccent(top: 0, left: 0),
                  _CornerAccent(top: 0, right: 0),
                  _CornerAccent(bottom: 0, left: 0),
                  _CornerAccent(bottom: 0, right: 0),
                ],
              ),
            ),
          ),

          // Top barcode display
          if (_scannedCode.isNotEmpty)
            Positioned(
              top: 16,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: BoxDecoration(
                  color: _done
                      ? Colors.green.withOpacity(0.9)
                      : Colors.black87,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: (_done ? Colors.green : Colors.blue).withOpacity(0.5),
                      blurRadius: 12,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _done ? Icons.check_circle : Icons.qr_code_scanner,
                      color: Colors.white,
                      size: 24,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _scannedCode,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                        letterSpacing: 2,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _done ? 'Done! Returning...' : 'Scan a barcode',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Instruction text at bottom
          if (_scannedCode.isEmpty)
            Positioned(
              bottom: 40,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Point camera at barcode',
                  style: TextStyle(color: Colors.white70, fontSize: 15),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ScanLine extends StatefulWidget {
  @override
  State<_ScanLine> createState() => _ScanLineState();
}

class _ScanLineState extends State<_ScanLine>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            height: 3,
            margin: EdgeInsets.only(
              top: MediaQuery.of(context).size.width * 0.55 * _controller.value,
            ),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.blue.withOpacity(0.3),
                  Colors.cyan,
                  Colors.blue.withOpacity(0.3),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CornerAccent extends StatelessWidget {
  final double? top, bottom, left, right;
  const _CornerAccent({this.top, this.bottom, this.left, this.right});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: top, bottom: bottom, left: left, right: right,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.cyan, width: 4),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(top != null && left != null ? 16 : 0),
            topRight: Radius.circular(top != null && right != null ? 16 : 0),
            bottomLeft: Radius.circular(bottom != null && left != null ? 16 : 0),
            bottomRight: Radius.circular(bottom != null && right != null ? 16 : 0),
          ),
        ),
      ),
    );
  }
}
