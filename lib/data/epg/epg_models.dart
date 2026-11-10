import 'package:flutter/foundation.dart';

/// Un programma in guida. Orari in secondi epoch UTC per tenere basso
/// l'ingombro in memoria (decine di migliaia di istanze sui box da 1 GB).
@immutable
class EpgProgramme {
  const EpgProgramme({
    required this.start,
    required this.end,
    required this.title,
    this.description,
    this.category,
  });

  final int start;
  final int end;
  final String title;
  final String? description;
  final String? category;

  DateTime get startTime => DateTime.fromMillisecondsSinceEpoch(start * 1000);
  DateTime get endTime => DateTime.fromMillisecondsSinceEpoch(end * 1000);
  Duration get duration => Duration(seconds: end - start);

  bool isLiveAt(int epochSeconds) =>
      start <= epochSeconds && epochSeconds < end;

  double progressAt(DateTime now) {
    final t = now.millisecondsSinceEpoch / 1000;
    if (end <= start) return 0;
    return ((t - start) / (end - start)).clamp(0.0, 1.0);
  }

  Duration remainingAt(DateTime now) {
    final s = end - now.millisecondsSinceEpoch ~/ 1000;
    return Duration(seconds: s < 0 ? 0 : s);
  }

  List<Object?> toCompact() => [start, end, title, description, category];

  static EpgProgramme fromCompact(List<Object?> c) => EpgProgramme(
    start: c[0] as int,
    end: c[1] as int,
    title: c[2] as String,
    description: c.length > 3 ? c[3] as String? : null,
    category: c.length > 4 ? c[4] as String? : null,
  );
}

/// Guida completa indicizzata per id canale dell'app.
class EpgSchedule {
  EpgSchedule(this._byChannel, {DateTime? fetchedAt})
    : fetchedAt = fetchedAt ?? DateTime.now();

  EpgSchedule.empty() : _byChannel = const {}, fetchedAt = null;

  final Map<String, List<EpgProgramme>> _byChannel;
  final DateTime? fetchedAt;

  bool get isEmpty => _byChannel.isEmpty;
  int get channelCount => _byChannel.length;
  int get programmeCount =>
      _byChannel.values.fold(0, (sum, list) => sum + list.length);

  bool has(String channelId) => _byChannel[channelId]?.isNotEmpty ?? false;

  List<EpgProgramme> forChannel(String channelId) =>
      _byChannel[channelId] ?? const [];

  Map<String, List<EpgProgramme>> get raw => _byChannel;

  /// Indice del programma in onda (ricerca binaria) o -1.
  int _indexAt(List<EpgProgramme> list, int t) {
    var lo = 0, hi = list.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final p = list[mid];
      if (p.end <= t) {
        lo = mid + 1;
      } else if (p.start > t) {
        hi = mid - 1;
      } else {
        return mid;
      }
    }
    return -1;
  }

  EpgProgramme? nowOn(String channelId, DateTime at) {
    final list = _byChannel[channelId];
    if (list == null || list.isEmpty) return null;
    final i = _indexAt(list, at.millisecondsSinceEpoch ~/ 1000);
    return i < 0 ? null : list[i];
  }

  EpgProgramme? nextOn(String channelId, DateTime at) {
    final list = _byChannel[channelId];
    if (list == null || list.isEmpty) return null;
    final t = at.millisecondsSinceEpoch ~/ 1000;
    for (final p in list) {
      if (p.start > t) return p;
    }
    return null;
  }

  /// Indice del programma in onda, altrimenti del primo successivo
  /// (o dell'ultimo se la guida è tutta nel passato); -1 se non c'è guida.
  int indexNear(String channelId, DateTime at) {
    final list = _byChannel[channelId];
    if (list == null || list.isEmpty) return -1;
    final t = at.millisecondsSinceEpoch ~/ 1000;
    final i = _indexAt(list, t);
    if (i >= 0) return i;
    final next = list.indexWhere((p) => p.start > t);
    return next >= 0 ? next : list.length - 1;
  }

  /// Nuova guida con i programmi di [channelId] sostituiti (es. short EPG).
  EpgSchedule withChannel(String channelId, List<EpgProgramme> programmes) {
    final copy = Map<String, List<EpgProgramme>>.of(_byChannel);
    copy[channelId] = programmes;
    return EpgSchedule(copy, fetchedAt: fetchedAt);
  }
}
