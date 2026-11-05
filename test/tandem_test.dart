import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/ui/games/tandem_game.dart';

const _l = LogicalKeyboardKey.arrowLeft;
const _r = LogicalKeyboardKey.arrowRight;
const _up = LogicalKeyboardKey.arrowUp;

TandemGame start(int players, {int level = 1}) {
  final g = TandemGame()
    ..players = players
    ..reset();
  if (level > 1) g.goTo(level);
  g.skipStory();
  // Le prove riguardano gli enigmi: i mostriciattoli restano a casa.
  for (final w in g.walkers) {
    w.alive = false;
  }
  return g;
}

/// Porta i giocatori alle colonne indicate camminando (e saltando da soli
/// buche e scalini bassi). Restituisce false se non ci arrivano.
bool walk(TandemGame g, Map<int, double> cols, {bool hop = true}) {
  for (var f = 0; f < 60 * 15; f++) {
    var done = true;
    for (var p = 0; p < g.heroes.length; p++) {
      g.pads[p].clear();
    }
    for (final e in cols.entries) {
      final h = g.heroes[e.key];
      if (h.inside) continue;
      final target = e.value * 8 + 1;
      final dx = target - h.x;
      if (dx.abs() < 1.2 && h.grounded) continue;
      done = false;
      if (dx.abs() < 1.2) continue;
      final dir = dx > 0 ? 1 : -1;
      g.pads[e.key].add(dir > 0 ? _r : _l);
      if (hop && h.grounded) {
        final ahead = ((dir > 0 ? h.x + 6 + 2 : h.x - 2) / 8).floor();
        final foot = ((h.y + 10) / 8).floor();
        final gap = !g.solidAt(ahead, foot) && g.tileAt(ahead, foot) != '=';
        final step = g.solidAt(ahead, foot - 1);
        final spike = g.tileAt(ahead, foot - 1) == '^';
        if ((gap || step || spike) && (dx.abs() > 4)) g.onPlayerKey(e.key, _up);
      }
    }
    if (done) return true;
    final lives = g.lives;
    g.update(1 / 60);
    if (g.lives < lives) {
      // ignore: avoid_print
      print(
        'morto: ${[for (final h in g.heroes) '${(h.x / 8).toStringAsFixed(1)},${(h.y / 8).toStringAsFixed(1)}']} verso $cols',
      );
    }
    expect(g.over, isFalse, reason: 'nessuno deve morire');
  }
  return false;
}

/// Aspetta la festa di fine livello e salta la scena della storia.
/// Restituisce il livello raggiunto.
int finish(TandemGame g) {
  final from = g.level;
  for (var i = 0; i < 60 * 5 && g.level == from && !g.inStory; i++) {
    g.update(1 / 60);
  }
  expect(g.inStory, isTrue, reason: 'dopo la porta parte la storia');
  g.skipStory();
  for (final w in g.walkers) {
    w.alive = false;
  }
  return g.over ? -1 : g.level;
}

/// Salto di [p] verso la colonna [col] (sulla testa del compagno, su un
/// tetto…), poi aspetta che atterri.
void jump(TandemGame g, int p, double col) {
  g.onPlayerKey(p, _up);
  g.update(1 / 60);
  walk(g, {p: col}, hop: false);
}

