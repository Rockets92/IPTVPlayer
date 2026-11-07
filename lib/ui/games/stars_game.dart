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

class _Basket {
  _Basket(this.player, this.x);
  final int player;
  double x, hurt = 0;
  int lives = 3, mult = 1, streak = 0, score = 0;
  bool get alive => lives > 0;
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
  int get maxPlayers => 4;
  @override
  List<String> get help => [
    '← →: MUOVI IL CESTINO',
    'STELLA 10  COMETA 50  BOMBA = -1 VITA',
    'PRESE DI FILA: MOLTIPLICATORE FINO A x5',
  ];
  @override
  Size get size => const Size(w, h);
  @override
  String get status => players == 1
      ? 'x$mult  VITE ${'♥' * lives}'
      : [
          for (final b in baskets)
            'G${b.player + 1}${b.alive ? '♥' * b.lives : ' KO'}',
        ].join(' ');

  static const by = 104.0;
  double get bw => players > 2 ? 18 : 20;
  final baskets = <_Basket>[];

  /// Il cestino del telecomando (gioco in singolo e test).
  _Basket get _p1 => baskets.first;
  double get bx => _p1.x;
  int get lives => _p1.lives;
  int get mult => _p1.mult;
  final items = <_Item>[];
  final pops = <_Pop>[];
  late List<Offset> _sky;
  double _t = 0, _spawn = 0, _elapsed = 0;

  @override
  void reset() {
    final n = players.clamp(1, 4);
    baskets
      ..clear()
      ..addAll([for (var i = 0; i < n; i++) _Basket(i, w * (i + 1) / (n + 1))]);
    items.clear();
    pops.clear();
    _elapsed = 0;
    _spawn = 0.5;
    _sky = [
      for (var i = 0; i < 40; i++)
        Offset(rnd.nextDouble() * w, rnd.nextDouble() * 90),
    ];
  }

  @override
  void onPlayerKey(int p, LogicalKeyboardKey k) {
    if (p >= baskets.length) return;
    final b = baskets[p];
    if (k == LogicalKeyboardKey.arrowLeft) b.x -= 8;
    if (k == LogicalKeyboardKey.arrowRight) b.x += 8;
  }

  @override
  void onKey(LogicalKeyboardKey k) => onPlayerKey(0, k);

  List<_Basket> get _ranked =>
      [...baskets]..sort((a, b) => b.score.compareTo(a.score));

  @override
  String? get endTitle =>
      players == 1 ? null : 'VINCE G${_ranked.first.player + 1}!';

  @override
  List<String> get results => players == 1
      ? const []
      : [
          for (final (i, b) in _ranked.indexed)
            '${i + 1}. G${b.player + 1} '
                '${names.length > b.player ? names[b.player] : ''}  ${b.score} PUNTI',
        ];

  @override
  void update(double dt) {
    _t += dt;
    _elapsed += dt;
    for (final b in baskets) {
      b.hurt = max(0, b.hurt - dt);
      if (!b.alive) continue;
      if (heldBy(b.player, LogicalKeyboardKey.arrowLeft)) b.x -= 130 * dt;
      if (heldBy(b.player, LogicalKeyboardKey.arrowRight)) b.x += 130 * dt;
      b.x = b.x.clamp(bw / 2 + 1, w - bw / 2 - 1);
    }

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
      // Se due cestini si sovrappongono, prende chi è più vicino.
      _Basket? b;
      if (it.y >= by - 3 && it.y <= by + 3) {
        for (final c in baskets) {
          if (!c.alive || (it.x - c.x).abs() > bw / 2 + 2) continue;
          if (b == null || (it.x - c.x).abs() < (it.x - b.x).abs()) b = c;
        }
      }
      if (b != null) {
        switch (it.kind) {
          case _Kind.bomb:
            b
              ..lives -= 1
              ..hurt = 0.4
              ..streak = 0
              ..mult = 1;
            sound(Sfx.bomb);
            buzz(b.player, 400);
            pops.add(_Pop(it.x, it.y - 6, 'BOOM', Retro.red));
            if (baskets.every((c) => !c.alive)) over = true;
          case _Kind.star || _Kind.comet:
            final pts = (it.kind == _Kind.comet ? 50 : 10) * b.mult;
            sound(it.kind == _Kind.comet ? Sfx.bonus : Sfx.eat);
            b
              ..score += pts
              ..streak += 1;
            score = baskets.fold(0, (a, c) => max(a, c.score));
            final before = b.mult;
            b.mult = min(5, 1 + b.streak ~/ 5);
            if (b.mult > before) sound(Sfx.level);
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
        // Una stella persa azzera la serie (le bombe no): in singolo.
        if (it.kind != _Kind.bomb && players == 1) {
          _p1
            ..streak = 0
            ..mult = 1;
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
    final hurt = players == 1 ? _p1.hurt : 0.0;
    if (hurt > 0) {
      p.rect(0, 0, w, h, Retro.red.withValues(alpha: hurt * 0.6));
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
    // Cestini a righe.
    for (final b in baskets) {
      if (!b.alive) continue;
      final l = b.x - bw / 2;
      final c = players == 1 ? Retro.magenta : Retro.players[b.player];
      final dark = Color.lerp(c, Retro.bg, 0.35)!;
      final light = b.hurt > 0 && (_t * 20).floor().isEven
          ? Retro.red
          : Color.lerp(c, Retro.white, 0.15)!;
      p.glow(l, by, bw, 1, c, r: 2);
      for (var y = 1; y < 5; y++) {
        p.rect(
          l + y * 0.5,
          by + y,
          bw - y.toDouble(),
          1,
          y.isOdd ? dark : light,
        );
      }
      if (players > 1) {
        p.label('${b.player + 1}', b.x, by + 4.2, Retro.white, size: 4);
      }
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
