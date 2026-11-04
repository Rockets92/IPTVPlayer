import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../widgets/focus_tile.dart';
import 'retro.dart';

class _Card {
  _Card(this.face);
  final int face;
  bool up = false, done = false;
  double flip = 0; // 0 = coperta, 1 = scoperta
}

/// MEMORY TV: 16 carte, 8 coppie di oggetti anni '90. Meno mosse e meno
/// tempo = più punti.
class MemoryGame extends RetroGame {
  static const w = 160.0, h = 120.0;
  static const _cw = 30.0, _ch = 24.0, _gap = 4.0;

  @override
  String get id => 'memory';
  @override
  String get title => 'MEMORY TV';
  @override
  List<String> get help => [
    'FRECCE: SCEGLI LA CARTA   OK: GIRALA',
    'TROVA LE 8 COPPIE DI OGGETTI ANNI \'90',
    'MENO MOSSE E MENO TEMPO = PIU\' PUNTI',
  ];
  @override
  Size get size => const Size(w, h);
  @override
  String get status => 'MOSSE $moves  TEMPO ${_time.floor()}s';

  var cards = <_Card>[];
  int sel = 0, moves = 0;
  int? _first, _second;
  double _wait = 0, _time = 0, _t = 0;

  @override
  void reset() {
    final faces = [
      for (var i = 0; i < 8; i++) ...[i, i],
    ]..shuffle(rnd);
    cards = [for (final f in faces) _Card(f)];
    sel = 0;
    moves = 0;
    _first = _second = null;
    _wait = 0;
    _time = 0;
  }

  @override
  void onKey(LogicalKeyboardKey k) {
    final c = sel % 4, r = sel ~/ 4;
    switch (k) {
      case LogicalKeyboardKey.arrowLeft:
        sel = r * 4 + (c + 3) % 4;
      case LogicalKeyboardKey.arrowRight:
        sel = r * 4 + (c + 1) % 4;
      case LogicalKeyboardKey.arrowUp:
        sel = ((r + 3) % 4) * 4 + c;
      case LogicalKeyboardKey.arrowDown:
        sel = ((r + 1) % 4) * 4 + c;
      default:
        if (isSelectKey(k) || k == LogicalKeyboardKey.space) _flip();
    }
  }

  void _flip() {
    if (_second != null) return; // si aspetta che le carte si richiudano
    final card = cards[sel];
    if (card.up || card.done) return;
    card.up = true;
    if (_first == null) {
      _first = sel;
      return;
    }
    _second = sel;
    moves++;
    final a = cards[_first!];
    if (a.face == card.face) {
      a.done = card.done = true;
      _first = _second = null;
      if (cards.every((c) => c.done)) {
        score = max(100, 2000 - moves * 40 - _time.round() * 6);
        won = true;
        over = true;
      }
    } else {
      _wait = 0.9;
    }
  }

  @override
  void update(double dt) {
    _t += dt;
    _time += dt;
    for (final c in cards) {
      final target = c.up || c.done ? 1.0 : 0.0;
      c.flip += (target - c.flip).sign * min(dt * 6, (target - c.flip).abs());
    }
    if (_wait > 0) {
      _wait -= dt;
      if (_wait <= 0) {
        cards[_first!].up = false;
        cards[_second!].up = false;
        _first = _second = null;
      }
    }
  }