void main() {
  test('i livelli sono rettangolari e hanno un\'uscita', () {
    for (var n = 1; n <= TandemGame.levelCount; n++) {
      final g = start(2, level: n);
      expect(g.grid, hasLength(15));
      expect(g.grid.every((r) => r.length == g.cols), isTrue);
      expect(g.grid.any((r) => r.contains('E')), isTrue);
    }
  });

  test('in squadra non ci sono casse, da soli sì', () {
    expect(start(2).crates, isEmpty);
    expect(start(1).crates, isNotEmpty);
  });

  test('si sta in piedi sulla testa del compagno', () {
    final g = start(2);
    walk(g, {0: 6, 1: 4});
    jump(g, 1, 6);
    expect(g.heroes[1].y, closeTo(g.heroes[0].y - 10, 0.5));
    expect(g.heroes[1].grounded, isTrue);
    // E chi sta sotto se lo porta in giro.
    walk(g, {0: 9}, hop: false);
    expect(g.heroes[1].x, greaterThan(9 * 8 - 4));
    expect(g.heroes[1].y, closeTo(g.heroes[0].y - 10, 0.5));
  });

  test('livello 1 in due: tetto, porta e ponte si superano insieme', () {
    final g = start(2);
    expect(walk(g, {0: 24, 1: 26}), isTrue);
    // Da soli il tetto è troppo alto: 0 sale sulla testa di 1, poi sul tetto.
    jump(g, 0, 26);
    jump(g, 0, 31);
    expect(g.heroes[0].y, lessThan(80));
    // 0 tiene la pedana: la porta si apre e 1 passa nel tunnel.
    expect(walk(g, {1: 36}), isTrue);
    expect(walk(g, {0: 37}), isTrue);
    // Ponte: uno tiene la pedana, l'altro attraversa e tiene quella opposta.
    expect(walk(g, {0: 42, 1: 40}), isTrue);
    expect(walk(g, {1: 53}), isTrue);
    expect(walk(g, {0: 55}), isTrue);
    expect(walk(g, {0: 67.2, 1: 67.9}), isTrue);
    expect(finish(g), 2);
  });

  test('livello 1 da soli con la cassa', () {
    final g = start(1);
    // Spinge la cassa sotto il tetto, ci sale e lo scavalca.
    expect(walk(g, {0: 21}), isTrue);
    walk(g, {0: 25}, hop: false);
    expect(g.crates.first.x, greaterThan(25 * 8));
    jump(g, 0, 25.5);
    jump(g, 0, 30);
    expect(walk(g, {0: 37}), isTrue);
    // Seconda cassa sulla pedana del ponte.
    walk(g, {0: 41.2}, hop: false);
    expect(g.solidAt(45, 13), isTrue, reason: 'il ponte è comparso');
    // La cassa resta sulla pedana: la si scavalca.
    jump(g, 0, 42);
    expect(walk(g, {0: 67.5}), isTrue);
    expect(finish(g), 2);
  });

  test('livello 2 in due: porta a pedane e scalino che compare', () {
    final g = start(2, level: 2);
    expect(walk(g, {0: 28, 1: 30}), isTrue);
    expect(walk(g, {0: 37}), isTrue);
    expect(walk(g, {1: 39}), isTrue);
    expect(walk(g, {0: 40}), isTrue);
    // Altopiano alto tre caselle: 1 sale grazie a 0, preme la pedana z.
    expect(walk(g, {0: 46, 1: 44}), isTrue);
    jump(g, 1, 46);
    jump(g, 1, 52);
    expect(g.solidAt(47, 12), isTrue, reason: 'lo scalino è comparso');
    expect(walk(g, {0: 50}), isTrue);
    expect(walk(g, {0: 63, 1: 62}), isTrue);
    // Spuntoni: si salta di piattaforma in piattaforma.
    expect(walk(g, {0: 65, 1: 64}, hop: false), isTrue);
    for (final p in [0, 1]) {
      jump(g, p, 67.5);
      jump(g, p, 70.5);
      jump(g, p, 75);
    }
    expect(walk(g, {0: 88.2, 1: 88.9}), isTrue);
    expect(finish(g), 3);
  });

  test('livello 3 in due: porta a tempo e gran finale', () {
    final g = start(2, level: 3);
    expect(walk(g, {0: 22, 1: 28}), isTrue);
    expect(walk(g, {0: 34, 1: 33}), isTrue);
    expect(walk(g, {0: 39, 1: 37}), isTrue);
    expect(walk(g, {1: 50}), isTrue);
    expect(walk(g, {0: 52}), isTrue);
    expect(walk(g, {0: 54, 1: 56}), isTrue);
    jump(g, 0, 56);
    jump(g, 0, 60);
    expect(walk(g, {1: 66}), isTrue);
    expect(walk(g, {0: 67}), isTrue);
    expect(walk(g, {0: 83, 1: 82}), isTrue);
    for (final p in [0, 1]) {
      jump(g, p, 85.5);
      jump(g, p, 90);
      // Chi è passato fa spazio, così l'altro non gli atterra in testa.
      expect(walk(g, {p: 93.0 - p}), isTrue);
    }
    expect(walk(g, {0: 96.2, 1: 96.9}), isTrue);
    expect(finish(g), 4);
  });

  test('livelli 2 e 3 da soli con le casse', () {
    final g = start(1, level: 2);
    expect(walk(g, {0: 25}), isTrue);
    walk(g, {0: 29.2}, hop: false);
    jump(g, 0, 30);
    expect(walk(g, {0: 42}), isTrue);
    walk(g, {0: 46.2}, hop: false);
    jump(g, 0, 46.5);
    jump(g, 0, 50);
    expect(walk(g, {0: 64}, hop: false), isTrue);
    jump(g, 0, 67.5);
    jump(g, 0, 70.5);
    jump(g, 0, 75);
    expect(walk(g, {0: 88.5}), isTrue);
    expect(finish(g), 3);
    for (final w in g.walkers) {
      w.alive = false;
    }
    expect(walk(g, {0: 18}), isTrue);
    walk(g, {0: 21.2}, hop: false);
    jump(g, 0, 22);
    expect(walk(g, {0: 28}), isTrue);
    expect(walk(g, {0: 34}), isTrue, reason: 'porta a tempo');
    walk(g, {0: 36}, hop: false);
    walk(g, {0: 38.2}, hop: false);
    jump(g, 0, 39);
    expect(walk(g, {0: 52}), isTrue);
    walk(g, {0: 55.2}, hop: false);
    jump(g, 0, 55.5);
    jump(g, 0, 60);
    expect(walk(g, {0: 83}), isTrue);
    jump(g, 0, 85.5);
    jump(g, 0, 90);
    expect(walk(g, {0: 96.5}), isTrue);
    expect(finish(g), 4);
  });

  test('livello 4 in due: chiavi, ponte e gabbia', () {
    final g = start(2, level: 4);
    expect(walk(g, {0: 11, 1: 13}), isTrue);
    jump(g, 0, 13);
    jump(g, 0, 15);
    expect(g.heroes[0].key, isNotNull, reason: 'prima chiave');
    expect(walk(g, {0: 23, 1: 22}), isTrue);
    walk(g, {0: 25.4}, hop: false);
    expect(g.heroes[0].key, isNull, reason: 'lucchetto aperto');
    expect(walk(g, {0: 30, 1: 29}), isTrue);
    expect(walk(g, {1: 32}), isTrue);
    expect(walk(g, {0: 43}), isTrue);
    expect(walk(g, {1: 45}), isTrue);
    // Gabbia: uno tiene la pedana fuori, l'altro entra e tiene quella dentro.
    expect(walk(g, {1: 48}), isTrue);
    expect(walk(g, {0: 52}), isTrue);
    expect(walk(g, {1: 55}), isTrue);
    jump(g, 0, 55);
    jump(g, 0, 56.5);
    expect(g.heroes[0].key, isNotNull, reason: 'seconda chiave');
    walk(g, {0: 58.4}, hop: false);
    expect(g.heroes[0].key, isNull);
    expect(walk(g, {0: 63, 1: 61}), isTrue);
    expect(walk(g, {0: 84.2, 1: 84.9}), isTrue);
    expect(finish(g), 5);
  });

  test('livello 4 da soli', () {
    final g = start(1, level: 4);
    expect(walk(g, {0: 9}), isTrue);
    walk(g, {0: 12.2}, hop: false);
    jump(g, 0, 13.3);
    jump(g, 0, 15);
    expect(g.heroes[0].key, isNotNull);
    walk(g, {0: 25.4});
    expect(g.heroes[0].key, isNull);
    expect(walk(g, {0: 29}), isTrue);
    walk(g, {0: 31.2}, hop: false);
    jump(g, 0, 32);
    expect(walk(g, {0: 45}), isTrue);
    walk(g, {0: 47.2}, hop: false);
    jump(g, 0, 48);
    expect(walk(g, {0: 53}), isTrue);
    walk(g, {0: 54.2}, hop: false);
    jump(g, 0, 55.3);
    jump(g, 0, 56.5);
    expect(g.heroes[0].key, isNotNull);
    walk(g, {0: 58.4}, hop: false);
    expect(g.heroes[0].key, isNull);
    expect(walk(g, {0: 84.5}), isTrue);
    expect(finish(g), 5);
  });

  test('livello 5 in due: uno sopra e uno sotto', () {
    final g = start(2, level: 5);
    expect(walk(g, {0: 12, 1: 10}), isTrue);
    jump(g, 0, 14.5);
    jump(g, 0, 17.5);
    jump(g, 0, 21);
    expect(g.heroes[0].y, lessThan(64));
    expect(walk(g, {0: 27}), isTrue);
    expect(walk(g, {1: 34}), isTrue);
    expect(walk(g, {0: 44}), isTrue);
    expect(walk(g, {1: 51}), isTrue);
    expect(walk(g, {0: 60}), isTrue);
    expect(walk(g, {0: 65, 1: 64}), isTrue);
    expect(walk(g, {0: 82.2, 1: 82.9}), isTrue);
    expect(finish(g), 6);
  });

  test('livello 5: senza il compagno sopra la porta di sotto resta chiusa', () {
    final g = start(2, level: 5);
    expect(walk(g, {0: 33, 1: 32}), isFalse);
  });

  test('livello 5 da soli sul camminamento', () {
    final g = start(1, level: 5);
    expect(walk(g, {0: 12}), isTrue);
    jump(g, 0, 14.5);
    jump(g, 0, 17.5);
    jump(g, 0, 21);
    expect(walk(g, {0: 64}), isTrue);
    expect(walk(g, {0: 82.5}), isTrue);
    expect(finish(g), 6);
  });

  test('livello 6 in due e finale della storia', () {
    final g = start(2, level: 6);
    expect(walk(g, {0: 8, 1: 18}), isTrue);
    expect(walk(g, {0: 24, 1: 23}), isTrue, reason: 'porta a tempo');
    expect(walk(g, {1: 27}), isTrue);
    expect(walk(g, {0: 38}), isTrue);
    expect(walk(g, {1: 41}), isTrue);
    jump(g, 0, 41);
    jump(g, 0, 43);
    expect(g.heroes[0].key, isNotNull);
    walk(g, {0: 45.4}, hop: false);
    expect(g.heroes[0].key, isNull);
    expect(walk(g, {0: 49, 1: 51}), isTrue);
    jump(g, 0, 51);
    jump(g, 0, 56);
    expect(walk(g, {1: 61}), isTrue);
    expect(walk(g, {0: 66, 1: 68}), isTrue);
    jump(g, 0, 68);
    jump(g, 0, 72);
    expect(walk(g, {0: 74}), isTrue);
    expect(walk(g, {1: 72}), isTrue);
    expect(walk(g, {0: 88.2, 1: 88.9}), isTrue);
    expect(finish(g), -1);
    expect(g.won, isTrue);
  });

  test('livello 6 da soli', () {
    final g = start(1, level: 6);
    expect(walk(g, {0: 4}), isTrue);
    walk(g, {0: 7.2}, hop: false);
    jump(g, 0, 8.5);
    expect(walk(g, {0: 18}), isTrue);
    expect(walk(g, {0: 23}), isTrue, reason: 'porta a tempo');
    walk(g, {0: 26.2}, hop: false);
    jump(g, 0, 27);
    expect(walk(g, {0: 39}), isTrue);
    walk(g, {0: 40.2}, hop: false);
    jump(g, 0, 41);
    jump(g, 0, 43);
    expect(g.heroes[0].key, isNotNull);
    walk(g, {0: 45.4}, hop: false);
    expect(g.heroes[0].key, isNull);
    expect(walk(g, {0: 48}), isTrue);
    walk(g, {0: 50.2}, hop: false);
    jump(g, 0, 51);
    jump(g, 0, 55);
    expect(walk(g, {0: 63}), isTrue);
    walk(g, {0: 68.2}, hop: false);
    jump(g, 0, 69.2);
    jump(g, 0, 72);
    expect(walk(g, {0: 88.5}), isTrue);
    expect(finish(g), -1);
    expect(g.won, isTrue);
  });

  test('la storia si sfoglia con OK', () {
    final g = TandemGame()
      ..players = 1
      ..reset();
    expect(g.inStory, isTrue);
    for (var i = 0; i < 40 && g.inStory; i++) {
      g.onPlayerKey(0, LogicalKeyboardKey.enter);
    }
    expect(g.inStory, isFalse);
  });

  test('cassa: si spinge, ci si salta sopra e ci si resta', () {
    for (final dt in [1 / 60, 1 / 30, 0.05]) {
      final g = start(1);
      final hero = g.heroes[0], crate = g.crates.first;
      hero.x = 19 * 8;
      g.pads[0].add(_r);
      // Spinge tenendo premuto: la cassa avanza.
      for (var i = 0; i < 0.8 / dt; i++) {
        g.update(dt);
      }
      expect(crate.x, greaterThan(23 * 8 + 4), reason: 'spinta a $dt');
      // Salto mentre spinge, sempre tenendo premuto a destra: atterra sopra.
      g.onPlayerKey(0, _up);
      var lowest = 0.0;
      for (var i = 0; i < 0.2 / dt; i++) {
        g.update(dt);
        lowest = hero.y > lowest ? hero.y : lowest;
      }
      expect(lowest, lessThanOrEqualTo(94), reason: 'mai dentro il terreno');
      // Lascia il tasto in volo: atterra sulla cassa e non scivola giù.
      g.pads[0].clear();
      for (var i = 0; i < 1 / dt; i++) {
        g.update(dt);
      }
      expect(hero.y, closeTo(crate.y - 10, 0.01), reason: 'fermo sulla cassa');
      expect(hero.grounded, isTrue);
    }
  });

  test('chi aspetta all\'uscita non basta: servono tutti', () {
    final g = start(2);
    g.heroes[0]
      ..x = 67 * 8 + 1
      ..y = 94;
    g.heroes[1]
      ..x = 40 * 8
      ..y = 94;
    for (var i = 0; i < 120; i++) {
      g.update(1 / 60);
    }
    expect(g.level, 1);
  });
}
