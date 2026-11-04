import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../remote/game_pads.dart';
import 'sfx.dart';

import '../widgets/focus_tile.dart';

/// Colori "anni '90": fosfori di un televisore a tubo catodico.
abstract final class Retro {
  static const bg = Color(0xFF07060F);
  static const screen = Color(0xFF0B0A1A);
  static const green = Color(0xFF4DFF7A);
  static const cyan = Color(0xFF3DF2FF);
  static const magenta = Color(0xFFFF3DCB);
  static const yellow = Color(0xFFFFE14D);
  static const orange = Color(0xFFFF8A3D);
  static const red = Color(0xFFFF4D5E);
  static const blue = Color(0xFF4D7BFF);
  static const purple = Color(0xFF9B5CFF);
  static const white = Color(0xFFF4F1FF);
  static const dim = Color(0xFF6E6A99);

  static const rainbow = [red, orange, yellow, green, cyan, blue, purple];

  /// Colore di ciascun giocatore (1 = telecomando, 2-4 = telefoni), uguale
  /// a quello mostrato sul controller del telefono.
  static const players = [green, magenta, yellow, cyan];

  /// Testo a blocchi, con un leggero bagliore come sui vecchi monitor.
  static TextStyle text(
    double size, {
    Color color = white,
    double glow = 0.8,
    FontWeight weight = FontWeight.w900,
  }) => TextStyle(
    fontFamily: 'monospace',
    fontFamilyFallback: const ['Courier New', 'Courier', 'DejaVu Sans Mono'],
    fontSize: size,
    fontWeight: weight,
    letterSpacing: size * 0.12,
    height: 1.1,
    color: color,
    shadows: glow <= 0
        ? null
        : [
            Shadow(color: color.withValues(alpha: 0.75 * glow), blurRadius: 8),
            Shadow(color: color.withValues(alpha: 0.35 * glow), blurRadius: 22),
          ],
  );
}

/// Pennello per disegnare a "pixel" su una griglia logica.
class Pix {
  Pix(this.canvas);
  final Canvas canvas;
  final _p = Paint()..isAntiAlias = false;

  void rect(double x, double y, double w, double h, Color c) {
    _p
      ..color = c
      ..maskFilter = null;
    canvas.drawRect(Rect.fromLTWH(x, y, w, h), _p);
  }

  /// Rettangolo con alone luminoso (fosforo).
  void glow(double x, double y, double w, double h, Color c, {double r = 3}) {
    _p
      ..color = c.withValues(alpha: 0.35)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, r);
    canvas.drawRect(Rect.fromLTWH(x - 1, y - 1, w + 2, h + 2), _p);
    rect(x, y, w, h, c);
  }

  /// Scritta centrata in [cx] (coordinate del gioco).
  void label(String text, double cx, double y, Color c, {double size = 6}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: Retro.text(size, color: c, glow: 0.6),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, y));
    tp.dispose();
  }

  /// Sprite da stringhe: ogni carattere diverso da '.' è un pixel del colore
  /// indicato nella mappa.
  void sprite(
    double x,
    double y,
    List<String> rows,
    Map<String, Color> colors, {
    double size = 1,
  }) {
    for (var j = 0; j < rows.length; j++) {
      final r = rows[j];
      for (var i = 0; i < r.length; i++) {
        final c = colors[r[i]];
        if (c != null) rect(x + i * size, y + j * size, size, size, c);
      }
    }
  }
}

/// Un gioco: logica a passo di tempo, disegno su una griglia logica.
abstract class RetroGame {
  String get id;
  String get title;

  /// Due righe di istruzioni mostrate prima di iniziare.
  List<String> get help;

  /// Grandezza logica dello schermo (in "pixel" del gioco).
  Size get size;

  int score = 0;
  bool over = false;

  /// Partita vinta (es. un gioco completato) invece che persa.
  bool won = false;

  /// Righe extra nella barra in alto (vite, livello…).
  String get status => '';

  final rnd = Random();

  /// Tasti tenuti premuti da ciascun giocatore (0 = telecomando).
  final pads = List.generate(4, (_) => <LogicalKeyboardKey>{});
  Set<LogicalKeyboardKey> get held => pads[0];

  /// Giocatori massimi: oltre 1, gli altri si collegano col telefono.
  int get maxPlayers => 1;

  /// Giocatori di questa partita (impostato dalla cornice prima di reset).
  int players = 1;

  /// Nomi dei giocatori, per i risultati.
  List<String> names = const ['G1'];

  /// Righe dei risultati a fine partita (classifica in multigiocatore).
  List<String> get results => const [];

