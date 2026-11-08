import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'refraction.dart';

import '../../core/glass_look.dart';
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
    final crystal = GlassLookTheme.of(context) == GlassLook.crystal;
    // Il crystal non sfoca: niente BackdropFilter, leggero anche in light.
    final blur = perf.useBackdropBlur && !crystal;

    // Velatura: nel profilo completo è sottile, il colore arriva dallo sfondo.
    final Color tint = perf.useBackdropBlur
        ? (strong ? const Color(0x940C0824) : const Color(0x570C0824))
        : (strong ? Palette.frostedSolidStrong : Palette.frostedSolid);

    // La struttura dei widget è la stessa in tutti gli stili: cambiando
    // stile al volo il contenuto (liste, focus, scorrimento) non si ricrea.
    final body = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      clipBehavior: blur || (crystal && GlassShader.available)
          ? Clip.antiAlias
          : Clip.none,
      child: BackdropFilter(
        enabled: blur,
        filter: ui.ImageFilter.compose(
          outer: _vibrancy,
          inner: ui.ImageFilter.blur(
            sigmaX: perf.blurSigma,
            sigmaY: perf.blurSigma,
            tileMode: TileMode.mirror,
          ),
        ),
        child: RefractiveBackdrop(
          enabled: crystal,
          radius: radius,
          density: strong ? 1 : 0.3,
          child: CustomPaint(
            painter: crystal
                ? _CrystalBodyPainter(
                    radius: radius,
                    strong: strong,
                    refracted: GlassShader.available,
                  )
                : _GlassBodyPainter(
                    radius: radius,
                    tint: tint,
                    strong: strong,
                    rich: perf.useBackdropBlur,
                  ),
            foregroundPainter: crystal
                ? _CrystalEdgePainter(
                    radius: radius,
                    refracted: GlassShader.available,
                  )
                : GlassEdgePainter(radius: radius, bevel: true),
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );

    if (!shadow) return body;
    return CustomPaint(
      painter: crystal
          ? _OuterShadowPainter(
              radius: radius,
              blur: perf.isLight ? 14 : 30,
              opacity: 0.20,
            )
          : _OuterShadowPainter(
              radius: radius,
              blur: perf.isLight ? 16 : 40,
              opacity: perf.isLight ? 0.35 : 0.36,
            ),
      child: body,
    );
  }
}

/// Goccia d'acqua: la lastra non vela lo sfondo, si riconosce dalla luce.
///
/// 1. una velatura quasi nulla, appena più densa in basso dove sta il testo;
/// 2. il menisco: lungo i bordi interni la goccia si scurisce, come l'acqua
///    che piega la luce verso l'interno (riflessione totale);
/// 3. la caustica: sul lato opposto alla luce (in basso a destra) la luce
///    rifratta si concentra in una mezzaluna chiara;
/// 4. il riflesso: una lunetta lucida lungo il bordo superiore e un punto
///    speculare netto in alto a sinistra, con un piccolo riflesso gemello.
class _CrystalBodyPainter extends CustomPainter {
  _CrystalBodyPainter({
    required this.radius,
    required this.strong,
    required this.refracted,
  });

  final double radius;
  final bool strong;

  /// Con lo shader di rifrazione luce e riflessi sono già nel vetro: qui si
  /// dipinge solo il disegno di riserva per i motori senza Impeller.
  final bool refracted;

  static const _ink = Color(0xFF05040E);

