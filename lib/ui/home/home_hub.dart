import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/performance.dart';
import '../../core/theme.dart';
import '../../data/vod/vod_models.dart';
import '../../domain/channel.dart';
import '../../state/app_controller.dart';
import '../../state/tuner_controller.dart';
import '../../state/vod_controller.dart';
import '../format.dart';
import '../vod/vod_widgets.dart';
import '../widgets/channel_logo.dart';
import '../widgets/epg_progress.dart';
import '../widgets/focus_tile.dart';
import '../widgets/now.dart';

/// Le quattro sezioni dell'app.
enum HomeChoice { live, movies, series, games }

/// Schermata di scelta: TV in diretta, Film, Serie TV, Giochi, con la
/// diretta che continua sullo sfondo e i titoli da riprendere sotto.
class HomeHub extends StatefulWidget {
  const HomeHub({
    super.key,
    required this.onPick,
    required this.onClose,
    required this.onResume,
  });

  final ValueChanged<HomeChoice> onPick;
  final VoidCallback onClose;

  /// Apre la scheda di un titolo da "Continua a guardare".
  final void Function(VodKind kind, VodItem item) onResume;

  @override
  State<HomeHub> createState() => _HomeHubState();
}

class _Accent {
  const _Accent(this.top, this.bottom, this.glow);
  final Color top;
  final Color bottom;
  final Color glow;
}

const _accents = [
  _Accent(Color(0xFF2F6BFF), Color(0xFF0C1C52), Color(0xFF3D7BFF)),
  _Accent(Color(0xFFE0483F), Color(0xFF3E0D1A), Color(0xFFFF5A4E)),
  _Accent(Color(0xFF9452E6), Color(0xFF1F0E45), Color(0xFFA463FF)),
  _Accent(Color(0xFF17B377), Color(0xFF07291E), Color(0xFF2BE39A)),
];

class _HomeHubState extends State<HomeHub> {
  final _focus = FocusNode(debugLabel: 'home');
  late final VodController _vod = context.read<VodController>();
  int _sel = 0;

  /// Riga "Continua a guardare" (null: si è sulle schede).
  int? _row;

