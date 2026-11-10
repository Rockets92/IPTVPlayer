import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../widgets/focus_tile.dart';
import 'retro.dart';
import 'sfx.dart';

enum _Kind { drone, diver, turret, boss }

class _Enemy {
  _Enemy(this.kind, this.x, this.y, this.hp, {this.phase = 0});
  final _Kind kind;
  double x, y, vx = 0, vy = 0, t = 0, fire = 0, flash = 0;
  final double phase;
  int hp;
  late final int maxHp = hp;
  double get half => kind == _Kind.boss ? 14 : 4.5;
}

class _Ship {
  _Ship(this.player, this.x);
  final int player;
  double x, y = 104, hurt = 0, cool = 0;
  int lives = 3, power = 1;
  bool shield = false;
  bool get alive => lives > 0;
}

class _Shot {
  _Shot(this.x, this.y, this.vx, this.vy);
  double x, y, vx, vy;
}

class _Bit {
  _Bit(this.x, this.y, this.vx, this.vy, this.color, [this.life = 0.5]);
  double x, y, vx, vy, life;
  final Color color;
}

enum _Drop {
  power('P', Retro.orange),
  shield('S', Retro.cyan),
  bomb('B', Retro.magenta);

  const _Drop(this.letter, this.color);
  final String letter;
  final Color color;
}

class _Item {
  _Item(this.x, this.y, this.kind);
  double x, y;
  final _Drop kind;
}

/// ASTRO PATTUGLIA: sparatutto verticale. La navetta spara da sola, con le
/// frecce si schivano i colpi e con OK si sgancia una bomba che ripulisce
/// lo schermo. Ogni cinque ondate arriva una nave madre.
class SpaceGame extends RetroGame {
  static const w = 160.0, h = 120.0;

  @override
  String get id => 'space';
  @override
  String get title => 'ASTRO PATTUGLIA';
  @override
  int get maxPlayers => 4;
  @override
  List<String> get help => [
    'FRECCE: MUOVI LA NAVETTA (SPARA DA SOLA)',
    if (players > 1)
      'OK O TASTO A: BOMBA (LE BOMBE SONO DI SQUADRA)'
    else
      'OK: BOMBA, RIPULISCE LO SCHERMO',
    'CAPSULE: P POTENZA  S SCUDO  B BOMBA',
  ];
  @override
  Size get size => const Size(w, h);
  @override
  String get status => players == 1
      ? 'ONDATA $wave  BOMBE $bombs  VITE ${'♥' * lives}'
      : 'ONDATA $wave  BOMBE $bombs  '
            '${[for (final s in ships) 'G${s.player + 1}${s.alive ? '♥' * s.lives : ' KO'}'].join(' ')}';

  final ships = <_Ship>[];
  int bombs = 2, wave = 0;
  double _flash = 0, _t = 0, _next = 0, _banner = 0;

  /// La navetta del telecomando (gioco in singolo e test).
  _Ship get _p1 => ships.first;
  double get x => _p1.x;
  double get y => _p1.y;
  int get lives => _p1.lives;
  int get power => _p1.power;
  bool get shield => _p1.shield;
  final enemies = <_Enemy>[];
  final shots = <_Shot>[];
  final bullets = <_Shot>[];
  final bits = <_Bit>[];
  final items = <_Item>[];
  late List<(double, double, double)> _stars;

  @override
  void reset() {
    final n = players.clamp(1, 4);
    ships
      ..clear()
      ..addAll([for (var i = 0; i < n; i++) _Ship(i, w * (i + 1) / (n + 1))]);
    bombs = n > 1 ? 3 : 2;
    wave = 0;
    _next = 1;
    enemies.clear();
    shots.clear();
    bullets.clear();
    bits.clear();
    items.clear();
    _stars = [
      for (var i = 0; i < 46; i++)
        (rnd.nextDouble() * w, rnd.nextDouble() * h, 8 + rnd.nextDouble() * 40),
    ];
  }

  @override
  void onPlayerKey(int p, LogicalKeyboardKey k) {
    if (p >= ships.length || !ships[p].alive) return;
    if (isSelectKey(k) ||
        k == LogicalKeyboardKey.space ||
        k == LogicalKeyboardKey.keyB) {
      _bomb();
    }
  }

  @override
  void onKey(LogicalKeyboardKey k) => onPlayerKey(0, k);

  void _bomb() {
    if (bombs <= 0) return;
    bombs--;
    _flash = 0.5;
    sound(Sfx.bomb);
    bullets.clear();
    for (final e in [...enemies]) {
      _damage(e, e.kind == _Kind.boss ? 12 : 99);
    }
  }

