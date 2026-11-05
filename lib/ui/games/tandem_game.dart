import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../widgets/focus_tile.dart';
import 'retro.dart';
import 'sfx.dart';

/// Un livello: 15 righe di caratteri, una colonna = 8 pixel.
///
/// `#` terreno, `=` piattaforma (si attraversa dal basso), `^` spuntoni,
/// `o` moneta, `w` mostriciattolo, `C` cassa (solo giocando da soli),
/// `F` bandierina di controllo, `E` uscita.
/// Pedane minuscole e blocchi maiuscoli della stessa lettera vanno insieme:
/// `a b c` aprono le porte `A B C` finché qualcuno ci sta sopra;
/// `d` aprono la porta `D` per qualche secondo, ma solo se premute tutte
/// insieme; `x y z` fanno comparire i ponti e gli scalini `X Y Z`.
class _Level {
  const _Level(this.name, this.rows);
  final String name;
  final List<String> rows;
}

const _levels = [
  _Level('PRIMI PASSI', [
    '........................................................................',
    '........................................................................',
    '........................................................................',
    '........................................................................',
    '........................................................................',
    '........................................................................',
    '........................................................................',
    '........................................................................',
    '.............................oo.o........................o.o............',
    '...............................a........................................',
    '....o.o.o..................########...........o.o.o......===............',
    '...........................A......A................................EE...',
    '.....................w.C...A......A...F.C.x..........x........w....EE...',
    '#############...############################XXXXXXXX####################',
    '#############...############################^^^^^^^^####################',
  ]),
  _Level('LA VALLE', [
    '..................................#.........................................................',
    '..................................#.........................................................',
    '..................................#.........................................................',
    '..................................#.........................................................',
    '..................................#.........................................................',
    '..................................#.........................................................',
    '..................................#.........................................................',
    '..............o...................#.........................................................',
    '..................................#...............o....o..o.........o..o....................',
    '.........oo..===..................#.................z....w..................................',
    '..................................B.............###############.......==....................',
    '........====......................B.............###############....==...................EE..',
    '.......................w..C...b...B..b...F.C...Z###############...^^^^^^^^....w.....w...EE..',
    '#################...########################################################################',
    '#################...########################################################################',
  ]),
  _Level('LA FORTEZZA', [
    '...............................#....................................................................',
    '...............................#....................................................................',
    '...............................#....................................................................',
    '...............................#....................................................................',
    '...............................#....................................................................',
    '...............................#....................................................................',
    '...............................#....................................................................',
    '...............................#...............................................o.o..................',
    '...............................#..........................oo.oo.....................................',
    '...............................#............................a...................w...................',
    '.....o.o.o.....................D...........o.o.o.........########..............===..................',
    '...............................D.........................A......A....................===........EE..',
    '.............w.....C..d.....d..D...F.C.y..........y..C...A......A..F...w............^^^^^...w...EE..',
    '###############...#######################YYYYYYYY#########################...#######################',
    '###############...#######################^^^^^^^^#########################...#######################',
  ]),
];

class _Hero {
  _Hero(this.player, this.x, this.y);
  final int player;
  double x, y, vx = 0, vy = 0;
  bool grounded = false, alive = true, facingLeft = false;
  double coyote = 0, jumpBuffer = 0, dead = 0, walk = 0, resetHold = 0;

  /// Su chi sta in piedi (per farsi trasportare).
  _Hero? on;
  static const w = 6.0, h = 10.0;
  Rect get rect => Rect.fromLTWH(x, y, w, h);
}

class _Crate {
  _Crate(this.x0, this.y0) : x = x0, y = y0;
  final double x0, y0;
  double x, y, vy = 0;
  static const s = 8.0;
  Rect get rect => Rect.fromLTWH(x, y, s, s);
}

class _Walker {
  _Walker(this.x, this.y);
  double x, y, dir = -1, t = 0;
  bool alive = true;
  Rect get rect => Rect.fromLTWH(x, y + 2, 7, 6);
}

class _Bit {
  _Bit(this.x, this.y, this.vx, this.vy, this.color);
  double x, y, vx, vy, life = 0.7;
  final Color color;
}

/// TANDEM: platform a scorrimento. Da soli si spingono le casse per salire
/// e tenere giù le pedane; in due (o più) le casse non ci sono: bisogna
/// salire sulla testa del compagno, tenere aperte porte e ponti a turno e
/// arrivare all'uscita tutti insieme.
class TandemGame extends RetroGame {
  static const w = 160.0, h = 120.0, t = 8.0;
  static int get levelCount => _levels.length;

