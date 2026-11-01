import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/performance.dart';
import '../../core/theme.dart';

/// Superficie in vetro.
///
/// Profilo completo: blur reale dello sfondo + velatura scura + riflesso
/// diagonale + bordo luminoso sfumato. Profilo light: stesso disegno senza
/// BackdropFilter (il costo maggiore sulle GPU economiche).
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.radius = 26,
    this.padding = EdgeInsets.zero,
    this.strong = false,
    this.shadow = true,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;

  /// Variante più coprente (pannelli con molto testo).
  final bool strong;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final perf = context.read<PerformanceProfile>();
    final shape = BorderRadius.circular(radius);
    final blur = perf.useBackdropBlur;

    Widget body = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: shape,
        color: blur
            ? (strong ? const Color(0x8C0A0F1C) : const Color(0x660A0F1C))
            : (strong ? Palette.frostedSolidStrong : Palette.frostedSolid),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: shape,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: const [0, 0.45, 1],
            colors: [
              Colors.white.withValues(alpha: strong ? 0.13 : 0.15),
              Colors.white.withValues(alpha: 0.04),
              Colors.white.withValues(alpha: 0.07),
            ],
          ),
        ),
        child: CustomPaint(
          foregroundPainter: GlassEdgePainter(radius: radius),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );

    if (blur) {
      body = ClipRRect(
        borderRadius: shape,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(
            sigmaX: perf.blurSigma,
            sigmaY: perf.blurSigma,
            tileMode: TileMode.mirror,
          ),
          child: body,
        ),
      );
    }

    if (!shadow) return body;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: shape,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.32),
            blurRadius: perf.isLight ? 18 : 48,
            spreadRadius: -6,
            offset: const Offset(0, 20),
          ),
        ],
      ),
      child: body,
    );
  }
}

/// Bordo del vetro: luce che entra dall'alto a sinistra e si spegne in basso.
class GlassEdgePainter extends CustomPainter {
  const GlassEdgePainter({
    required this.radius,
    this.intensity = 1,
    this.accent,
  });

  final double radius;
  final double intensity;
  final Color? accent;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(
      rect.deflate(0.5),
      Radius.circular(radius),
    );
    final a = accent;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = a == null ? 1 : 1.6
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        stops: const [0, 0.35, 0.7, 1],
        colors: a == null
            ? [
                Colors.white.withValues(alpha: 0.42 * intensity),
                Colors.white.withValues(alpha: 0.10 * intensity),
                Colors.white.withValues(alpha: 0.05 * intensity),
                Colors.white.withValues(alpha: 0.20 * intensity),
              ]
            : [
                a,
                a.withValues(alpha: 0.55),
                a.withValues(alpha: 0.35),
                a.withValues(alpha: 0.8),
              ],
      ).createShader(rect);
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(GlassEdgePainter old) =>
      old.radius != radius ||
      old.intensity != intensity ||
      old.accent != accent;
}
