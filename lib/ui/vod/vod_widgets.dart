import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/performance.dart';
import '../../core/theme.dart';
import '../../data/vod/vod_models.dart';

/// "1:42:05" o "42:05".
String formatClock(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

/// "1 h 42 min" o "42 min".
String formatLength(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  if (h == 0) return '$m min';
  return m == 0 ? '$h h' : '$h h $m min';
}

/// Locandina con ripiego tipografico se manca l'immagine.
class Poster extends StatelessWidget {
  const Poster({
    super.key,
    required this.url,
    required this.title,
    this.radius = 14,
    this.decodeWidth,
    this.fit = BoxFit.cover,
  });

  final String? url;
  final String title;
  final double radius;
  final int? decodeWidth;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final perf = context.read<PerformanceProfile>();
    final fallback = _PosterFallback(title: title);
    final u = url;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: u == null || !u.startsWith('http')
          ? fallback
          : CachedNetworkImage(
              imageUrl: u,
              memCacheWidth: decodeWidth ?? (perf.isLight ? 200 : 320),
              fit: fit,
              fadeInDuration: perf.fast,
              fadeOutDuration: Duration.zero,
              placeholder: (_, _) => fallback,
              errorWidget: (_, _, _) => fallback,
              filterQuality: perf.isLight
                  ? FilterQuality.low
                  : FilterQuality.medium,
            ),
    );
  }
}

class _PosterFallback extends StatelessWidget {
  const _PosterFallback({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final hue = (title.hashCode % 360).abs().toDouble();
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            HSLColor.fromAHSL(1, hue, 0.35, 0.22).toColor(),
            HSLColor.fromAHSL(1, (hue + 40) % 360, 0.30, 0.10).toColor(),
          ],
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            title,
            textAlign: TextAlign.center,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: AppText.headline.copyWith(fontSize: 15),
          ),
        ),
      ),
    );
  }
}

/// Tessera della griglia: locandina, titolo, anno e avanzamento.
class PosterTile extends StatelessWidget {
  const PosterTile({
    super.key,
    required this.item,
    required this.focused,
    this.progress,
    this.onTap,
  });

  final VodItem item;
  final bool focused;

  /// 0–1 se il titolo è stato iniziato.
  final double? progress;
  final VoidCallback? onTap;

  static const textHeight = 46.0;