  @override
  String get id => 'tandem';
  @override
  String get title => 'TANDEM';
  @override
  int get maxPlayers => 4;
  @override
  List<String> get help => [
    '← →: CAMMINA   OK O ↑: SALTA',
    'DA SOLI: SPINGI LE CASSE SU PEDANE E MURI',
    'IN SQUADRA: SALI SUL COMPAGNO, TENETE LE PEDANE',
    '↓ TENUTO: RIPARTI (SE TI BLOCCHI)',
  ];
  @override
  Size get size => const Size(w, h);
  @override
  String get status =>
      'LIVELLO $level/${_levels.length}  VITE ${'♥' * max(0, lives)}  '
      'MONETE $coins';

  int level = 1, lives = 5, coins = 0;
  late List<List<String>> grid;
  int cols = 0;
  final heroes = <_Hero>[];
  final crates = <_Crate>[];
  final walkers = <_Walker>[];
  final bits = <_Bit>[];
  final _pressed = <String>{};
  final _timedOpen = <String, double>{};

  /// Ponti appena comparsi addosso a qualcuno: restano vuoti finché non si
  /// sposta, così nessuno ci resta incastrato dentro.
  final _ghost = <int>{};
  double cam = 0, _t = 0, _banner = 0, _flash = 0, _exitWait = 0;
  double spawnX = 16, spawnY = 94;

  _Level get _level => _levels[level - 1];
  bool get coop => players > 1;

  /// Per le prove: la casella è piena?
  @visibleForTesting
  bool solidAt(int c, int r) => _solid(c, r);

  /// Per le prove: il carattere della casella.
  @visibleForTesting
  String tileAt(int c, int r) => _at(c, r);

  @override
  void reset() {
    level = 1;
    lives = 4 + players.clamp(1, 4);
    coins = 0;
    _load();
  }

  /// Salta a un livello (per le prove).
  void goTo(int n) {
    level = n;
    _load();
  }

  void _load() {
    grid = [for (final r in _level.rows) r.split('')];
    cols = grid.first.length;
    crates.clear();
    walkers.clear();
    bits.clear();
    _pressed.clear();
    _timedOpen.clear();
    _ghost.clear();
    for (var r = 0; r < grid.length; r++) {
      for (var c = 0; c < cols; c++) {
        switch (grid[r][c]) {
          case 'C':
            grid[r][c] = '.';
            // Le casse servono solo a chi gioca da solo.
            if (!coop) crates.add(_Crate(c * t, r * t));
          case 'w':
            grid[r][c] = '.';
            walkers.add(_Walker(c * t, r * t));
        }
      }
    }
    spawnX = 16;
    spawnY = 13 * t - _Hero.h;
    heroes
      ..clear()
      ..addAll([
        for (var i = 0; i < players.clamp(1, 4); i++)
          _Hero(i, spawnX + i * 9, spawnY),
      ]);
    cam = 0;
    _banner = 3.5;
    _exitWait = 0;
  }

  // --- Mappa ----------------------------------------------------------------

  String _at(int c, int r) {
    if (c < 0 || c >= cols) return '#';
    if (r < 0) return '.';
    if (r >= grid.length) return '.';
    return grid[r][c];
  }

  bool _isDoor(String ch) => 'ABCD'.contains(ch) && ch.isNotEmpty;
  bool _isBridge(String ch) => 'XYZ'.contains(ch) && ch.isNotEmpty;

  bool _open(String door) =>
      door == 'D' ? (_timedOpen['D'] ?? 0) > 0 : _pressed.contains(door);

  /// Pieno per i corpi (non per le piattaforme attraversabili).
  bool _solid(int c, int r) {
    final ch = _at(c, r);
    if (ch == '#') return true;
    if (_isDoor(ch)) return !_open(ch);
    if (_isBridge(ch)) {
      return _pressed.contains(ch) && !_ghost.contains(r * 1000 + c);
    }
    return false;
  }

  Iterable<Rect> _bodies({Object? except}) sync* {
    for (final k in crates) {
      if (!identical(k, except)) yield k.rect;
    }
  }

  // --- Ingresso -------------------------------------------------------------

  @override
  void onPlayerKey(int p, LogicalKeyboardKey k) {
    if (p >= heroes.length) return;
    if (k == LogicalKeyboardKey.arrowUp ||
        isSelectKey(k) ||
        k == LogicalKeyboardKey.keyB) {
      heroes[p].jumpBuffer = 0.14;
    }
  }

  @override
  void onKey(LogicalKeyboardKey k) => onPlayerKey(0, k);

  // --- Logica ---------------------------------------------------------------

