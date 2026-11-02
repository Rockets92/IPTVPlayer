import 'dart:convert';

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

/// Preferenze persistenti.
class SettingsStore {
  SettingsStore(this._prefs);

  static Future<SettingsStore> open() async =>
      SettingsStore(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;

  /// Accesso diretto per gli archivi che gestiscono da sé i propri dati.
  SharedPreferences get prefs => _prefs;

  static const _kCreds = 'xtream.credentials';
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
  static const _kAdultPin = 'channels.adultPin';

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

  String? get lastChannelId => _prefs.getString(_kLastChannel);
  Future<void> setLastChannelId(String id) =>
      _prefs.setString(_kLastChannel, id);

  /// Sorgente della mappatura: vuoto = integrata, altrimenti URL o percorso.
  String get mappingSource => _prefs.getString(_kMapping) ?? '';
  Future<void> setMappingSource(String v) =>
      _prefs.setString(_kMapping, v.trim());

  List<String> get extraEpgSources =>
      _prefs.getStringList(_kExtraEpg) ?? const [];
  Future<void> setExtraEpgSources(List<String> v) => _prefs.setStringList(
    _kExtraEpg,
    v.map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
  );

  bool get useProviderEpg => _prefs.getBool(_kProviderEpg) ?? true;
  Future<void> setUseProviderEpg(bool v) => _prefs.setBool(_kProviderEpg, v);

  /// `null` = segue l'impostazione della mappatura.
  bool? get showUnmapped => _prefs.getBool(_kShowUnmapped);
  Future<void> setShowUnmapped(bool v) => _prefs.setBool(_kShowUnmapped, v);

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

  Future<void> setSourceChoice(String channelId, String? label) {
    final m = Map<String, String>.of(sourceChoices);
    if (label == null) {
      m.remove(channelId);
    } else {
      m[channelId] = label;
    }
    return _prefs.setString(_kSources, jsonEncode(m));
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

  /// PIN del parental control (solo in modalità [AdultMode.pin]).
  String? get adultPin => _prefs.getString(_kAdultPin);

  Future<void> setAdultMode(AdultMode m, {String? pin}) async {
    await _prefs.setString(_kAdult, m.name);
    if (m == AdultMode.pin && pin != null) {
      await _prefs.setString(_kAdultPin, pin);
    } else if (m != AdultMode.pin) {
      await _prefs.remove(_kAdultPin);
    }
  }

  bool checkAdultPin(String pin) => pin.isNotEmpty && pin == adultPin;

  Future<void> clearAccount() async {
    await _prefs.remove(_kCreds);
    await _prefs.remove(_kAccount);
    await _prefs.remove(_kLastChannel);
  }
}