  // Oggetti anni '90, 8x8.
  static const _faces = <List<String>>[
    // televisore
    [
      '.A....A.',
      '..A..A..',
      'GGGGGGGG',
      'GCCCCCGW',
      'GCCCCCGR',
      'GCCCCCGW',
      'GGGGGGGG',
      '.G....G.',
    ],
    // musicassetta
    [
      'OOOOOOOO',
      'OWWWWWWO',
      'OWKWWKWO',
      'OWWWWWWO',
      'OOOOOOOO',
      'O.OOOO.O',
      'OOOOOOOO',
      '........',
    ],
    // joystick
    [
      '...RR...',
      '...RR...',
      '....K...',
      '....K...',
      '..KKKK..',
      '.KKKKKK.',
      '.KYKKKK.',
      '.KKKKKK.',
    ],
    // floppy
    [
      'BBBBBBB.',
      'BBWWWBBB',
      'BBWWWBBB',
      'BBBBBBBB',
      'BWWWWWWB',
      'BWWWWWWB',
      'BWWWWWWB',
      'BBBBBBBB',
    ],
    // cuore
    [
      '........',
      '.RR..RR.',
      'RRRRRRRR',
      'RRRRRRRR',
      '.RRRRRR.',
      '..RRRR..',
      '...RR...',
      '........',
    ],
    // telefono cellulare
    [
      '......A.',
      '..GGGGA.',
      '..GCCG..',
      '..GCCG..',
      '..GGGG..',
      '..GWWG..',
      '..GWWG..',
      '..GGGG..',
    ],
    // nota musicale
    [
      '...MMMMM',
      '...M...M',
      '...M...M',
      '...M...M',
      '.MMM.MMM',
      'MMMMMMMM',
      'MMM..MMM',
      '........',
    ],
    // pianeta
    [
      '...YY...',
      '.YYYYY..',
      'PPPPPPPP',
      '.YYYYY..',
      '..YYYY..',
      '...YY...',
      '........',
      '........',
    ],
  ];

  static final _colors = <String, Color>{
    'A': Retro.dim,
    'G': const Color(0xFF8A86B0),
    'C': Retro.cyan,
    'W': Retro.white,
    'R': Retro.red,
    'O': Retro.orange,
    'K': const Color(0xFF3A3550),
    'Y': Retro.yellow,
    'B': Retro.blue,
    'M': Retro.magenta,
    'P': Retro.purple,
  };

  @override
  void paint(Canvas canvas) {
    final p = Pix(canvas);
    const x0 = (w - 4 * _cw - 3 * _gap) / 2;
    const y0 = (h - 4 * _ch - 3 * _gap) / 2;
    for (var i = 0; i < 16; i++) {
      final c = cards[i];
      final x = x0 + (i % 4) * (_cw + _gap);
      final y = y0 + (i ~/ 4) * (_ch + _gap);
      // Girata: la carta si stringe e si riapre mostrando l'altra faccia.
      final sx = (cos(c.flip * pi)).abs();
      final face = c.flip > 0.5;
      final cw = _cw * max(sx, 0.06);
      final cx = x + (_cw - cw) / 2;
      if (i == sel) {
        final pulse = 0.6 + 0.4 * sin(_t * 7);
        p.glow(
          x - 1.5,
          y - 1.5,
          _cw + 3,
          _ch + 3,
          Retro.yellow.withValues(alpha: pulse),
          r: 3,
        );
      }
      if (!face) {
        p.rect(cx, y, cw, _ch, const Color(0xFF2B1F5C));
        // Retro della carta: scacchi viola.
        for (var yy = 0.0; yy < _ch - 2; yy += 3) {
          for (var xx = 0.0; xx < cw - 2; xx += 3) {
            if (((xx + yy) / 3).round().isEven) {
              p.rect(
                cx + 1 + xx,
                y + 1 + yy,
                1.5,
                1.5,
                const Color(0xFF4A3590),
              );
            }
          }
        }
      } else {
        p.rect(
          cx,
          y,
          cw,
          _ch,
          c.done ? const Color(0xFF173A2A) : const Color(0xFF1E1C3A),
        );
        if (sx > 0.5) {
          p.sprite(
            x + (_cw - 16) / 2,
            y + (_ch - 16) / 2,
            _faces[c.face],
            _colors,
            size: 2,
          );
        }
      }
      p.rect(cx, y, cw, 0.6, const Color(0x66FFFFFF));
    }
  }
}
