import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'retro.dart';
import 'sfx.dart';

class _Car {
  _Car(this.lane, this.y, this.color, this.speed);
  final int lane;
  double y;
  final Color color;
  double speed; // velocità propria (più lenta della nostra)
}

class _Coin {
  _Coin(this.lane, this.y);
  final int lane;
  double y;
}

/// CORSA NOTTURNA: tre corsie in autostrada, si cambia corsia per evitare
/// le auto e prendere i gettoni. La velocità sale col tempo.
class RacerGame extends RetroGame {
  static const w = 160.0, h = 120.0;
  static const _road = 66.0, _lane = 22.0, _left = (w - _road) / 2;
  static const _py = 96.0;

  /// Distanza minima tra due auto nella stessa corsia (sono alte 14).
  static const _gap = 17.0;

  @override
  String get id => 'racer';
  @override
  String get title => 'CORSA NOTTURNA';
  @override
  List<String> get help => [
    '← →: CAMBIA CORSIA',
    'EVITA LE AUTO, PRENDI I GETTONI',
    'PIU\' VAI LONTANO, PIU\' VAI VELOCE',
  ];
  @override
  Size get size => const Size(w, h);
  @override
  String get status => '${(speed * 1.6).round()} KM/H';

  int lane = 1;
  double x = 0, speed = 60, _dist = 0, _scroll = 0, _spawn = 0, _t = 0;
  double _crash = 0;
  final cars = <_Car>[];
  final coins = <_Coin>[];

  static double laneX(int l) => _left + _lane * l + _lane / 2;

  @override
  void reset() {
    lane = 1;
    x = laneX(1);
    speed = 60;
    _dist = 0;
    _spawn = 1;
    _crash = 0;
    _bonus = 0;
    cars.clear();
    coins.clear();
  }

  @override
  void onKey(LogicalKeyboardKey k) {
    final before = lane;
    if (k == LogicalKeyboardKey.arrowLeft) lane = max(0, lane - 1);
    if (k == LogicalKeyboardKey.arrowRight) lane = min(2, lane + 1);
    if (lane != before) sound(Sfx.move);
  }

  static const _paints = [
    Retro.red,
    Retro.yellow,
    Retro.cyan,
    Retro.orange,
    Retro.purple,
  ];

  @override
  void update(double dt) {
    _t += dt;
    if (_crash > 0) {
      _crash -= dt;
      if (_crash <= 0) over = true;
      return;
    }
    speed = min(150, speed + dt * 1.6);
    _dist += speed * dt;
    _scroll = (_scroll + speed * dt) % 12;
    score = (_dist / 10).floor() + _bonus;
    x += (laneX(lane) - x) * min(1, dt * 14);

    _spawn -= dt;
    if (_spawn <= 0) {
      _spawn = max(0.45, 1.3 - speed / 160) * (0.8 + rnd.nextDouble() * 0.5);
      // Mai tutte e tre le corsie chiuse alla stessa altezza.
      final busy = {
        for (final c in cars)
          if (c.y < _gap) c.lane,
      };
      final free = [0, 1, 2].where((l) => !busy.contains(l)).toList();
      if (free.length > 1) {
        final l = free[rnd.nextInt(free.length)];
        if (rnd.nextDouble() < 0.22) {
          coins.add(_Coin(l, -6));
        } else {
          cars.add(
            _Car(
              l,
              -14,
              _paints[rnd.nextInt(_paints.length)],
              speed * (0.25 + rnd.nextDouble() * 0.3),
            ),
          );
        }
      }
    }
    for (final c in cars) {
      c.y += (speed - c.speed) * dt;
    }
    // Nella stessa corsia un'auto non passa attraverso quella davanti:
    // la raggiunge, frena e la segue a distanza.
    cars.sort((a, b) => b.y.compareTo(a.y));
    for (var i = 0; i < cars.length; i++) {
      final c = cars[i];
      for (var j = i - 1; j >= 0; j--) {
        final ahead = cars[j];
        if (ahead.lane != c.lane) continue;
        if (c.y > ahead.y - _gap) {
          c.y = ahead.y - _gap;
          c.speed = ahead.speed;
        }
        break;
      }
    }
    for (final c in coins) {
      c.y += speed * dt;
    }
    cars.removeWhere((c) => c.y > h + 16);
    // Gettoni presi.
    coins.removeWhere((c) {
      if (c.y > h + 6) return true;
      if ((laneX(c.lane) - x).abs() < 8 && (c.y - _py).abs() < 9) {
        _bonus += 25;
        sound(Sfx.coin);
        return true;
      }
      return false;
    });
    // Scontro.
    for (final c in cars) {
      if ((laneX(c.lane) - x).abs() < 9 && (c.y - _py).abs() < 13) {
        if (_crash <= 0) sound(Sfx.crash);
        _crash = 0.8;
      }
    }
  }

