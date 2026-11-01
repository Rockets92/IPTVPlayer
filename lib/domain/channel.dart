import 'package:flutter/foundation.dart';

/// Uno stream Xtream utilizzabile per un canale.
@immutable
class ChannelSource {
  const ChannelSource({
    required this.streamId,
    required this.label,
    this.preferred = false,
  });
  final int streamId;

  /// Nome originale nel provider: è quello che l'utente vede nella scelta
  /// della fonte.
  final String label;

  /// Fonte indicata come preferita dalla lista (es. "hermes +").
  final bool preferred;

  /// Qualità dichiarata nel nome dello stream.
  String? get quality {
    final n = label.toUpperCase();
    if (n.contains('4K') || n.contains('UHD')) return '4K';
    if (n.contains('FHD') || n.contains('1080')) return 'FHD';
    if (RegExp(r'\bHD\b').hasMatch(n) || n.contains('720')) return 'HD';
    if (RegExp(r'\bSD\b').hasMatch(n)) return 'SD';
    return null;
  }
}

/// Canale pronto per la visione, già ordinato e numerato.
@immutable
class Channel {
  const Channel({
    required this.id,
    required this.number,
    required this.name,
    required this.group,
    required this.sources,
    this.logoUrl,
    this.epgIds = const [],
    this.nameKeys = const [],
    this.mapped = true,
  });

  /// Identificativo stabile: `m<numero>` per i mappati, `s<streamId>` per gli altri.
  final String id;
  final int number;
  final String name;
  final String group;
  final String? logoUrl;

  /// Id XMLTV da cercare nelle guide, in ordine di priorità.
  final List<String> epgIds;

  /// Chiavi normalizzate del nome, per associare la guida tramite display-name.
  final List<String> nameKeys;

  /// Stream disponibili, dal migliore al peggiore (failover automatico).
  final List<ChannelSource> sources;

  final bool mapped;

  bool get playable => sources.isNotEmpty;

  /// Etichetta di qualità derivata dal nome dello stream principale.
  String? get qualityBadge {
    if (sources.isEmpty) return null;
    final q = sources.first.quality;
    return q == 'SD' ? null : q;
  }
}
