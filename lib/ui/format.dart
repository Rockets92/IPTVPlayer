import 'package:intl/intl.dart';

final _hm = DateFormat('HH:mm', 'it_IT');
final _day = DateFormat('EEEE d MMMM', 'it_IT');
final _dayShort = DateFormat('EEE d MMM', 'it_IT');

String hm(DateTime t) => _hm.format(t);

String dayLong(DateTime t) => _day.format(t);

String dayShort(DateTime t) => _dayShort.format(t);

String timeRange(DateTime a, DateTime b) => '${hm(a)} – ${hm(b)}';

/// "mancano 42 min", "mancano 1 h 05".
String remaining(Duration d) {
  final m = (d.inSeconds / 60).ceil();
  if (m <= 1) return 'ultimo minuto';
  if (m < 60) return 'mancano $m min';
  final h = m ~/ 60;
  final r = m % 60;
  return 'mancano $h h ${r.toString().padLeft(2, '0')}';
}

String durationLabel(Duration d) {
  final m = d.inMinutes;
  if (m < 60) return '$m min';
  final h = m ~/ 60;
  final r = m % 60;
  return r == 0 ? '$h h' : '$h h ${r.toString().padLeft(2, '0')}';
}

/// Giorno relativo per la guida: "Oggi", "Domani", altrimenti data breve.
String relativeDay(DateTime t, DateTime now) {
  final a = DateTime(t.year, t.month, t.day);
  final b = DateTime(now.year, now.month, now.day);
  final diff = a.difference(b).inDays;
  if (diff == 0) return 'Oggi';
  if (diff == 1) return 'Domani';
  if (diff == -1) return 'Ieri';
  return dayShort(t);
}