  @override
  void update(double dt) {
    _t += dt;
    _banner = max(0, _banner - dt);
    _flash = max(0, _flash - dt);
    for (final k in _timedOpen.keys.toList()) {
      _timedOpen[k] = _timedOpen[k]! - dt;
    }
    // Passi piccoli: niente compenetrazioni anche coi salti veloci.
    const steps = 3;
    for (var i = 0; i < steps && !over; i++) {
      _step(dt / steps);
    }
    for (final b in bits) {
      b
        ..x += b.vx * dt
        ..y += b.vy * dt
        ..vy += 160 * dt
        ..life -= dt;
    }
    bits.removeWhere((b) => b.life <= 0);
    _camera();
  }

  void _step(double dt) {
    _plates();
    for (final k in crates) {
      _crateFall(k, dt);
    }
    // Prima chi sta più in basso: chi gli sta sopra trova già la sua testa
    // al posto giusto.
    final order = [...heroes]..sort((a, b) => b.y.compareTo(a.y));
    for (final hero in order) {
      _hero(hero, dt);
    }
    for (final wk in walkers) {
      if (wk.alive) _walker(wk, dt);
    }
    _exit(dt);
  }

  void _plates() {
    final before = {..._pressed};
    _pressed.clear();
    final feet = <Rect>[
      for (final hero in heroes)
        if (hero.alive) hero.rect,
      for (final k in crates) k.rect,
    ];
    final d = <String, int>{};
    final dTotal = <String, int>{};
    for (var r = 0; r < grid.length; r++) {
      for (var c = 0; c < cols; c++) {
        final ch = grid[r][c];
        if (!'abcdxyz'.contains(ch)) continue;
        final top = (r + 1) * t;
        final on = feet.any(
          (f) =>
              (f.bottom - top).abs() < 1.5 &&
              f.right > c * t + 1 &&
              f.left < c * t + t - 1,
        );
        final up = ch.toUpperCase();
        if (ch == 'd') {
          dTotal[up] = (dTotal[up] ?? 0) + 1;
          if (on) d[up] = (d[up] ?? 0) + 1;
        } else if (on) {
          _pressed.add(up);
        }
      }
    }
    // Porta a tempo: tutte le pedane insieme, poi resta aperta 4 secondi.
    for (final e in dTotal.entries) {
      if (d[e.key] == e.value) {
        if ((_timedOpen[e.key] ?? 0) <= 0) sound(Sfx.level);
        _timedOpen[e.key] = 4;
      }
    }
    // Una porta non si chiude addosso a qualcuno.
    for (var r = 0; r < grid.length; r++) {
      for (var c = 0; c < cols; c++) {
        final ch = grid[r][c];
        if (!_isDoor(ch) || _open(ch)) continue;
        final cell = Rect.fromLTWH(c * t, r * t, t, t);
        if (heroes.any((x) => x.alive && x.rect.overlaps(cell)) ||
            crates.any((k) => k.rect.overlaps(cell))) {
          if (ch == 'D') {
            _timedOpen['D'] = 0.2;
          } else {
            _pressed.add(ch);
          }
        }
      }
    }
    _ghost.clear();
    for (var r = 0; r < grid.length; r++) {
      for (var c = 0; c < cols; c++) {
        final ch = grid[r][c];
        if (!_isBridge(ch) || !_pressed.contains(ch)) continue;
        final cell = Rect.fromLTWH(c * t, r * t, t, t);
        // Lo scalino che compare sotto i piedi solleva chi c'è sopra.
        for (final hero in heroes) {
          if (!hero.alive || !hero.rect.overlaps(cell)) continue;
          final y0 = hero.y;
          hero.y = cell.top - _Hero.h;
          if (_hitsSolid(hero.rect)) hero.y = y0;
        }
        if ([
          for (final hero in heroes)
            if (hero.alive) hero.rect,
          for (final k in crates) k.rect,
        ].any((f) => f.overlaps(cell))) {
          _ghost.add(r * 1000 + c);
        }
      }
    }
    if (_pressed.difference(before).isNotEmpty) sound(Sfx.plate);
  }

  bool _hitsSolid(Rect r) {
    final c0 = (r.left / t).floor(), c1 = ((r.right - 0.01) / t).floor();
    final r0 = (r.top / t).floor(), r1 = ((r.bottom - 0.01) / t).floor();
    for (var c = c0; c <= c1; c++) {
      for (var rr = r0; rr <= r1; rr++) {
        if (_solid(c, rr)) return true;
      }
    }
    return false;
  }

  /// Piattaforme attraversabili: si atterra solo scendendo da sopra.
  double? _oneWayTop(Rect before, Rect after) {
    final c0 = (after.left / t).floor(),
        c1 = ((after.right - 0.01) / t).floor();
    final r = ((after.bottom - 0.01) / t).floor();
    for (var c = c0; c <= c1; c++) {
      if (_at(c, r) == '=' && before.bottom <= r * t + 0.01) return r * t;
    }
    return null;
  }

