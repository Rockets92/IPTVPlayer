import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/epg/epg_models.dart';
import '../domain/channel.dart';

/// Un programma futuro "prenotato" dall'utente.
@immutable
class Reminder {
  const Reminder({
    required this.channelId,
    required this.channelNumber,
    required this.channelName,
    required this.title,
    required this.start,
  });

  final String channelId;
  final int channelNumber;
  final String channelName;
  final String title;

  /// Inizio del programma, secondi epoch.
  final int start;

  DateTime get startTime => DateTime.fromMillisecondsSinceEpoch(start * 1000);

  String get key => '$channelId@$start';

  Map<String, Object?> toJson() => {
    'c': channelId,
    'n': channelNumber,
    'name': channelName,
    't': title,
    's': start,
  };

  static Reminder? fromJson(Object? j) {
    if (j is! Map) return null;
    final c = j['c'], s = j['s'];
    if (c is! String || s is! int) return null;
    return Reminder(
      channelId: c,
      channelNumber: (j['n'] as num?)?.toInt() ?? 0,
      channelName: j['name']?.toString() ?? '',
      title: j['t']?.toString() ?? '',
      start: s,
    );
  }
}

/// Promemoria dei programmi: si prenotano dalla guida o dal banner e cinque
/// minuti prima dell'inizio compare un avviso per passare al canale.
class ReminderController extends ChangeNotifier {
  ReminderController(this._prefs) {
    _load();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _check());
    _check();
  }

  static const lead = Duration(minutes: 5);
  static const _key = 'reminders.v1';

  final SharedPreferences _prefs;
  final List<Reminder> _items = [];
  Timer? _timer;

  /// Promemoria da mostrare adesso (uno alla volta).
  Reminder? due;

  List<Reminder> get items => List.unmodifiable(_items);

  bool isSet(String channelId, EpgProgramme p) =>
      _items.any((r) => r.channelId == channelId && r.start == p.start);

  /// Prenota o cancella; restituisce true se ora il promemoria è attivo.
  bool toggle(Channel c, EpgProgramme p) {
    final i = _items.indexWhere(
      (r) => r.channelId == c.id && r.start == p.start,
    );
    if (i >= 0) {
      _items.removeAt(i);
      _save();
      notifyListeners();
      return false;
    }
    if (p.startTime.isBefore(DateTime.now())) return false;
    _items
      ..add(
        Reminder(
          channelId: c.id,
          channelNumber: c.number,
          channelName: c.name,
          title: p.title,
          start: p.start,
        ),
      )
      ..sort((a, b) => a.start.compareTo(b.start));
    _save();
    notifyListeners();
    _check();
    return true;
  }

  /// L'utente ha risposto all'avviso (vai o annulla): non si ripropone.
  void resolve() {
    final d = due;
    if (d == null) return;
    _items.removeWhere((r) => r.key == d.key);
    due = null;
    _save();
    notifyListeners();
    _check();
  }

  void _check() {
    final now = DateTime.now();
    final d = due;
    if (d != null) {
      // Nessuna risposta e programma ormai avanzato: l'avviso sparisce.
      if (d.startTime.add(const Duration(minutes: 10)).isBefore(now)) {
        resolve();
      }
      return;
    }
    // Programmi iniziati da più di 10 minuti senza risposta: scaduti.
    final before = _items.length;
    _items.removeWhere(
      (r) => r.startTime.add(const Duration(minutes: 10)).isBefore(now),
    );
    if (_items.length != before) _save();
    for (final r in _items) {
      if (!now.isBefore(r.startTime.subtract(lead))) {
        due = r;
        notifyListeners();
        return;
      }
    }
  }

  void _load() {
    final raw = _prefs.getString(_key);
    if (raw == null) return;
    try {
      final list = jsonDecode(raw);
      if (list is List) {
        _items.addAll(list.map(Reminder.fromJson).whereType<Reminder>());
        _items.sort((a, b) => a.start.compareTo(b.start));
      }
    } catch (_) {}
  }

  void _save() => unawaited(
    _prefs.setString(_key, jsonEncode([for (final r in _items) r.toJson()])),
  );

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