  @override
  Widget build(BuildContext context) {
    final perf = context.read<PerformanceProfile>();
    final meta = [
      if (item.year != null) '${item.year}',
      if (item.rating != null) '★ ${item.rating!.toStringAsFixed(1)}',
    ].join('  ·  ');
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(7),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: AnimatedScale(
                duration: perf.fast,
                curve: Curves.easeOutCubic,
                scale: focused ? 1.05 : 1,
                child: CustomPaint(
                  foregroundPainter: NeonBorderPainter(
                    radius: 14,
                    width: focused ? 3 : 1,
                    neon: focused,
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Poster(url: item.poster, title: item.title),
                      if (progress != null)
                        Positioned(
                          left: 8,
                          right: 8,
                          bottom: 8,
                          child: _ProgressLine(value: progress!),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            SizedBox(
              height: textHeight,
              child: Padding(
                padding: const EdgeInsets.only(top: 7),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.label.copyWith(
                        color: focused
                            ? Palette.textPrimary
                            : Palette.textSecondary,
                        fontWeight: focused ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        meta,
                        maxLines: 1,
                        style: AppText.label.copyWith(
                          fontSize: 11.5,
                          color: Palette.textTertiary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressLine extends StatelessWidget {
  const _ProgressLine({required this.value});
  final double value;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: SizedBox(
        height: 5,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Color(0x88000000)),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: value.clamp(0.03, 1),
              child: const DecoratedBox(
                decoration: BoxDecoration(gradient: Palette.progress),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Barra di avanzamento più grande (scheda e player).
class ProgressBar extends StatelessWidget {
  const ProgressBar({super.key, required this.value, this.height = 6});
  final double value;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: Colors.white.withValues(alpha: 0.16)),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: value.clamp(0, 1),
              child: const DecoratedBox(
                decoration: BoxDecoration(gradient: Palette.progress),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pulsante a pillola usato in schede e menu (stato di focus gestito da chi
/// lo usa, per la navigazione a indici col telecomando).
class Pill extends StatelessWidget {
  const Pill({
    super.key,
    required this.label,
    required this.focused,
    this.icon,
    this.active = false,
    this.onTap,
    this.primary = false,
    this.compact = false,
  });

  final String label;
  final IconData? icon;
  final bool focused;

  /// Scelta corrente (es. scheda attiva).
  final bool active;
  final bool primary;
  final bool compact;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final perf = context.read<PerformanceProfile>();
    final bg = focused
        ? null
        : primary
        ? Palette.accentDeep.withValues(alpha: 0.55)
        : active
        ? Colors.white.withValues(alpha: 0.16)
        : Colors.white.withValues(alpha: 0.06);
    const fg = Palette.textPrimary;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: perf.fast,
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 14 : 20,
          vertical: compact ? 8 : 11,
        ),
        decoration: BoxDecoration(
          color: bg,
          gradient: focused ? Palette.neon : null,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(
            color: active && !focused
                ? Palette.accent.withValues(alpha: 0.6)
                : Colors.white.withValues(alpha: focused ? 0 : 0.10),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: compact ? 17 : 20, color: fg),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: AppText.label.copyWith(
                color: fg,
                fontSize: compact ? 13 : 14.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tastiera a schermo per la ricerca col telecomando.
class SearchKeyboard extends StatelessWidget {
  const SearchKeyboard({
    super.key,
    required this.focusedIndex,
    required this.onKey,
  });

  /// Indice in [keys], o null se la tastiera non ha il focus.
  final int? focusedIndex;
  final ValueChanged<String> onKey;

  static const columns = 6;
  static const space = ' ';
  static const delete = '⌫';
  static const done = 'OK';

  static final keys = [
    ...'ABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890'.split(''),
    space,
    delete,
    done,
  ];

  /// Spostamento col D-pad sulla griglia dei tasti (null: si esce dal bordo).
  static int? move(int i, int dx, int dy) {
    final n = keys.length;
    final r = i ~/ columns, c = i % columns;
    final nc = c + dx, nr = r + dy;
    if (nc < 0 || nc >= columns || nr < 0) return null;
    final j = nr * columns + nc;
    if (j >= n) return dy > 0 ? (dx == 0 ? n - 1 : null) : null;
    return j;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final w = (box.maxWidth - 4 * (columns - 1)) / columns;
        return Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (var i = 0; i < keys.length; i++)
              GestureDetector(
                onTap: () => onKey(keys[i]),
                child: Container(
                  width: w,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(9),
                    color: focusedIndex == i
                        ? null
                        : Colors.white.withValues(alpha: 0.07),
                    gradient: focusedIndex == i ? Palette.neon : null,
                  ),
                  child: keys[i] == space
                      ? Icon(
                          Icons.space_bar_rounded,
                          size: 18,
                          color: focusedIndex == i
                              ? Palette.textPrimary
                              : Palette.textSecondary,
                        )
                      : Text(
                          keys[i],
                          style: AppText.headline.copyWith(
                            fontSize: 15,
                            color: Palette.textPrimary,
                          ),
                        ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Bordo arrotondato: col focus è un filo neon coi colori del logo.
class NeonBorderPainter extends CustomPainter {
  const NeonBorderPainter({
    required this.radius,
    this.width = 3,
    this.neon = true,
  });

  final double radius;
  final double width;
  final bool neon;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;
    if (neon) {
      p.shader = Palette.neon.createShader(rect);
    } else {
      p.color = Colors.white.withValues(alpha: 0.10);
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.deflate(width / 2), Radius.circular(radius)),
      p,
    );
  }

  @override
  bool shouldRepaint(NeonBorderPainter old) =>
      old.neon != neon || old.width != width || old.radius != radius;
}