  void _crateFall(_Crate k, double dt) {
    k.vy = min(k.vy + 420 * dt, 220);
    final before = k.rect;
    k.y += k.vy * dt;
    if (_hitsSolid(k.rect) ||
        _bodies(except: k).any((b) => b.overlaps(k.rect))) {
      k
        ..y = before.top
        ..vy = 0;
      // Appoggio preciso sul pavimento.
      k.y = ((k.y + _Crate.s) / t).round() * t - _Crate.s;
      if (_hitsSolid(k.rect) ||
          _bodies(except: k).any((b) => b.overlaps(k.rect))) {
        k.y = before.top;
      }
    } else {
      final top = _oneWayTop(before, k.rect);
      if (top != null) {
        k
          ..y = top - _Crate.s
          ..vy = 0;
      }
    }
    if (k.y > h + 20) {
      // Caduta nel vuoto: la cassa torna al suo posto.
      k
        ..x = k.x0
        ..y = k.y0
        ..vy = 0;
    }
  }

  /// Sposta una cassa in orizzontale; restituisce di quanto si è mossa.
  double _push(_Crate k, double dx, _Hero pusher) {
    final x0 = k.x;
    k.x += dx;
    if (_hitsSolid(k.rect) ||
        _bodies(except: k).any((b) => b.overlaps(k.rect)) ||
        heroes.any(
          (o) =>
              !identical(o, pusher) &&
              o.alive &&
              o.rect.deflate(0.5).overlaps(k.rect) &&
              o.on == null,
        )) {
      k.x = x0;
    }
    return k.x - x0;
  }

  void _hero(_Hero p, double dt) {
    if (!p.alive) {
      p.dead -= dt;
      if (p.dead <= 0 && lives > 0) _respawn(p);
      return;
    }
    final i = p.player;
    final l = heldBy(i, LogicalKeyboardKey.arrowLeft);
    final r = heldBy(i, LogicalKeyboardKey.arrowRight);
    const speed = 56.0;
    final target = l == r ? 0.0 : (l ? -speed : speed);
    // A terra ci si ferma subito (niente pattinate giù dalle casse), in aria
    // si cambia direzione con un po' meno prontezza.
    final grip = p.grounded ? (target == 0 ? 45.0 : 22.0) : 14.0;
    p.vx += (target - p.vx) * min(1, dt * grip);
    if (target != 0) p.facingLeft = target < 0;
    if (p.grounded && target != 0) p.walk += dt * 10;

    // Ripartenza: ↓ tenuto premuto.
    if (heldBy(i, LogicalKeyboardKey.arrowDown)) {
      p.resetHold += dt;
      if (p.resetHold > 1.2) {
        p.resetHold = 0;
        if (!coop) {
          for (final k in crates) {
            k
              ..x = k.x0
              ..y = k.y0
              ..vy = 0;
          }
        }
        _respawn(p, lose: false);
        return;
      }
    } else {
      p.resetHold = 0;
    }

    // Salto (con un attimo di tolleranza dopo il bordo e prima di atterrare).
    p.coyote = p.grounded ? 0.09 : p.coyote - dt;
    p.jumpBuffer -= dt;
    if (p.jumpBuffer > 0 && p.coyote > 0) {
      p
        ..vy = -127
        ..jumpBuffer = 0
        ..coyote = 0
        ..grounded = false
        ..on = null;
      if (i == 0 || !coop) sound(Sfx.jump);
    }

    // Trasportato da chi sta sotto.
    final carrier = p.on;
    double carry = 0;
    if (carrier != null && carrier.alive) carry = carrier.vx * dt;

    // Orizzontale.
    final dx = p.vx * dt + carry;
    final before = p.rect;
    p.x += dx;
    if (_hitsSolid(p.rect)) {
      p.x = before.left;
      p.vx = 0;
    } else {
      for (final k in crates) {
        if (!k.rect.overlaps(p.rect)) continue;
        // Quasi sopra la cassa: ci si sta atterrando, non la si urta di lato.
        if (p.rect.bottom - k.y < 3) continue;
        // Spinta: la cassa si muove un po' più piano di chi la spinge.
        final moved = p.grounded ? _push(k, dx * 0.8, p) : 0.0;
        p.x = dx > 0 ? k.x - _Hero.w : k.x + _Crate.s;
        if (moved == 0 && p.grounded) p.vx = 0;
        if (_hitsSolid(p.rect)) p.x = before.left;
      }
    }
    // Insieme si resta nell'inquadratura: chi corre avanti aspetta gli altri.
    if (coop) p.x = p.x.clamp(cam + 1, cam + w - _Hero.w - 1);
    p.x = p.x.clamp(0, cols * t - _Hero.w);

    // Verticale.
    p.vy = min(p.vy + 400 * dt, 230);
    final b2 = p.rect;
    p.y += p.vy * dt;
    final wasStanding = p.grounded;
    p.grounded = false;
    p.on = null;
    if (_hitsSolid(p.rect)) {
      if (p.vy > 0) {
        p.y = ((p.y + _Hero.h) / t).floor() * t - _Hero.h;
        if (_hitsSolid(p.rect)) p.y = b2.top;
        p.grounded = true;
      } else {
        p.y = b2.top;
      }
      p.vy = 0;
    } else if (p.vy >= 0) {
      final top = _oneWayTop(b2, p.rect);
      if (top != null) {
        p
          ..y = top - _Hero.h
          ..vy = 0
          ..grounded = true;
      }
    }
    for (final k in crates) {
      if (!k.rect.overlaps(p.rect)) continue;
      if (p.vy >= 0 && b2.bottom <= k.y + 3) {
        p
          ..y = k.y - _Hero.h
          ..vy = 0
          ..grounded = true;
        if (!wasStanding) _settleOn(p, k.x, _Crate.s);
      } else if (p.vy < 0 && b2.top >= k.rect.bottom - 3) {
        // Testata contro una cassa sopra di sé.
        p
          ..y = k.rect.bottom
          ..vy = 0;
      }
    }
    // La testa dei compagni è un appoggio: si sale uno sull'altro.
    for (final o in heroes) {
      if (identical(o, p) || !o.alive || p.vy < 0) continue;
      final ox = p.x + _Hero.w > o.x + 1 && p.x < o.x + _Hero.w - 1;
      if (ox && b2.bottom <= o.y + 0.5 && p.y + _Hero.h >= o.y) {
        p
          ..y = o.y - _Hero.h
          ..vy = 0
          ..grounded = true
          ..on = o;
        if (!wasStanding) _settleOn(p, o.x, _Hero.w);
      }
    }

    _touch(p);
  }

