import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/performance.dart';
import '../../core/theme.dart';

/// Superficie in vetro lucido, ispirata al "liquid glass" dei sistemi Apple.
///
/// Profilo completo, a strati:
/// 1. lo sfondo viene sfocato e reso più vivo (saturazione e un filo di luce):
///    il colore del video attraversa la lastra;
/// 2. una velatura sottile e liscia dà corpo al vetro senza spegnerlo;
/// 3. una lucentezza morbida scende dall'alto e un riflesso speculare entra
///    dall'angolo in alto a sinistra;
/// 4. lungo i bordi interni la luce si addensa, come nello spessore di una
///    lastra curva che rifrange (più forte negli angoli opposti);
/// 5. il bordo è un filo di luce, vivo in alto a sinistra e in basso a destra;
/// 6. l'ombra è disegnata solo all'esterno, così il vetro resta trasparente.
///
/// Nessuna grana: la superficie è pulita e glossy.
/// Profilo light: stesso disegno senza BackdropFilter né sfumature costose.
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

  /// Saturazione e luminosità applicate a ciò che sta dietro il vetro.
  static final ui.ColorFilter _vibrancy = ui.ColorFilter.matrix(
    _saturation(1.8, brightness: 1.03),
  );

  static List<double> _saturation(double s, {double brightness = 1}) {
    const lr = 0.2126, lg = 0.7152, lb = 0.0722;
    final b = brightness;
    return [
      ((1 - s) * lr + s) * b,
      (1 - s) * lg * b,
      (1 - s) * lb * b,
      0,
      0,
      (1 - s) * lr * b,
      ((1 - s) * lg + s) * b,
      (1 - s) * lb * b,
      0,
      0,
      (1 - s) * lr * b,
      (1 - s) * lg * b,
      ((1 - s) * lb + s) * b,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final perf = context.read<PerformanceProfile>();
    final shape = BorderRadius.circular(radius);
    final blur = perf.useBackdropBlur;

    // Velatura: nel profilo completo è sottile, il colore arriva dallo sfondo.
    final Color tint = blur
        ? (strong ? const Color(0x940C0824) : const Color(0x570C0824))
        : (strong ? Palette.frostedSolidStrong : Palette.frostedSolid);

    Widget body = CustomPaint(
      painter: _GlassBodyPainter(
        radius: radius,
        tint: tint,
        strong: strong,
        rich: blur,
      ),
      foregroundPainter: GlassEdgePainter(radius: radius, bevel: true),
      child: Padding(padding: padding, child: child),
    );

    if (blur) {
      body = ClipRRect(
        borderRadius: shape,
        child: BackdropFilter(
          filter: ui.ImageFilter.compose(
            outer: _vibrancy,
            inner: ui.ImageFilter.blur(
              sigmaX: perf.blurSigma,
              sigmaY: perf.blurSigma,
              tileMode: TileMode.mirror,
            ),
          ),
          child: body,
        ),
      );
    }

    if (!shadow) return body;
    return CustomPaint(
      painter: _OuterShadowPainter(
        radius: radius,
        blur: perf.isLight ? 16 : 40,
        opacity: perf.isLight ? 0.35 : 0.36,
      ),
      child: body,
    );
  }
}

/// Riempimento della lastra: velatura, lucentezza, riflesso, luce sui bordi.
class _GlassBodyPainter extends CustomPainter {
  _GlassBodyPainter({
    required this.radius,
    required this.tint,
    required this.strong,
    required this.rich,
  });

  final double radius;
  final Color tint;
  final bool strong;

  /// Strati aggiuntivi (luce sui bordi interni) solo nel profilo completo.
  final bool rich;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    canvas.save();
    canvas.clipRRect(rrect);