  @override
  void paint(Canvas canvas, Size size) {
    if (refracted) return;
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    canvas.save();
    canvas.clipRRect(rrect);

    // 1. Velatura: quasi trasparente.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _ink.withValues(alpha: strong ? 0.10 : 0.03),
            _ink.withValues(alpha: strong ? 0.22 : 0.10),
          ],
        ).createShader(rect),
    );

    // 2. Menisco scuro lungo il bordo interno.
    final rim = math.min(14.0, size.shortestSide * 0.12);
    canvas.drawRRect(
      rrect,
      Paint()
        ..maskFilter = MaskFilter.blur(BlurStyle.inner, rim)
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _ink.withValues(alpha: 0.38),
            _ink.withValues(alpha: 0.20),
            _ink.withValues(alpha: 0.46),
          ],
        ).createShader(rect),
    );

    // 3. Caustica: mezzaluna di luce rifratta in basso a destra.
    final cRect = Rect.fromLTRB(
      size.width * 0.18,
      size.height * 0.55,
      size.width * 1.02,
      size.height * 1.05,
    );
    final caustic = Path()
      ..fillType = PathFillType.evenOdd
      ..addRRect(rrect.deflate(1.5))
      ..addRRect(
        RRect.fromRectAndRadius(
          rect.deflate(1.5).translate(-9, -8).deflate(2),
          Radius.circular(math.max(0, radius - 2)),
        ),
      );
    canvas.drawPath(
      caustic,
      Paint()
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5)
        ..shader = RadialGradient(
          center: const Alignment(0.75, 0.9),
          radius: 0.9,
          colors: [
            Colors.white.withValues(alpha: 0.70),
            const Color(0xFFBFE6FF).withValues(alpha: 0.26),
            Colors.white.withValues(alpha: 0),
          ],
          stops: const [0, 0.45, 1],
        ).createShader(cRect),
    );

    // 4a. Lunetta lucida lungo il bordo superiore (superficie curva).
    final lune = Path()
      ..fillType = PathFillType.evenOdd
      ..addRRect(rrect.deflate(1.2))
      ..addRRect(
        RRect.fromRectAndRadius(
          rect.deflate(1.2).translate(0, math.min(9.0, size.height * 0.06)),
          Radius.circular(math.max(0, radius - 1)),
        ),
      );
    final top = Rect.fromLTWH(0, 0, size.width, math.min(40.0, size.height));
    canvas.drawPath(
      lune,
      Paint()
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5)
        ..shader = LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0.10),
            Colors.white.withValues(alpha: 0.42),
            Colors.white.withValues(alpha: 0.14),
            Colors.white.withValues(alpha: 0.02),
          ],
          stops: const [0, 0.22, 0.6, 1],
        ).createShader(top),
    );

    // 4b. Punto speculare netto in alto a sinistra e riflesso gemello.
    final sw = math.min(size.width * 0.22, 150.0);
    final sh = math.min(size.height * 0.07, 12.0);
    if (sw > 12 && sh > 3) {
      final spec = Rect.fromLTWH(
        math.max(radius * 0.8, 10),
        math.max(4, sh * 0.8),
        sw,
        sh,
      );
      canvas.drawOval(
        spec,
        Paint()
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, sh * 0.35)
          ..shader = LinearGradient(
            colors: [
              Colors.white.withValues(alpha: 0.75),
              Colors.white.withValues(alpha: 0.10),
            ],
          ).createShader(spec),
      );
      final twin = Rect.fromCenter(
        center: spec.topRight + Offset(sh * 1.6, sh * 0.7),
        width: sh * 0.9,
        height: sh * 0.9,
      );
      canvas.drawOval(
        twin,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.6)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, sh * 0.2),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CrystalBodyPainter old) =>
      old.radius != radius ||
      old.strong != strong ||
      old.refracted != refracted;
}

/// Bordo crystal: un filo di luce netto con una frangia prismatica (azzurro
/// in alto a sinistra, magenta in basso a destra), come la luce scomposta
/// dallo spessore dell'acqua.
class _CrystalEdgePainter extends CustomPainter {
  const _CrystalEdgePainter({required this.radius, required this.refracted});

  final double radius;
  final bool refracted;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    RRect r(double d) => RRect.fromRectAndRadius(
      rect.deflate(d),
      Radius.circular(math.max(0, radius - d)),
    );

    if (refracted) {
      // Solo un'ombra di contatto sottilissima: il resto lo fa la rifrazione.
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          rect.inflate(0.6),
          Radius.circular(radius + 0.6),
        ),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..color = Colors.black.withValues(alpha: 0.22),
      );
      return;
    }

    // Filo esterno chiaro.
    canvas.drawRRect(
      r(0.6),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: const [0, 0.35, 0.7, 1],
          colors: [
            Colors.white.withValues(alpha: 0.90),
            Colors.white.withValues(alpha: 0.28),
            Colors.white.withValues(alpha: 0.22),
            Colors.white.withValues(alpha: 0.70),
          ],
        ).createShader(rect),
    );

    // Frangia prismatica appena all'interno.
    canvas.drawRRect(
      r(2.2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.8)
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: [0, 0.3, 0.7, 1],
          colors: [
            Color(0x8C7FD8FF),
            Color(0x00FFFFFF),
            Color(0x00FFFFFF),
            Color(0x80F27DFF),
          ],
        ).createShader(rect),
    );

    // Filo scuro sottilissimo all'esterno: stacca la goccia su fondi chiari.
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.inflate(0.6), Radius.circular(radius + 0.6)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = Colors.black.withValues(alpha: 0.28),
    );
  }

  @override
  bool shouldRepaint(_CrystalEdgePainter old) =>
      old.radius != radius || old.refracted != refracted;
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