  @override
  void initState() {
    super.initState();
    // Copertine per le schede Film e Serie.
    _vod.load(VodKind.movies);
    _vod.load(VodKind.series);
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  bool _enabled(int i) => i == 0 || i == 3 || _vod.available;

  void _pick(int i) {
    if (!_enabled(i)) return;
    widget.onPick(HomeChoice.values[i]);
  }

  /// Titoli iniziati, film e serie insieme, dal più recente.
  List<(VodKind, WatchEntry)> get _resume {
    if (!_vod.available) return const [];
    final all = [
      for (final w in _vod.continueWatching(VodKind.movies))
        (VodKind.movies, w),
      for (final w in _vod.continueWatching(VodKind.series))
        (VodKind.series, w),
    ]..sort((a, b) => b.$2.at.compareTo(a.$2.at));
    return all.take(8).toList();
  }

  void _open((VodKind, WatchEntry) r) {
    final (kind, w) = r;
    final id = kind == VodKind.movies
        ? int.tryParse(w.key.substring(2))
        : w.seriesId;
    if (id == null) return;
    final known = _vod.catalog(kind).items.where((i) => i.id == id).firstOrNull;
    widget.onResume(
      kind,
      known ??
          VodItem(
            id: id,
            name: w.title,
            poster: w.poster,
            extension: w.extension,
          ),
    );
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final k = e.logicalKey;
    final resume = _resume;
    final row = _row;
    if (k == LogicalKeyboardKey.arrowLeft ||
        k == LogicalKeyboardKey.arrowRight) {
      final d = k == LogicalKeyboardKey.arrowRight ? 1 : -1;
      setState(() {
        if (row != null) {
          _row = (row + d).clamp(0, resume.length - 1);
        } else {
          _sel = (_sel + d).clamp(0, 3);
        }
      });
    } else if (k == LogicalKeyboardKey.arrowDown) {
      if (row == null && resume.isNotEmpty) setState(() => _row = 0);
    } else if (k == LogicalKeyboardKey.arrowUp) {
      if (row != null) setState(() => _row = null);
    } else if (e is KeyRepeatEvent) {
      return KeyEventResult.handled;
    } else if (isSelectKey(k)) {
      if (row != null && row < resume.length) {
        _open(resume[row]);
      } else {
        _pick(_sel);
      }
    } else if (isBackKey(k)) {
      if (row != null) {
        setState(() => _row = null);
      } else {
        widget.onClose();
      }
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  static String _greeting(DateTime t) {
    final h = t.hour;
    if (h >= 5 && h < 13) return 'Buongiorno';
    if (h >= 13 && h < 18) return 'Buon pomeriggio';
    return 'Buonasera';
  }

  static String _question(DateTime t) {
    final h = t.hour;
    if (h >= 5 && h < 12) return 'Cosa guardiamo stamattina?';
    if (h >= 12 && h < 18) return 'Cosa guardiamo oggi?';
    if (h >= 18 && h < 23) return 'Cosa guardiamo stasera?';
    return 'Ancora qualcosa prima di dormire?';
  }

  @override
  Widget build(BuildContext context) {
    context.watch<VodController>();
    final perf = context.read<PerformanceProfile>();
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 900;
    final pad = compact ? 20.0 : 44.0;
    final resume = _resume;
    if (_row != null && _row! >= resume.length) {
      _row = resume.isEmpty ? null : resume.length - 1;
    }
    final accent = _accents[_sel];

    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // La diretta resta visibile, velata.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0, 0.45, 1],
                colors: [
                  Color(0x6604060B),
                  Color(0xB804060B),
                  Color(0xF004060B),
                ],
              ),
            ),
          ),
          // Alone del colore della sezione scelta.
          AnimatedContainer(
            duration: perf.slow,
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(-1 + _sel * 2 / 3, -0.1),
                radius: 1.1,
                colors: [
                  accent.glow.withValues(alpha: 0.30),
                  accent.glow.withValues(alpha: 0),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(pad, pad * 0.8, pad, pad * 0.6),
              child: NowBuilder(
                builder: (context, now) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _header(now, compact),
                    SizedBox(height: compact ? 18 : 34),
                    Expanded(
                      flex: resume.isEmpty ? 1 : 0,
                      child: resume.isEmpty
                          ? Align(
                              alignment: const Alignment(0, -0.4),
                              child: SizedBox(
                                height: compact ? 230 : 340,
                                child: _cards(now, compact),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                    if (resume.isNotEmpty) ...[
                      Expanded(flex: 11, child: _cards(now, compact)),
                      SizedBox(height: compact ? 16 : 28),
                      Expanded(flex: 8, child: _resumeRow(resume, compact)),
                    ],
                    _hints(resume.isNotEmpty),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(DateTime now, bool compact) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _greeting(now).toUpperCase(),
                style: AppText.overline.copyWith(
                  color: _accents[_sel].glow,
                  fontSize: compact ? 11 : 13,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _question(now),
                style: AppText.display.copyWith(
                  fontSize: compact ? 26 : 40,
                  letterSpacing: -1,
                ),
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              hm(now),
              style: AppText.clock.copyWith(fontSize: compact ? 26 : 36),
            ),
            const SizedBox(height: 4),
            Text(
              dayLong(now),
              style: AppText.label.copyWith(color: Palette.textTertiary),
            ),
          ],
        ),
      ],
    );
  }

  Widget _cards(DateTime now, bool compact) {
    final perf = context.read<PerformanceProfile>();
    final gap = compact ? 12.0 : 20.0;
    return LayoutBuilder(
      builder: (context, box) {
        final free = box.maxWidth - gap * 3;
        // La scheda scelta si allarga, le altre si stringono.
        final wide = free * 0.34;
        final narrow = (free - wide) / 3;
        final tuner = context.watch<TunerController>();
        final app = context.watch<AppController>();
        final channel = tuner.current;
        final contents = <Widget>[
          _LiveCard(
            channel: channel,
            title: channel == null
                ? null
                : app.epg.nowOn(channel.id, now)?.title,
            progress: channel == null
                ? null
                : app.epg.nowOn(channel.id, now)?.progressAt(now),
            compact: compact,
          ),
          _VodCard(
            title: 'Film',
            subtitle: _count(VodKind.movies, 'film', 'film'),
            posters: _posters(VodKind.movies),
            compact: compact,
          ),
          _VodCard(
            title: 'Serie TV',
            subtitle: _count(VodKind.series, 'serie', 'serie'),
            posters: _posters(VodKind.series),
            compact: compact,
          ),
          _GamesCard(compact: compact),
        ];
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < 4; i++) ...[
              if (i > 0) SizedBox(width: gap),
              AnimatedContainer(
                duration: perf.medium,
                curve: Curves.easeOutCubic,
                width: i == _sel ? wide : narrow,
                child: _Shell(
                  accent: _accents[i],
                  focused: _row == null && i == _sel,
                  selected: i == _sel,
                  enabled: _enabled(i),
                  onTap: () {
                    setState(() {
                      _sel = i;
                      _row = null;
                    });
                    _pick(i);
                  },
                  child: contents[i],
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  String _count(VodKind k, String one, String many) {
    if (!_vod.available) return 'Solo con liste Xtream';
    final c = _vod.catalog(k);
    if (c.loading && c.items.isEmpty) return 'Carico il catalogo…';
    final n = c.items.length;
    if (n == 0) return 'Sfoglia il catalogo';
    return '$n ${n == 1 ? one : many}';
  }

  /// Tre copertine: prima quelle in corso, poi le ultime aggiunte.
  List<String> _posters(VodKind k) {
    final out = <String>[];
    for (final w in _vod.continueWatching(k)) {
      final p = w.poster;
      if (p != null && p.startsWith('http') && !out.contains(p)) out.add(p);
      if (out.length == 3) return out;
    }
    final items = _vod.catalog(k).items;
    var best = <VodItem>[
      for (final i in items)
        if (i.poster != null &&
            i.poster!.startsWith('http') &&
            !_vod.isAdult(k, i))
          i,
    ];
    if (best.length > 40) {
      best.sort((a, b) => b.added.compareTo(a.added));
      best = best.take(40).toList();
    }
    for (final i in best) {
      if (!out.contains(i.poster)) out.add(i.poster!);
      if (out.length == 3) break;
    }
    return out;
  }

  Widget _resumeRow(List<(VodKind, WatchEntry)> resume, bool compact) {
    final focusedRow = _row != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'CONTINUA A GUARDARE',
          style: AppText.overline.copyWith(
            color: focusedRow ? Palette.textPrimary : Palette.textTertiary,
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) {
              final h = box.maxHeight;
              final w = h * 1.5;
              return ListView.separated(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                itemCount: resume.length,
                separatorBuilder: (_, _) => const SizedBox(width: 14),
                itemBuilder: (context, i) => SizedBox(
                  width: w,
                  child: _ResumeTile(
                    kind: resume[i].$1,
                    entry: resume[i].$2,
                    focused: _row == i,
                    onTap: () {
                      setState(() => _row = i);
                      _open(resume[i]);
                    },
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _hints(bool hasRow) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Wrap(
        spacing: 22,
        runSpacing: 8,
        children: [
          const KeyHint('← →', 'Scegli'),
          const KeyHint('OK', 'Apri'),
          if (hasRow)
            KeyHint(
              _row == null ? '↓' : '↑',
              _row == null ? 'Continua a guardare' : 'Sezioni',
            ),
          const KeyHint('Indietro', 'Torna alla TV'),
        ],
      ),
    );
  }
}

/// Cornice comune delle schede: colore, bordo e risalto del focus.
class _Shell extends StatelessWidget {
  const _Shell({
    required this.accent,
    required this.focused,
    required this.selected,
    required this.enabled,
    required this.onTap,
    required this.child,
  });

  final _Accent accent;
  final bool focused;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final perf = context.read<PerformanceProfile>();
    final compact = MediaQuery.sizeOf(context).width < 900;
    final r = compact ? 20.0 : 28.0;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedOpacity(
        duration: perf.fast,
        opacity: !enabled ? 0.4 : (selected ? 1 : 0.78),
        child: AnimatedContainer(
          duration: perf.medium,
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(r),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [accent.top, accent.bottom],
            ),
            border: Border.all(
              width: focused ? 3 : 1,
              color: focused
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.14),
            ),
            boxShadow: focused && !perf.isLight
                ? [
                    BoxShadow(
                      color: accent.glow.withValues(alpha: 0.45),
                      blurRadius: 40,
                      spreadRadius: -6,
                      offset: const Offset(0, 14),
                    ),
                  ]
                : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(r - 1),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Riflesso lucido in alto.
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.center,
                      colors: [Color(0x33FFFFFF), Color(0x00FFFFFF)],
                    ),
                  ),
                ),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Titolo e sottotitolo in basso a sinistra, sopra una velatura.
class _Caption extends StatelessWidget {
  const _Caption({
    required this.title,
    required this.subtitle,
    required this.compact,
    this.extra,
  });
  final String title;
  final String subtitle;
  final bool compact;
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomLeft,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(
          compact ? 14 : 22,
          compact ? 26 : 40,
          compact ? 14 : 22,
          compact ? 14 : 22,
        ),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x00000000), Color(0x99000000)],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.display.copyWith(
                fontSize: compact ? 19 : 28,
                letterSpacing: -0.6,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.label.copyWith(
                fontSize: compact ? 11.5 : 13.5,
                color: Colors.white.withValues(alpha: 0.78),
              ),
            ),
            ?extra,
          ],
        ),
      ),
    );
  }
}

class _LiveCard extends StatelessWidget {
  const _LiveCard({
    required this.channel,
    required this.title,
    required this.progress,
    required this.compact,
  });

