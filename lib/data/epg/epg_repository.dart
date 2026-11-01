import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path_provider/path_provider.dart';

import '../../core/performance.dart';
import '../../domain/channel.dart';
import 'epg_models.dart';
import 'xmltv_parser.dart';

/// Esito di un aggiornamento EPG, per fonte.
class EpgSourceReport {
  const EpgSourceReport(this.source, {this.channels = 0, this.error});
  final String source;
  final int channels;
  final String? error;
  bool get ok => error == null;
}

/// Scarica, unisce e mette in cache la guida.
///
/// Le fonti vengono lette in ordine: per ogni canale vale la prima fonte
/// che lo copre (le fonti esterne della mappatura hanno priorità, poi
/// l'XMLTV del provider come riempitivo).
class EpgRepository {
  static const cacheTtl = Duration(hours: 10);

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}epg_cache.json');
  }

  Future<EpgSchedule?> loadCache(String signature) async {
    try {
      final f = await _file();
      if (!await f.exists()) return null;
      final path = f.path;
      return await Isolate.run(() => _readCache(path, signature));
    } catch (_) {
      return null;
    }
  }

  static EpgSchedule? _readCache(String path, String signature) {
    final json = jsonDecode(File(path).readAsStringSync());
    if (json is! Map || json['sig'] != signature) return null;
    final fetchedAt = DateTime.fromMillisecondsSinceEpoch(json['fetchedAt'] as int);
    final data = (json['data'] as Map).cast<String, Object?>();
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final map = <String, List<EpgProgramme>>{};
    data.forEach((k, v) {
      final list = [
        for (final p in v as List) EpgProgramme.fromCompact((p as List).cast()),
      ].where((p) => p.end > now - 3 * 3600).toList();
      if (list.isNotEmpty) map[k] = list;
    });
    return EpgSchedule(map, fetchedAt: fetchedAt);
  }

  Future<void> _writeCache(EpgSchedule s, String signature) async {
    try {
      final f = await _file();
      await f.parent.create(recursive: true);
      final path = f.path;
      final data = s.raw;
      final at = s.fetchedAt!.millisecondsSinceEpoch;
      await Isolate.run(() {
        final json = jsonEncode({
          'sig': signature,
          'fetchedAt': at,
          'data': {
            for (final e in data.entries)
              e.key: [for (final p in e.value) p.toCompact()],
          },
        });
        File(path).writeAsStringSync(json, flush: true);
      });
    } catch (_) {}
  }

  static XmltvRequest _request(
    List<Channel> channels,
    PerformanceProfile perf,
    Set<String> skip,
  ) {
    final idIndex = <String, List<String>>{};
    final nameIndex = <String, List<String>>{};
    for (final c in channels) {
      for (final id in c.epgIds) {
        (idIndex[id.toLowerCase()] ??= []).add(c.id);
      }
      for (final k in c.nameKeys) {
        (nameIndex[k] ??= []).add(c.id);
      }
    }
    final now = DateTime.now();
    return XmltvRequest(
      idIndex: idIndex,
      nameIndex: nameIndex,
      windowStart: now.subtract(perf.epgBehind).millisecondsSinceEpoch ~/ 1000,
      windowEnd: now.add(perf.epgAhead).millisecondsSinceEpoch ~/ 1000,
      maxDescription: perf.epgMaxDescription,
      skip: skip,
    );
  }

  Future<(EpgSchedule, List<EpgSourceReport>)> fetch({
    required List<String> sources,
    required List<Channel> channels,
    required PerformanceProfile perf,
    required String signature,
    void Function(String message)? onProgress,
  }) async {
    final merged = <String, List<EpgProgramme>>{};
    final reports = <EpgSourceReport>[];
    for (var i = 0; i < sources.length; i++) {
      final src = sources[i];
      onProgress?.call('Guida TV: fonte ${i + 1} di ${sources.length}');
      final req = _request(channels, perf, merged.keys.toSet());
      try {
        final part = await Isolate.run(() => fetchAndParseXmltv(src, req));
        merged.addAll(part);
        reports.add(EpgSourceReport(src, channels: part.length));
      } catch (e) {
        reports.add(EpgSourceReport(src, error: e.toString()));
      }
      // Tutti i canali coperti: inutile scaricare altro.
      if (merged.length >= channels.length) break;
    }
    final schedule = EpgSchedule(merged, fetchedAt: DateTime.now());
    if (merged.isNotEmpty) await _writeCache(schedule, signature);
    return (schedule, reports);
  }
}