  bool get boss => wave % 5 == 0;

  void _spawnWave() {
    wave++;
    _banner = 1.6;
    final speedUp = 1 + min(wave, 20) * 0.04;
    if (boss) {
      enemies.add(
        _Enemy(_Kind.boss, w / 2, -16, 60 + wave * 8)
          ..vx = 22 * speedUp
          ..vy = 18,
      );
      return;
    }
    switch (wave % 4) {
      case 1:
        // Fila di droni che ondeggia.
        for (var i = 0; i < 6 + min(wave ~/ 4, 4); i++) {
          enemies.add(
            _Enemy(_Kind.drone, 14.0 + i * 13, -8 - i * 6, 1, phase: i * 0.6)
              ..vy = 14 * speedUp,
          );
        }
      case 2:
        // Tuffatori da destra e sinistra.
        for (var i = 0; i < 6; i++) {
          final fromLeft = i.isEven;
          enemies.add(
            _Enemy(_Kind.diver, fromLeft ? -6 : w + 6, 14.0 + (i ~/ 2) * 9, 1)
              ..vx = (fromLeft ? 40 : -40) * speedUp
              ..t = -i * 0.35,
          );
        }
      case 3:
        // Torrette che scendono piano e sparano.
        for (var i = 0; i < 3 + min(wave ~/ 6, 2); i++) {
          enemies.add(
            _Enemy(_Kind.turret, 26.0 + i * 36 % (w - 40), -10, 4)
              ..vy = 9 * speedUp
              ..fire = 0.6 + i * 0.4,
          );
        }
      default:
        // Un po' di tutto.
        for (var i = 0; i < 5; i++) {
          enemies.add(
            _Enemy(_Kind.drone, 20.0 + i * 30, -8 - i * 10, 1, phase: i * 1.1)
              ..vy = 16 * speedUp,
          );
        }
        for (var i = 0; i < 2; i++) {
          enemies.add(
            _Enemy(_Kind.turret, 40.0 + i * 80, -14, 4)
              ..vy = 8 * speedUp
              ..fire = 1,
          );
        }
    }
  }

  @override
  void update(double dt) {
    _t += dt;
    _flash = max(0, _flash - dt);
    _banner = max(0, _banner - dt);
    for (final s in _stars.indexed) {
      final (sx, sy, v) = s.$2;
      _stars[s.$1] = (sx, (sy + v * dt) % h, v);
    }
    for (final sh in ships) {
      if (sh.alive) _ship(sh, dt);
    }
    for (final s in [...shots, ...bullets]) {
      s
        ..x += s.vx * dt
        ..y += s.vy * dt;
    }
    shots.removeWhere((s) => s.y < -4 || s.x < -4 || s.x > w + 4);
    bullets.removeWhere(
      (s) => s.y > h + 4 || s.y < -4 || s.x < -4 || s.x > w + 4,
    );
    for (final b in bits) {
      b
        ..x += b.vx * dt
        ..y += b.vy * dt
        ..life -= dt;
    }
    bits.removeWhere((b) => b.life <= 0);
    for (final i in items) {
      i.y += 26 * dt;
    }
    items.removeWhere((i) {
      if (i.y > h + 4) return true;
      for (final sh in ships) {
        if (sh.alive && (i.x - sh.x).abs() < 7 && (i.y - sh.y).abs() < 7) {
          _take(sh, i.kind);
          return true;
        }
      }
      return false;
    });

    for (final e in enemies) {
      _ai(e, dt);
    }
    // Colpi della navetta.
    for (final s in [...shots]) {
      for (final e in enemies) {
        if (e.hp <= 0) continue;
        if ((s.x - e.x).abs() < e.half + 1 && (s.y - e.y).abs() < e.half + 2) {
          shots.remove(s);
          _damage(e, 1);
          break;
        }
      }
    }
    enemies.removeWhere((e) => e.hp <= 0 || e.y > h + 16);
    // Colpi nemici e scontri.
    for (final sh in ships) {
      if (!sh.alive || sh.hurt > 0) continue;
      for (final b in bullets) {
        if ((b.x - sh.x).abs() < 3.5 && (b.y - sh.y).abs() < 4.5) {
          bullets.remove(b);
          _hit(sh);
          break;
        }
      }
      if (sh.hurt > 0) continue;
      for (final e in enemies) {
        if ((e.x - sh.x).abs() < e.half + 4 &&
            (e.y - sh.y).abs() < e.half + 4) {
          if (e.kind != _Kind.boss) _damage(e, 99);
          _hit(sh);
          break;
        }
      }
    }
    enemies.removeWhere((e) => e.hp <= 0);
    if (enemies.isEmpty) {
      _next -= dt;
      if (_next <= 0) {
        _spawnWave();
        _next = 1.2;
      }
    }
  }

