import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/performance.dart';

import '../widgets/focus_tile.dart';
import 'bricks_game.dart';
import 'space_game.dart';
import 'racer_game.dart';
import 'retro.dart';
import 'sfx.dart';
import '../../remote/game_pads.dart';
import '../../remote/remote_server.dart';
import '../widgets/qr_card.dart';
import 'snake_game.dart';
import 'stars_game.dart';
import 'tandem_game.dart';

class _Entry {
  const _Entry(this.make, this.title, this.tagline, this.color, this.icon);
  final RetroGame Function() make;
  final String title;
  final String tagline;
  final Color color;
  final List<String> icon;
}

final _games = <_Entry>[
  _Entry(SnakeGame.new, 'SERPENTINA', 'MANGIA E CRESCI', Retro.green, const [
    '..........',
    '.GGGGGG...',
    '.G....G...',
    '.G....GGW.',
    '.G.......R',
    '.GGGG.....',
    '....G.....',
    '....GGGG..',
    '..........',
  ]),
  _Entry(BricksGame.new, 'MATTONCINI', 'ABBATTI IL MURO', Retro.orange, const [
    'RRRRROOOOO',
    'YYYYYGGGGG',
    'CCCCCBBBBB',
    '..........',
    '......W...',
    '..........',
    '..........',
    '...CCCC...',
    '..........',
  ]),
  _Entry(
    StarsGame.new,
    'STELLE CADENTI',
    'RACCOGLI LE STELLE',
    Retro.yellow,
    const [
      '..Y.......',
      '.YWY...O..',
      '..Y...OY..',
      '......Y...',
      '...K......',
      '..KKK..Y..',
      '...K..YWY.',
      '.......Y..',
      '..MMMMMM..',
    ],
  ),
  _Entry(
    SpaceGame.new,
    'ASTRO PATTUGLIA',
    'DIFENDI LA GALASSIA',
    Retro.magenta,
    const [
      '.R.....R..',
      'RRR...RRR.',
      '.R.....R..',
      '..........',
      '....C.....',
      '....C.....',
      '....W.....',
      '...MCM....',
      '..MMCMM...',
    ],
  ),
  _Entry(
    RacerGame.new,
    'CORSA NOTTURNA',
    'SFRECCIA IN CITTA\'',
    Retro.cyan,
    const [
      'K.W..W..K.',
      'K.......K.',
      'K.W.YY..K.',
      'K...YY..K.',
      'K.W.....K.',
      'K...MM..K.',
      'K.W.MM..K.',
      'K...MM..K.',
      'K.W.....K.',
    ],
  ),
  _Entry(
    TandemGame.new,
    'TANDEM',
    'SI VA AVANTI SOLO INSIEME',
    Retro.green,
    const [
      '........YY',
      '..GG....YY',
      '..GG......',
      '..GG......',
      '..MM...###',
      '..MM...###',
      '..MM...###',
      '##########',
      '##########',
    ],
  ),
];

const _iconColors = <String, Color>{
  'G': Retro.green,
  'W': Retro.white,
  'R': Retro.red,
  'O': Retro.orange,
  'Y': Retro.yellow,
  'C': Retro.cyan,
  'B': Retro.blue,
  'K': Color(0xFF8A86B0),
  'M': Retro.magenta,
  'P': Retro.purple,
  '#': Color(0xFF5A3A7A),
};

/// SALA GIOCHI: sei giochi in stile anni '90, col telecomando.
class GamesHub extends StatefulWidget {
  const GamesHub({super.key, required this.prefs, required this.onClose});
  final SharedPreferences prefs;
  final VoidCallback onClose;

  @override
  State<GamesHub> createState() => _GamesHubState();
}

