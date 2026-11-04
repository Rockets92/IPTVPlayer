import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'retro.dart';

/// SERPENTINA: il serpente cresce mangiando, non deve toccare i bordi né
/// la propria coda. Ogni 5 frutti compare per poco una stella bonus.
class SnakeGame extends RetroGame {
  static const cols = 32, rows = 22, cell = 5.0;

  @override
  String get id => 'snake';
  @override
  String get title => 'SERPENTINA';
  @override
  List<String> get help => [
    'FRECCE: CAMBIA DIREZIONE',
    'MANGIA LE MELE, PRENDI LE STELLE BONUS',
    'NON TOCCARE I BORDI NE\' LA CODA',
  ];
  @override
  Size get size => const Size(cols * cell, rows * cell);
  @override
  String get status => 'LUNGHEZZA ${body.length}';

  var body = <Point<int>>[];
  var dir = const Point(1, 0);
  final _turns = <Point<int>>[];
  var food = const Point(0, 0);
  Point<int>? bonus;
  double bonusLeft = 0;
  double _acc = 0, _t = 0, _step = 0.12;
  int _grow = 0, _eaten = 0;
  double _flash = 0;

  @override
  void reset() {
    body = [const Point(10, 11), const Point(9, 11), const Point(8, 11)];
    dir = const Point(1, 0);
    _turns.clear();
    bonus = null;
    _acc = 0;
    _step = 0.12;
    _grow = 0;
    _eaten = 0;
    _flash = 0;
    food = _free();
  }

  Point<int> _free() {
    while (true) {
      final p = Point(1 + rnd.nextInt(cols - 2), 1 + rnd.nextInt(rows - 2));
      if (!body.contains(p) && p != bonus) return p;
    }
  }

  @override
  void onKey(LogicalKeyboardKey k) {
    final d = switch (k) {
      LogicalKeyboardKey.arrowUp => const Point(0, -1),
      LogicalKeyboardKey.arrowDown => const Point(0, 1),
      LogicalKeyboardKey.arrowLeft => const Point(-1, 0),
      LogicalKeyboardKey.arrowRight => const Point(1, 0),
      _ => null,
    };
    if (d == null) return;
    final last = _turns.isEmpty ? dir : _turns.last;
    // Niente inversioni a U e niente pressioni ripetute.
    if (d == last || d == Point(-last.x, -last.y)) return;
    if (_turns.length < 2) _turns.add(d);
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
    if (_turns.isNotEmpty) dir = _turns.removeAt(0);
    final h = Point(body.first.x + dir.x, body.first.y + dir.y);
    final tailMoves = _grow == 0;
    final hitsSelf = body
        .take(tailMoves ? body.length - 1 : body.length)
        .contains(h);
    if (h.x < 0 || h.y < 0 || h.x >= cols || h.y >= rows || hitsSelf) {
      over = true;
      return;
    }
    body.insert(0, h);
    if (h == food) {
      score += 10;
      _grow += 2;
      _eaten++;
      _flash = 0.15;
      food = _free();
      _step = max(0.055, 0.12 - _eaten * 0.0022);
      if (_eaten % 5 == 0) {
        bonus = _free();
        bonusLeft = 6;
      }
    } else if (h == bonus) {
      score += 50 + (bonusLeft * 10).round();
      _grow += 3;
      _flash = 0.3;
      bonus = null;
    }
    if (_grow > 0) {
      _grow--;
    } else {
      body.removeLast();
    }
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
    // Serpente: testa chiara, corpo a strisce verde/ciano.
    for (var i = body.length - 1; i >= 0; i--) {
      final s = body[i];
      final c = i == 0
          ? Retro.white
          : (i.isEven ? Retro.green : const Color(0xFF2BD9A0));
      if (i == 0) {
        p.glow(s.x * cell, s.y * cell, cell, cell, Retro.green, r: 3);
      }
      p.rect(s.x * cell + 0.5, s.y * cell + 0.5, cell - 1, cell - 1, c);
    }
    // Occhi.
    final h = body.first;
    final ex = dir.x == 0 ? [1.0, 3.0] : [dir.x > 0 ? 3.0 : 1.0];
    final ey = dir.y == 0 ? [1.0, 3.0] : [dir.y > 0 ? 3.0 : 1.0];
    for (final x in ex) {
      for (final y in ey) {
        p.rect(h.x * cell + x, h.y * cell + y, 1, 1, Retro.bg);
      }
    }
    // Bordo.
    const edge = Color(0xFF3B3670);
    p.rect(0, 0, size.width, 0.6, edge);
    p.rect(0, size.height - 0.6, size.width, 0.6, edge);
    p.rect(0, 0, 0.6, size.height, edge);
    p.rect(size.width - 0.6, 0, 0.6, size.height, edge);
  }
}
