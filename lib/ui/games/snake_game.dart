import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'retro.dart';
import 'sfx.dart';

class _Snake {
  _Snake(this.player, this.body, this.dir);
  final int player;
  List<Point<int>> body;
  Point<int> dir;
  final turns = <Point<int>>[];
  int grow = 0, score = 0;
  bool alive = true;
  double deadAt = 0;
}

/// SERPENTINA: il serpente cresce mangiando, non deve toccare i bordi né
/// la propria coda. Ogni 5 frutti compare per poco una stella bonus.
/// Fino a 4 giocatori: ognuno guida il suo serpente e vince chi resta.
class SnakeGame extends RetroGame {
  static const cols = 32, rows = 22, cell = 5.0;

  @override
  String get id => 'snake';
  @override
  String get title => 'SERPENTINA';
  @override
  int get maxPlayers => 4;
  @override
  List<String> get help => [
    'FRECCE: CAMBIA DIREZIONE',
    'MANGIA LE MELE, PRENDI LE STELLE BONUS',
    if (players > 1)
      'NON TOCCARE BORDI E SERPENTI: VINCE CHI RESTA'
    else
      'NON TOCCARE I BORDI NE\' LA CODA',
  ];
  @override
  Size get size => const Size(cols * cell, rows * cell);
  @override
  String get status => players == 1
      ? 'LUNGHEZZA ${body.length}'
      : [
          for (final s in snakes)
            'G${s.player + 1} ${s.alive ? s.body.length : 'KO'}',
        ].join('  ');

  final snakes = <_Snake>[];
  var food = const Point(0, 0);
  Point<int>? bonus;
  double bonusLeft = 0;
  double _acc = 0, _t = 0, _step = 0.12;
  int _eaten = 0;
  double _flash = 0;
  int? _winner;

  /// Il serpente del telecomando (per i test e il gioco in singolo).
  List<Point<int>> get body => snakes.first.body;
  Point<int> get dir => snakes.first.dir;

  @override
  void reset() {
    snakes.clear();
    // Partenze: sinistra, destra, alto, basso.
    const starts = [
      (Point(6, 11), Point(1, 0)),
      (Point(25, 10), Point(-1, 0)),
      (Point(15, 3), Point(0, 1)),
      (Point(16, 18), Point(0, -1)),
    ];
    for (var i = 0; i < players.clamp(1, 4); i++) {
      final (h, d) = starts[i];
      snakes.add(
        _Snake(i, [
          for (var k = 0; k < 3; k++) Point(h.x - d.x * k, h.y - d.y * k),
        ], d),
      );
    }
    if (players == 1) {
      snakes.first.body = [
        const Point(10, 11),
        const Point(9, 11),
        const Point(8, 11),
      ];
    }
    bonus = null;
    _acc = 0;
    _step = players > 1 ? 0.11 : 0.12;
    _eaten = 0;
    _flash = 0;
    _winner = null;
    food = _free();
  }

  bool _taken(Point<int> p) => snakes.any((s) => s.body.contains(p));

  Point<int> _free() {
    while (true) {
      final p = Point(1 + rnd.nextInt(cols - 2), 1 + rnd.nextInt(rows - 2));
      if (!_taken(p) && p != bonus && p != food) return p;
    }
  }

  @override
  void onPlayerKey(int p, LogicalKeyboardKey k) {
    if (p >= snakes.length) return;
    final s = snakes[p];
    if (!s.alive) return;
    final d = switch (k) {
      LogicalKeyboardKey.arrowUp => const Point(0, -1),
      LogicalKeyboardKey.arrowDown => const Point(0, 1),
      LogicalKeyboardKey.arrowLeft => const Point(-1, 0),
      LogicalKeyboardKey.arrowRight => const Point(1, 0),
      _ => null,
    };
    if (d == null) return;
    final last = s.turns.isEmpty ? s.dir : s.turns.last;
    // Niente inversioni a U e niente pressioni ripetute.
    if (d == last || d == Point(-last.x, -last.y)) return;
    if (s.turns.length < 2) s.turns.add(d);
  }

