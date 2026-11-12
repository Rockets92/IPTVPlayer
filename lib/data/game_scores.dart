import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Record della sala giochi (`games.best.<id>`), con la data in cui sono
/// stati fatti: con l'account seguono l'utente su tutti i dispositivi e tra
/// due record vince sempre il più alto.
class GameScores {
  GameScores(this._prefs);

  final SharedPreferences _prefs;

  static const _prefix = 'games.best.';
  static const _kStamps = 'games.bestAt.v1';

  /// Avvisato quando su questo dispositivo si fa un nuovo record.
  static VoidCallback? onLocalChange;

  /// Orologio, sostituibile nei test.
  @visibleForTesting
  static int Function() clock = () => DateTime.now().millisecondsSinceEpoch;

  int best(String gameId) => _prefs.getInt('$_prefix$gameId') ?? 0;

  Map<String, int> get _stamps {
    try {
      final m = jsonDecode(_prefs.getString(_kStamps) ?? '{}');
      if (m is Map) {
        return {
          for (final e in m.entries)
            if (e.value is num) '${e.key}': (e.value as num).toInt(),
        };
      }
    } catch (_) {}
    return {};
  }

  /// Salva [score] se è un nuovo record; true se lo è.
  Future<bool> submit(String gameId, int score) async {
    if (score <= best(gameId)) return false;
    await _prefs.setInt('$_prefix$gameId', score);
    await _prefs.setString(_kStamps, jsonEncode(_stamps..[gameId] = clock()));
    onLocalChange?.call();
    return true;
  }

  /// Tutti i record: id gioco → (punti, quando).
  Map<String, ({int best, int at})> get all {
    final st = _stamps;
    return {
      for (final k in _prefs.getKeys())
        if (k.startsWith(_prefix))
          k.substring(_prefix.length): (
            best: _prefs.getInt(k) ?? 0,
            at: st[k.substring(_prefix.length)] ?? 0,
          ),
    };
  }

  /// Record arrivato da un altro dispositivo: si tiene il più alto.
  /// Se quello locale è più alto, si rinfresca la data perché venga
  /// rimandato. Restituisce true se il record locale è cambiato.
  Future<bool> mergeRemote(String gameId, int remoteBest, int at) async {
    final mine = best(gameId);
    if (remoteBest > mine) {
      await _prefs.setInt('$_prefix$gameId', remoteBest);
      await _prefs.setString(_kStamps, jsonEncode(_stamps..[gameId] = at));
      return true;
    }
    if (mine > remoteBest) {
      await _prefs.setString(_kStamps, jsonEncode(_stamps..[gameId] = clock()));
      onLocalChange?.call();
    }
    return false;
  }
}
