import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../widgets/focus_tile.dart';
import 'retro.dart';
import 'sfx.dart';

class _Brick {
  _Brick(this.rect, this.color, this.points, this.hits);
  final Rect rect;
  final Color color;
  final int points;

  /// Colpi che mancano; -1: dorato, indistruttibile.
  int hits;
  bool get gold => hits < 0;
}

class _Ball {
  _Ball(this.x, this.y, this.vx, this.vy);
  double x, y, vx, vy;
}

class _Spark {
  _Spark(this.x, this.y, this.vx, this.vy, this.color);
  double x, y, vx, vy, life = 0.6;
  final Color color;
}

/// Capsule che cadono dai mattoncini.
enum _Power {
  wide('L', Retro.cyan),
  multi('M', Retro.magenta),
  slow('S', Retro.green),
  life('V', Retro.red);

  const _Power(this.letter, this.color);
  final String letter;
  final Color color;
}

class _Capsule {
  _Capsule(this.x, this.y, this.kind);
  double x, y;
  final _Power kind;
}

/// Un quadro: righe di 10 caratteri. r o y g c b p = colori, s = argentato
/// (due colpi), X = dorato (indistruttibile), . = vuoto.
class _Stage {
  const _Stage(this.name, this.rows);
  final String name;
  final List<String> rows;
}

const _stages = [
  _Stage('BENVENUTO', [
    '..........',
    'rrrrrrrrrr',
    'oooooooooo',
    'yyyyyyyyyy',
    'gggggggggg',
    'cccccccccc',
  ]),
  _Stage('PIRAMIDE', [
    '....rr....',
    '...oooo...',
    '..yyyyyy..',
    '.gggggggg.',
    'cccccccccc',
    'ssssssssss',
  ]),
  _Stage('SCACCHIERA', [
    'r.r.r.r.r.',
    '.o.o.o.o.o',
    'y.y.y.y.y.',
    '.g.g.g.g.g',
    'c.c.c.c.c.',
    '.b.b.b.b.b',
    'p.p.p.p.p.',
  ]),
  _Stage('CUORE', [
    '.rr....rr.',
    'rrrr..rrrr',
    'rrrrssrrrr',
    '.pppppppp.',
    '..pppppp..',
    '...pppp...',
    '....pp....',
  ]),
  _Stage('FORTEZZA', [
    'ssssssssss',
    's.rrrrrr.s',
    's.oXXXXo.s',
    's.yyyyyy.s',
    's........s',
    'gggg..gggg',
  ]),
  _Stage('DIAMANTE', [
    '....cc....',
    '...cbbc...',
    '..cbppbc..',
    '.cbpsspbc.',
    '..cbppbc..',
    '...cbbc...',
    '....cc....',
  ]),
  _Stage('LE PORTE', [
    'ssssssssss',
    'rrrrrrrrrr',
    'XXX....XXX',
    'oooooooooo',
    'yyyyyyyyyy',
    'XX..XX..XX',
    'gggggggggg',
  ]),
  _Stage('ONDE', [
    'r...rr...r',
    '.o.o..o.o.',
    '..y....y..',
    'gggggggggg',
    '.c.c..c.c.',
    'b...bb...b',
    'ssssssssss',
  ]),
  _Stage('COLONNE', [
    'r.o.y.g.c.',
    'r.o.y.g.c.',
    's.s.s.s.s.',
    'r.o.y.g.c.',
    'r.o.y.g.c.',
    'X..X..X..X',
  ]),
  _Stage('LABIRINTO', [
    'ssssssssss',
    'X.rrrrrr.X',
    'X.o.XX.o.X',
    'X.y....y.X',
    'X.gggggg.X',
    'X........X',
    'cccccccccc',
  ]),
  _Stage('ARCOBALENO', [
    'rrrrrrrrrr',
    'oooooooooo',
    'yyyyyyyyyy',
    'ssssssssss',
    'gggggggggg',
    'cccccccccc',
    'bbbbbbbbbb',
    'pppppppppp',
  ]),
  _Stage('BERSAGLIO', [
    'ssssssssss',
    's........s',
    's.rrrrrr.s',
    's.r.XX.r.s',
    's.r.pp.r.s',
    's.rrrrrr.s',
    's........s',
    'ssssssssss',
  ]),
];

const _palette = {
  'r': Retro.red,
  'o': Retro.orange,
  'y': Retro.yellow,
  'g': Retro.green,
  'c': Retro.cyan,
  'b': Retro.blue,
  'p': Retro.purple,
};