  @override
  void onKey(LogicalKeyboardKey k) => onPlayerKey(0, k);

  @override
  String? get endTitle => players == 1
      ? null
      : _winner == null
      ? 'PAREGGIO!'
      : 'VINCE G${_winner! + 1}!';

  @override
  List<String> get results {
    if (players == 1) return const [];
    final ranked = [...snakes]
      ..sort((a, b) {
        if (a.alive != b.alive) return a.alive ? -1 : 1;
        if (a.deadAt != b.deadAt) return b.deadAt.compareTo(a.deadAt);
        return b.score.compareTo(a.score);
      });
    return [
      for (final (i, s) in ranked.indexed)
        '${i + 1}. G${s.player + 1} ${names.length > s.player ? names[s.player] : ''}'
            '  ${s.score} PUNTI',
    ];
  }

  @override
  void update(double dt) {
    _t += dt;
    _flash = max(0, _flash - dt);
    if (bonus != null) {
      bonusLeft -= dt;
      if (bonusLeft <= 0) bonus = null;
    }
    _acc += dt;
    while (_acc >= _step && !over) {
      _acc -= _step;
      _advance();
    }
  }

  void _advance() {
    final live = snakes.where((s) => s.alive).toList();
    // Nuove teste di tutti, poi le collisioni: chi si scontra frontalmente
    // perde insieme all'altro.
    final heads = <_Snake, Point<int>>{};
    for (final s in live) {
      if (s.turns.isNotEmpty) s.dir = s.turns.removeAt(0);
      heads[s] = Point(s.body.first.x + s.dir.x, s.body.first.y + s.dir.y);
    }
    final dying = <_Snake>{};
    for (final s in live) {
      final h = heads[s]!;
      if (h.x < 0 || h.y < 0 || h.x >= cols || h.y >= rows) {
        dying.add(s);
        continue;
      }
      // Anche i serpenti eliminati restano sul campo come ostacolo.
      for (final o in snakes) {
        // La coda che si sposta in questo passo lascia libero il posto.
        final tailMoves = o.alive && o.grow == 0;
        final occupied = o.body.take(
          tailMoves ? o.body.length - 1 : o.body.length,
        );
        if (occupied.contains(h)) {
          dying.add(s);
          break;
        }
        if (o.alive && !identical(o, s) && heads[o] == h) {
          dying
            ..add(s)
            ..add(o);
        }
      }
    }
    for (final s in dying) {
      s
        ..alive = false
        ..deadAt = _t;
      if (players > 1) {
        sound(Sfx.hurt);
        buzz(s.player, 400);
      }
    }
    final survivors = live.where((s) => s.alive).toList();
    if (players == 1 ? survivors.isEmpty : survivors.length <= 1) {
      if (players > 1) {
        _winner = survivors.isEmpty ? null : survivors.first.player;
        won = survivors.isNotEmpty;
        score = snakes.fold(0, (a, s) => max(a, s.score));
      }
      over = true;
      return;
    }
    for (final s in survivors) {
      final h = heads[s]!;
      s.body.insert(0, h);
      if (h == food) {
        s
          ..score += 10
          ..grow += 2;
        sound(Sfx.eat);
        _eaten++;
        _flash = 0.15;
        food = _free();
        _step = max(0.055, (players > 1 ? 0.11 : 0.12) - _eaten * 0.0022);
        if (_eaten % 5 == 0) {
          bonus = _free();
          bonusLeft = 6;
          sound(Sfx.select);
        }
      } else if (h == bonus) {
        s
          ..score += 50 + (bonusLeft * 10).round()
          ..grow += 3;
        sound(Sfx.bonus);
        _flash = 0.3;
        bonus = null;
      }
      if (s.grow > 0) {
        s.grow--;
      } else {
        s.body.removeLast();
      }
    }
    score = players == 1
        ? snakes.first.score
        : snakes.fold(0, (a, s) => max(a, s.score));
  }

