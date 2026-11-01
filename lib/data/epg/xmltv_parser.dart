import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:xml/xml_events.dart';

import '../../domain/name_normalizer.dart';
import 'epg_models.dart';

/// Parametri di parsing: quali canali interessano e quale finestra temporale.
///
/// Tutti i campi sono tipi semplici, così la richiesta può essere passata
/// a un isolate.
class XmltvRequest {
  const XmltvRequest({
    required this.idIndex,
    required this.nameIndex,
    required this.windowStart,
    required this.windowEnd,
    this.maxDescription = 600,
    this.skip = const {},
  });

  /// id XMLTV (minuscolo) → id canali dell'app.
  final Map<String, List<String>> idIndex;

  /// chiave nome normalizzata → id canali dell'app (fallback su display-name).
  final Map<String, List<String>> nameIndex;

  final int windowStart;
  final int windowEnd;
  final int maxDescription;

  /// Canali già coperti da una fonte precedente.
  final Set<String> skip;
}

/// Converte `20261101153000 +0100` in secondi epoch UTC.
int? parseXmltvTime(String raw) {
  final s = raw.trim();
  if (s.length < 12) return null;
  int? n(int a, int b) => int.tryParse(s.substring(a, b));
  final y = n(0, 4), mo = n(4, 6), d = n(6, 8), h = n(8, 10), mi = n(10, 12);
  if (y == null || mo == null || d == null || h == null || mi == null) {
    return null;
  }
  var idx = 12;
  var sec = 0;
  if (s.length >= 14) {
    final v = n(12, 14);
    if (v != null) {
      sec = v;
      idx = 14;
    }
  }
  var t = DateTime.utc(y, mo, d, h, mi, sec).millisecondsSinceEpoch ~/ 1000;
  final tz = s.substring(idx).trim();
  final m = RegExp(r'^([+-])(\d{2}):?(\d{2})').firstMatch(tz);
  if (m != null) {
    final sign = m.group(1) == '-' ? -1 : 1;
    final off = int.parse(m.group(2)!) * 3600 + int.parse(m.group(3)!) * 60;
    t -= sign * off;
  }
  return t;
}

/// Decomprime al volo se il flusso è gzip (magic 1f 8b), indipendentemente
/// dall'estensione o dagli header.
Stream<List<int>> maybeGunzip(Stream<List<int>> input) async* {
  final it = StreamIterator(input);
  if (!await it.moveNext()) return;
  final head = it.current;
  Stream<List<int>> rest() async* {
    yield head;
    while (await it.moveNext()) {
      yield it.current;
    }
  }

  if (head.length >= 2 && head[0] == 0x1f && head[1] == 0x8b) {
    yield* rest().transform(gzip.decoder);
  } else {
    yield* rest();
  }
}