  /// Titolo a fine partita al posto di "GAME OVER" (es. chi ha vinto).
  String? get endTitle => null;

  /// Vibrazione sul telefono del giocatore [p] (1-3).
  void Function(int p, int ms)? onBuzz;
  void buzz(int p, [int ms = 150]) {
    if (p > 0) onBuzz?.call(p, ms);
  }

  /// Effetti sonori (impostati dalla cornice).
  void Function(Sfx)? onSound;
  void sound(Sfx s) => onSound?.call(s);

  /// Rumore di motore in sottofondo, da 0 (minimo) a 1 (al massimo);
  /// null se il gioco non ne ha.
  double? get engine => null;

  void reset();
  void update(double dt);
  void paint(Canvas canvas);

  /// Tasto premuto durante la partita.
  void onKey(LogicalKeyboardKey k) {}

  /// Tasto premuto dal giocatore [p] (0 = telecomando).
  void onPlayerKey(int p, LogicalKeyboardKey k) {
    if (p == 0) onKey(k);
  }

  bool isHeld(LogicalKeyboardKey k) => held.contains(k);
  bool heldBy(int p, LogicalKeyboardKey k) => pads[p].contains(k);
  bool get left => isHeld(LogicalKeyboardKey.arrowLeft);
  bool get right => isHeld(LogicalKeyboardKey.arrowRight);
}

enum _Phase { ready, playing, paused, over }

/// Cornice comune: televisore anni '90, barra del punteggio, pausa, record.
class GameShell extends StatefulWidget {
  const GameShell({
    super.key,
    required this.game,
    required this.prefs,
    required this.onExit,
    this.sfx,
    this.pads,
  });

  final SfxPlayer? sfx;

  /// Telefoni collegati come controller (giocatori 2-4).
  final GamePads? pads;
  final RetroGame game;
  final SharedPreferences prefs;
  final VoidCallback onExit;

  @override
  State<GameShell> createState() => _GameShellState();
}