  @override
  void paint(Canvas canvas) {
    final p = Pix(canvas);
    // Griglia leggera, come la carta millimetrata del monitor.
    for (var x = 0; x < cols; x++) {
      for (var y = 0; y < rows; y++) {
        if ((x + y).isEven) {
          p.rect(x * cell, y * cell, cell, cell, const Color(0xFF0F0E22));
        }
      }
    }
    if (_flash > 0) {
      p.rect(
        0,
        0,
        size.width,
        size.height,
        Retro.green.withValues(alpha: _flash * 0.5),
      );
    }
    // Mela che pulsa.
    final pulse = 0.5 + 0.5 * sin(_t * 8);
    p.glow(
      food.x * cell + 0.5,
      food.y * cell + 1,
      4,
      4,
      Retro.red.withValues(alpha: 0.5),
      r: 2 + pulse * 3,
    );
    p.sprite(
      food.x * cell,
      food.y * cell,
      const ['...G.', '.RRG.', 'RWRRR', 'RRRRR', '.RRR.'],
      {
        'R': Color.lerp(Retro.red, Retro.orange, pulse * 0.4)!,
        'W': Retro.white,
        'G': Retro.green,
      },
    );
    // Stella bonus: lampeggia negli ultimi 2 secondi.
    final b = bonus;
    if (b != null && (bonusLeft > 2 || (_t * 8).floor().isEven)) {
      p.sprite(
        b.x * cell,
        b.y * cell,
        const ['..Y..', '.YYY.', 'YYWYY', '.YYY.', 'Y...Y'],
        {'Y': Retro.yellow, 'W': Retro.white},
      );
    }
    for (final sn in snakes) {
      _paintSnake(p, sn);
    }
    // Bordo.
    const edge = Color(0xFF3B3670);
    p.rect(0, 0, size.width, 0.6, edge);
    p.rect(0, size.height - 0.6, size.width, 0.6, edge);
    p.rect(0, 0, 0.6, size.height, edge);
    p.rect(size.width - 0.6, 0, 0.6, size.height, edge);
  }

  void _paintSnake(Pix p, _Snake sn) {
    final body = sn.body;
    final base = players == 1 ? Retro.green : Retro.players[sn.player];
    final stripe = players == 1
        ? const Color(0xFF2BD9A0)
        : Color.lerp(base, Retro.white, 0.35)!;
    // Serpente eliminato: grigio che lampeggia per un attimo, poi spento.
    if (!sn.alive && _t - sn.deadAt > 1.2) {
      for (final s in body) {
        p.rect(
          s.x * cell + 1,
          s.y * cell + 1,
          cell - 2,
          cell - 2,
          const Color(0xFF2A2650),
        );
      }
      return;
    }
    if (!sn.alive && (_t * 10).floor().isEven) return;
    // Testa chiara, corpo a strisce.
    for (var i = body.length - 1; i >= 0; i--) {
      final s = body[i];
      final c = i == 0 ? Retro.white : (i.isEven ? base : stripe);
      if (i == 0) {
        p.glow(s.x * cell, s.y * cell, cell, cell, base, r: 3);
      }
      p.rect(s.x * cell + 0.5, s.y * cell + 0.5, cell - 1, cell - 1, c);
    }
    // Occhi.
    final h = body.first;
    final dir = sn.dir;
    final ex = dir.x == 0 ? [1.0, 3.0] : [dir.x > 0 ? 3.0 : 1.0];
    final ey = dir.y == 0 ? [1.0, 3.0] : [dir.y > 0 ? 3.0 : 1.0];
    for (final x in ex) {
      for (final y in ey) {
        p.rect(h.x * cell + x, h.y * cell + y, 1, 1, Retro.bg);
      }
    }
  }
}