/// MATTONCINI: con la racchetta si rimbalza la pallina e si abbattono i
/// mattoncini, quadro dopo quadro. Gli argentati vanno colpiti due volte,
/// i dorati non si rompono. Alcuni mattoncini lasciano cadere una capsula.
class BricksGame extends RetroGame {
  static const w = 160.0, h = 120.0;
  static const _cols = 10;
  static int get stageCount => _stages.length;

  @override
  String get id => 'bricks';
  @override
  String get title => 'MATTONCINI';
  @override
  int get maxPlayers => 4;
  @override
  List<String> get help => [
    '← →: MUOVI LA RACCHETTA   OK: LANCIA',
    'ARGENTO: DUE COLPI   ORO: INDISTRUTTIBILE',
    'CAPSULE: L LUNGA  M MULTI  S LENTA  V VITA',
  ];
  @override
  Size get size => const Size(w, h);
  @override
  String get status =>
      'QUADRO ${(level - 1) % _stages.length + 1}/${_stages.length}  '
      'VITE ${'♥' * lives}';

  /// Racchette: una per giocatore, in squadra (si possono sovrapporre).
  final paddles = <double>[w / 2];
  double pw = 28;
  double get px => paddles.first;
  double get _basePw => players > 1 ? 24 : 28;

  /// Chi ha la pallina attaccata alla racchetta prima del lancio.
  int _server = 0;
  static const py = 110.0, ph = 3.0, r = 1.6;
  double speed = 85;
  bool stuck = true;
  int lives = 3, level = 1;
  var bricks = <_Brick>[];
  final balls = <_Ball>[];
  final sparks = <_Spark>[];
  final capsules = <_Capsule>[];
  double _t = 0, _shake = 0, _wide = 0, _slow = 0, _banner = 0;

  _Stage get _stage => _stages[(level - 1) % _stages.length];

  /// Giro (dopo l'ultimo quadro si ricomincia, più veloci).
  int get lap => (level - 1) ~/ _stages.length;

  @override
  void reset() {
    lives = 3;
    level = 1;
    final n = players.clamp(1, 4);
    paddles
      ..clear()
      ..addAll([for (var i = 0; i < n; i++) w * (i + 1) / (n + 1)]);
    pw = _basePw;
    _server = 0;
    lives = 3 + (n - 1);
    _build();
  }

  /// Salta a un quadro (per le prove).
  void goTo(int n) {
    level = n;
    _build();
  }

  void _build() {
    bricks = [];
    const bw = 14.0, bh = 5.0, gap = 1.0;
    const x0 = (w - _cols * (bw + gap) + gap) / 2;
    final rows = _stage.rows;
    for (var j = 0; j < rows.length; j++) {
      for (var i = 0; i < _cols; i++) {
        final ch = rows[j][i];
        if (ch == '.') continue;
        final rect = Rect.fromLTWH(
          x0 + i * (bw + gap),
          14 + j * (bh + gap),
          bw,
          bh,
        );
        final (color, hits) = switch (ch) {
          's' => (const Color(0xFFC9CCE8), 2),
          'X' => (const Color(0xFFE8B84A), -1),
          _ => (_palette[ch] ?? Retro.white, 1),
        };
        bricks.add(_Brick(rect, color, (rows.length - j) * 10, hits));
      }
    }
    speed = 85 + ((level - 1) % _stages.length) * 4 + lap * 20;
    capsules.clear();
    _wide = 0;
    _slow = 0;
    _banner = 2;
    _serve();
  }

  void _serve() {
    stuck = true;
    balls
      ..clear()
      ..add(_Ball(paddles[_server], py - r - 0.5, 0, 0));
  }

  void _launch() {
    if (!stuck) return;
    stuck = false;
    _banner = 0;
    sound(Sfx.select);
    final a = -pi / 2 + (rnd.nextDouble() - 0.5) * 0.8;
    final b = balls.first;
    b
      ..vx = cos(a) * _ballSpeed
      ..vy = sin(a) * _ballSpeed;
  }

  double get _ballSpeed => _slow > 0 ? speed * 0.7 : speed;

  @override
  void onPlayerKey(int p, LogicalKeyboardKey k) {
    if (p >= paddles.length) return;
    if (isSelectKey(k) ||
        k == LogicalKeyboardKey.space ||
        k == LogicalKeyboardKey.arrowUp) {
      _launch();
    } else if (k == LogicalKeyboardKey.arrowLeft) {
      paddles[p] -= 6; // un tocco sposta un po' anche senza tenere premuto
    } else if (k == LogicalKeyboardKey.arrowRight) {
      paddles[p] += 6;
    }
  }