  int _bonus = 0;

  @override
  double? get engine => _crash > 0 ? null : (speed - 60) / 90;

  void _car(Pix p, double cx, double y, Color body, {bool mine = false}) {
    // Auto vista da dietro, 10x14 pixel.
    p.sprite(
      cx - 5,
      y - 7,
      const [
        '..BBBBBB..',
        '.BWWWWWWB.',
        '.BWWWWWWB.',
        'KBBBBBBBBK',
        'KBBBBBBBBK',
        '.BBBBBBBB.',
        '.BBDDDDBB.',
        '.BBDDDDBB.',
        'KBBBBBBBBK',
        'KBBBBBBBBK',
        '.BBBBBBBB.',
        '.RBBBBBBR.',
        '.BBBBBBBB.',
        '..K....K..',
      ],
      {
        'B': body,
        'W': const Color(0xFF9FD8FF),
        'D': Color.lerp(body, const Color(0xFF000000), 0.35)!,
        'K': const Color(0xFF151320),
        'R': mine ? Retro.red : const Color(0xFFFFE9A0),
      },
    );
  }

  @override
  void paint(Canvas canvas) {
    final p = Pix(canvas);
    // Città di notte ai lati: palazzi con finestre accese.
    p.rect(0, 0, w, h, const Color(0xFF0A0920));
    for (var side = 0; side < 2; side++) {
      for (var i = 0; i < 4; i++) {
        final bx = side == 0 ? 2.0 + i * 11 : w - 46 + i * 11;
        final bh = 30.0 + ((i * 37 + side * 11) % 50);
        final yy = ((_scroll * 0.4 + i * 40) % (h + 60)) - 60;
        p.rect(bx, yy, 9, bh, const Color(0xFF1A1740));
        for (var wy = 3.0; wy < bh - 2; wy += 5) {
          for (var wx = 1.0; wx < 8; wx += 3) {
            if (((wx + wy + i) * 7).round() % 3 != 0) {
              p.rect(
                bx + wx,
                yy + wy,
                1.5,
                2,
                ((wx + wy).round() % 4 == 0)
                    ? Retro.yellow
                    : const Color(0xFF6B5FD0),
              );
            }
          }
        }
      }
    }
    // Strada.
    p.rect(_left - 3, 0, _road + 6, h, const Color(0xFF26243A));
    p.rect(_left, 0, _road, h, const Color(0xFF17162A));
    // Bordi a strisce rosse e bianche.
    for (var y = -12.0 + _scroll; y < h; y += 12) {
      p.rect(_left - 3, y, 2, 6, Retro.red);
      p.rect(_left - 3, y + 6, 2, 6, Retro.white);
      p.rect(_left + _road + 1, y, 2, 6, Retro.red);
      p.rect(_left + _road + 1, y + 6, 2, 6, Retro.white);
    }
    // Linee tratteggiate.
    for (var l = 1; l < 3; l++) {
      for (var y = -12.0 + _scroll; y < h; y += 12) {
        p.rect(_left + _lane * l - 0.5, y, 1, 6, const Color(0xFFBDB8E8));
      }
    }
    for (final c in coins) {
      final spin = (cos(_t * 8)).abs();
      p.glow(
        laneX(c.lane) - 2.5 * spin,
        c.y - 2.5,
        5 * max(spin, 0.2),
        5,
        Retro.yellow,
        r: 2,
      );
    }
    for (final c in cars) {
      _car(p, laneX(c.lane), c.y, c.color);
    }
    // Fari della nostra auto sulla strada.
    // Due coni di luce che si allargano e sfumano.
    for (var i = 0; i < 20; i++) {
      final a = 0.16 * (1 - i / 20);
      final spread = 1 + i * 0.18;
      for (final side in [-2.5, 2.5]) {
        p.rect(
          x + side - spread / 2,
          _py - 8 - i,
          spread,
          1,
          const Color(0xFFFFF2B0).withValues(alpha: a),
        );
      }
    }
    if (_crash <= 0 || (_t * 16).floor().isEven) {
      _car(p, x, _py, Retro.magenta, mine: true);
    }
    if (_crash > 0) {
      p.rect(0, 0, w, h, Retro.orange.withValues(alpha: _crash * 0.35));
    }
  }
}
