import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'retro.dart';
import 'sfx.dart';

enum _Kind { star, comet, bomb }

class _Item {
  _Item(this.x, this.y, this.vy, this.kind);
  double x, y, vy;
  final _Kind kind;
  double spin = 0;
}

class _Pop {
  _Pop(this.x, this.y, this.text, this.color);
  double x, y, life = 0.9;
  final String text;
  final Color color;
}

/// STELLE CADENTI: col cestino si raccolgono stelle e comete, evitando le
/// bombe. Prese di fila aumentano il moltiplicatore.
class StarsGame extends RetroGame {
  static const w = 160.0, h = 120.0;

  @override
  String get id => 'stars';
  @override
  String get title => 'STELLE CADENTI';
  @override
  List<String> get help => [
    '← →: MUOVI IL CESTINO',
    'STELLA 10  COMETA 50  BOMBA = -1 VITA',
    'PRESE DI FILA: MOLTIPLICATORE FINO A x5',
  ];
  @override
  Size get size => const Size(w, h);
  @override
  String get status => 'x$mult  VITE ${'♥' * lives}';

  double bx = w / 2;
  static const bw = 20.0, by = 104.0;
  int lives = 3, mult = 1, _streak = 0;
  final items = <_Item>[];
  final pops = <_Pop>[];
  late List<Offset> _sky;
  double _t = 0, _spawn = 0, _elapsed = 0, _hurt = 0;

  @override
  void reset() {
    bx = w / 2;
    lives = 3;
    mult = 1;
    _streak = 0;
    items.clear();
    pops.clear();
    _elapsed = 0;
    _spawn = 0.5;
    _hurt = 0;
    _sky = [
      for (var i = 0; i < 40; i++)
        Offset(rnd.nextDouble() * w, rnd.nextDouble() * 90),
    ];
  }

  @override
  void onKey(LogicalKeyboardKey k) {
    if (k == LogicalKeyboardKey.arrowLeft) bx -= 8;
    if (k == LogicalKeyboardKey.arrowRight) bx += 8;
  }

  @override
  void update(double dt) {
    _t += dt;
    _elapsed += dt;
    _hurt = max(0, _hurt - dt);
    if (left) bx -= 130 * dt;
    if (right) bx += 130 * dt;
    bx = bx.clamp(bw / 2 + 1, w - bw / 2 - 1);

    // Più passa il tempo, più cade roba e più veloce.
    final level = min(_elapsed / 20, 4.0);
    _spawn -= dt;
    if (_spawn <= 0) {
      _spawn = max(0.28, 0.9 - level * 0.15) * (0.7 + rnd.nextDouble() * 0.6);
      final r = rnd.nextDouble();
      final kind = r < 0.08
          ? _Kind.comet
          : r < 0.08 + min(0.18 + level * 0.05, 0.38)
          ? _Kind.bomb
          : _Kind.star;
      final v =
          (26 + level * 9) *
          (kind == _Kind.comet ? 1.7 : 1) *
          (0.85 + rnd.nextDouble() * 0.3);
      items.add(_Item(6 + rnd.nextDouble() * (w - 12), 4, v, kind));
    }
    for (final it in items) {
      it.y += it.vy * dt;
      it.spin += dt * 6;
    }
    for (final pop in pops) {
      pop
        ..y -= 14 * dt
        ..life -= dt;
    }
    pops.removeWhere((p) => p.life <= 0);

    items.removeWhere((it) {
      final caught =
          it.y >= by - 3 && it.y <= by + 3 && (it.x - bx).abs() <= bw / 2 + 2;
      if (caught) {
        switch (it.kind) {
          case _Kind.bomb:
            lives--;
            _hurt = 0.4;
            sound(Sfx.bomb);
            _streak = 0;
            mult = 1;
            pops.add(_Pop(it.x, it.y - 6, 'BOOM', Retro.red));
            if (lives <= 0) over = true;
          case _Kind.star || _Kind.comet:
            final pts = (it.kind == _Kind.comet ? 50 : 10) * mult;
            sound(it.kind == _Kind.comet ? Sfx.bonus : Sfx.eat);
            score += pts;
            _streak++;
            final before = mult;
            mult = min(5, 1 + _streak ~/ 5);
            if (mult > before) sound(Sfx.level);
            pops.add(
              _Pop(
                it.x,
                it.y - 6,
                '+$pts',
                it.kind == _Kind.comet ? Retro.orange : Retro.yellow,
              ),
            );
        }
        return true;
      }
      if (it.y > h + 4) {
        // Una stella persa azzera la serie (le bombe no).
        if (it.kind != _Kind.bomb) {
          _streak = 0;
          mult = 1;
        }
        return true;
      }
      return false;
    });
  }

