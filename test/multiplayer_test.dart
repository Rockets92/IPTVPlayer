import 'dart:math';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/remote/game_pads.dart';
import 'package:iptv_player/ui/games/bricks_game.dart';
import 'package:iptv_player/ui/games/racer_game.dart';
import 'package:iptv_player/ui/games/retro.dart';
import 'package:iptv_player/ui/games/snake_game.dart';
import 'package:iptv_player/ui/games/space_game.dart';
import 'package:iptv_player/ui/games/stars_game.dart';
import 'package:iptv_player/ui/games/tandem_game.dart';

/// Gioca [g] con [n] giocatori premendo tasti a caso finché finisce.
void play(RetroGame g, int n, {int seconds = 240}) {
  g
    ..players = n
    ..names = [for (var i = 0; i < n; i++) 'G${i + 1}']
    ..reset();
  const keys = [
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowDown,
  ];
  for (var i = 0; i < 60 * seconds && !g.over; i++) {
    if (i % 23 == 0) {
      final p = (i ~/ 23) % n;
      final k = keys[g.rnd.nextInt(keys.length)];
      g.pads[p]
        ..clear()
        ..add(k);
      g.onPlayerKey(p, k);
    }
    g.update(1 / 60);
  }
}

void main() {
  test('tutti i giochi accettano da 1 a 4 giocatori', () {
    for (final make in [
      SnakeGame.new,
      BricksGame.new,
      StarsGame.new,
      SpaceGame.new,
      RacerGame.new,
      TandemGame.new,
    ]) {
      for (var n = 1; n <= 4; n++) {
        final g = make();
        expect(g.maxPlayers, 4);
        play(g, n, seconds: 60);
        // Nei giochi a sfida c'è la classifica; in quelli di squadra no.
        final versus = g is! BricksGame && g is! SpaceGame && g is! TandemGame;
        if (g.over && n > 1 && versus) {
          expect(g.results, hasLength(n), reason: '${g.id} con $n');
        }
      }
    }
  });

  test('serpentina a due: lo scontro frontale elimina entrambi', () {
    final g = SnakeGame()
      ..players = 2
      ..reset();
    // I due serpenti partono uno contro l'altro sulla stessa fila.
    g.snakes[1].body = [
      const Point(10, 11),
      const Point(11, 11),
      const Point(12, 11),
    ];
    g.snakes[0].body = [
      const Point(6, 11),
      const Point(5, 11),
      const Point(4, 11),
    ];
    for (var i = 0; i < 60 && !g.over; i++) {
      g.update(0.2);
    }
    expect(g.over, isTrue);
    expect(g.endTitle, 'PAREGGIO!');
  });

  test('i telefoni si collegano e mandano i tasti', () async {
    final pads = GamePads();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(
      (r) async => pads.attach(await WebSocketTransformer.upgrade(r)),
    );
    final got = <(int, String, bool)>[];
    pads.onInput = (s, k, d) => got.add((s, k, d));

    final ws = await WebSocket.connect('ws://127.0.0.1:${server.port}');
    final msgs = StreamController<Map>();
    ws.listen((m) => msgs.add(jsonDecode(m as String) as Map));
    final it = StreamIterator(msgs.stream);
    ws.add(jsonEncode({'t': 'hello', 'name': 'anna'}));
    expect(await it.moveNext(), isTrue);
    expect(it.current['t'], 'welcome');
    expect(it.current['player'], 2);
    expect(pads.players.single.name, 'ANNA');

    ws.add(jsonEncode({'t': 'k', 'k': 'left', 'd': true}));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(got, [(1, 'left', true)]);

    // Chiuso il telefono, i tasti tenuti premuti vengono rilasciati.
    await ws.close();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(got.last, (1, 'left', false));
    expect(pads.count, 0);
    await server.close(force: true);
  });
}
