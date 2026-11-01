import 'package:flutter/foundation.dart';

import '../json_utils.dart';

/// Fonte EPG esterna (XMLTV, anche .gz).
@immutable
class EpgSourceConfig {
  const EpgSourceConfig({
    required this.id,
    required this.name,
    required this.url,
  });
  final String id;
  final String name;
  final String url;

  factory EpgSourceConfig.fromJson(Map<String, Object?> j) => EpgSourceConfig(
    id: asString(j['id'], asString(j['url'])),
    name: asString(j['name'], 'EPG'),
    url: asString(j['url']),
  );
}

/// Un canale come deve apparire all'utente: numero, nome, logo, EPG,
/// più le regole per trovarlo nella lista Xtream.
@immutable
class MappedChannel {
  const MappedChannel({
    required this.number,
    required this.name,
    required this.group,
    this.logo,
    this.epgIds = const [],
    this.aliases = const [],
    this.streamIds = const [],
    this.hidden = false,
  });

  final int number;
  final String name;
  final String group;

  /// URL assoluto del logo (già risolto rispetto a `logoBaseUrl`).
  final String? logo;

  /// Id XMLTV (`<channel id="...">`) da usare per la guida.
  final List<String> epgIds;

  /// Nomi alternativi con cui il canale può comparire nella lista del provider.
  final List<String> aliases;

  /// Stream Xtream da usare esplicitamente (ha priorità sui nomi).
  final List<int> streamIds;

  final bool hidden;

  Iterable<String> get allNames sync* {
    yield name;
    yield* aliases;
  }

  static MappedChannel? tryFromJson(Map<String, Object?> j, String? logoBase) {
    final number = asInt(j['number']);
    final name = asNonEmptyString(j['name']);
    if (number == null || name == null) return null;
    final rawLogo = asNonEmptyString(j['logo']);
    String? logo;
    if (rawLogo != null) {
      logo = rawLogo.contains('://') || logoBase == null
          ? rawLogo
          : '$logoBase$rawLogo';
    }
    List<String> strings(Object? v) => v is List
        ? v.map(asString).where((s) => s.isNotEmpty).toList()
        : (v is String && v.isNotEmpty ? [v] : const []);
    final ids = j['streamId'] ?? j['streamIds'];
    return MappedChannel(
      number: number,
      name: name,
      group: asString(j['group'], 'Altri'),
      logo: logo,
      epgIds: strings(j['epgId'] ?? j['epgIds']),
      aliases: strings(j['aliases']),
      streamIds: ids is List
          ? ids.map(asInt).whereType<int>().toList()
          : [?asInt(ids)],
      hidden: asBool(j['hidden']),
    );
  }
}

/// Gruppo di canali creato in automatico dalla lista del provider, per i
/// canali che cambiano spesso (eventi, partite): tutti gli stream che
/// contengono una delle parole chiave, numerati da [startNumber].
@immutable
class DynamicGroup {
  const DynamicGroup({
    required this.name,
    required this.startNumber,
    required this.keywords,
  });

  final String name;
  final int startNumber;

  /// Parole chiave in ordine: prima tutti i canali della prima, poi della
  /// seconda, e così via.
  final List<String> keywords;

  static DynamicGroup? tryFromJson(Map<String, Object?> j) {
    final name = asNonEmptyString(j['name']);
    final start = asInt(j['startNumber']);
    final kw = j['keywords'];
    if (name == null || start == null || kw is! List) return null;
    final keywords = kw
        .map((e) => asString(e).trim().toLowerCase())
        .where((e) => e.isNotEmpty)
        .toList();
    if (keywords.isEmpty) return null;
    return DynamicGroup(name: name, startNumber: start, keywords: keywords);
  }
}