  /// Atterraggio su un appoggio stretto: chi non tiene premuta una
  /// direzione si ferma lì sopra (niente scivolate), chi la tiene continua a
  /// correre. Se si arriva proprio sul bordo ci si sposta un pelo verso
  /// l'interno, purché non si finisca dentro un muro.
  void _settleOn(_Hero p, double left, double width) {
    final x0 = p.x;
    final l = heldBy(p.player, LogicalKeyboardKey.arrowLeft);
    final r = heldBy(p.player, LogicalKeyboardKey.arrowRight);
    if (l == r) p.vx = 0;
    p.x = p.x.clamp(left - 1, left + width - _Hero.w + 1);
    if (_hitsSolid(p.rect)) p.x = x0;
  }

  void _touch(_Hero p) {
    final rect = p.rect;
    if (p.y > h + 4) return _die(p);
    final c0 = (rect.left / t).floor(), c1 = ((rect.right - 0.01) / t).floor();
    final r0 = (rect.top / t).floor(), r1 = ((rect.bottom - 0.01) / t).floor();
    for (var c = c0; c <= c1; c++) {
      for (var r = r0; r <= r1; r++) {
        switch (_at(c, r)) {
          case '^':
            final spike = Rect.fromLTWH(c * t + 1, r * t + 4, t - 2, 4);
            if (rect.overlaps(spike)) return _die(p);
          case 'o':
            grid[r][c] = '.';
            coins++;
            score += 10;
            sound(Sfx.coin);
            buzz(p.player, 30);
          case 'F':
            final fx = c * t, fy = (r + 1) * t - _Hero.h;
            if (spawnX != fx) {
              spawnX = fx;
              spawnY = fy;
              sound(Sfx.bonus);
              _flash = 0.25;
            }
        }
      }
    }
    for (final wk in walkers) {
      if (!wk.alive || !wk.rect.overlaps(rect)) continue;
      if (p.vy > 0 && rect.bottom - wk.rect.top < 5) {
        wk.alive = false;
        p.vy = -110;
        score += 50;
        sound(Sfx.bounce);
        _burst(wk.x + 3, wk.y + 4, Retro.purple, 10);
      } else {
        return _die(p);
      }
    }
  }

  void _die(_Hero p) {
    if (!p.alive) return;
    p
      ..alive = false
      ..dead = 1.1
      ..on = null;
    lives--;
    sound(Sfx.hurt);
    buzz(p.player, 400);
    _burst(p.x + 3, min(p.y + 5, h - 4), _color(p), 18);
    if (lives < 0 || (lives == 0 && heroes.every((x) => !x.alive))) {
      over = true;
    }
  }