  void _ai(_Enemy e, double dt) {
    e.t += dt;
    e.flash = max(0, e.flash - dt);
    switch (e.kind) {
      case _Kind.drone:
        e
          ..y += e.vy * dt
          ..x += cos(e.t * 2.2 + e.phase) * 34 * dt;
        if (rnd.nextDouble() < dt * 0.12 * (1 + wave * 0.05) && e.y > 0) {
          _aim(e, 55);
        }
      case _Kind.diver:
        if (e.t < 0) return;
        if (e.t < 1.4) {
          e.x += e.vx * dt;
        } else {
          // In picchiata verso la navetta.
          final dx = (_target(e)?.x ?? e.x) - e.x;
          e
            ..vy = min(e.vy + 90 * dt, 70)
            ..x += dx.sign * min(dx.abs(), 30 * dt)
            ..y += e.vy * dt;
        }
      case _Kind.turret:
        if (e.y < 30) e.y += e.vy * dt * 3;
        e.y += e.vy * dt * 0.3;
        e.fire -= dt;
        if (e.fire <= 0) {
          e.fire = max(0.9, 1.8 - wave * 0.04);
          _aim(e, 48);
        }
      case _Kind.boss:
        if (e.y < 24) {
          e.y += e.vy * dt;
          return;
        }
        e.x += e.vx * dt;
        if (e.x < 20 || e.x > w - 20) {
          e
            ..vx = -e.vx
            ..x = e.x.clamp(20, w - 20);
        }
        e.fire -= dt;
        if (e.fire <= 0) {
          final angry = e.hp < e.maxHp / 2;
          e.fire = angry ? 0.75 : 1.1;
          sound(Sfx.enemyShot);
          // Ventaglio.
          final n = angry ? 7 : 5;
          for (var i = 0; i < n; i++) {
            final a = pi / 2 + (i - (n - 1) / 2) * 0.28;
            bullets.add(_Shot(e.x, e.y + 8, cos(a) * 50, sin(a) * 50));
          }
        }
    }
  }

  void _aim(_Enemy e, double v) {
    final t = _target(e);
    if (t == null) return;
    final dx = t.x - e.x, dy = t.y - e.y;
    final d = sqrt(dx * dx + dy * dy);
    if (d < 1 || dy < 10) return;
    sound(Sfx.enemyShot);
    bullets.add(_Shot(e.x, e.y + 3, dx / d * v, dy / d * v));
  }

  void _damage(_Enemy e, int n) {
    if (e.hp <= 0) return;
    e
      ..hp -= n
      ..flash = 0.08;
    if (e.hp > 0) {
      if (e.kind == _Kind.boss) sound(Sfx.wall);
      return;
    }
    final big = e.kind == _Kind.boss;
    score += switch (e.kind) {
      _Kind.drone => 10,
      _Kind.diver => 20,
      _Kind.turret => 40,
      _Kind.boss => 500 + wave * 20,
    };
    sound(big ? Sfx.crash : Sfx.boom);
    if (big) {
      // Nave madre abbattuta: i compagni eliminati rientrano in gioco.
      for (final sh in ships) {
        if (!sh.alive) {
          sh
            ..lives = 1
            ..hurt = 2
            ..y = 104;
          buzz(sh.player, 200);
        }
      }
    }
    _explode(e.x, e.y, big ? 40 : 12, big ? Retro.yellow : Retro.orange);
    final chance = big ? 1.0 : (e.kind == _Kind.turret ? 0.3 : 0.06);
    if (rnd.nextDouble() < chance) {
      final r = rnd.nextDouble();
      final weakest = ships
          .where((s) => s.alive)
          .fold(3, (a, s) => min(a, s.power));
      final kind = weakest < 3 && r < 0.5
          ? _Drop.power
          : r < 0.8
          ? _Drop.shield
          : _Drop.bomb;
      items.add(_Item(e.x, e.y, kind));
    }
  }

  void _explode(double ex, double ey, int n, Color c) {
    for (var i = 0; i < n; i++) {
      final a = rnd.nextDouble() * pi * 2;
      final v = 15 + rnd.nextDouble() * 50;
      bits.add(
        _Bit(
          ex,
          ey,
          cos(a) * v,
          sin(a) * v,
          i.isEven ? c : Retro.white,
          0.3 + rnd.nextDouble() * 0.4,
        ),
      );
    }
  }

