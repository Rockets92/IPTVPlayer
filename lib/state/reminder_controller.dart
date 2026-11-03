import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/epg/epg_models.dart';
import '../domain/channel.dart';

/// Ripetizione di un promemoria.
enum ReminderRepeat {
  once('Una volta'),
  daily('Ogni giorno'),
  weekly('Ogni settimana'),
  monthly('Ogni mese');

  const ReminderRepeat(this.label);
  final String label;

  static ReminderRepeat parse(Object? v) =>
      values.firstWhere((r) => r.name == v, orElse: () => ReminderRepeat.once);
}

/// Un programma futuro "prenotato" dall'utente.
@immutable
class Reminder {
  const Reminder({
    required this.channelId,
    required this.channelNumber,
    required this.channelName,
    required this.title,
    required this.start,
    this.repeat = ReminderRepeat.once,
    this.days = const [],
    this.snooze,
  });

  /// Giorni della settimana per la ripetizione settimanale
  /// (1 = lunedì … 7 = domenica, come [DateTime.weekday]).
  final List<int> days;

  final ReminderRepeat repeat;

  /// "Ricordamelo tra 1 minuto": quando riproporre l'avviso (secondi epoch).
  final int? snooze;

  bool get recurring => repeat != ReminderRepeat.once;

  /// Giorni effettivi della ripetizione settimanale (di base quello del
  /// programma).
  List<int> get weekDays => days.isEmpty ? [startTime.weekday] : days;

  /// Quando mostrare l'avviso.
  DateTime get notifyAt => snooze != null
      ? DateTime.fromMillisecondsSinceEpoch(snooze! * 1000)
      : startTime.subtract(ReminderController.lead);

  /// Oltre questo momento, senza risposta, l'avviso è scaduto.
  DateTime get expiresAt {
    final a = startTime.add(const Duration(minutes: 10));
    final s = snooze;
    if (s == null) return a;
    final b = DateTime.fromMillisecondsSinceEpoch(s * 1000)
        .add(const Duration(minutes: 2));
    return b.isAfter(a) ? b : a;
  }

  /// Descrizione breve della ripetizione (es. "Ogni settimana · lun, mer").
  String get repeatLabel {
    if (repeat != ReminderRepeat.weekly) return repeat.label;
    final d = [...weekDays]..sort();
    return '${repeat.label} · ${d.map((x) => weekdayShort[x - 1]).join(', ')}';
  }

  static const weekdayShort = ['lun', 'mar', 'mer', 'gio', 'ven', 'sab', 'dom'];

  Reminder copyWith({
    int? start,
    ReminderRepeat? repeat,
    List<int>? days,
    int? Function()? snooze,
  }) => Reminder(
    channelId: channelId,
    channelNumber: channelNumber,
    channelName: channelName,
    title: title,
    start: start ?? this.start,
    repeat: repeat ?? this.repeat,
    days: days ?? this.days,
    snooze: snooze != null ? snooze() : this.snooze,
  );

  /// Prossima volta, per i promemoria ricorrenti (stesso orario).
  DateTime? nextAfter(DateTime t) {
    final s = startTime;
    DateTime at(int y, int m, int d) =>
        DateTime(y, m, d, s.hour, s.minute, s.second);
    switch (repeat) {
      case ReminderRepeat.once:
        return null;
      case ReminderRepeat.daily:
        var d = at(t.year, t.month, t.day);
        while (!d.isAfter(t)) {
          d = at(d.year, d.month, d.day + 1);
        }
        return d;
      case ReminderRepeat.weekly:
        final w = weekDays;
        var d = at(t.year, t.month, t.day);
        for (var i = 0; i < 8; i++) {
          if (d.isAfter(t) && w.contains(d.weekday)) return d;
          d = at(d.year, d.month, d.day + 1);
        }
        return null;
      case ReminderRepeat.monthly:
        var y = t.year, m = t.month;
        for (var i = 0; i < 14; i++) {
          final last = DateTime(y, m + 1, 0).day;
          final d = at(y, m, s.day > last ? last : s.day);
          if (d.isAfter(t)) return d;
          m++;
          if (m > 12) {
            m = 1;
            y++;
          }
        }
        return null;
    }
  }

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
    if (recurring) 'r': repeat.name,
    if (days.isNotEmpty) 'd': days,
    'z': ?snooze,
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
      repeat: ReminderRepeat.parse(j['r']),
      days: j['d'] is List
          ? (j['d'] as List).whereType<num>().map((e) => e.toInt()).toList()
          : const [],
      snooze: (j['z'] as num?)?.toInt(),
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