  final Channel? channel;
  final String? title;
  final double? progress;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = channel;
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          left: compact ? 14 : 22,
          top: compact ? 14 : 22,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFE5373A),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'IN ONDA',
                  style: AppText.overline.copyWith(
                    color: Colors.white,
                    fontSize: 10,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (c != null)
          Align(
            alignment: const Alignment(0, -0.25),
            child: ChannelLogo(
              channel: c,
              width: compact ? 92 : 140,
              height: compact ? 60 : 92,
              radius: 16,
              padding: 12,
            ),
          )
        else
          Align(
            alignment: const Alignment(0, -0.25),
            child: Icon(
              Icons.live_tv_rounded,
              size: compact ? 54 : 80,
              color: Colors.white.withValues(alpha: 0.9),
            ),
          ),
        _Caption(
          title: 'TV in diretta',
          subtitle: c == null
              ? 'Torna ai canali'
              : '${c.number}  ${c.name}${title == null ? '' : '  ·  $title'}',
          compact: compact,
          extra: progress == null
              ? null
              : Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: EpgProgress(value: progress!),
                ),
        ),
      ],
    );
  }
}

class _VodCard extends StatelessWidget {
  const _VodCard({
    required this.title,
    required this.subtitle,
    required this.posters,
    required this.compact,
  });