class _GamesHubState extends State<GamesHub>
    with SingleTickerProviderStateMixin {
  final _focus = FocusNode(debugLabel: 'games');
  late final _anim = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  )..repeat();
  int _sel = 0;
  RetroGame? _playing;
  bool _qr = false;
  late final GamePads? _pads = Provider.of<GamePads?>(context, listen: false);

  void _padsChanged() {
    if (mounted) setState(() {});
  }

  late final SfxPlayer _sfx = SfxPlayer(
    light: context.read<PerformanceProfile>().isLight,
  )..enabled = widget.prefs.getBool(_soundKey) ?? true;
  static const _soundKey = 'games.sound';

  void _toggleSound() {
    setState(() => _sfx.enabled = !_sfx.enabled);
    widget.prefs.setBool(_soundKey, _sfx.enabled);
    _sfx.play(Sfx.select);
  }

  @override
  void initState() {
    super.initState();
    _sfx.init();
    _pads?.addListener(_padsChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _pads?.removeListener(_padsChanged);
    _sfx.dispose();
    _focus.dispose();
    _anim.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final k = e.logicalKey;
    if (_qr) {
      // Qualsiasi tasto chiude il pannello del QR.
      _sfx.play(Sfx.pause);
      setState(() => _qr = false);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.colorF3Blue || k == LogicalKeyboardKey.keyG) {
      _sfx.play(Sfx.select);
      setState(() => _qr = true);
      return KeyEventResult.handled;
    }
    final n = _games.length;
    final before = _sel;
    if (k == LogicalKeyboardKey.arrowRight) {
      setState(() => _sel = (_sel + 1) % n);
    } else if (k == LogicalKeyboardKey.arrowLeft) {
      setState(() => _sel = (_sel - 1 + n) % n);
    } else if (k == LogicalKeyboardKey.arrowDown) {
      setState(() => _sel = min(n - 1, _sel + 3));
    } else if (k == LogicalKeyboardKey.arrowUp) {
      setState(() => _sel = max(0, _sel - 3));
    } else if (k == LogicalKeyboardKey.keyS ||
        k == LogicalKeyboardKey.colorF2Yellow) {
      _toggleSound();
    } else if (isSelectKey(k) || k == LogicalKeyboardKey.space) {
      _play(_sel);
    } else if (isBackKey(k)) {
      widget.onClose();
    } else {
      return KeyEventResult.ignored;
    }
    if (_sel != before) _sfx.play(Sfx.move);
    return KeyEventResult.handled;
  }

  void _play(int i) => setState(() {
    _sfx.play(Sfx.select);
    _sel = i;
    _playing = _games[i].make();
  });

  void _back() {
    setState(() => _playing = null);
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  Widget build(BuildContext context) {
    final g = _playing;
    if (g != null) {
      return GameShell(
        key: ValueKey(g),
        game: g,
        prefs: widget.prefs,
        sfx: _sfx,
        pads: _pads,
        onExit: _back,
      );
    }
    return Focus(
      focusNode: _focus,
      onKeyEvent: _onKey,
      child: Stack(
        fit: StackFit.expand,
        children: [_hub(), if (_qr) _qrPanel()],
      ),
    );
  }

  /// Giocatori collegati: G1 è sempre il telecomando.
  Widget _playersStrip(bool compact, {bool hint = true}) {
    final phones = _pads?.players ?? const <PadPlayer>[];
    final style = Retro.text(compact ? 11 : 13, color: Retro.white, glow: 0.3);
    return Wrap(
      spacing: compact ? 14 : 22,
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          'GIOCATORI',
          style: Retro.text(compact ? 11 : 13, color: Retro.dim, glow: 0),
        ),
        Text('G1 TV', style: style.copyWith(color: Retro.players[0])),
        for (final p in phones)
          Text(
            'G${p.slot + 1} ${p.name}',
            style: style.copyWith(color: Retro.players[p.slot]),
          ),
        if (hint && _pads != null && phones.length < GamePads.maxPads)
          Text(
            'BLU/G: COLLEGA UN TELEFONO',
            style: Retro.text(compact ? 11 : 13, color: Retro.cyan, glow: 0.3),
          ),
      ],
    );
  }

  Widget _qrPanel() {
    final url = Provider.of<RemoteServer?>(context)?.padUrl;
    final phones = _pads?.players ?? const <PadPlayer>[];
    return GestureDetector(
      onTap: () => setState(() => _qr = false),
      child: ColoredBox(
        color: Retro.bg.withValues(alpha: 0.88),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'COLLEGA UN TELEFONO',
                style: Retro.text(30, color: Retro.cyan),
              ),
              const SizedBox(height: 10),
              Text(
                'INQUADRA IL CODICE (STESSA RETE WI-FI): IL TELEFONO DIVENTA UN CONTROLLER',
                textAlign: TextAlign.center,
                style: Retro.text(12, color: Retro.white, glow: 0),
              ),
              const SizedBox(height: 20),
              if (url == null)
                Text(
                  'RETE NON DISPONIBILE',
                  style: Retro.text(16, color: Retro.red),
                )
              else
                QrCode(data: url, size: 170),
              const SizedBox(height: 18),
              Text(
                '${phones.length + 1} DI 4 GIOCATORI',
                style: Retro.text(15, color: Retro.yellow),
              ),
              const SizedBox(height: 8),
              _playersStrip(false, hint: false),
              const SizedBox(height: 18),
              Blink(
                child: Text(
                  'PREMI UN TASTO PER TORNARE AI GIOCHI',
                  style: Retro.text(13, color: Retro.yellow),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hub() {
    return CrtFrame(
      child: LayoutBuilder(
        builder: (context, box) {
          final compact = box.maxHeight < 560;
          return Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 24 : 48,
              vertical: compact ? 16 : 32,
            ),
            child: Column(
              children: [
                AnimatedBuilder(
                  animation: _anim,
                  builder: (context, _) {
                    final c = Retro.rainbow[(_anim.value * 7).floor() % 7];
                    return Text(
                      'SALA GIOCHI',
                      style: Retro.text(compact ? 34 : 52, color: c),
                    );
                  },
                ),
                const SizedBox(height: 6),
                Text(
                  '★ SEI GIOCHI DA SALOTTO ★ DA 1 A 4 GIOCATORI ★',
                  style: Retro.text(
                    compact ? 11 : 14,
                    color: Retro.dim,
                    glow: 0,
                  ),
                ),
                SizedBox(height: compact ? 14 : 28),
                Expanded(
                  child: Center(
                    child: SizedBox(
                      // Tre cartucce per fila, come i tasti ↑↓ si aspettano.
                      width:
                          3 * _Cartridge.cartridgeWidth(compact) +
                          2 * (compact ? 14 : 22),
                      child: Wrap(
                        spacing: compact ? 14 : 22,
                        runSpacing: compact ? 12 : 22,
                        alignment: WrapAlignment.center,
                        children: [
                          for (var i = 0; i < _games.length; i++)
                            _Cartridge(
                              entry: _games[i],
                              best:
                                  widget.prefs.getInt(
                                    'games.best.${_games[i].make().id}',
                                  ) ??
                                  0,
                              selected: i == _sel,
                              compact: compact,
                              onTap: () => i == _sel
                                  ? _play(i)
                                  : setState(() => _sel = i),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                _playersStrip(compact),
                SizedBox(height: compact ? 8 : 12),
                Blink(
                  child: Text(
                    'OK: GIOCA    GIALLO/S: SUONI '
                    '${_sfx.enabled ? 'SÌ' : 'NO'}    INDIETRO: TORNA ALLA TV',
                    style: Retro.text(compact ? 12 : 15, color: Retro.yellow),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Una "cartuccia" del gioco, con anteprima a pixel e record.
class _Cartridge extends StatelessWidget {
  static double cartridgeWidth(bool compact) => compact ? 262 : 340;

  const _Cartridge({
    required this.entry,
    required this.best,
    required this.selected,
    required this.compact,
    required this.onTap,
  });

  final _Entry entry;
  final int best;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final w = cartridgeWidth(compact);
    final c = entry.color;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedScale(
        scale: selected ? 1.06 : 1,
        duration: const Duration(milliseconds: 140),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: w,
          padding: EdgeInsets.all(compact ? 10 : 14),
          decoration: BoxDecoration(
            color: selected
                ? c.withValues(alpha: 0.14)
                : const Color(0xFF12102A),
            border: Border.all(
              color: selected ? c : const Color(0xFF2E2A55),
              width: selected ? 3 : 2,
            ),
            boxShadow: selected
                ? [BoxShadow(color: c.withValues(alpha: 0.45), blurRadius: 24)]
                : null,
          ),
          child: Row(
            children: [
              SizedBox(
                width: compact ? 74 : 104,
                child: AspectRatio(
                  aspectRatio: 10 / 9,
                  child: Container(
                    color: Retro.screen,
                    padding: const EdgeInsets.all(6),
                    child: CustomPaint(painter: _IconPainter(entry.icon)),
                  ),
                ),
              ),
              SizedBox(width: compact ? 10 : 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title,
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                      style: Retro.text(compact ? 13 : 17, color: c),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      entry.tagline,
                      maxLines: 2,
                      style: Retro.text(
                        compact ? 9 : 11,
                        color: Retro.white,
                        glow: 0,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'RECORD ${best.toString().padLeft(5, '0')}',
                      style: Retro.text(
                        compact ? 9 : 11,
                        color: Retro.yellow,
                        glow: 0,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconPainter extends CustomPainter {
  _IconPainter(this.rows);
  final List<String> rows;

  @override
  void paint(Canvas canvas, Size size) {
    final cell = min(size.width / rows.first.length, size.height / rows.length);
    final dx = (size.width - cell * rows.first.length) / 2;
    final dy = (size.height - cell * rows.length) / 2;
    canvas.translate(dx, dy);
    Pix(canvas).sprite(0, 0, rows, _iconColors, size: cell);
  }

  @override
  bool shouldRepaint(_IconPainter old) => old.rows != rows;
}