  void _respawn(_Hero p, {bool lose = true}) {
    // Si rinasce accanto a un compagno ancora in gioco, altrimenti
    // all'ultima bandierina.
    final mate = heroes
        .where((x) => x.alive && !identical(x, p) && x.grounded)
        .firstOrNull;
    if (mate != null) {
      p
        ..x = mate.x
        ..y = mate.y;
    } else {
      p
        ..x = spawnX
        ..y = spawnY;
      if (!coop || heroes.every((x) => !x.alive || identical(x, p))) {
        cam = (spawnX - 60).clamp(0, max(0, cols * t - w));
      }
    }
    p
      ..alive = true
      ..vx = 0
      ..vy = 0
      ..dead = 0;
    _burst(p.x + 3, p.y + 5, Retro.white, 8);
  }

  void _walker(_Walker wk, double dt) {
    wk.t += dt;
    final nx = wk.x + wk.dir * 16 * dt;
    final ahead = wk.dir > 0 ? nx + 7 : nx;
    final col = (ahead / t).floor();
    final row = ((wk.y + 4) / t).floor();
    final below = row + 1;
    final ground = _solid(col, below) || _at(col, below) == '=';
    if (_solid(col, row) || !ground || _at(col, row) == '^') {
      wk.dir = -wk.dir;
    } else {
      wk.x = nx;
    }
  }

  void _exit(double dt) {
    final alive = heroes.where((x) => x.alive).toList();
    if (alive.length < heroes.length || alive.isEmpty) {
      _exitWait = 0;
      return;
    }
    bool inExit(_Hero p) {
      final c0 = (p.rect.left / t).floor(),
          c1 = ((p.rect.right - 0.01) / t).floor();
      final r = ((p.rect.bottom - 1) / t).floor();
      for (var c = c0; c <= c1; c++) {
        if (_at(c, r) == 'E') return true;
      }
      return false;
    }

    if (alive.every(inExit)) {
      _exitWait += dt;
      if (_exitWait > 0.4) _nextLevel();
    } else {
      _exitWait = 0;
    }
  }

  /// Qualcuno è all'uscita ma mancano dei compagni.
  bool get _someoneWaiting {
    if (!coop) return false;
    var any = false, all = true;
    for (final p in heroes) {
      final c = ((p.x + 3) / t).floor(), r = ((p.y + _Hero.h - 1) / t).floor();
      final ok = p.alive && _at(c, r) == 'E';
      any |= ok;
      all &= ok;
    }
    return any && !all;
  }

  void _nextLevel() {
    score += 500 + max(0, lives) * 20;
    sound(Sfx.level);
    for (final p in heroes) {
      buzz(p.player, 150);
    }
    if (level >= _levels.length) {
      won = true;
      over = true;
      return;
    }
    level++;
    _load();
  }

  void _camera() {
    final alive = heroes.where((x) => x.alive).toList();
    if (alive.isEmpty) return;
    var lo = alive.first.x, hi = alive.first.x;
    for (final p in alive) {
      lo = min(lo, p.x);
      hi = max(hi, p.x);
    }
    final target = ((lo + hi) / 2 + 3 - w / 2).clamp(
      0.0,
      max(0.0, cols * t - w),
    );
    cam += (target - cam) * 0.25;
  }

  void _burst(double x, double y, Color c, int n) {
    for (var i = 0; i < n; i++) {
      final a = rnd.nextDouble() * pi * 2;
      final v = 20 + rnd.nextDouble() * 50;
      bits.add(_Bit(x, y, cos(a) * v, sin(a) * v - 30, c));
    }
  }

  Color _color(_Hero p) => Retro.players[p.player];

  static const _letterColors = {
    'A': Retro.cyan,
    'B': Retro.magenta,
    'C': Retro.orange,
    'D': Retro.red,
    'X': Retro.green,
    'Y': Retro.yellow,
    'Z': Retro.blue,
  };

  String get _hint {
    final hints = coop
        ? const [
            'SALITE SULLA TESTA DEL COMPAGNO',
            'UNO TIENE LA PEDANA, L\'ALTRO PASSA',
            'LE DUE PEDANE ROSSE VANNO PREMUTE INSIEME',
          ]
        : const [
            'SPINGI LA CASSA PER SALIRE',
            'LA CASSA PUO\' TENERE GIU\' UNA PEDANA',
            'CASSA SU UNA PEDANA, TU SULL\'ALTRA',
          ];
    return hints[(level - 1) % hints.length];
  }

  // --- Disegno --------------------------------------------------------------