/// Documento di mappatura canali (vedi `assets/channels/sky_italia.json`).
@immutable
class ChannelMapping {
  const ChannelMapping({
    required this.id,
    required this.name,
    required this.revision,
    required this.channels,
    this.epgSources = const [],
    this.showUnmapped = false,
    this.unmappedStartNumber = 1000,
    this.preferredSources = defaultPreferredSources,
    this.dynamicGroups = defaultDynamicGroups,
    this.origin = 'integrata',
  });

  static const supportedSchema = 1;

  /// Fonti preferite quando un canale è disponibile da più stream.
  static const defaultPreferredSources = ['hermes +', 'hermes'];

  /// Canali evento: prima DAZN, poi quelli con "eventi" nel nome, dall'800.
  static const defaultDynamicGroups = [
    DynamicGroup(
      name: 'Eventi',
      startNumber: 800,
      keywords: ['dazn', 'eventi'],
    ),
  ];

  final String id;
  final String name;
  final String revision;
  final List<MappedChannel> channels;
  final List<EpgSourceConfig> epgSources;
  final bool showUnmapped;
  final int unmappedStartNumber;

  /// Etichette di fonte da preferire, in ordine (es. "hermes +"): lo stream
  /// che le contiene nel nome diventa la fonte principale del canale.
  final List<String> preferredSources;

  /// Gruppi automatici (es. "Eventi"), fuori dall'elenco fisso dei canali.
  final List<DynamicGroup> dynamicGroups;

  /// Da dove è stata caricata (integrata, remota, file locale, cache).
  final String origin;

  ChannelMapping withOrigin(String o) => ChannelMapping(
    id: id,
    name: name,
    revision: revision,
    channels: channels,
    epgSources: epgSources,
    showUnmapped: showUnmapped,
    unmappedStartNumber: unmappedStartNumber,
    preferredSources: preferredSources,
    dynamicGroups: dynamicGroups,
    origin: o,
  );

  factory ChannelMapping.fromJson(Map<String, Object?> j) {
    final schema = asInt(j['schemaVersion']) ?? 1;
    if (schema > supportedSchema) {
      throw FormatException(
        'Versione schema $schema non supportata (max $supportedSchema).',
      );
    }
    final base = asNonEmptyString(j['logoBaseUrl']);
    final rawChannels = j['channels'];
    if (rawChannels is! List) {
      throw const FormatException('Campo "channels" mancante.');
    }
    final seen = <int>{};
    final channels = <MappedChannel>[];
    for (final c in rawChannels) {
      if (c is! Map) continue;
      final m = MappedChannel.tryFromJson(c.cast<String, Object?>(), base);
      // Numeri duplicati: vince la prima occorrenza.
      if (m != null && seen.add(m.number)) channels.add(m);
    }
    channels.sort((a, b) => a.number.compareTo(b.number));
    final unmapped = j['unmappedChannels'];
    final sources = j['epgSources'];
    final preferred = j['preferredSources'];
    final dynGroups = j['dynamicGroups'];
    return ChannelMapping(
      id: asString(j['id'], 'custom'),
      name: asString(j['name'], 'Lista personalizzata'),
      revision: asString(j['revision']),
      channels: channels,
      epgSources: sources is List
          ? [
              for (final s in sources)
                if (s is Map)
                  EpgSourceConfig.fromJson(s.cast<String, Object?>()),
            ].where((s) => s.url.isNotEmpty).toList()
          : const [],
      showUnmapped: unmapped is Map && asBool(unmapped['show'] ?? false),
      unmappedStartNumber: unmapped is Map
          ? asInt(unmapped['startNumber']) ?? 1000
          : 1000,
      preferredSources: preferred is List
          ? preferred.map(asString).where((e) => e.isNotEmpty).toList()
          : defaultPreferredSources,
      dynamicGroups: dynGroups is List
          ? [
              for (final g in dynGroups)
                if (g is Map)
                  DynamicGroup.tryFromJson(g.cast<String, Object?>()),
            ].whereType<DynamicGroup>().toList()
          : defaultDynamicGroups,
    );
  }
}
