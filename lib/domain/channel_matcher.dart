import '../data/mapping/channel_mapping.dart';
import '../data/xtream/xtream_models.dart';
import 'channel.dart';
import 'name_normalizer.dart';

/// Unisce la lista del provider con la mappatura dell'utente:
/// ordine e numerazione dalla mappatura, stream dal provider.
///
/// Ogni canale della lista compare una sola volta, come su un decoder: tutti
/// gli stream del provider che lo rappresentano (qualità diverse, copie con
/// etichette di fonte tipo "HERMES + SKY UNO") diventano fonti alternative
/// dello stesso canale.
class ChannelMatcher {
  const ChannelMatcher({this.preferLighterStreams = false});

  final bool preferLighterStreams;

  /// Un'etichetta di fonte sconosciuta viene riconosciuta come tale solo se
  /// accompagna almeno questo numero di canali diversi della lista.
  static const minTagChannels = 3;

  List<Channel> build({
    required ChannelMapping mapping,
    required List<XtreamLiveStream> streams,
    Map<String, String> categoryNames = const {},
    bool? showUnmapped,
  }) {
    final visible = mapping.channels.where((m) => !m.hidden).toList();
    final byId = <int, XtreamLiveStream>{
      for (final s in streams) s.streamId: s,
    };
    final preferredTags = [
      for (final t in mapping.preferredSources) NameNormalizer.tokens(t),
    ].where((t) => t.isNotEmpty).toList();

    // Nomi del canale in forma di token: ["sky", "cinema", "uno"].
    final names = <List<List<String>>>[
      for (final m in visible)
        {for (final n in m.allNames) NameNormalizer.tokens(n).join(' '): n}.keys
            .where((k) => k.isNotEmpty)
            .map((k) => k.split(' '))
            .toList(),
    ];
    final byKey = <String, int>{};
    for (var i = 0; i < visible.length; i++) {
      for (final t in names[i]) {
        byKey.putIfAbsent(t.join(), () => i);
      }
    }

    final assigned = <int, int>{}; // streamId -> indice canale
    // 1) Stream indicati esplicitamente nella lista.
    for (var i = 0; i < visible.length; i++) {
      for (final id in visible[i].streamIds) {
        if (byId.containsKey(id)) assigned.putIfAbsent(id, () => i);
      }
    }
    // 2) Nome identico (dopo la normalizzazione).
    for (final s in streams) {
      if (assigned.containsKey(s.streamId)) continue;
      final i = byKey[NameNormalizer.key(s.name)];
      if (i != null) assigned[s.streamId] = i;
    }
    // 3) Nome del canale più un'etichetta di fonte prima o dopo
    //    ("HERMES + SKY UNO", "SKY UNO | BACKUP 2"...).
    final affix = <_AffixMatch>[];
    for (final s in streams) {
      if (assigned.containsKey(s.streamId)) continue;
      final m = _bestAffix(NameNormalizer.tokens(s.name), names);
      if (m != null) affix.add(_AffixMatch(s.streamId, m.$1, m.$2));
    }
    final tagChannels = <String, Set<int>>{};
    for (final a in affix) {
      (tagChannels[a.tag] ??= {}).add(a.channel);
    }
    for (final a in affix) {
      final known = preferredTags.any((t) => t.join(' ') == a.tag);
      if (known || tagChannels[a.tag]!.length >= minTagChannels) {
        assigned[a.streamId] = a.channel;
      }
    }

    final perChannel = <int, List<XtreamLiveStream>>{};
    for (final s in streams) {
      final i = assigned[s.streamId];
      if (i != null) (perChannel[i] ??= []).add(s);
    }

    final channels = <Channel>[];
    for (var i = 0; i < visible.length; i++) {
      final m = visible[i];
      final picked = perChannel[i];
      // Canale non presente nel provider: non lo si mostra, così lo zapping
      // non incontra "buchi" (la numerazione resta comunque quella scelta).
      if (picked == null || picked.isEmpty) continue;
      final explicit = m.streamIds;
      int rank(XtreamLiveStream s) {
        final e = explicit.indexOf(s.streamId);
        if (e >= 0) return -1000 + e;
        final p = _preferredRank(s.name, preferredTags);
        return (p < 0 ? 0 : (preferredTags.length - p) * -100) - _score(s.name);
      }

      picked.sort((a, b) => rank(a).compareTo(rank(b)));

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
          epgIds: [
            ...m.epgIds,
            ...providerEpg.where((e) => !m.epgIds.contains(e)),
          ],
          nameKeys: [for (final t in names[i]) t.join()],
          sources: [
            for (final s in picked)
              ChannelSource(
                streamId: s.streamId,
                label: s.name.trim(),
                preferred: _preferredRank(s.name, preferredTags) >= 0,
              ),
          ],
        ),
      );
    }

    if (showUnmapped ?? mapping.showUnmapped) {
      final rest = streams.where((s) => !assigned.containsKey(s.streamId));
      final taken = channels.map((c) => c.number).toSet();
      final seen = <String>{};
      var n = mapping.unmappedStartNumber;
      for (final s in rest) {
        final key = NameNormalizer.key(s.name);
        // Anche fuori lista un canale compare una volta sola.
        if (key.isNotEmpty && !seen.add(key)) continue;
        while (taken.contains(n)) {
          n++;
        }
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

  /// Il nome del canale più lungo contenuto all'inizio o alla fine dello
  /// stream; restituisce (indice canale, etichetta rimanente).
  static (int, String)? _bestAffix(
    List<String> stream,
    List<List<List<String>>> names,
  ) {
    if (stream.length < 2) return null;
    (int, String)? best;
    var bestLen = 0;
    for (var i = 0; i < names.length; i++) {
      for (final n in names[i]) {
        if (n.length >= stream.length || n.length < bestLen) continue;
        List<String>? rest;
        if (_startsWith(stream, n)) {
          rest = stream.sublist(n.length);
        } else if (_startsWith(stream.reversed.toList(), n.reversed.toList())) {
          rest = stream.sublist(0, stream.length - n.length);
        }
        if (rest == null || !_isSourceTag(rest)) continue;
        final len = n.join().length;
        if (len > bestLen) {
          bestLen = len;
          best = (i, rest.join(' '));
        }
      }
    }
    return best;
  }

  static bool _startsWith(List<String> a, List<String> b) {
    for (var i = 0; i < b.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Un'etichetta di fonte contiene parole, non numeri: così "+1", "2" o
  /// "24" restano canali diversi ("Sky Uno +1" non diventa "Sky Uno").
  static bool _isSourceTag(List<String> rest) {
    var word = false;
    for (final t in rest) {
      if (RegExp(r'\d').hasMatch(t)) return false;
      if (t != 'plus' && t != 'and') word = true;
    }
    return word;
  }

  /// Posizione della prima etichetta preferita contenuta nel nome, o -1.
  static int _preferredRank(String name, List<List<String>> tags) {
    final t = NameNormalizer.tokens(name);
    for (var i = 0; i < tags.length; i++) {
      if (_contains(t, tags[i])) return i;
    }
    return -1;
  }

  static bool _contains(List<String> hay, List<String> needle) {
    for (var i = 0; i + needle.length <= hay.length; i++) {
      var ok = true;
      for (var j = 0; j < needle.length; j++) {
        if (hay[i + j] != needle[j]) {
          ok = false;
          break;
        }
      }
      if (ok) return true;
    }
    return false;
  }

  int _score(String name) =>
      NameNormalizer.qualityScore(name, preferLighter: preferLighterStreams);

  /// Rimuove prefissi tecnici dai nomi non mappati ("IT: ", "|IT| ").
  static String _clean(String name) {
    final s = name.replaceFirst(
      RegExp(
        r'^\s*(?:[\[\(|]\s*)?(?:it|ita)\s*(?:[\]\)|:\-]\s*)+',
        caseSensitive: false,
      ),
      '',
    );
    return s.trim().isEmpty ? name.trim() : s.trim();
  }
}

class _AffixMatch {
  const _AffixMatch(this.streamId, this.channel, this.tag);
  final int streamId;
  final int channel;
  final String tag;
}
