import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../widgets/focus_tile.dart';
import 'retro.dart';

class _Brick {
  _Brick(this.rect, this.color, this.points, this.hits);
  final Rect rect;
  final Color color;
  final int points;
  int hits;
}

class _Spark {
  _Spark(this.x, this.y, this.vx, this.vy, this.color);
  double x, y, vx, vy, life = 0.6;
  final Color color;
}

/// MATTONCINI: con la racchetta si rimbalza la pallina e si abbattono i
/// mattoncini. I mattoncini argentati vanno colpiti due volte.
class BricksGame extends RetroGame {
  static const w = 160.0, h = 120.0;
  static const _cols = 10, _rows = 6;

  @override
  String get id => 'bricks';
  @override
  String get title => 'MATTONCINI';
  @override
  List<String> get help => [
    '← →: MUOVI LA RACCHETTA',
    'OK: LANCIA LA PALLINA',
    'GLI ARGENTATI VANNO COLPITI DUE VOLTE',
  ];
  @override
  Size get size => const Size(w, h);
  @override
  String get status => 'LIVELLO $level  VITE ${'♥' * lives}';

  double px = w / 2, pw = 28;
  static const py = 110.0, ph = 3.0, r = 1.6;
  double bx = 0, by = 0, vx = 0, vy = 0, speed = 85;
  bool stuck = true;
  int lives = 3, level = 1;
  var bricks = <_Brick>[];
  final sparks = <_Spark>[];
  double _t = 0, _shake = 0;

  @override
  void reset() {
    lives = 3;
    level = 1;
    px = w / 2;
    _build();
  }

  void _build() {
    bricks = [];
    const bw = 14.0, bh = 5.0, gap = 1.0;
    const x0 = (w - _cols * (bw + gap) + gap) / 2;
    for (var j = 0; j < _rows; j++) {
      for (var i = 0; i < _cols; i++) {
        // Dal secondo livello la fila in alto è argentata (due colpi).
        final silver = level >= 2 && j == 0;
        // Disegni diversi a ogni livello.
        final skip = switch (level % 3) {
          2 => (i + j).isOdd && j > 1,
          0 => (i == 4 || i == 5) && j > 0,
          _ => false,
        };
        if (skip) continue;
        bricks.add(
          _Brick(
            Rect.fromLTWH(x0 + i * (bw + gap), 14 + j * (bh + gap), bw, bh),
            silver ? const Color(0xFFC9CCE8) : Retro.rainbow[j % 7],
            (_rows - j) * 10,
            silver ? 2 : 1,
          ),
        );
      }
    }
    speed = 85 + (level - 1) * 12;
    stuck = true;
  }

  void _launch() {
    if (!stuck) return;
    stuck = false;
    final a = -pi / 2 + (rnd.nextDouble() - 0.5) * 0.8;
    vx = cos(a) * speed;
    vy = sin(a) * speed;
  }

  @override
  void onKey(LogicalKeyboardKey k) {
    if (isSelectKey(k) ||
        k == LogicalKeyboardKey.space ||
        k == LogicalKeyboardKey.arrowUp) {
      _launch();
    } else if (k == LogicalKeyboardKey.arrowLeft) {
      px -= 6; // un tocco sposta un po' anche senza tenere premuto
    } else if (k == LogicalKeyboardKey.arrowRight) {
      px += 6;
    }
  }

  @override
  void update(double dt) {
    _t += dt;
    _shake = max(0, _shake - dt);
    if (left) px -= 150 * dt;
    if (right) px += 150 * dt;
    px = px.clamp(pw / 2 + 1, w - pw / 2 - 1);
    for (final s in sparks) {
      s
        ..x += s.vx * dt
        ..y += s.vy * dt
        ..vy += 120 * dt
        ..life -= dt;
    }
    sparks.removeWhere((s) => s.life <= 0);
    if (stuck) {
      bx = px;
      by = py - r - 0.5;
      return;
    }
    const steps = 4;
    for (var i = 0; i < steps && !over; i++) {
      _move(dt / steps);
    }
  }