  void _take(_Ship sh, _Drop d) {
    sound(Sfx.power);
    buzz(sh.player, 60);
    score += 25;
    switch (d) {
      case _Drop.power:
        sh.power = min(3, sh.power + 1);
      case _Drop.shield:
        sh.shield = true;
      case _Drop.bomb:
        bombs = min(5, bombs + 1);
    }
  }

  void _hit(_Ship sh) {
    buzz(sh.player, sh.shield ? 120 : 350);
    if (sh.shield) {
      sh
        ..shield = false
        ..hurt = 1;
      sound(Sfx.wall);
      _explode(sh.x, sh.y, 10, Retro.cyan);
      return;
    }
    sh
      ..lives -= 1
      ..power = max(1, sh.power - 1)
      ..hurt = 2;
    sound(sh.alive ? Sfx.hurt : Sfx.crash);
    _explode(sh.x, sh.y, 24, _color(sh));
    if (players == 1) bullets.clear();
    if (!ships.any((s) => s.alive)) over = true;
  }

  Color _color(_Ship sh) =>
      players == 1 ? Retro.magenta : Retro.players[sh.player];

  /// La navetta più vicina ancora in gioco.
  _Ship? _target(_Enemy e) {
    _Ship? best;
    var bd = double.infinity;
    for (final sh in ships) {
      if (!sh.alive) continue;
      final d = (sh.x - e.x).abs() + (sh.y - e.y).abs() * 0.5;
      if (d < bd) {
        bd = d;
        best = sh;
      }
    }
    return best;
  }

  void _ship(_Ship sh, double dt) {
    if (sh.hurt > 0) sh.hurt -= dt;
    const sp = 75.0;
    final p = sh.player;
    if (heldBy(p, LogicalKeyboardKey.arrowLeft)) sh.x -= sp * dt;
    if (heldBy(p, LogicalKeyboardKey.arrowRight)) sh.x += sp * dt;
    if (heldBy(p, LogicalKeyboardKey.arrowUp)) sh.y -= sp * dt;
    if (heldBy(p, LogicalKeyboardKey.arrowDown)) sh.y += sp * dt;
    sh
      ..x = sh.x.clamp(6, w - 6)
      ..y = sh.y.clamp(50, h - 7);
    // Fuoco automatico (più navette: un po' sfasate, suono più leggero).
    sh.cool -= dt;
    if (sh.cool > 0) return;
    sh.cool = 0.2;
    if (p == 0 || players == 1) sound(Sfx.shoot);
    final x = sh.x, y = sh.y;
    shots.add(_Shot(x, y - 6, 0, -150));
    if (sh.power >= 2) {
      shots
        ..add(_Shot(x - 4, y - 3, -12, -145))
        ..add(_Shot(x + 4, y - 3, 12, -145));
    }
    if (sh.power >= 3) {
      shots
        ..add(_Shot(x - 5, y - 2, -40, -130))
        ..add(_Shot(x + 5, y - 2, 40, -130));
    }
  }

  static const _shipSprite = [
    '....W....',
    '...WCW...',
    '...CCC...',
    '..MCWCM..',
    '.MMCCCMM.',
    'MMMCCCMMM',
    'M.O...O.M',
  ];
  static const _drone = ['.GGGGGGG.', 'GGWGGGWGG', 'GGGGGGGGG', '.G.G.G.G.'];
  static const _diver = [
    'R.......R',
    'RR.RRR.RR',
    '.RRRWRRR.',
    '..RRRRR..',
    '...RRR...',
    '....R....',
  ];
  static const _turret = [
    '..YYYYY..',
    '.YYOOOYY.',
    'YYOWWWOYY',
    'YYOWWWOYY',
    '.YYOOOYY.',
    '..Y.Y.Y..',
    '....Y....',
  ];
  static const _boss = [
    '.......PPPPPPPPPPPPPP.......',
    '....PPPPPPPPPPPPPPPPPPPP....',
    '..PPPPMMMMPPPPPPPPMMMMPPPP..',
    '.PPPPMMWWMMPPPPPPMMWWMMPPPP.',
    'PPPPPMMWWMMPPPPPPMMWWMMPPPPP',
    'PPPPPPMMMMPPPPPPPPMMMMPPPPPP',
    'PPPPPPPPPPPPPPPPPPPPPPPPPPPP',
    '.PPPPPPPPPPPMMMMPPPPPPPPPPP.',
    '..PP..PPPPPPMRRMPPPPPP..PP..',
    '..PP...PPPPPMRRMPPPPP...PP..',
    '..OO....PPPPPMMPPPPP....OO..',
    '..OO......PPPPPPPP......OO..',
    '...O........PPPP........O...',
  ];