  @override
  void paint(Canvas canvas) {
    final p = Pix(canvas);
    // Cielo al tramonto a fasce, stelle e colline lontane (parallasse).
    for (var i = 0; i < 6; i++) {
      p.rect(
        0,
        i * 20.0,
        w,
        20,
        Color.lerp(const Color(0xFF120B2E), const Color(0xFF4A1C4F), i / 5)!,
      );
    }
    for (var i = 0; i < 30; i++) {
      final sx = (i * 37.0 - cam * 0.15) % w;
      final sy = (i * 23.0) % 60;
      p.rect(
        sx < 0 ? sx + w : sx,
        sy,
        1,
        1,
        (i + (_t * 2).floor()).isEven ? Retro.white : Retro.dim,
      );
    }
    for (var x = 0.0; x < w; x += 2) {
      final wx = x + cam * 0.35;
      final hy = 72 + sin(wx / 23) * 9 + sin(wx / 9) * 3;
      p.rect(x, hy, 2, h - hy, const Color(0xFF26174A));
    }
    for (var x = 0.0; x < w; x += 2) {
      final wx = x + cam * 0.6;
      final hy = 86 + sin(wx / 17 + 1) * 7;
      p.rect(x, hy, 2, h - hy, const Color(0xFF1B1238));
    }

    canvas.save();
    canvas.translate(-cam.roundToDouble(), 0);
    final c0 = max(0, (cam / t).floor() - 1);
    final c1 = min(cols - 1, ((cam + w) / t).ceil() + 1);
    for (var r = 0; r < grid.length; r++) {
      for (var c = c0; c <= c1; c++) {
        _tile(p, c, r);
      }
    }
    for (final k in crates) {
      final x = k.x, y = k.y;
      p.rect(x, y, 8, 8, const Color(0xFF8A4B22));
      p.rect(x + 1, y + 1, 6, 6, const Color(0xFFC07A3A));
      p.rect(x + 1, y + 1, 6, 1, const Color(0xFFE2A060));
      for (var i = 1; i < 7; i++) {
        p.rect(x + i, y + i, 1, 1, const Color(0xFF8A4B22));
        p.rect(x + 7 - i, y + i, 1, 1, const Color(0xFF8A4B22));
      }
    }
    for (final wk in walkers) {
      if (!wk.alive) continue;
      final squash = (wk.t * 6).floor().isEven ? 0.0 : 1.0;
      p.sprite(
        wk.x,
        wk.y + 2 + squash,
        const ['.PPPPP.', 'PWKPWKP', 'PPPPPPP', 'PPPPPPP', '.P...P.'],
        {'P': Retro.purple, 'W': Retro.white, 'K': Retro.bg},
      );
    }
    for (final hero in heroes) {
      if (hero.alive) _paintHero(p, hero);
    }
    for (final b in bits) {
      p.rect(
        b.x,
        b.y,
        1,
        1,
        b.color.withValues(alpha: b.life.clamp(0, 0.7) / 0.7),
      );
    }
    canvas.restore();

    if (_banner > 0) {
      p.rect(0, 30, w, 26, Retro.bg.withValues(alpha: min(0.75, _banner)));
      p.label(
        'LIVELLO $level  ${_level.name}',
        w / 2,
        33,
        Retro.yellow,
        size: 7,
      );
      p.label(_hint, w / 2, 44, Retro.cyan, size: 5);
    } else if (_someoneWaiting) {
      p.label('TUTTI ALL\'USCITA!', w / 2, 20, Retro.yellow, size: 6);
    }
    final timer = _timedOpen['D'] ?? 0;
    if (timer > 0.3) {
      p.label('PORTA APERTA ${timer.ceil()}', w / 2, 4, Retro.red, size: 5);
    }
    if (_flash > 0) {
      p.rect(0, 0, w, h, Retro.green.withValues(alpha: _flash * 0.5));
    }
  }

