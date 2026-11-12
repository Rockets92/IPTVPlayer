import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/settings_store.dart';
import '../state/reminder_controller.dart';
import '../state/vod_controller.dart';
import 'sync_backend.dart';

/// Tiene allineati promemoria, "continua a guardare" e preferenze personali
/// con l'account. L'app resta offline-first: legge sempre i dati locali,
/// invia le modifiche quando c'è rete e applica quelle degli altri
/// dispositivi appena arrivano.
class SyncEngine extends ChangeNotifier {
  SyncEngine({
    required this.backend,
    required this.prefs,
    required this.reminders,
    required this.settings,
    this.vod,
    this.onPrefsApplied,
    this.pushDelay = const Duration(seconds: 2),
    this.pollEvery = const Duration(minutes: 5),
  });

  final SyncBackend backend;
  final SharedPreferences prefs;
  final ReminderController reminders;
  final SettingsStore settings;
  final VodController? vod;

  /// Chiamato con le chiavi delle preferenze arrivate da un altro
  /// dispositivo (es. per ricaricare l'EPG).
  final Future<void> Function(Set<String> keys)? onPrefsApplied;

  final Duration pushDelay;
  final Duration pollEvery;

  static const _kCursor = 'sync.cursor';
  static const _kPushed = 'sync.pushedUpTo';

  StreamSubscription<SyncRecord>? _sub;
  Timer? _pushTimer;
  Timer? _poll;
  bool _running = false;
  bool _busy = false;
  bool _again = false;

  /// Ultima sincronizzazione riuscita.
  DateTime? lastSync;

  /// Ultimo errore (es. niente rete); null se tutto ok.
  String? error;

  bool get running => _running;

  /// Cursore del server: righe già scaricate.
  int get _cursor => prefs.getInt(_kCursor) ?? 0;

  /// Modifiche locali già inviate fino a questo istante (orologio locale).
  /// -1 = mai: al primo accesso si invia tutto, anche i dati salvati prima
  /// della sincronizzazione (con data 0).
  int get _pushedUpTo => prefs.getInt(_kPushed) ?? -1;

  Future<void> start() async {
    if (_running) return;
    _running = true;
    reminders.onLocalChange = _schedulePush;
    settings.onLocalChange = _schedulePush;
    vod?.onLocalChange = _schedulePush;
    _sub = backend.changes.listen(
      (r) => unawaited(_apply([r])),
      onError: (Object _) {},
    );
    _poll = Timer.periodic(pollEvery, (_) => unawaited(syncNow()));
    await syncNow();
  }

  Future<void> stop() async {
    _running = false;
    reminders.onLocalChange = null;
    settings.onLocalChange = null;
    vod?.onLocalChange = null;
    _pushTimer?.cancel();
    _poll?.cancel();
    await _sub?.cancel();
    _sub = null;
  }

  /// Dopo l'uscita dall'account: il prossimo accesso riparte da capo.
  Future<void> reset() async {
    await stop();
    await prefs.remove(_kCursor);
    await prefs.remove(_kPushed);
    lastSync = null;
    error = null;
    notifyListeners();
  }

  void _schedulePush() {
    if (!_running) return;
    _pushTimer?.cancel();
    _pushTimer = Timer(pushDelay, () => unawaited(syncNow()));
  }

  /// Invia le modifiche locali e scarica quelle degli altri dispositivi.
  Future<void> syncNow() async {
    if (!_running) return;
    if (_busy) {
      _again = true;
      return;
    }
    _busy = true;
    try {
      do {
        _again = false;
        await _push();
        final page = await backend.pull(cursor: _cursor);
        await _apply(page.records);
        await prefs.setInt(_kCursor, page.cursor);
      } while (_again && _running);
      lastSync = DateTime.now();
      error = null;
    } catch (e) {
      error = 'Sincronizzazione non riuscita: controlla la connessione';
      debugPrint('sync: $e');
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> _push() async {
    final since = _pushedUpTo;
    final now = DateTime.now().millisecondsSinceEpoch;
    final out = <SyncRecord>[
      for (final r in reminders.items)
        if (r.updatedAt > since)
          SyncRecord(
            table: SyncTable.reminders,
            id: r.id,
            updatedAt: r.updatedAt,
            data: r.toJson(),
          ),
      for (final e in reminders.deletions.entries)
        if (e.value > since)
          SyncRecord(
            table: SyncTable.reminders,
            id: e.key,
            updatedAt: e.value,
            deleted: true,
          ),
      for (final e in settings.syncedPrefs.entries)
        if (e.value.updatedAt > since && e.value.updatedAt > 0)
          SyncRecord(
            table: SyncTable.prefs,
            id: e.key,
            updatedAt: e.value.updatedAt,
            data: {'v': e.value.value},
          ),
      ...?_vodRecords(since),
    ];
    if (out.isNotEmpty) await backend.push(out);
    await prefs.setInt(_kPushed, now);
  }

  List<SyncRecord>? _vodRecords(int since) {
    final v = vod;
    if (v == null) return null;
    return [
      for (final w in v.progressEntries)
        if (w.at.millisecondsSinceEpoch > since)
          SyncRecord(
            table: SyncTable.vodProgress,
            id: w.key,
            updatedAt: w.at.millisecondsSinceEpoch,
            data: w.toJson(),
          ),
      for (final e in v.forgotten.entries)
        if (e.value > since)
          SyncRecord(
            table: SyncTable.vodProgress,
            id: e.key,
            updatedAt: e.value,
            deleted: true,
          ),
    ];
  }

  Future<void> _apply(List<SyncRecord> records) async {
    if (records.isEmpty) return;
    final remUp = <Reminder>[];
    final remDel = <String, int>{};
    final vodUp = <WatchEntry>[];
    final vodDel = <String, int>{};
    final pr = <String, SyncedPref>{};
    for (final r in records) {
      switch (r.table) {
        case SyncTable.reminders:
          if (r.deleted) {
            remDel[r.id] = r.updatedAt;
          } else {
            final x = Reminder.fromJson(r.data);
            if (x != null) {
              remUp.add(x.copyWith(updatedAt: r.updatedAt));
            }
          }
        case SyncTable.vodProgress:
          if (r.deleted) {
            vodDel[r.id] = r.updatedAt;
          } else {
            final d = r.data;
            final w = WatchEntry.fromJson(
              r.id,
              d is Map ? {...d, 't': r.updatedAt ~/ 1000} : d,
            );
            if (w != null) vodUp.add(w);
          }
        case SyncTable.prefs:
          final d = r.data;
          pr[r.id] = (
            value: r.deleted || d is! Map ? null : d['v'],
            updatedAt: r.updatedAt,
          );
      }
    }
    if (remUp.isNotEmpty || remDel.isNotEmpty) {
      reminders.mergeRemote(upserts: remUp, deletions: remDel);
    }
    if (vodUp.isNotEmpty || vodDel.isNotEmpty) {
      vod?.mergeRemote(upserts: vodUp, deletions: vodDel);
    }
    if (pr.isNotEmpty) {
      final keys = await settings.applyRemotePrefs(pr);
      if (keys.isNotEmpty) await onPrefsApplied?.call(keys);
    }
  }

  @override
  void dispose() {
    unawaited(stop());
    super.dispose();
  }
}