  final String title;
  final String subtitle;
  final List<String> posters;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        LayoutBuilder(
          builder: (context, box) {
            final h = box.maxHeight * 0.62;
            final w = h / 1.5;
            const angles = [-0.16, 0.0, 0.16];
            const dx = [-0.55, 0.0, 0.55];
            final n = posters.length;
            return Stack(
              alignment: Alignment.center,
              children: [
                for (final i in n == 3 ? [0, 2, 1] : List.generate(n, (i) => i))
                  Positioned(
                    top: box.maxHeight * 0.08 + (n == 3 && i != 1 ? 10 : 0),
                    left: box.maxWidth / 2 - w / 2 + (n == 3 ? dx[i] * w : 0),
                    width: w,
                    height: h,
                    child: Transform.rotate(
                      angle: n == 3 ? angles[i] : 0,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Poster(
                          url: posters[i],
                          title: '',
                          radius: 10,
                          decodeWidth: 220,
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        _Caption(title: title, subtitle: subtitle, compact: compact),
      ],
    );
  }
}

/// Scheda giochi: invasore a pixel e sottotitolo arcade.
class _GamesCard extends StatelessWidget {
  const _GamesCard({required this.compact});
  final bool compact;

  static const _art = [
    '..W.....W..',
    '...W...W...',
    '..WWWWWWW..',
    '.WW.WWW.WW.',
    'WWWWWWWWWWW',
    'W.WWWWWWW.W',
    'W.W.....W.W',
    '...WW.WW...',
  ];

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Align(
          alignment: const Alignment(0, -0.35),
          child: SizedBox(
            width: compact ? 77 : 121,
            height: compact ? 56 : 88,
            child: const CustomPaint(painter: _PixelPainter(_art)),
          ),
        ),
        _Caption(
          title: 'Giochi',
          subtitle: 'Sei giochi, anche col telefono',
          compact: compact,
        ),
      ],
    );
  }
}

class _PixelPainter extends CustomPainter {
  const _PixelPainter(this.rows);
  final List<String> rows;