  void _tile(Pix p, int c, int r) {
    final ch = grid[r][c];
    final x = c * t, y = r * t;
    switch (ch) {
      case '#':
        final top = r == 0 || _at(c, r - 1) != '#';
        p.rect(x, y, t, t, const Color(0xFF3A2456));
        p.rect(
          x + ((c * 3 + r) % 5),
          y + ((c + r * 2) % 6),
          1,
          1,
          const Color(0xFF5A3A7A),
        );
        if (top) {
          p.rect(x, y, t, 2, Retro.green);
          p.rect(x, y + 2, t, 1, const Color(0xFF2BA05A));
          if ((c + r).isEven) p.rect(x + 2, y - 1, 1, 1, Retro.green);
        }
      case '=':
        p.rect(x, y, t, 3, const Color(0xFFB0703A));
        p.rect(x, y, t, 1, const Color(0xFFE2A060));
      case '^':
        for (var i = 0; i < 2; i++) {
          final sx = x + i * 4;
          p.rect(sx + 1, y + 7, 3, 1, const Color(0xFFBDB8E8));
          p.rect(sx + 1.5, y + 5, 2, 2, const Color(0xFFDCD8F8));
          p.rect(sx + 2, y + 4, 1, 1, Retro.white);
        }
      case 'o':
        final spin = cos(_t * 6 + c).abs();
        p.glow(
          x + 4 - 2 * spin,
          y + 2,
          max(1, 4 * spin),
          4,
          Retro.yellow,
          r: 1.5,
        );
      case 'F':
        final on = spawnX == x;
        p.rect(x + 1, y - 6, 1, 14, Retro.white);
        p.rect(x + 2, y - 6 + (on ? 0 : 6), 5, 4, on ? Retro.green : Retro.red);
      case 'E':
        if (_at(c - 1, r) == 'E' || _at(c, r - 1) == 'E') return;
        final pulse = (sin(_t * 4) + 1) / 2;
        p.glow(
          x,
          y,
          16,
          16,
          Retro.yellow.withValues(alpha: 0.25 + pulse * 0.2),
          r: 4,
        );
        p.rect(x + 2, y + 1, 12, 15, const Color(0xFF1A1238));
        p.rect(x + 2, y + 1, 12, 1, Retro.yellow);
        p.rect(x + 2, y + 1, 1, 15, Retro.yellow);
        p.rect(x + 13, y + 1, 1, 15, Retro.yellow);
        p.label('ESCI', x + 8, y - 6, Retro.yellow, size: 4);
      default:
        if ('abcdxyz'.contains(ch)) {
          final up = ch.toUpperCase();
          final down = up == 'D' ? _plateDown(c, r) : _pressed.contains(up);
          final color = _letterColors[up]!;
          p.rect(x + 1, y + (down ? 7 : 6), 6, down ? 1 : 2, color);
          p.rect(x, y + 7.5, 8, 0.5, Color.lerp(color, Retro.bg, 0.5)!);
        } else if (_isDoor(ch)) {
          final open = _open(ch);
          final color = _letterColors[ch]!;
          if (open) {
            p.rect(x + 1, y, 6, 1, color.withValues(alpha: 0.35));
          } else {
            p.rect(x + 1, y, 6, t, color.withValues(alpha: 0.25));
            for (var i = 1; i < 7; i += 2) {
              p.rect(x + i, y, 1, t, color);
            }
          }
        } else if (_isBridge(ch)) {
          final color = _letterColors[ch]!;
          if (_pressed.contains(ch)) {
            p.glow(x, y, t, 3, color, r: 2);
            p.rect(x, y, t, 1, Retro.white);
          } else {
            p.rect(x + 1, y + 1, 2, 1, color.withValues(alpha: 0.4));
            p.rect(x + 5, y + 1, 2, 1, color.withValues(alpha: 0.4));
          }
        }
    }
  }

  bool _plateDown(int c, int r) {
    final top = (r + 1) * t;
    return [
      for (final hero in heroes)
        if (hero.alive) hero.rect,
      for (final k in crates) k.rect,
    ].any(
      (f) =>
          (f.bottom - top).abs() < 1.5 &&
          f.right > c * t + 1 &&
          f.left < c * t + t - 1,
    );
  }

  void _paintHero(Pix p, _Hero hero) {
    final c = _color(hero);
    final dark = Color.lerp(c, Retro.bg, 0.45)!;
    final step = hero.grounded && hero.vx.abs() > 5
        ? (hero.walk.floor() % 2)
        : 0;
    final rows = [
      '.HHHH.',
      'HHHHHH',
      'HSEESH',
      '.SSSS.',
      'BBBBBB',
      'BBBBBB',
      '.BBBB.',
      '.DDDD.',
      if (!hero.grounded) 'D....D' else if (step == 0) '.D..D.' else 'D...D.',
      if (!hero.grounded) '......' else if (step == 0) '.D..D.' else '....D.',
    ];
    final flipped = hero.facingLeft
        ? [for (final r in rows) r.split('').reversed.join()]
        : rows;
    p.sprite(hero.x, hero.y, flipped, {
      'H': c,
      'S': const Color(0xFFFFD8B0),
      'E': Retro.bg,
      'B': c,
      'D': dark,
    });
    if (coop && !heroes.any((o) => identical(o.on, hero))) {
      p.label('${hero.player + 1}', hero.x + 3, hero.y - 7, c, size: 4);
    }
  }
}
