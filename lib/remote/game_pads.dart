import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Un giocatore collegato col telefono.
class PadPlayer {
  PadPlayer(this.slot, this.name, this._ws);

  /// 1, 2 o 3: il telecomando è il giocatore 0.
  final int slot;
  final String name;
  final WebSocket _ws;
  final held = <String>{};

  void send(Map<String, Object?> m) {
    try {
      _ws.add(jsonEncode(m));
    } catch (_) {}
  }
}

/// Smartphone usati come controller della sala giochi: si collegano
/// inquadrando un QR e mandano i tasti su un WebSocket, così arrivano in
/// pochi millisecondi.
class GamePads extends ChangeNotifier {
  static const maxPads = 3;
  static const tvPlayerName = 'TELECOMANDO';

  final _slots = List<PadPlayer?>.filled(maxPads, null);

  /// Tasto premuto (down = true) o rilasciato da un telefono.
  /// Tasti: up, down, left, right, a, b.
  void Function(int slot, String key, bool down)? onInput;

  /// Stato mostrato sui telefoni (gioco in corso, messaggio).
  Map<String, Object?> _state = const {'game': null};

  List<PadPlayer> get players => [for (final p in _slots) ?p];

  int get count => players.length;

  PadPlayer? bySlot(int slot) =>
      slot >= 1 && slot <= maxPads ? _slots[slot - 1] : null;

  /// Collega un telefono appena aperto il WebSocket.
  void attach(WebSocket ws) {
    PadPlayer? me;
    ws.pingInterval = const Duration(seconds: 5);
    ws.listen(
      (data) {
        if (data is! String) return;
        Map<String, Object?> m;
        try {
          final j = jsonDecode(data);
          if (j is! Map) return;
          m = j.cast<String, Object?>();
        } catch (_) {
          return;
        }
        switch (m['t']) {
          case 'hello':
            if (me != null) return;
            final i = _slots.indexOf(null);
            if (i < 0) {
              _sendRaw(ws, {'t': 'full'});
              unawaited(ws.close());
              return;
            }
            var name = '${m['name'] ?? ''}'.trim().toUpperCase();
            if (name.isEmpty) name = 'GIOCATORE ${i + 2}';
            if (name.length > 12) name = name.substring(0, 12);
            me = _slots[i] = PadPlayer(i + 1, name, ws);
            me!
              ..send({'t': 'welcome', 'player': i + 2})
              ..send({'t': 'state', ..._state});
            notifyListeners();
          case 'k':
            final p = me;
            if (p == null) return;
            final k = '${m['k']}';
            final down = m['d'] == true;
            if (down) {
              p.held.add(k);
            } else {
              p.held.remove(k);
            }
            onInput?.call(p.slot, k, down);
        }
      },
      onDone: () => _drop(me),
      onError: (Object _) => _drop(me),
      cancelOnError: true,
    );
  }

  void _drop(PadPlayer? p) {
    if (p == null) return;
    for (final k in [...p.held]) {
      onInput?.call(p.slot, k, false);
    }
    if (_slots[p.slot - 1] == p) _slots[p.slot - 1] = null;
    notifyListeners();
  }

  static void _sendRaw(WebSocket ws, Map<String, Object?> m) {
    try {
      ws.add(jsonEncode(m));
    } catch (_) {}
  }

  /// Vibrazione sul telefono del giocatore (colpito, fine partita…).
  void buzz(int slot, [int ms = 120]) =>
      bySlot(slot)?.send({'t': 'buzz', 'ms': ms});

  /// Aggiorna quello che i telefoni mostrano (nome del gioco, messaggio).
  void setState({String? game, String? message, bool playing = false}) {
    _state = {'game': game, 'message': message, 'playing': playing};
    for (final p in players) {
      p.send({'t': 'state', ..._state});
    }
  }
}
