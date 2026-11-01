import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/performance.dart';
import '../../core/theme.dart';

/// Sfondo profondo con luci morbide in lento movimento, visibile dietro al
/// vetro nelle schermate senza video. Statico nel profilo light.
class AmbientBackground extends StatefulWidget {
  const AmbientBackground({super.key, this.child});
  final Widget? child;

  @override
  State<AmbientBackground> createState() => _AmbientBackgroundState();
}

class _AmbientBackgroundState extends State<AmbientBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 28),
  );

  @override
  void initState() {
    super.initState();
    if (context.read<PerformanceProfile>().animatedBackground) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) =>
                CustomPaint(painter: _AuroraPainter(_c.value)),
          ),
        ),
        ?widget.child,
      ],
    );
  }
}

class _AuroraPainter extends CustomPainter {
  _AuroraPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Palette.deep, Palette.night, Palette.ink],
        ).createShader(rect),
    );
    final a = t * 2 * math.pi;
    final d = size.shortestSide;
    void glow(Offset c, double r, Color color) {
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(colors: [color, color.withValues(alpha: 0)])
              .createShader(Rect.fromCircle(center: c, radius: r)),
      );
    }

    glow(
      Offset(
        size.width * (0.22 + 0.06 * math.sin(a)),
        size.height * (0.28 + 0.05 * math.cos(a)),
      ),
      d * 0.75,
      const Color(0x553D7BFF),
    );
    glow(
      Offset(
        size.width * (0.82 + 0.05 * math.cos(a * 1.3)),
        size.height * (0.72 + 0.06 * math.sin(a * 0.7)),
      ),
      d * 0.7,
      const Color(0x3D2BD4C8),
    );
    glow(
      Offset(
        size.width * (0.62 + 0.08 * math.sin(a * 0.6)),
        size.height * (0.12 + 0.04 * math.sin(a)),
      ),
      d * 0.45,
      const Color(0x2E9B7BFF),
    );
  }

  @override
  bool shouldRepaint(_AuroraPainter old) => old.t != t;
}