  @override
  void paint(Canvas canvas) {
    final p = Pix(canvas);
    for (final (sx, sy, v) in _stars) {
      final c = v > 30
          ? Retro.white
          : v > 18
          ? const Color(0xFF8C88C8)
          : const Color(0xFF45417A);
      p.rect(sx, sy, 1, v > 30 ? 2 : 1, c);
    }
    for (final i in items) {
      final pulse = (sin(_t * 10) + 1) / 2;
      p.glow(i.x - 4, i.y - 3, 8, 6, i.kind.color, r: 2 + pulse * 2);
      p.label(i.kind.letter, i.x, i.y - 3.6, Retro.bg, size: 5);
    }
    for (final e in enemies) {
      final white = e.flash > 0;
      Map<String, Color> col(Map<String, Color> m) =>
          white ? {for (final k in m.keys) k: Retro.white} : m;
      switch (e.kind) {
        case _Kind.drone:
          p.sprite(
            e.x - 4.5,
            e.y - 2,
            _drone,
            col({'G': Retro.green, 'W': Retro.white}),
          );
        case _Kind.diver:
          p.sprite(
            e.x - 4.5,
            e.y - 3,
            _diver,
            col({'R': Retro.red, 'W': Retro.yellow}),
          );
        case _Kind.turret:
          p.sprite(
            e.x - 4.5,
            e.y - 3.5,
            _turret,
            col({
              'Y': Retro.yellow,
              'O': Retro.orange,
              'W': (_t * 4).floor().isEven ? Retro.red : Retro.white,
            }),
          );
        case _Kind.boss:
          p.sprite(
            e.x - 14,
            e.y - 6.5,
            _boss,
            col({
              'P': Retro.purple,
              'M': Retro.magenta,
              'W': Retro.white,
              'R': (_t * 6).floor().isEven ? Retro.red : Retro.yellow,
              'O': Retro.orange,
            }),
          );
          // Barra dell'energia.
          p.rect(30, 10, w - 60, 2, const Color(0xFF2A2650));
          p.rect(30, 10, (w - 60) * e.hp / e.maxHp, 2, Retro.magenta);
      }
    }
    for (final s in shots) {
      p.glow(s.x - 0.5, s.y - 2, 1, 4, Retro.cyan, r: 1.5);
    }
    for (final b in bullets) {
      p.glow(b.x - 1, b.y - 1, 2, 2, Retro.red, r: 2);
    }
    for (final b in bits) {
      p.rect(
        b.x,
        b.y,
        1,
        1,
        b.color.withValues(alpha: (b.life * 2).clamp(0, 1)),
      );
    }
    for (final sh in ships) {
      if (!sh.alive || (sh.hurt > 0 && (_t * 14).floor().isOdd)) continue;
      final x = sh.x, y = sh.y;
      // Fiamma dei motori.
      final f = (_t * 20).floor().isEven;
      p.rect(x - 3, y + 3.5, 1, f ? 2 : 1, Retro.yellow);
      p.rect(x + 2, y + 3.5, 1, f ? 1 : 2, Retro.yellow);
      p.sprite(x - 4.5, y - 3.5, _shipSprite, {
        'W': Retro.white,
        'C': Retro.cyan,
        'M': _color(sh),
        'O': Retro.orange,
      });
      if (sh.shield) {
        final a = 0.35 + 0.25 * sin(_t * 8);
        p.rect(x - 7, y - 6, 14, 1, Retro.cyan.withValues(alpha: a));
        p.rect(x - 7, y + 5, 14, 1, Retro.cyan.withValues(alpha: a));
        p.rect(x - 7, y - 6, 1, 12, Retro.cyan.withValues(alpha: a));
        p.rect(x + 6, y - 6, 1, 12, Retro.cyan.withValues(alpha: a));
      }
      if (players > 1) {
        p.label('${sh.player + 1}', x, y + 5, _color(sh), size: 4);
      }
    }
    if (_banner > 0) {
      p.label(
        boss ? 'ARRIVA LA NAVE MADRE!' : 'ONDATA $wave',
        w / 2,
        48,
        boss ? Retro.magenta : Retro.yellow,
        size: 7,
      );
    }
    if (_flash > 0) {
      p.rect(0, 0, w, h, Retro.white.withValues(alpha: _flash));
    }
  }
}