  void _move(double dt) {
    bx += vx * dt;
    by += vy * dt;
    if (bx < r + 1) {
      bx = r + 1;
      vx = vx.abs();
    } else if (bx > w - r - 1) {
      bx = w - r - 1;
      vx = -vx.abs();
    }
    if (by < r + 9) {
      by = r + 9;
      vy = vy.abs();
    }
    // Racchetta: l'angolo dipende da dove la si colpisce.
    if (vy > 0 &&
        by + r >= py &&
        by - r <= py + ph &&
        (bx - px).abs() <= pw / 2 + r) {
      final f = ((bx - px) / (pw / 2)).clamp(-1.0, 1.0);
      final a = -pi / 2 + f * 1.1;
      vx = cos(a) * speed;
      vy = sin(a) * speed;
      by = py - r;
    }
    final ball = Rect.fromCircle(center: Offset(bx, by), radius: r);
    for (final b in bricks) {
      if (b.hits <= 0 || !b.rect.overlaps(ball)) continue;
      final ox = min(ball.right - b.rect.left, b.rect.right - ball.left);
      final oy = min(ball.bottom - b.rect.top, b.rect.bottom - ball.top);
      if (ox < oy) {
        vx = -vx;
      } else {
        vy = -vy;
      }
      b.hits--;
      if (b.hits == 0) {
        score += b.points;
        _burst(b.rect.center, b.color);
        speed = min(speed + 1.2, 170);
        final s = sqrt(vx * vx + vy * vy);
        vx = vx / s * speed;
        vy = vy / s * speed;
      } else {
        _burst(b.rect.center, Retro.white, n: 4);
      }
      break;
    }
    bricks.removeWhere((b) => b.hits <= 0);
    if (bricks.isEmpty) {
      score += 100 * level;
      level++;
      _build();
      return;
    }
    if (by > h + 4) {
      lives--;
      _shake = 0.35;
      if (lives <= 0) {
        over = true;
      } else {
        stuck = true;
      }
    }
  }

  void _burst(Offset c, Color color, {int n = 9}) {
    for (var i = 0; i < n; i++) {
      final a = rnd.nextDouble() * pi * 2;
      final v = 20 + rnd.nextDouble() * 40;
      sparks.add(_Spark(c.dx, c.dy, cos(a) * v, sin(a) * v - 20, color));
    }
  }

  @override
  void paint(Canvas canvas) {
    final p = Pix(canvas);
    if (_shake > 0) {
      canvas.translate(sin(_t * 90) * _shake * 4, 0);
      p.rect(0, 0, w, h, Retro.red.withValues(alpha: _shake * 0.5));
    }
    // Cornice del campo.
    const edge = Color(0xFF3B3670);
    p.rect(0, 8, w, 1, edge);
    p.rect(0, 8, 1, h, edge);
    p.rect(w - 1, 8, 1, h, edge);
    for (final b in bricks) {
      final r = b.rect;
      p.glow(r.left, r.top, r.width, r.height, b.color, r: 2);
      // Luce in alto e ombra in basso: effetto a rilievo.
      p.rect(r.left, r.top, r.width, 1, const Color(0x88FFFFFF));
      p.rect(r.left, r.bottom - 1, r.width, 1, const Color(0x55000000));
      if (b.hits > 1) {
        p.rect(r.left + 2, r.top + 2, 2, 1, Retro.white);
      }
    }
    for (final s in sparks) {
      p.rect(
        s.x,
        s.y,
        1,
        1,
        s.color.withValues(alpha: s.life.clamp(0, 1) / 0.6),
      );
    }
    // Racchetta.
    p.glow(px - pw / 2, py, pw, ph, Retro.cyan, r: 3);
    p.rect(px - pw / 2, py, 3, ph, Retro.magenta);
    p.rect(px + pw / 2 - 3, py, 3, ph, Retro.magenta);
    p.rect(px - pw / 2 + 3, py, pw - 6, 1, Retro.white);
    // Pallina.
    p.glow(bx - r, by - r, r * 2, r * 2, Retro.white, r: 3);
    if (stuck && (_t * 3).floor().isEven) {
      p.rect(bx - 0.5, by - 8, 1, 4, Retro.yellow);
      p.rect(bx - 1.5, by - 7, 3, 1, Retro.yellow);
    }
  }
}
