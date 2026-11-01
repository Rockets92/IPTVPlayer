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
        {
          for (final n in m.allNames)
            if (!n.contains('*')) NameNormalizer.tokens(n).join(' '): n,
        }.keys.where((k) => k.isNotEmpty).map((k) => k.split(' ')).toList(),
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
    // 2) Nome identico (dopo la normalizzazione), anche togliendo l'etichetta
    //    di fonte finale tra parentesi: "Sky Uno FHD ( sat-stella )".
    for (final s in streams) {
      if (assigned.containsKey(s.streamId)) continue;
      final i =
          byKey[NameNormalizer.key(s.name)] ??
          byKey[NameNormalizer.key(NameNormalizer.baseName(s.name))];
      if (i != null) assigned[s.streamId] = i;
    }
    // 2b) Alias con asterisco per i canali che cambiano nome a tema
    //     ("Sky Cinema * Collection" → "Sky Cinema Oscar Collection").
    final patterns = <(RegExp, int)>[
      for (var i = 0; i < visible.length; i++)
        for (final n in visible[i].allNames)
          if (n.contains('*')) (_wildcard(n), i),
    ];
    if (patterns.isNotEmpty) {
      for (final s in streams) {
        if (assigned.containsKey(s.streamId)) continue;
        final t = NameNormalizer.tokens(NameNormalizer.baseName(s.name))
            .join(' ');
        for (final (re, i) in patterns) {
          if (re.hasMatch(t)) {
            assigned[s.streamId] = i;
            break;
          }
        }
      }
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
      for (final t in a.tags) {
        (tagChannels[t] ??= {}).add(a.channel);
      }
    }
    final knownTags = {for (final t in preferredTags) t.join(' ')};
    for (final a in affix) {
      final ok = a.tags.every(
        (t) =>
            knownTags.contains(t) || tagChannels[t]!.length >= minTagChannels,
      );
      if (ok) assigned[a.streamId] = a.channel;
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

    // Gruppi automatici (es. "Eventi" dall'800): stream non già in lista che
    // contengono le parole chiave, una volta sola per evento.
    final dynamicUsed = <int>{};
    for (final g in mapping.dynamicGroups) {
      channels.addAll(
        _dynamicGroup(
          g,
          streams,
          skip: (id) => assigned.containsKey(id) || dynamicUsed.contains(id),
          used: dynamicUsed,
          taken: channels.map((c) => c.number).toSet(),
          preferredTags: preferredTags,
        ),
      );
    }

    if (showUnmapped ?? mapping.showUnmapped) {
      final rest = streams.where(
        (s) =>
            !assigned.containsKey(s.streamId) &&
            !dynamicUsed.contains(s.streamId),
      );
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

  List<Channel> _dynamicGroup(
    DynamicGroup g,
    List<XtreamLiveStream> streams, {
    required bool Function(int streamId) skip,
    required Set<int> used,
    required Set<int> taken,
    required List<List<String>> preferredTags,
  }) {
    // Chiave dell'evento: il nome senza qualità ed etichette di fonte, così
    // "DAZN 1 FHD" e "DAZN 1 ( hermes )" sono lo stesso canale.
    String eventKey(String name) {
      final t = NameNormalizer.tokens(NameNormalizer.baseName(name));
      for (final tag in preferredTags) {
        for (var i = 0; i + tag.length <= t.length; i++) {
          var hit = true;
          for (var j = 0; j < tag.length; j++) {
            if (t[i + j] != tag[j]) {
              hit = false;
              break;
            }
          }
          if (hit) {
            t.removeRange(i, i + tag.length);
            break;
          }
        }
      }
      return t.join(' ');
    }

    final buckets = <String, List<XtreamLiveStream>>{};
    for (final kw in g.keywords) {
      final matches =
          [
            for (final s in streams)
              if (!skip(s.streamId) &&
                  NameNormalizer.fold(s.name).toLowerCase().contains(kw))
                s,
          ]..sort(
            (a, b) =>
                _naturalCompare(_displayName(a.name), _displayName(b.name)),
          );
      for (final s in matches) {
        used.add(s.streamId);
        final k = eventKey(s.name);
        (buckets[k.isEmpty ? 's${s.streamId}' : k] ??= []).add(s);
      }
    }

    final out = <Channel>[];
    var n = g.startNumber;
    for (final MapEntry(key: k, value: list) in buckets.entries) {
      while (taken.contains(n)) {
        n++;
      }
      int rank(XtreamLiveStream s) {
        final p = _preferredRank(s.name, preferredTags);
        return (p < 0 ? 0 : (preferredTags.length - p) * -100) - _score(s.name);
      }

      list.sort((a, b) => rank(a).compareTo(rank(b)));
      final first = list.first;
      out.add(
        Channel(
          id: 'e:$k',
          number: n++,
          name: _displayName(first.name),
          group: g.name,
          logoUrl: list
              .map((s) => s.icon)
              .firstWhere((i) => i != null && i.isNotEmpty, orElse: () => null),
          epgIds: {
            for (final s in list)
              if (s.epgChannelId != null) s.epgChannelId!,
          }.toList(),
          nameKeys: [k.replaceAll(' ', '')],
          sources: [
            for (final s in list)
              ChannelSource(
                streamId: s.streamId,
                label: s.name.trim(),
                preferred: _preferredRank(s.name, preferredTags) >= 0,
              ),
          ],
        ),
      );
    }
    return out;
  }

  /// Nome leggibile senza prefissi, qualità ed etichette di fonte tra
  /// parentesi: "IT: DAZN 1 HEVC ( hermes )" → "DAZN 1".
  static String _displayName(String raw) {
    var s = _clean(NameNormalizer.fold(raw));
    s = s.replaceAll(RegExp(r'[\(\[][^\)\]]*[\)\]]'), ' ');
    s = s.replaceAll(
      RegExp(
        r'\b(?:fhd|uhd|hd|sd|4k|hevc|h\.?26[45]|1080p?|720p?|50fps)\b',
        caseSensitive: false,
      ),
      ' ',
    );
    s = s.replaceAll(RegExp(r'[ᴀ-ᶿʰ-˿⁰-₟]+'), ' ');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    s = s.replaceAll(RegExp(r'^[\-|:•▎\s]+|[\-|:•▎\s]+$'), '');
    return s.isEmpty ? raw.trim() : s;
  }

  /// Ordine "naturale": DAZN 2 prima di DAZN 10.
  static int _naturalCompare(String a, String b) {
    final re = RegExp(r'(\d+)|(\D+)');
    final x = re.allMatches(a.toLowerCase()).toList();
    final y = re.allMatches(b.toLowerCase()).toList();
    for (var i = 0; i < x.length && i < y.length; i++) {
      final p = x[i].group(0)!, q = y[i].group(0)!;
      final np = int.tryParse(p), nq = int.tryParse(q);
      final c = np != null && nq != null ? np.compareTo(nq) : p.compareTo(q);
      if (c != 0) return c;
    }
    return x.length.compareTo(y.length);
  }

  /// "Sky Cinema * Collection" → ^sky cinema(?: \w+)+ collection$
  static RegExp _wildcard(String alias) {
    final raw = alias.split('*');
    final pieces = [for (final p in raw) NameNormalizer.tokens(p).join(' ')]
        .where((p) => p.isNotEmpty)
        .map(RegExp.escape)
        .toList();
    const words = r'(?: [a-z0-9]+)*';
    final lead = alias.trimLeft().startsWith('*') ? r'(?:[a-z0-9]+ )*' : '';
    final tail = alias.trimRight().endsWith('*') ? words : '';
    return RegExp('^$lead${pieces.join('$words ')}$tail\$');
  }

  /// Il nome del canale più lungo contenuto all'inizio o alla fine dello
  /// stream; restituisce (indice canale, etichetta rimanente).
  static (int, List<String>)? _bestAffix(
    List<String> stream,
    List<List<List<String>>> names,
  ) {
    if (stream.length < 2) return null;
    (int, List<String>)? best;
    var bestLen = 0;
    for (var i = 0; i < names.length; i++) {
      for (final n in names[i]) {
        if (n.isEmpty || n.length >= stream.length) continue;
        final len = n.join().length;
        if (len <= bestLen) continue;
        // Il nome del canale può stare all'inizio, alla fine o in mezzo
        // ("CINEMA | SKY CINEMA UNO ( hermes )"): ciò che resta prima e dopo
        // deve essere un'etichetta di fonte o di categoria.
        for (var at = 0; at + n.length <= stream.length; at++) {
          var hit = true;
          for (var j = 0; j < n.length; j++) {
            if (stream[at + j] != n[j]) {
              hit = false;
              break;
            }
          }
          if (!hit) continue;
          final before = stream.sublist(0, at);
          final after = stream.sublist(at + n.length);
          final parts = [
            if (before.isNotEmpty) before,
            if (after.isNotEmpty) after,
          ];
          if (parts.isEmpty || !parts.every(_isSourceTag)) continue;
          bestLen = len;
          best = (i, [for (final p in parts) p.join(' ')]);
          break;
        }
      }
    }
    return best;
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
  const _AffixMatch(this.streamId, this.channel, this.tags);
  final int streamId;
  final int channel;

  /// Etichette prima e/o dopo il nome del canale.
  final List<String> tags;
}
