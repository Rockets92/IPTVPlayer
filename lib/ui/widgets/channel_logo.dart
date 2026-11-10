import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/performance.dart';
import '../../core/theme.dart';
import '../../data/mapping/channel_mapping.dart';
import '../../domain/channel.dart';

/// Logo canale su tessera scura. Se il logo manca o non si carica,
/// mostra un monogramma tipografico (mai un'icona generica).
class ChannelLogo extends StatelessWidget {
  const ChannelLogo({
    super.key,
    required this.channel,
    this.width = 64,
    this.height = 44,
    this.radius = 12,
    this.padding = 7,
    this.tile = true,
  });

  final Channel channel;
  final double width;
  final double height;
  final double radius;
  final double padding;
  final bool tile;

  @override
  Widget build(BuildContext context) {
    final perf = context.read<PerformanceProfile>();
    final url = channel.logoUrl;
    final mono = _Monogram(name: channel.name, size: height);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final decodeW = (width * dpr).clamp(48, perf.logoDecodeWidth).round();

    final asset = assetLogoPath(url);
    final Widget img = url == null
        ? mono
        : asset != null
        ? Image.asset(
            asset,
            cacheWidth: decodeW,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, _, _) => mono,
          )
        : CachedNetworkImage(
            imageUrl: url,
            memCacheWidth: decodeW,
            fit: BoxFit.contain,
            fadeInDuration: perf.fast,
            fadeOutDuration: Duration.zero,
            placeholder: (_, _) => Opacity(opacity: 0.35, child: mono),
            errorWidget: (_, _, _) => mono,
            filterQuality: FilterQuality.medium,
          );

    return SizedBox(
      width: width,
      height: height,
      child: tile
          ? DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(radius),
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x1FFFFFFF), Color(0x0AFFFFFF)],
                ),
                border: Border.all(color: const Color(0x1AFFFFFF)),
              ),
              child: Padding(padding: EdgeInsets.all(padding), child: img),
            )
          : img,
    );
  }
}

class _Monogram extends StatelessWidget {
  const _Monogram({required this.name, required this.size});
  final String name;
  final double size;

  String get _letters {
    final words = name
        .split(RegExp(r'[\s\-_.]+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return '·';
    if (words.length == 1) {
      final w = words.first;
      return w.length <= 3 ? w.toUpperCase() : w.substring(0, 2).toUpperCase();
    }
    final a = words[0][0];
    final last = words.last;
    // "Sky Sport 24" → "S24", "Rai 1" → "R1"
    final b = RegExp(r'^\d+$').hasMatch(last) ? last : last[0];
    return (a + b).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FittedBox(
        child: Text(
          _letters,
          maxLines: 1,
          style: AppText.title.copyWith(
            fontSize: size * 0.42,
            color: Palette.textSecondary,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}