/// Parser XMLTV in streaming: memoria costante rispetto alla dimensione del
/// file, conserva solo i programmi dei canali richiesti nella finestra.
Future<Map<String, List<EpgProgramme>>> parseXmltv(
  Stream<List<int>> bytes,
  XmltvRequest req,
) async {
  final out = <String, List<EpgProgramme>>{};

  // Fase canali: raccolta di <channel id> + display-name.
  final xmlChannels = <(String, List<String>)>[];
  String? chId;
  List<String>? chNames;

  Map<String, List<String>>? resolved;
  Map<String, List<String>> resolve() {
    final map = <String, List<String>>{};
    final claimed = <String>{};
    for (final (id, _) in xmlChannels) {
      final targets = req.idIndex[id.toLowerCase()];
      if (targets == null) continue;
      final t = targets.where((c) => !req.skip.contains(c)).toList();
      if (t.isEmpty) continue;
      map[id] = t;
      claimed.addAll(t);
    }
    for (final (id, names) in xmlChannels) {
      if (map.containsKey(id)) continue;
      for (final n in names) {
        final targets = req.nameIndex[NameNormalizer.key(n)];
        if (targets == null) continue;
        final t = targets
            .where((c) => !claimed.contains(c) && !req.skip.contains(c))
            .toList();
        if (t.isEmpty) continue;
        map[id] = t;
        claimed.addAll(t);
        break;
      }
    }
    return map;
  }

  // Stato del programma corrente.
  List<String>? targets;
  int start = 0, end = 0;
  String? title, desc, category;
  String? capturing; // 'title' | 'desc' | 'category' | 'display-name'
  final text = StringBuffer();

  await for (final e
      in maybeGunzip(bytes)
          .transform(const Utf8Decoder(allowMalformed: true))
          .toXmlEvents()
          .flatten()) {
    if (e is XmlStartElementEvent) {
      switch (e.name) {
        case 'channel':
          chId = _attr(e, 'id');
          chNames = [];
        case 'display-name':
          if (chId != null) {
            capturing = 'display-name';
            text.clear();
          }
        case 'programme':
          resolved ??= resolve();
          final ch = _attr(e, 'channel');
          final s = parseXmltvTime(_attr(e, 'start') ?? '');
          final st = parseXmltvTime(_attr(e, 'stop') ?? '');
          targets = null;
          if (ch == null || s == null) break;
          final stop = st ?? s + 3600;
          if (stop < req.windowStart || s > req.windowEnd) break;
          var t = resolved[ch];
          if (t == null) {
            final direct = req.idIndex[ch.toLowerCase()];
            if (direct != null) {
              t = direct.where((c) => !req.skip.contains(c)).toList();
            }
          }
          if (t == null || t.isEmpty) break;
          targets = t;
          start = s;
          end = stop;
          title = desc = category = null;
        case 'title' || 'desc' || 'category':
          if (targets != null) {
            final already = switch (e.name) {
              'title' => title != null,
              'desc' => desc != null,
              _ => category != null,
            };
            if (!already && !e.isSelfClosing) {
              capturing = e.name;
              text.clear();
            }
          }
      }
    } else if (e is XmlTextEvent) {
      if (capturing != null) text.write(e.value);
    } else if (e is XmlCDATAEvent) {
      if (capturing != null) text.write(e.value);
    } else if (e is XmlEndElementEvent) {
      switch (e.name) {
        case 'display-name':
          if (capturing == 'display-name') {
            final v = text.toString().trim();
            if (v.isNotEmpty) chNames?.add(v);
            capturing = null;
          }
        case 'channel':
          if (chId != null) xmlChannels.add((chId, chNames ?? const []));
          chId = null;
          chNames = null;
        case 'title' || 'desc' || 'category':
          if (capturing == e.name) {
            final v = text.toString().trim();
            capturing = null;
            if (v.isEmpty) break;
            if (e.name == 'title') {
              title = v;
            } else if (e.name == 'desc') {
              desc = v.length > req.maxDescription
                  ? '${v.substring(0, req.maxDescription).trimRight()}…'
                  : v;
            } else {
              category = v;
            }
          }
        case 'programme':
          final t = targets;
          if (t != null && title != null) {
            final p = EpgProgramme(
              start: start,
              end: end,
              title: title,
              description: desc,
              category: category,
            );
            for (final c in t) {
              (out[c] ??= []).add(p);
            }
          }
          targets = null;
      }
    }
  }

  for (final list in out.values) {
    list.sort((a, b) => a.start.compareTo(b.start));
    // Rimuove duplicati e sovrapposizioni dovute a più fonti per lo stesso canale.
    var w = 0;
    for (var r = 0; r < list.length; r++) {
      if (w > 0 && list[r].start < list[w - 1].end) {
        if (list[r].start == list[w - 1].start) continue;
      }
      list[w++] = list[r];
    }
    list.length = w;
  }
  return out;
}

String? _attr(XmlStartElementEvent e, String name) {
  for (final a in e.attributes) {
    if (a.name == name) return a.value;
  }
  return null;
}

/// Scarica (o legge da file) e analizza una fonte XMLTV. Pensata per
/// essere eseguita in un isolate.
Future<Map<String, List<EpgProgramme>>> fetchAndParseXmltv(
  String source,
  XmltvRequest req,
) async {
  if (!source.startsWith('http://') && !source.startsWith('https://')) {
    final path = source.startsWith('file://')
        ? Uri.parse(source).toFilePath()
        : source;
    return parseXmltv(File(path).openRead(), req);
  }
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15)
    ..userAgent = 'IPTVPlayer/0.1';
  try {
    final request = await client.getUrl(Uri.parse(source));
    final response = await request.close().timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw HttpException(
        'HTTP ${response.statusCode}',
        uri: Uri.parse(source),
      );
    }
    return await parseXmltv(response, req);
  } finally {
    client.close(force: true);
  }
}
