import '../data/mapping/channel_mapping.dart';
import '../data/xtream/xtream_models.dart';
import 'channel.dart';
import 'name_normalizer.dart';

/// Unisce la lista del provider con la mappatura dell'utente:
/// ordine e numerazione dalla mappatura, stream dal provider.
class ChannelMatcher {
  const ChannelMatcher({this.preferLighterStreams = false});

  final bool preferLighterStreams;

  List<Channel> build({
    required ChannelMapping mapping,
    required List<XtreamLiveStream> streams,
    Map<String, String> categoryNames = const {},
    bool? showUnmapped,
  }) {
    final byKey = <String, List<XtreamLiveStream>>{};
    final byId = <int, XtreamLiveStream>{};
    for (final s in streams) {
      byId[s.streamId] = s;
      final k = NameNormalizer.key(s.name);
      if (k.isNotEmpty) (byKey[k] ??= []).add(s);
    }

    final used = <int>{};
    final channels = <Channel>[];

    for (final m in mapping.channels) {
      if (m.hidden) continue;
      final picked = <XtreamLiveStream>[];
      for (final id in m.streamIds) {
        final s = byId[id];
        if (s != null) picked.add(s);
      }
      final keys = <String>{for (final n in m.allNames) NameNormalizer.key(n)}
        ..remove('');
      final candidates = <XtreamLiveStream>[
        for (final k in keys) ...?byKey[k],
      ];
      candidates.sort(
        (a, b) => _score(b.name).compareTo(_score(a.name)),
      );
      for (final c in candidates) {
        if (!picked.contains(c)) picked.add(c);
      }
      // Canale non presente nel provider: non lo si mostra, così lo zapping
      // non incontra "buchi" (la numerazione resta comunque quella scelta).
      if (picked.isEmpty) continue;
      used.addAll(picked.map((s) => s.streamId));

      final providerEpg = {
        for (final s in picked)
          if (s.epgChannelId != null) s.epgChannelId!,
      };
      channels.add(
        Channel(
          id: 'm${m.number}',
          number: m.number,
          name: m.name,
          group: m.group,
          logoUrl: m.logo ?? picked.first.icon,
          epgIds: [...m.epgIds, ...providerEpg.where((e) => !m.epgIds.contains(e))],
          nameKeys: keys.toList(),
          sources: [
            for (final s in picked)
              ChannelSource(streamId: s.streamId, label: s.name),
          ],
        ),
      );
    }

    if (showUnmapped ?? mapping.showUnmapped) {
      final rest = streams.where((s) => !used.contains(s.streamId)).toList();
      final taken = channels.map((c) => c.number).toSet();
      var n = mapping.unmappedStartNumber;
      for (final s in rest) {
        while (taken.contains(n)) {
          n++;
        }
        final key = NameNormalizer.key(s.name);
        channels.add(
          Channel(
            id: 's${s.streamId}',
            number: n++,
            name: _clean(s.name),
            group: categoryNames[s.categoryId] ?? 'Altri canali',
            logoUrl: s.icon,
            epgIds: [?s.epgChannelId],
            nameKeys: [if (key.isNotEmpty) key],
            sources: [ChannelSource(streamId: s.streamId, label: s.name)],
            mapped: false,
          ),
        );
      }
    }
    return channels;
  }

  int _score(String name) =>
      NameNormalizer.qualityScore(name, preferLighter: preferLighterStreams);

  /// Rimuove prefissi tecnici dai nomi non mappati ("IT: ", "|IT| ").
  static String _clean(String name) {
    final s = name.replaceFirst(
      RegExp(r'^\s*(?:[\[\(|]\s*)?(?:it|ita)\s*(?:[\]\)|:\-]\s*)+', caseSensitive: false),
      '',
    );
    return s.trim().isEmpty ? name.trim() : s.trim();
  }
}
