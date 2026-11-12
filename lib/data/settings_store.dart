import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/performance.dart';
import 'xtream/xtream_models.dart';

/// Formato di trasporto per i canali live.
enum StreamFormat { ts, hls }

extension StreamFormatX on StreamFormat {
  String get extension => this == StreamFormat.ts ? 'ts' : 'm3u8';
  String get label => this == StreamFormat.ts ? 'MPEG-TS' : 'HLS';
}

/// Canali per adulti (categoria "XXX" del provider).
enum AdultMode { off, on, pin }

/// Dimensione dell'interfaccia: su TV "auto" la riduce come su un decoder.
enum UiScale { auto, large, medium, small }

/// Preferenza personale da sincronizzare: valore salvato (stringa, bool o
/// lista di stringhe; null = tolta) e ultima modifica in millisecondi epoch.
typedef SyncedPref = ({Object? value, int updatedAt});

/// Preferenze persistenti.
///
/// Si dividono in personali ([syncedKeys]: seguono l'account su tutti i
/// dispositivi) e del dispositivo (scala dell'interfaccia, profilo light,
/// ultimo canale, dati della lista, codici del telecomando), che restano
/// locali.
class SettingsStore {
  SettingsStore(this._prefs) {
    _migrateAdultPin();
  }

  static Future<SettingsStore> open() async =>
      SettingsStore(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;

  /// Accesso diretto per gli archivi che gestiscono da sé i propri dati.
  SharedPreferences get prefs => _prefs;

  static const _kCreds = 'xtream.credentials';

  /// Chiavi pubbliche di alcune preferenze personali, per reagire quando
  /// arrivano da un altro dispositivo.
  static const keyMapping = _kMapping;
  static const keyExtraEpg = _kExtraEpg;
  static const keyProviderEpg = _kProviderEpg;
  static const keyFavorites = _kFavorites;
  static const keyLastWatched = _kLastWatched;
  static const _kAccount = 'xtream.account';
  static const _kLastChannel = 'tuner.lastChannel';
  static const _kMapping = 'mapping.source';
  static const _kExtraEpg = 'epg.extraSources';
  static const _kProviderEpg = 'epg.useProvider';
  static const _kShowUnmapped = 'channels.showUnmapped';
  static const _kPerf = 'ui.performanceMode';
  static const _kFormat = 'stream.format';
  static const _kSources = 'tuner.sourceChoices';
  static const _kAdult = 'channels.adultMode';
  static const _kUiScale = 'ui.scale';

  /// Vecchio PIN in chiaro: alla prima apertura diventa [_kAdultPinHash].
  static const _kAdultPinLegacy = 'channels.adultPin';
  static const _kAdultPinHash = 'channels.adultPinHash';
  static const _kFavorites = 'channels.favorites';

  /// Ultimo canale visto su uno qualsiasi dei dispositivi dell'account:
  /// `{"c": id canale, "t": millisecondi epoch}`.
  static const _kLastWatched = 'tuner.lastWatched';
  static const _kSyncStamps = 'sync.prefsUpdated.v1';

  /// Preferenze personali, uguali su tutti i dispositivi dell'account.
  /// Il formato dello stream resta per dispositivo: alcuni decoder vanno
  /// meglio con HLS, altri con MPEG-TS.
  static const syncedKeys = {
    _kMapping,
    _kExtraEpg,
    _kProviderEpg,
    _kShowUnmapped,
    _kSources,
    _kAdult,
    _kAdultPinHash,
    _kFavorites,
    _kLastWatched,
  };

  /// Orologio, sostituibile nei test.
  int Function() clock = () => DateTime.now().millisecondsSinceEpoch;

  /// Chiamato quando cambia una preferenza personale su questo dispositivo.
  void Function()? onLocalChange;

  Map<String, int> get _stamps {
    try {
      final m = jsonDecode(_prefs.getString(_kSyncStamps) ?? '{}');
      if (m is Map) {
        return {
          for (final e in m.entries)
            if (e.value is num) '${e.key}': (e.value as num).toInt(),
        };
      }
    } catch (_) {}
    return {};
  }

  Future<void> _stamp(String key) async {
    final m = _stamps..[key] = clock();
    await _prefs.setString(_kSyncStamps, jsonEncode(m));
    onLocalChange?.call();
  }

  Object? _raw(String key) {
    final v = _prefs.get(key);
    return v is List ? v.map((e) => '$e').toList() : v;
  }

  /// Preferenze personali con la data dell'ultima modifica, da inviare
  /// agli altri dispositivi. Quelle mai toccate hanno data 0.
  Map<String, SyncedPref> get syncedPrefs {
    final st = _stamps;
    return {
      for (final k in syncedKeys) k: (value: _raw(k), updatedAt: st[k] ?? 0),
    };
  }

  /// Applica le preferenze arrivate da un altro dispositivo, solo se più
  /// recenti di quelle locali. Restituisce le chiavi cambiate.
  Future<Set<String>> applyRemotePrefs(Map<String, SyncedPref> remote) async {
    final st = _stamps;
    final changed = <String>{};
    for (final e in remote.entries) {
      if (!syncedKeys.contains(e.key)) continue;
      if (e.value.updatedAt <= (st[e.key] ?? 0)) continue;
      final v = e.value.value;
      switch (v) {
        case null:
          await _prefs.remove(e.key);
        case String():
          await _prefs.setString(e.key, v);
        case bool():
          await _prefs.setBool(e.key, v);
        case List():
          await _prefs.setStringList(e.key, [for (final x in v) '$x']);
        default:
          continue;
      }
      st[e.key] = e.value.updatedAt;
      changed.add(e.key);
    }
    if (changed.isNotEmpty) {
      await _prefs.setString(_kSyncStamps, jsonEncode(st));
    }
    return changed;
  }

  /// Impronta del PIN: sul dispositivo e sul server non resta il PIN in
  /// chiaro. Con 4 cifre non è una protezione forte: serve a non mostrarlo
  /// a chi guarda i dati salvati.
  static String hashPin(String pin) =>
      sha256.convert(utf8.encode('bb-iptv-player/pin:$pin')).toString();

  void _migrateAdultPin() {
    final old = _prefs.getString(_kAdultPinLegacy);
    if (old == null) return;
    if (_prefs.getString(_kAdultPinHash) == null) {
      unawaited(_prefs.setString(_kAdultPinHash, hashPin(old)));
    }
    unawaited(_prefs.remove(_kAdultPinLegacy));
  }

  XtreamCredentials? get credentials {
    final raw = _prefs.getString(_kCreds);
    if (raw == null) return null;
    try {
      return XtreamCredentials.fromJson(
        (jsonDecode(raw) as Map).cast<String, Object?>(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> setCredentials(XtreamCredentials? c) => c == null
      ? _prefs.remove(_kCreds)
      : _prefs.setString(_kCreds, jsonEncode(c.toJson()));

  XtreamAccountInfo? get account {
    final raw = _prefs.getString(_kAccount);
    if (raw == null) return null;
    try {
      return XtreamAccountInfo.fromJson(
        (jsonDecode(raw) as Map).cast<String, Object?>(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> setAccount(XtreamAccountInfo? a) => a == null
      ? _prefs.remove(_kAccount)
      : _prefs.setString(_kAccount, jsonEncode(a.toJson()));

  /// Ultimo canale visto: il più recente tra questo dispositivo e gli
  /// altri dell'account.
  String? get lastChannelId =>
      lastWatched?.channelId ?? _prefs.getString(_kLastChannel);

  ({String channelId, int at})? get lastWatched {
    try {
      final j = jsonDecode(_prefs.getString(_kLastWatched) ?? '');
      if (j is Map && j['c'] is String && j['t'] is num) {
        return (channelId: j['c'] as String, at: (j['t'] as num).toInt());
      }
    } catch (_) {}
    return null;
  }

  /// [chosen] = falso quando è il canale ripreso all'accensione: non conta
  /// come scelta nuova, così non copre quella fatta su un altro dispositivo.
  Future<void> setLastChannelId(String id, {bool chosen = true}) async {
    await _prefs.setString(_kLastChannel, id);
    if (!chosen || lastWatched?.channelId == id) return;
    await _prefs.setString(_kLastWatched, jsonEncode({'c': id, 't': clock()}));
    await _stamp(_kLastWatched);
  }

  /// Canali preferiti (id), nell'ordine in cui sono stati aggiunti.
  List<String> get favorites => _prefs.getStringList(_kFavorites) ?? const [];

  bool isFavorite(String channelId) => favorites.contains(channelId);

  /// Aggiunge o toglie un preferito; true se ora è preferito.
  Future<bool> toggleFavorite(String channelId) async {
    final l = [...favorites];
    final on = !l.remove(channelId);
    if (on) l.add(channelId);
    await _prefs.setStringList(_kFavorites, l);
    await _stamp(_kFavorites);
    return on;
  }

  /// Sorgente della mappatura: vuoto = integrata, altrimenti URL o percorso.
  String get mappingSource => _prefs.getString(_kMapping) ?? '';
  Future<void> setMappingSource(String v) async {
    await _prefs.setString(_kMapping, v.trim());
    await _stamp(_kMapping);
  }

  List<String> get extraEpgSources =>
      _prefs.getStringList(_kExtraEpg) ?? const [];
  Future<void> setExtraEpgSources(List<String> v) async {
    await _prefs.setStringList(
      _kExtraEpg,
      v.map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
    );
    await _stamp(_kExtraEpg);
  }

  bool get useProviderEpg => _prefs.getBool(_kProviderEpg) ?? true;
  Future<void> setUseProviderEpg(bool v) async {
    await _prefs.setBool(_kProviderEpg, v);
    await _stamp(_kProviderEpg);
  }

  /// `null` = segue l'impostazione della mappatura.
  bool? get showUnmapped => _prefs.getBool(_kShowUnmapped);
  Future<void> setShowUnmapped(bool v) async {
    await _prefs.setBool(_kShowUnmapped, v);
    await _stamp(_kShowUnmapped);
  }

  PerformanceMode get performanceMode => PerformanceMode.values.firstWhere(
    (m) => m.name == _prefs.getString(_kPerf),
    orElse: () => PerformanceMode.auto,
  );
  Future<void> setPerformanceMode(PerformanceMode m) =>
      _prefs.setString(_kPerf, m.name);

  StreamFormat get streamFormat => StreamFormat.values.firstWhere(
    (f) => f.name == _prefs.getString(_kFormat),
    orElse: () => StreamFormat.ts,
  );
  Future<void> setStreamFormat(StreamFormat f) =>
      _prefs.setString(_kFormat, f.name);

  /// Fonte scelta dall'utente per ogni canale (id canale → nome dello stream).
  /// Si salva il nome e non l'id dello stream, che il provider può cambiare.
  Map<String, String> get sourceChoices {
    final raw = _prefs.getString(_kSources);
    if (raw == null) return const {};
    try {
      return (jsonDecode(raw) as Map).map(
        (k, v) => MapEntry(k.toString(), v.toString()),
      );
    } catch (_) {
      return const {};
    }
  }

  String? sourceChoice(String channelId) => sourceChoices[channelId];

  Future<void> setSourceChoice(String channelId, String? label) async {
    final m = Map<String, String>.of(sourceChoices);
    if (label == null) {
      m.remove(channelId);
    } else {
      m[channelId] = label;
    }
    await _prefs.setString(_kSources, jsonEncode(m));
    await _stamp(_kSources);
  }

  UiScale get uiScale => UiScale.values.firstWhere(
    (m) => m.name == _prefs.getString(_kUiScale),
    orElse: () => UiScale.auto,
  );
  Future<void> setUiScale(UiScale v) => _prefs.setString(_kUiScale, v.name);

  /// Predefinito: canali per adulti nascosti.
  AdultMode get adultMode => AdultMode.values.firstWhere(
    (m) => m.name == _prefs.getString(_kAdult),
    orElse: () => AdultMode.off,
  );

  /// Impronta del PIN del parental control (solo in modalità
  /// [AdultMode.pin]).
  String? get _adultPinHash => _prefs.getString(_kAdultPinHash);

  Future<void> setAdultMode(AdultMode m, {String? pin}) async {
    await _prefs.setString(_kAdult, m.name);
    await _stamp(_kAdult);
    if (m == AdultMode.pin && pin != null) {
      await _prefs.setString(_kAdultPinHash, hashPin(pin));
      await _stamp(_kAdultPinHash);
    } else if (m != AdultMode.pin) {
      await _prefs.remove(_kAdultPinHash);
      await _stamp(_kAdultPinHash);
    }
  }

  bool checkAdultPin(String pin) =>
      pin.isNotEmpty && hashPin(pin) == _adultPinHash;

  Future<void> clearAccount() async {
    await _prefs.remove(_kCreds);
    await _prefs.remove(_kAccount);
    await _prefs.remove(_kLastChannel);
  }
}
