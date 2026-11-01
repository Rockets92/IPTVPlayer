import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/performance.dart';
import '../../core/theme.dart';

/// Superficie in vetro.
///
/// Profilo completo, costruito a strati come un vetro vero:
/// 1. lo sfondo viene sfocato e reso più saturo e luminoso (la luce che
///    attraversa il vetro si "concentra");
/// 2. una velatura molto leggera, appena fredda, dà corpo alla lastra;
/// 3. un riflesso speculare morbido in alto a sinistra e una lama di luce
///    diagonale simulano la superficie lucida;
/// 4. una grana finissima rende la smerigliatura;
/// 5. il bordo smussato ha una luce viva in alto e un'ombra interna in basso,
///    che danno spessore alla lastra;
/// 6. l'ombra è disegnata solo all'esterno, così il vetro resta trasparente.
///
/// Profilo light: stesso disegno senza BackdropFilter né grana.
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
    _saturation(1.6, brightness: 0.98),
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
        ? (strong ? const Color(0x9E0A101E) : const Color(0x660A101E))
        : (strong ? Palette.frostedSolidStrong : Palette.frostedSolid);

    Widget body = CustomPaint(
      painter: _GlassBodyPainter(
        radius: radius,
        tint: tint,
        strong: strong,
        grain: blur ? GlassGrain.image : null,
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
        blur: perf.isLight ? 16 : 44,
        opacity: perf.isLight ? 0.35 : 0.42,
      ),
      child: body,
    );
  }
}

/// Riempimento della lastra: velatura, riflesso speculare, lama di luce, grana.
class _GlassBodyPainter extends CustomPainter {
  _GlassBodyPainter({
    required this.radius,
    required this.tint,
    required this.strong,
    required this.grain,
  });

  final double radius;
  final Color tint;
  final bool strong;
  final ui.Image? grain;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    canvas.save();
    canvas.clipRRect(rrect);

    // 1. Velatura con una leggera sfumatura verticale (più densa in basso,
    //    dove si appoggia il testo).
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            tint.withValues(alpha: tint.a * 0.75),
            tint,
          ],
        ).createShader(rect),
    );

    // 2. Riflesso diagonale generale.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: const [0, 0.4, 0.75, 1],
          colors: [
            Colors.white.withValues(alpha: strong ? 0.12 : 0.15),
            Colors.white.withValues(alpha: 0.03),
            Colors.white.withValues(alpha: 0.02),
            Colors.white.withValues(alpha: 0.08),
          ],
        ).createShader(rect),
    );

    // 3. Riflesso speculare: una luce morbida che entra dall'alto a sinistra.
    final glowCenter = Offset(size.width * 0.18, -size.height * 0.15);
    final glowRadius = size.longestSide * 0.55;
    canvas.drawCircle(
      glowCenter,
      glowRadius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withValues(alpha: 0.13),
            Colors.white.withValues(alpha: 0.035),
            Colors.white.withValues(alpha: 0),
          ],
          stops: const [0, 0.45, 1],
        ).createShader(Rect.fromCircle(center: glowCenter, radius: glowRadius)),
    );

    // 4. Lama di luce: una fascia sottile e inclinata, come su una lastra lucida.
    final band = Path()
      ..moveTo(size.width * 0.52, 0)
      ..lineTo(size.width * 0.64, 0)
      ..lineTo(size.width * 0.44, size.height)
      ..lineTo(size.width * 0.38, size.height)
      ..close();
    canvas.drawPath(
      band,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0.035),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(rect),
    );

    // 5. Grana della smerigliatura.
    final g = grain;
    if (g != null) {
      canvas.drawRect(
        rect,
        Paint()
          ..shader = ImageShader(
            g,
            TileMode.repeated,
            TileMode.repeated,
            Matrix4.identity().storage,
          )
          ..blendMode = BlendMode.overlay,
      );
    }

    // 6. Ombra interna in basso: dà spessore al vetro.
    canvas.drawRect(
      Rect.fromLTWH(0, size.height - 28, size.width, 28),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0),
            Colors.black.withValues(alpha: 0.10),
          ],
        ).createShader(Rect.fromLTWH(0, size.height - 28, size.width, 28)),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GlassBodyPainter old) =>
      old.radius != radius ||
      old.tint != tint ||
      old.strong != strong ||
      old.grain != grain;
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

/// Texture di grana generata una volta all'avvio (nessun asset da caricare).
abstract final class GlassGrain {
  static ui.Image? image;

  static Future<void> prepare() async {
    if (image != null) return;
    const size = 96;
    final pixels = Uint8List(size * size * 4);
    final rnd = math.Random(7);
    for (var i = 0; i < size * size; i++) {
      final v = 108 + rnd.nextInt(40);
      pixels[i * 4] = v;
      pixels[i * 4 + 1] = v;
      pixels[i * 4 + 2] = v;
      pixels[i * 4 + 3] = 12;
    }
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels,
      size,
      size,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    image = await completer.future;
  }
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
                  alpha: (bevel ? 0.62 : 0.42) * intensity,
                ),
                Colors.white.withValues(alpha: 0.12 * intensity),
                Colors.white.withValues(alpha: 0.05 * intensity),
                Colors.white.withValues(
                  alpha: (bevel ? 0.30 : 0.20) * intensity,
                ),
              ]
            : [
                a,
                a.withValues(alpha: 0.55),
                a.withValues(alpha: 0.35),
                a.withValues(alpha: 0.8),
              ],
      ).createShader(rect);
    canvas.drawRRect(rrect, paint);
    if (!bevel || a != null) return;

    // Riflesso interno: la luce che rimbalza dentro lo spessore della lastra.
    final inner = RRect.fromRectAndRadius(
      rect.deflate(2),
      Radius.circular(math.max(0, radius - 1.5)),
    );
    canvas.drawRRect(
      inner,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0, 0.18, 0.8, 1],
          colors: [
            Colors.white.withValues(alpha: 0.22),
            Colors.white.withValues(alpha: 0),
            Colors.black.withValues(alpha: 0),
            Colors.black.withValues(alpha: 0.28),
          ],
        ).createShader(rect),
    );

    // Filo di luce sul bordo superiore, più intenso al centro-sinistra.
    final top = Rect.fromLTWH(radius, 0, size.width - radius * 2, 1.4);
    canvas.drawRect(
      top,
      Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0.85),
            Colors.white.withValues(alpha: 0.25),
            Colors.white.withValues(alpha: 0),
          ],
          stops: const [0, 0.3, 0.7, 1],
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