    // 1. Velatura liscia, appena più densa in basso dove si appoggia il testo.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            tint.withValues(alpha: tint.a * 0.7),
            tint,
          ],
        ).createShader(rect),
    );

    // 2. Lucentezza: la luce scende dall'alto e si spegne a metà lastra.
    final glossH = math.min(size.height * 0.6, 220.0);
    final gloss = Rect.fromLTWH(0, 0, size.width, glossH);
    canvas.drawRect(
      gloss,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0, 0.35, 1],
          colors: [
            Colors.white.withValues(alpha: strong ? 0.11 : 0.14),
            Colors.white.withValues(alpha: strong ? 0.04 : 0.05),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(gloss),
    );

    // 3. Riflesso speculare morbido dall'alto a sinistra.
    final glowCenter = Offset(size.width * 0.16, -size.height * 0.2);
    final glowRadius = size.longestSide * 0.5;
    canvas.drawCircle(
      glowCenter,
      glowRadius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withValues(alpha: 0.12),
            Colors.white.withValues(alpha: 0.03),
            Colors.white.withValues(alpha: 0),
          ],
          stops: const [0, 0.5, 1],
        ).createShader(Rect.fromCircle(center: glowCenter, radius: glowRadius)),
    );

    // 4. Luce nello spessore dei bordi: un alone interno che segue la forma,
    //    più vivo negli angoli opposti, come la rifrazione di un vetro curvo.
    if (rich) {
      canvas.drawRRect(
        rrect,
        Paint()
          ..maskFilter = const MaskFilter.blur(BlurStyle.inner, 7)
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: const [0, 0.4, 0.65, 1],
            colors: [
              Colors.white.withValues(alpha: 0.30),
              Colors.white.withValues(alpha: 0.06),
              Colors.white.withValues(alpha: 0.05),
              Colors.white.withValues(alpha: 0.22),
            ],
          ).createShader(rect),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GlassBodyPainter old) =>
      old.radius != radius ||
      old.tint != tint ||
      old.strong != strong ||
      old.rich != rich;
}

/// Ombra portata solo fuori dalla lastra: sotto il vetro non si scurisce nulla.
class _OuterShadowPainter extends CustomPainter {
  const _OuterShadowPainter({
    required this.radius,
    required this.blur,
    required this.opacity,
  });

  final double radius;
  final double blur;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect((Offset.zero & size).inflate(blur * 3))
      ..addRRect(rrect);
    canvas.save();
    canvas.clipPath(outside);
    canvas.drawRRect(
      rrect.shift(Offset(0, blur * 0.35)).deflate(4),
      Paint()
        ..color = Colors.black.withValues(alpha: opacity)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur * 0.5),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_OuterShadowPainter old) =>
      old.radius != radius || old.blur != blur || old.opacity != opacity;
}

/// Bordo del vetro: luce che entra dall'alto a sinistra e si spegne in basso.
class GlassEdgePainter extends CustomPainter {
  const GlassEdgePainter({
    required this.radius,
    this.intensity = 1,
    this.accent,
    this.bevel = false,
  });

  final double radius;
  final double intensity;
  final Color? accent;

  /// Bordo smussato completo (lastre grandi): filo luminoso esterno, riflesso
  /// interno in alto e ombra interna in basso.
  final bool bevel;

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
                Colors.white.withValues(
                  alpha: (bevel ? 0.70 : 0.42) * intensity,
                ),
                Colors.white.withValues(
                  alpha: (bevel ? 0.14 : 0.12) * intensity,
                ),
                Colors.white.withValues(
                  alpha: (bevel ? 0.10 : 0.05) * intensity,
                ),
                Colors.white.withValues(
                  alpha: (bevel ? 0.48 : 0.20) * intensity,
                ),
              ]
            : [
                Color.lerp(a, Palette.accent, 0.5)!,
                Palette.violet.withValues(alpha: a.a),
                Palette.magenta.withValues(alpha: a.a * 0.85),
                Palette.sunset.withValues(alpha: a.a),
              ],
      ).createShader(rect);
    canvas.drawRRect(rrect, paint);
    if (!bevel || a != null) return;

    // Secondo filo, interno e sottile: lo spessore della lastra.
    final inner = RRect.fromRectAndRadius(
      rect.deflate(1.8),
      Radius.circular(math.max(0, radius - 1.3)),
    );
    canvas.drawRRect(
      inner,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: const [0, 0.3, 0.7, 1],
          colors: [
            Colors.white.withValues(alpha: 0.26),
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0.16),
          ],
        ).createShader(rect),
    );

    // Punto di luce sul bordo superiore, morbido e decentrato a sinistra.
    final top = Rect.fromLTWH(radius, 0, size.width - radius * 2, 1.2);
    canvas.drawRect(
      top,
      Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0.75),
            Colors.white.withValues(alpha: 0.12),
            Colors.white.withValues(alpha: 0),
          ],
          stops: const [0, 0.25, 0.65, 1],
        ).createShader(top),
    );
  }

  @override
  bool shouldRepaint(GlassEdgePainter old) =>
      old.bevel != bevel ||
      old.radius != radius ||
      old.intensity != intensity ||
      old.accent != accent;
}
