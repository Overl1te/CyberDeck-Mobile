import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'theme.dart';

class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );

  bool _done = false;
  bool _torch = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final raw = barcodes.first.rawValue;
    if (raw == null || raw.trim().isEmpty) return;

    _done = true;
    Navigator.of(context).pop(raw.trim());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBgColor,
      appBar: AppBar(
        backgroundColor: kBgColor,
        title: const Text('Сканировать QR'),
        actions: [
          IconButton(
            tooltip: 'Вспышка',
            icon: Icon(_torch ? Icons.flash_on : Icons.flash_off),
            onPressed: () async {
              setState(() => _torch = !_torch);
              await _controller.toggleTorch();
            },
          ),
          IconButton(
            tooltip: 'Камера',
            icon: const Icon(Icons.cameraswitch),
            onPressed: () async => _controller.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: MobileScanner(
              controller: _controller,
              onDetect: _onDetect,
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _QrOverlayPainter(),
              ),
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 24,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: kPanelColor.withOpacity(0.85),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white10),
              ),
              child: const Text(
                'Наведи камеру на QR-код с ПК.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, height: 1.2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QrOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withOpacity(0.55);
    canvas.drawRect(Offset.zero & size, paint);

    final scanSize = (size.shortestSide * 0.62).clamp(220.0, 360.0);
    final rect = Rect.fromCenter(center: size.center(Offset.zero), width: scanSize, height: scanSize);
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawRect(Offset.zero & size, paint);

    final hole = Paint()
      ..blendMode = BlendMode.clear
      ..style = PaintingStyle.fill;
    canvas.drawRRect(RRect.fromRectXY(rect, 18, 18), hole);
    canvas.restore();

    final border = Paint()
      ..color = kAccentColor.withOpacity(0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawRRect(RRect.fromRectXY(rect, 18, 18), border);

    final corner = Paint()
      ..color = kAccentColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.0
      ..strokeCap = StrokeCap.round;

    const c = 24.0;
    canvas.drawLine(Offset(rect.left, rect.top + c), Offset(rect.left, rect.top), corner);
    canvas.drawLine(Offset(rect.left, rect.top), Offset(rect.left + c, rect.top), corner);
    canvas.drawLine(Offset(rect.right - c, rect.top), Offset(rect.right, rect.top), corner);
    canvas.drawLine(Offset(rect.right, rect.top), Offset(rect.right, rect.top + c), corner);
    canvas.drawLine(Offset(rect.left, rect.bottom - c), Offset(rect.left, rect.bottom), corner);
    canvas.drawLine(Offset(rect.left, rect.bottom), Offset(rect.left + c, rect.bottom), corner);
    canvas.drawLine(Offset(rect.right - c, rect.bottom), Offset(rect.right, rect.bottom), corner);
    canvas.drawLine(Offset(rect.right, rect.bottom - c), Offset(rect.right, rect.bottom), corner);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