  static const _star = ['..Y..', '.YWY.', 'YWWWY', '.YWY.', '..Y..'];
  static const _comet = ['..OOY', '.OYWY', 'OYWWY', '.OYY.', '..O..'];
  static const _bomb = ['...R.', '..K..', '.KKK.', 'KKGKK', '.KKK.'];

  @override
  void paint(Canvas canvas) {
    final p = Pix(canvas);
    // Cielo notturno a fasce, stelline che brillano, luna.
    for (var i = 0; i < 6; i++) {
      p.rect(
        0,
        i * 20.0,
        w,
        20,
        Color.lerp(const Color(0xFF0B0A24), const Color(0xFF2A0F3B), i / 5)!,
      );
    }
    for (var i = 0; i < _sky.length; i++) {
      final tw = sin(_t * 3 + i) > 0.6;
      p.rect(
        _sky[i].dx,
        _sky[i].dy,
        1,
        1,
        tw ? Retro.white : const Color(0xFF5A5690),
      );
    }
    p.sprite(
      128,
      10,
      const ['.WWW.', 'WWWW.', 'WWW..', 'WWWW.', '.WWW.'],
      {'W': const Color(0xFFEDE6C8)},
      size: 2,
    );
    // Prato pixel.
    p.rect(0, 110, w, 10, const Color(0xFF123A24));
    for (var x = 0.0; x < w; x += 4) {
      p.rect(x, 109, 1, 1, Retro.green.withValues(alpha: 0.6));
    }
    if (_hurt > 0) {
      p.rect(0, 0, w, h, Retro.red.withValues(alpha: _hurt * 0.6));
    }
    for (final it in items) {
      final rows = switch (it.kind) {
        _Kind.star => _star,
        _Kind.comet => _comet,
        _Kind.bomb => _bomb,
      };
      if (it.kind == _Kind.comet) {
        // Scia della cometa.
        for (var k = 1; k <= 4; k++) {
          p.rect(
            it.x - 0.5,
            it.y - 2.5 - k * 3,
            1,
            2,
            Retro.orange.withValues(alpha: 0.6 - k * 0.12),
          );
        }
      }
      p.sprite(it.x - 2.5, it.y - 2.5, rows, {
        'Y': it.kind == _Kind.comet ? Retro.yellow : Retro.yellow,
        'W': Retro.white,
        'O': Retro.orange,
        'K': const Color(0xFF3A3550),
        'G': const Color(0xFF8A86B0),
        'R': (_t * 10).floor().isEven ? Retro.red : Retro.yellow,
      });
    }
    // Cestino a righe.
    final l = bx - bw / 2;
    p.glow(l, by, bw, 1, Retro.magenta, r: 2);
    for (var y = 1; y < 5; y++) {
      p.rect(
        l + y * 0.5,
        by + y,
        bw - y.toDouble(),
        1,
        y.isOdd ? const Color(0xFFB0306E) : const Color(0xFFE05596),
      );
    }
    for (final pop in pops) {
      final a = pop.life.clamp(0.0, 1.0);
      final tp = TextPainter(
        text: TextSpan(
          text: pop.text,
          style: Retro.text(5, color: pop.color.withValues(alpha: a), glow: 0),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(pop.x - tp.width / 2, pop.y));
    }
  }
}