  @override
  void paint(Canvas canvas, Size size) {
    final cols = rows.first.length;
    final s = math.min(size.width / cols, size.height / rows.length);
    final p = Paint()..color = const Color(0xFFDFFFEF);
    for (var y = 0; y < rows.length; y++) {
      for (var x = 0; x < cols; x++) {
        if (rows[y][x] == 'W') {
          canvas.drawRect(Rect.fromLTWH(x * s, y * s, s - 1, s - 1), p);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_PixelPainter old) => false;
}

/// Titolo da riprendere: copertina orizzontale, avanzamento, episodio.
class _ResumeTile extends StatelessWidget {
  const _ResumeTile({
    required this.kind,
    required this.entry,
    required this.focused,
    required this.onTap,
  });

  final VodKind kind;
  final WatchEntry entry;
  final bool focused;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final perf = context.read<PerformanceProfile>();
    final left = entry.duration - entry.position;
    final sub = [
      ?entry.label,
      if (entry.duration > Duration.zero) 'mancano ${formatLength(left)}',
    ].join('  ·  ');
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedScale(
        duration: perf.fast,
        scale: focused ? 1.05 : 1,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: const Color(0xFF111827),
            border: Border.all(
              width: focused ? 3 : 1,
              color: focused
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.10),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Poster(
                  url: entry.poster,
                  title: entry.title,
                  radius: 0,
                  decodeWidth: 320,
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: [0.25, 1],
                      colors: [Color(0x00000000), Color(0xE6000000)],
                    ),
                  ),
                ),
                Positioned(
                  left: 12,
                  top: 10,
                  child: Text(
                    kind == VodKind.movies ? 'FILM' : 'SERIE',
                    style: AppText.overline.copyWith(
                      fontSize: 9.5,
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                  ),
                ),
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 10,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        entry.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.headline.copyWith(fontSize: 14.5),
                      ),
                      if (sub.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          sub,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.label.copyWith(
                            fontSize: 11.5,
                            color: Palette.textTertiary,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      ProgressBar(value: entry.fraction, height: 4),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