  @override
  void onKey(LogicalKeyboardKey k) => onPlayerKey(0, k);

  @override
  void update(double dt) {
    _t += dt;
    _shake = max(0, _shake - dt);
    _banner = max(0, _banner - dt);
    if (_wide > 0) _wide = max(0, _wide - dt);
    if (_slow > 0) {
      _slow -= dt;
      if (_slow <= 0) _setSpeed(speed);
    }
    final target = _wide > 0 ? _basePw * 1.5 : _basePw;
    pw += (target - pw) * min(1, dt * 10);
    for (var i = 0; i < paddles.length; i++) {
      var x = paddles[i];
      if (heldBy(i, LogicalKeyboardKey.arrowLeft)) x -= 150 * dt;
      if (heldBy(i, LogicalKeyboardKey.arrowRight)) x += 150 * dt;
      paddles[i] = x.clamp(pw / 2 + 1, w - pw / 2 - 1);
    }
    for (final s in sparks) {
      s
        ..x += s.vx * dt
        ..y += s.vy * dt
        ..vy += 120 * dt
        ..life -= dt;
    }
    sparks.removeWhere((s) => s.life <= 0);
    _capsules(dt);
    if (stuck) {
      balls.first
        ..x = paddles[_server.clamp(0, paddles.length - 1)]
        ..y = py - r - 0.5;
      return;
    }
    // Passi piccoli: anche a tutta velocità la pallina non "salta" i
    // mattoncini e ogni colpo ha il suo suono.
    final steps = max(4, (_ballSpeed * dt / 1.2).ceil());
    for (var i = 0; i < steps && !over && !stuck; i++) {
      _move(dt / steps);
    }
  }

  void _capsules(double dt) {
    capsules.removeWhere((c) {
      c.y += 32 * dt;
      if (c.y > h + 4) return true;
      if (c.y + 2.5 >= py &&
          c.y - 2.5 <= py + ph &&
          paddles.any((x) => (c.x - x).abs() <= pw / 2 + 5)) {
        _take(c.kind);
        return true;
      }
      return false;
    });
  }

  void _take(_Power p) {
    sound(Sfx.power);
    score += 50;
    switch (p) {
      case _Power.wide:
        _wide = 15;
      case _Power.slow:
        _slow = 10;
        _setSpeed(speed * 0.7);
      case _Power.life:
        lives = min(5, lives + 1);
      case _Power.multi:
        if (stuck) _launch();
        for (final b in [...balls]) {
          if (balls.length >= 6) break;
          final a = atan2(b.vy, b.vx);
          for (final d in [-0.5, 0.5]) {
            balls.add(
              _Ball(b.x, b.y, cos(a + d) * _ballSpeed, sin(a + d) * _ballSpeed),
            );
          }
        }
    }
  }

  void _setSpeed(double v) {
    for (final b in balls) {
      final s = sqrt(b.vx * b.vx + b.vy * b.vy);
      if (s == 0) continue;
      b
        ..vx = b.vx / s * v
        ..vy = b.vy / s * v;
    }
  }

  void _move(double dt) {
    for (final b in balls) {
      _moveBall(b, dt);
    }
    balls.removeWhere((b) => b.y > h + 4);
    bricks.removeWhere((b) => b.hits == 0);
    if (!bricks.any((b) => !b.gold)) {
      score += 100 * level;
      sound(Sfx.level);
      level++;
      _build();
      return;
    }
    if (balls.isEmpty) {
      lives--;
      _shake = 0.35;
      _wide = 0;
      if (_slow > 0) _slow = 0;
      capsules.clear();
      if (lives <= 0) {
        over = true;
      } else {
        sound(Sfx.hurt);
        for (var i = 1; i < paddles.length; i++) {
          buzz(i, 300);
        }
        _server = (_server + 1) % paddles.length;
        _serve();
      }
    }
  }

