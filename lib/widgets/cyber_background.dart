import 'package:flutter/material.dart';

import '../theme.dart';

class CyberBackground extends StatelessWidget {
  final Widget child;

  const CyberBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[kBgColorDeep, kBgColor, kBgColorSoft],
            ),
          ),
        ),
        Positioned(
          top: -120,
          right: -80,
          child: _GlowOrb(
            size: 260,
            color: kAccentColor.withValues(alpha: 0.12),
          ),
        ),
        Positioned(
          left: -90,
          bottom: -140,
          child: _GlowOrb(
            size: 300,
            color: kAccentColorDim.withValues(alpha: 0.10),
          ),
        ),
        IgnorePointer(
          child: CustomPaint(
            painter: _GridPainter(
              color: Colors.white.withValues(alpha: 0.035),
              step: 34,
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class _GlowOrb extends StatelessWidget {
  final double size;
  final Color color;

  const _GlowOrb({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: <Color>[
            color,
            color.withValues(alpha: 0.06),
            Colors.transparent,
          ],
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  final Color color;
  final double step;

  const _GridPainter({required this.color, required this.step});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;

    for (double x = 0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.step != step;
  }
}