class _GameShellState extends State<GameShell>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  final _frame = ValueNotifier<int>(0);
  final _focus = FocusNode(debugLabel: 'game');
  _Phase _phase = _Phase.ready;
  Duration _last = Duration.zero;
  int _best = 0;
  bool _newBest = false;

  RetroGame get g => widget.game;
  String get _bestKey => 'games.best.${g.id}';

  @override
  void initState() {
    super.initState();
    _best = widget.prefs.getInt(_bestKey) ?? 0;
    g.onSound = (s) => widget.sfx?.play(s);
    g.onBuzz = (p, ms) => widget.pads?.buzz(p, ms);
    widget.pads?.onInput = _onPad;
    widget.pads?.addListener(_padsChanged);
    _syncPhones();
    g.reset();
    _ticker.start();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    widget.pads?.removeListener(_padsChanged);
    if (widget.pads?.onInput == _onPad) widget.pads?.onInput = null;
    widget.pads?.setState(game: null);
    widget.sfx?.engineOff();
    _ticker.dispose();
    _frame.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _tick(Duration t) {
    final dt = ((t - _last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _last = t;
    if (_phase == _Phase.playing) {
      g.update(dt);
      if (g.over) _finish();
    }
    final e = _phase == _Phase.playing ? g.engine : null;
    if (e != null) {
      widget.sfx?.engine(e);
    } else {
      widget.sfx?.engineOff();
    }
    _frame.value++;
  }

  void _finish() {
    _newBest = g.score > _best;
    if (_newBest) {
      _best = g.score;
      widget.prefs.setInt(_bestKey, _best);
    }
    for (final p in g.pads) {
      p.clear();
    }
    widget.sfx?.play(g.won ? Sfx.win : Sfx.over);
    setState(() => _phase = _Phase.over);
    _syncPhones();
  }

  /// Giocatori collegati col telefono, nell'ordine dei posti (1-3).
  List<PadPlayer> get _phones =>
      g.maxPlayers > 1 ? (widget.pads?.players ?? const []) : const [];

  /// Posto del telefono (1-3) → giocatore della partita (1-3), o null se
  /// non partecipa (collegato a partita iniziata, o gioco a un giocatore).
  final _seat = <int, int>{};

  void _padsChanged() {
    if (mounted) setState(() {});
    _syncPhones();
  }

  void _syncPhones() {
    final pads = widget.pads;
    if (pads == null) return;
    pads.setState(
      game: g.title,
      playing: _phase == _Phase.playing,
      message: g.maxPlayers <= 1
          ? 'GIOCO A UN SOLO GIOCATORE: GUARDA LA TV'
          : switch (_phase) {
              _Phase.ready || _Phase.over => 'PREMI A PER INIZIARE',
              _Phase.paused => 'PAUSA: A PER CONTINUARE',
              _Phase.playing => '',
            },
    );
  }

  static const _padKeys = {
    'up': LogicalKeyboardKey.arrowUp,
    'down': LogicalKeyboardKey.arrowDown,
    'left': LogicalKeyboardKey.arrowLeft,
    'right': LogicalKeyboardKey.arrowRight,
    'a': LogicalKeyboardKey.enter,
    'b': LogicalKeyboardKey.keyB,
  };

  void _onPad(int slot, String key, bool down) {
    if (!mounted || g.maxPlayers <= 1) return;
    final k = _padKeys[key];
    if (!down) {
      final p = _seat[slot];
      if (p != null && k != null) g.pads[p].remove(k);
      return;
    }
    if (k == null) return;
    final p = _seat[slot];
    if (_phase != _Phase.playing) {
      // A dal telefono: inizia o riprende la partita.
      if (down && key == 'a') {
        if (_phase == _Phase.paused) {
          widget.sfx?.play(Sfx.select);
          setState(() => _phase = _Phase.playing);
          _syncPhones();
        } else {
          _start();
        }
      }
      return;
    }
    if (p == null) {
      if (down) {
        widget.pads?.bySlot(slot)?.send({
          't': 'state',
          'game': g.title,
          'message': 'ENTRI ALLA PROSSIMA PARTITA',
        });
      }
      return;
    }
    if (down) {
      g.pads[p].add(k);
      g.onPlayerKey(p, k);
    } else {
      g.pads[p].remove(k);
    }
  }

  void _start() {
    _seat.clear();
    final names = [widget.pads == null ? 'G1' : GamePads.tvPlayerName];
    for (final ph in _phones.take(3)) {
      _seat[ph.slot] = names.length;
      names.add(ph.name);
      // Colore e numero sul telefono uguali a quelli della partita.
      ph.send({'t': 'welcome', 'player': names.length});
    }
    g.players = names.length;
    g.names = names;
    for (final p in g.pads) {
      p.clear();
    }
    g.reset();
    g.score = 0;
    g.over = false;
    g.won = false;
    _newBest = false;
    widget.sfx?.play(Sfx.start);
    setState(() => _phase = _Phase.playing);
    _syncPhones();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    final k = e.logicalKey;
    if (e is KeyUpEvent) {
      g.held.remove(k);
      return KeyEventResult.handled;
    }
    final down = e is KeyDownEvent;
    if (down) g.held.add(k);
    final back = isBackKey(k) || k == LogicalKeyboardKey.keyP;
    switch (_phase) {
      case _Phase.ready || _Phase.over:
        if (!down) return KeyEventResult.handled;
        if (isSelectKey(k) || k == LogicalKeyboardKey.space) {
          _start();
        } else if (isBackKey(k)) {
          widget.onExit();
        }
      case _Phase.paused:
        if (!down) return KeyEventResult.handled;
        if (isSelectKey(k) ||
            k == LogicalKeyboardKey.space ||
            k == LogicalKeyboardKey.keyP) {
          widget.sfx?.play(Sfx.select);
          setState(() => _phase = _Phase.playing);
          _syncPhones();
        } else if (isBackKey(k)) {
          // Secondo Indietro in pausa: si torna alla sala giochi.
          widget.onExit();
        }
      case _Phase.playing:
        if (back && down) {
          for (final p in g.pads) {
            p.clear();
          }
          widget.sfx?.play(Sfx.pause);
          setState(() => _phase = _Phase.paused);
          _syncPhones();
        } else if (down) {
          g.onPlayerKey(0, k);
        }
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focus,
      onKeyEvent: _onKey,
      child: GestureDetector(
        onTap: () {
          if (_phase != _Phase.playing) _start();
        },
        child: CrtFrame(
          child: Column(
            children: [
              // Barra del punteggio.
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 8),
                child: Row(
                  children: [
                    Text(g.title, style: Retro.text(16, color: Retro.cyan)),
                    const Spacer(),
                    ValueListenableBuilder<int>(
                      valueListenable: _frame,
                      builder: (context, _, _) => Text(
                        '${g.status.isEmpty ? '' : '${g.status}   '}'
                        'PUNTI ${g.score.toString().padLeft(5, '0')}   '
                        'RECORD ${max(_best, g.score).toString().padLeft(5, '0')}',
                        style: Retro.text(14, color: Retro.yellow),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Center(
                      child: AspectRatio(
                        aspectRatio: g.size.width / g.size.height,
                        child: CustomPaint(
                          painter: _GamePainter(g, _frame),
                          isComplex: true,
                          willChange: true,
                        ),
                      ),
                    ),
                    if (_phase != _Phase.playing) _overlay(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Chi gioca la prossima partita (solo nei giochi a più giocatori).
  List<String> _playersLine() {
    if (g.maxPlayers <= 1 || widget.pads == null) return const [];
    final phones = _phones;
    if (phones.isEmpty) {
      return const ['', 'BLU/G NELLA SALA GIOCHI: COLLEGA UN TELEFONO'];
    }
    return [
      '',
      'GIOCATORI: G1 TV  ${[for (final (i, p) in phones.take(3).indexed) 'G${i + 2} ${p.name}'].join('  ')}',
    ];
  }

  Widget _overlay() {
    final (
      String title,
      Color color,
      List<String> lines,
      String action,
    ) = switch (_phase) {
      _Phase.ready => (
        g.title,
        Retro.cyan,
        [...g.help, ..._playersLine()],
        'PREMI OK PER GIOCARE',
      ),
      _Phase.paused => (
        'PAUSA',
        Retro.yellow,
        ['OK: CONTINUA', 'INDIETRO: ESCI DAL GIOCO'],
        '',
      ),
      _ => (
        g.endTitle ?? (g.won ? 'COMPLIMENTI!' : 'GAME OVER'),
        g.won || g.endTitle != null ? Retro.green : Retro.red,
        [
          ...g.results,
          'PUNTI ${g.score}',
          if (_newBest) '*** NUOVO RECORD! ***' else 'RECORD $_best',
          ..._playersLine(),
        ],
        'OK: RIGIOCA   INDIETRO: ESCI',
      ),
    };
    return ColoredBox(
      color: Retro.bg.withValues(alpha: 0.72),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: Retro.text(40, color: color)),
            const SizedBox(height: 18),
            for (final l in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  l,
                  textAlign: TextAlign.center,
                  style: Retro.text(
                    17,
                    color: l.startsWith('***') ? Retro.magenta : Retro.white,
                    glow: 0.4,
                  ),
                ),
              ),
            if (action.isNotEmpty) ...[
              const SizedBox(height: 14),
              Blink(
                child: Text(action, style: Retro.text(18, color: Retro.yellow)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _GamePainter extends CustomPainter {
  _GamePainter(this.game, Listenable repaint) : super(repaint: repaint);
  final RetroGame game;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / game.size.width;
    canvas
      ..save()
      ..clipRect(Offset.zero & size)
      ..drawRect(Offset.zero & size, Paint()..color = Retro.screen)
      ..scale(s);
    game.paint(canvas);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GamePainter old) => old.game != game;
}

/// Scritta che lampeggia come le "INSERT COIN" delle sale giochi.
class Blink extends StatefulWidget {
  const Blink({super.key, required this.child});
  final Widget child;

  @override
  State<Blink> createState() => _BlinkState();
}

class _BlinkState extends State<Blink> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (context, child) =>
        Opacity(opacity: _c.value < 0.62 ? 1 : 0.08, child: child),
    child: widget.child,
  );
}

/// Televisore a tubo: bordo scuro arrotondato, righe di scansione e vignetta.
class CrtFrame extends StatelessWidget {
  const CrtFrame({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF020205),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(34),
            color: Retro.bg,
            border: Border.all(color: const Color(0xFF1C1A2E), width: 3),
            boxShadow: [
              BoxShadow(
                color: Retro.purple.withValues(alpha: 0.18),
                blurRadius: 40,
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              child,
              const IgnorePointer(
                child: CustomPaint(painter: _ScanlinePainter()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScanlinePainter extends CustomPainter {
  const _ScanlinePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Colors.black.withValues(alpha: 0.22);
    for (var y = 0.0; y < size.height; y += 3) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), p);
    }
    // Vignetta: il vetro del tubo è più scuro ai bordi.
    final r = Offset.zero & size;
    canvas.drawRect(
      r,
      Paint()
        ..shader = ui.Gradient.radial(
          r.center,
          size.longestSide * 0.62,
          [Colors.transparent, Colors.black.withValues(alpha: 0.55)],
          [0.62, 1],
        ),
    );
    // Riflesso sul vetro in alto a sinistra.
    canvas.drawRect(
      r,
      Paint()
        ..shader = ui.Gradient.linear(r.topLeft, r.center, [
          Colors.white.withValues(alpha: 0.045),
          Colors.transparent,
        ]),
    );
  }

  @override
  bool shouldRepaint(_ScanlinePainter old) => false;
}