  void _moveBall(_Ball b, double dt) {
    b
      ..x += b.vx * dt
      ..y += b.vy * dt;
    if (b.x < r + 1) {
      b
        ..x = r + 1
        ..vx = b.vx.abs();
      sound(Sfx.wall);
    } else if (b.x > w - r - 1) {
      b
        ..x = w - r - 1
        ..vx = -b.vx.abs();
      sound(Sfx.wall);
    }
    if (b.y < r + 9) {
      b
        ..y = r + 9
        ..vy = b.vy.abs();
      sound(Sfx.wall);
    }
    // Racchetta: l'angolo dipende da dove la si colpisce.
    final hit = b.vy > 0 && b.y + r >= py && b.y - r <= py + ph
        ? paddles.indexed
              .where((e) => (b.x - e.$2).abs() <= pw / 2 + r)
              .map((e) => e.$1)
              .firstOrNull
        : null;
    if (hit != null) {
      final px = paddles[hit];
      final f = ((b.x - px) / (pw / 2)).clamp(-1.0, 1.0);
      buzz(hit, 25);
      final a = -pi / 2 + f * 1.1;
      b
        ..vx = cos(a) * _ballSpeed
        ..vy = sin(a) * _ballSpeed
        ..y = py - r;
      sound(Sfx.bounce);
    }
    final ball = Rect.fromCircle(center: Offset(b.x, b.y), radius: r);
    for (final k in bricks) {
      if (k.hits == 0 || !k.rect.overlaps(ball)) continue;
      final ox = min(ball.right - k.rect.left, k.rect.right - ball.left);
      final oy = min(ball.bottom - k.rect.top, k.rect.bottom - ball.top);
      // Fuori dal mattoncino, così non lo colpisce di nuovo al passo dopo.
      if (ox < oy) {
        b.vx = b.x < k.rect.center.dx ? -b.vx.abs() : b.vx.abs();
        b.x += b.vx > 0 ? ox : -ox;
      } else {
        b.vy = b.y < k.rect.center.dy ? -b.vy.abs() : b.vy.abs();
        b.y += b.vy > 0 ? oy : -oy;
      }
      if (k.gold) {
        sound(Sfx.wall);
        _burst(k.rect.center, Retro.yellow, n: 3);
        break;
      }
      k.hits--;
      if (k.hits == 0) {
        score += k.points;
        sound(Sfx.brick);
        _burst(k.rect.center, k.color);
        if (rnd.nextDouble() < 0.13) {
          final roll = rnd.nextDouble();
          final kind = roll < 0.05
              ? _Power.life
              : roll < 0.4
              ? _Power.wide
              : roll < 0.7
              ? _Power.multi
              : _Power.slow;
          capsules.add(_Capsule(k.rect.center.dx, k.rect.center.dy, kind));
        }
        speed = min(speed + 0.8, 175 + lap * 15);
        if (_slow <= 0) _setSpeed(speed);
      } else {
        sound(Sfx.wall);
        _burst(k.rect.center, Retro.white, n: 4);
      }
      break;
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
      if (b.gold) {
        // Riflesso che scorre sull'oro.
        final sx = ((_t * 20 + r.left) % 30) - 8;
        if (sx >= 0 && sx < r.width - 1) {
          p.rect(r.left + sx, r.top + 1, 1, r.height - 2, Retro.white);
        }
      }
    }
    for (final c in capsules) {
      p.glow(c.x - 5, c.y - 2.5, 10, 5, c.kind.color, r: 2);
      p.label(c.kind.letter, c.x, c.y - 3.4, Retro.bg, size: 5);
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
    // Racchette.
    for (final (i, px) in paddles.indexed) {
      final body = players == 1 ? Retro.cyan : Retro.players[i];
      final tips = players == 1 ? Retro.magenta : Retro.white;
      p.glow(px - pw / 2, py, pw, ph, body, r: 3);
      p.rect(px - pw / 2, py, 3, ph, tips);
      p.rect(px + pw / 2 - 3, py, 3, ph, tips);
      p.rect(px - pw / 2 + 3, py, pw - 6, 1, Retro.white);
    }
    // Palline.
    for (final b in balls) {
      p.glow(
        b.x - r,
        b.y - r,
        r * 2,
        r * 2,
        _slow > 0 ? Retro.green : Retro.white,
        r: 3,
      );
    }
    if (stuck) {
      final b = balls.first;
      if ((_t * 3).floor().isEven) {
        p.rect(b.x - 0.5, b.y - 8, 1, 4, Retro.yellow);
        p.rect(b.x - 1.5, b.y - 7, 3, 1, Retro.yellow);
      }
      {
        p.label(
          'QUADRO ${(level - 1) % _stages.length + 1}'
          '${lap > 0 ? '  GIRO ${lap + 1}' : ''}',
          w / 2,
          70,
          Retro.yellow,
          size: 7,
        );
        p.label(_stage.name, w / 2, 80, Retro.cyan, size: 6);
      }
    }
  }
}