  /// L'utente ha risposto all'avviso (vai o annulla): non si ripropone,
  /// se è ricorrente si passa alla volta successiva.
  void resolve() {
    final d = due;
    if (d == null) return;
    _done(d);
    due = null;
    _save();
    notifyListeners();
    _check();
  }

  /// "Ricordamelo tra 1 minuto".
  void snooze([Duration after = const Duration(minutes: 1)]) {
    final d = due;
    if (d == null) return;
    final i = _items.indexWhere((r) => r.key == d.key);
    final at = DateTime.now().add(after).millisecondsSinceEpoch ~/ 1000;
    if (i >= 0) _items[i] = d.copyWith(snooze: () => at);
    due = null;
    _save();
    notifyListeners();
  }

  /// Cambia la ripetizione di un promemoria.
  Reminder? setRepeat(Reminder r, ReminderRepeat repeat, [List<int>? days]) {
    final i = _items.indexWhere((x) => x.key == r.key);
    if (i < 0) return null;
    var n = r.copyWith(repeat: repeat, days: days ?? r.days);
    // Settimanale su giorni che non comprendono quello del programma: si
    // parte dal primo giorno scelto.
    if (n.repeat == ReminderRepeat.weekly &&
        !n.weekDays.contains(n.startTime.weekday)) {
      final next = n.nextAfter(n.startTime);
      if (next != null) {
        n = n.copyWith(start: next.millisecondsSinceEpoch ~/ 1000);
      }
    }
    _items[i] = n;
    _sort();
    _save();
    notifyListeners();
    return n;
  }

  void remove(Reminder r) {
    _items.removeWhere((x) => x.key == r.key);
    if (due?.key == r.key) due = null;
    _save();
    notifyListeners();
  }

  Reminder? byKey(String key) => _items.where((r) => r.key == key).firstOrNull;

  /// Avviso gestito o scaduto: i ricorrenti passano alla volta successiva.
  void _done(Reminder d) {
    final i = _items.indexWhere((r) => r.key == d.key);
    if (i < 0) return;
    final base = DateTime.now().isAfter(d.startTime)
        ? DateTime.now()
        : d.startTime;
    final next = d.nextAfter(base);
    if (next == null) {
      _items.removeAt(i);
    } else {
      _items[i] = d.copyWith(
        start: next.millisecondsSinceEpoch ~/ 1000,
        snooze: () => null,
      );
      _sort();
    }
  }

  void _sort() => _items.sort((a, b) => a.start.compareTo(b.start));

  void _check() {
    final now = DateTime.now();
    final d = due;
    if (d != null) {
      // Nessuna risposta e programma ormai avanzato: l'avviso sparisce.
      if (d.expiresAt.isBefore(now)) resolve();
      return;
    }
    // Programmi iniziati da più di 10 minuti senza risposta: scaduti (i
    // ricorrenti passano alla volta successiva).
    final expired = [
      for (final r in _items)
        if (r.expiresAt.isBefore(now)) r,
    ];
    for (final r in expired) {
      _done(r);
    }
    if (expired.isNotEmpty) {
      _save();
      notifyListeners();
    }
    for (final r in _items) {
      if (!now.isBefore(r.notifyAt)) {
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
