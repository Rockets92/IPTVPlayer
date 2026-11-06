import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/performance.dart';
import '../../core/theme.dart';
import '../../data/vod/vod_models.dart';
import '../../state/vod_controller.dart';
import '../widgets/focus_tile.dart';
import 'vod_player.dart';
import 'vod_widgets.dart';

/// Apre la scheda di un film o di una serie sopra il catalogo.
Future<void> showVodDetail(
  BuildContext context, {
  required VodKind kind,
  required VodItem item,
}) {
  final perf = context.read<PerformanceProfile>();
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: true,
      transitionDuration: perf.medium,
      reverseTransitionDuration: perf.fast,
      pageBuilder: (_, _, _) => Material(
        color: Palette.ink,
        child: kind == VodKind.movies
            ? MovieDetail(item: item)
            : SeriesDetail(item: item),
      ),
      transitionsBuilder: (_, a, _, child) =>
          FadeTransition(opacity: a, child: child),
    ),
  );
}

/// Sfondo della scheda: immagine grande sfumata verso sinistra.
class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.url, required this.child});
  final String? url;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Palette.ink,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (url != null)
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: MediaQuery.sizeOf(context).width * 0.72,
              child: Opacity(
                opacity: 0.55,
                child: Poster(
                  url: url,
                  title: '',
                  radius: 0,
                  decodeWidth: context.read<PerformanceProfile>().isLight
                      ? 640
                      : 1280,
                ),
              ),
            ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                stops: [0.25, 0.75, 1],
                colors: [Palette.ink, Color(0xCC04060B), Color(0x6604060B)],
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                stops: [0, 0.4],
                colors: [Palette.ink, Color(0x0004060B)],
              ),
            ),
          ),
          SafeArea(child: child),
        ],
      ),
    );
  }
}

String _meta(List<String?> parts) =>
    parts.whereType<String>().where((s) => s.trim().isNotEmpty).join('   ·   ');

// --- Film --------------------------------------------------------------------

class MovieDetail extends StatefulWidget {
  const MovieDetail({super.key, required this.item});
  final VodItem item;

  @override
  State<MovieDetail> createState() => _MovieDetailState();
}

class _MovieDetailState extends State<MovieDetail> {
  late final VodController _vod = context.read<VodController>();
  late final Future<MovieInfo> _info = _vod.movieInfo(widget.item.id);
  int _btn = 0;

  String get _key => 'm:${widget.item.id}';

  WatchEntry? get _progress {
    final w = _vod.progressOf(_key);
    return w == null || w.finished ? null : w;
  }

  Future<void> _play({required bool resume}) async {
    final m = widget.item;
    final w = _progress;
    await playVod(
      context,
      VodPlayback(
        title: m.title,
        url: _vod.movieUrl(m),
        start: resume ? w?.position : null,
        entry: (pos, dur) => WatchEntry(
          key: _key,
          position: pos,
          duration: dur,
          at: DateTime.now(),
          title: m.title,
          poster: m.poster,
          extension: m.extension,
        ),
      ),
    );
    if (mounted) setState(() => _btn = 0);
  }

  List<(String, IconData, VoidCallback)> get _buttons {
    final w = _progress;
    return [
      if (w != null)
        (
          'Riprendi da ${formatClock(w.position)}',
          Icons.play_arrow_rounded,
          () => _play(resume: true),
        ),
      (
        w != null ? 'Dall\'inizio' : 'Guarda',
        w != null ? Icons.replay_rounded : Icons.play_arrow_rounded,
        () => _play(resume: false),
      ),
      if (_vod.progressOf(_key) != null)
        (
          'Togli da Continua a guardare',
          Icons.close_rounded,
          () {
            _vod.forget(_key);
            setState(() => _btn = 0);
          },
        ),
    ];
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final n = _buttons.length;
    if (k == LogicalKeyboardKey.arrowLeft) {
      setState(() => _btn = (_btn - 1).clamp(0, n - 1));
    } else if (k == LogicalKeyboardKey.arrowRight) {
      setState(() => _btn = (_btn + 1).clamp(0, n - 1));
    } else if (isSelectKey(k)) {
      _buttons[_btn.clamp(0, n - 1)].$3();
    } else if (isBackKey(k)) {
      Navigator.of(context).pop();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    context.watch<VodController>();
    final m = widget.item;
    final compact = MediaQuery.sizeOf(context).width < 900;
    final buttons = _buttons;
    _btn = _btn.clamp(0, buttons.length - 1);
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: FutureBuilder<MovieInfo>(
        future: _info,
        builder: (context, snap) {
          final info = snap.data ?? const MovieInfo();
          final w = _progress;
          return _Backdrop(
            url: info.backdrop ?? m.poster,
            child: Padding(
              padding: EdgeInsets.all(compact ? 20 : 48),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: compact ? 170 : 260,
                    child: AspectRatio(
                      aspectRatio: 2 / 3,
                      child: Poster(url: m.poster, title: m.title, radius: 18),
                    ),
                  ),
                  SizedBox(width: compact ? 22 : 44),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('FILM', style: AppText.overline),
                        const SizedBox(height: 10),
                        Text(
                          m.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.display.copyWith(
                            fontSize: compact ? 28 : 40,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _meta([
                            '${info.year ?? m.year ?? ''}',
                            info.duration == null
                                ? null
                                : formatLength(info.duration!),
                            info.genre ?? m.genre,
                            (info.rating ?? m.rating) == null
                                ? null
                                : '★ ${(info.rating ?? m.rating)!.toStringAsFixed(1)}',
                          ]),
                          style: AppText.label.copyWith(fontSize: 14),
                        ),
                        const SizedBox(height: 18),
                        if (snap.connectionState != ConnectionState.done)
                          Text('Carico la scheda…', style: AppText.body)
                        else if ((info.plot ?? m.plot) != null)
                          Text(
                            (info.plot ?? m.plot)!,
                            maxLines: compact ? 4 : 6,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.body.copyWith(fontSize: 16),
                          ),
                        if (info.director != null || info.cast != null) ...[
                          const SizedBox(height: 14),
                          if (info.director != null)
                            Text(
                              'Regia: ${info.director}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.label.copyWith(
                                color: Palette.textTertiary,
                              ),
                            ),
                          if (info.cast != null)
                            Text(
                              'Con: ${info.cast}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.label.copyWith(
                                color: Palette.textTertiary,
                              ),
                            ),
                        ],
                        const SizedBox(height: 26),
                        if (w != null) ...[
                          SizedBox(
                            width: 360,
                            child: ProgressBar(value: w.fraction),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Visto ${formatClock(w.position)} di ${formatClock(w.duration)}',
                            style: AppText.label.copyWith(
                              color: Palette.textTertiary,
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            for (var i = 0; i < buttons.length; i++)
                              Pill(
                                label: buttons[i].$1,
                                icon: buttons[i].$2,
                                primary: i == 0,
                                focused: i == _btn,
                                onTap: buttons[i].$3,
                              ),
                          ],
                        ),
                        const SizedBox(height: 22),
                        const KeyHint('Indietro', 'Torna ai film'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// --- Serie -------------------------------------------------------------------

enum _SZone { resume, seasons, episodes }

class SeriesDetail extends StatefulWidget {
  const SeriesDetail({super.key, required this.item});
  final VodItem item;

  @override
  State<SeriesDetail> createState() => _SeriesDetailState();
}

class _SeriesDetailState extends State<SeriesDetail> {
  late final VodController _vod = context.read<VodController>();
  late final Future<SeriesInfo> _future = _vod.seriesInfo(widget.item.id);
  final _list = ScrollController();

  _SZone _zone = _SZone.episodes;
  int _season = 0;
  int _ep = 0;
  bool _placed = false;

  String get _key => 's:${widget.item.id}';

  @override
  void dispose() {
    _list.dispose();
    super.dispose();
  }

  WatchEntry? get _resume {
    final w = _vod.progressOf(_key);
    return w == null || w.finished ? null : w;
  }

  /// Alla prima apertura si parte dall'ultimo episodio visto.
  void _place(SeriesInfo info) {
    if (_placed || info.seasons.isEmpty) return;
    _placed = true;
    final w = _vod.progressOf(_key);
    final seasons = info.seasonNumbers;
    if (w?.episodeId != null) {
      for (var s = 0; s < seasons.length; s++) {
        final eps = info.seasons[seasons[s]]!;
        final i = eps.indexWhere((e) => e.id == w!.episodeId);
        if (i >= 0) {
          _season = s;
          _ep = i;
          // Episodio finito: si propone il successivo.
          if (w!.finished) {
            if (i + 1 < eps.length) {
              _ep = i + 1;
            } else if (s + 1 < seasons.length) {
              _season = s + 1;
              _ep = 0;
            }
          }
          break;
        }
      }
    }
    if (_resume != null) _zone = _SZone.resume;
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(false));
  }

  static const _rowH = 92.0;

  void _reveal([bool animate = true]) {
    if (!_list.hasClients) return;
    final pos = _list.position;
    final t = (_ep * _rowH - pos.viewportDimension / 2 + _rowH / 2).clamp(
      0.0,
      pos.maxScrollExtent,
    );
    _list.jumpTo(t);
  }

  /// Episodio successivo a [e] (anche nella stagione dopo).
  Episode? _after(SeriesInfo info, Episode e) {
    final seasons = info.seasonNumbers;
    final eps = info.seasons[e.season] ?? const [];
    final i = eps.indexWhere((x) => x.id == e.id);
    if (i >= 0 && i + 1 < eps.length) return eps[i + 1];
    final s = seasons.indexOf(e.season);
    if (s >= 0 && s + 1 < seasons.length) {
      final next = info.seasons[seasons[s + 1]]!;
      if (next.isNotEmpty) return next.first;
    }
    return null;
  }

  VodPlayback _playbackOf(SeriesInfo info, Episode e, {Duration? start}) {
    final s = widget.item;
    return VodPlayback(
      title: s.title,
      subtitle: '${e.code}  ·  ${e.title}',
      url: _vod.episodeUrl(e),
      start: start,
      entry: (pos, dur) => WatchEntry(
        key: _key,
        position: pos,
        duration: dur,
        at: DateTime.now(),
        title: s.title,
        poster: s.poster,
        seriesId: s.id,
        episodeId: e.id,
        extension: e.extension,
        label: '${e.code} · ${e.title}',
      ),
      next: () {
        final n = _after(info, e);
        return n == null ? null : _playbackOf(info, n);
      },
    );
  }

  Future<void> _play(SeriesInfo info, Episode e, {bool resume = true}) async {
    final pos = resume ? _vod.episodePosition(e.id) : null;
    final w = _vod.progressOf(_key);
    final done =
        w?.episodeId == e.id && w!.finished ||
        (pos != null &&
            e.duration != null &&
            e.duration!.inSeconds - pos.inSeconds < 150);
    await playVod(context, _playbackOf(info, e, start: done ? null : pos));
    if (!mounted) return;
    _placed = false;
    setState(() => _place(info));
  }

  void _playResume(SeriesInfo info) {
    final id = _resume?.episodeId;
    for (final s in info.seasonNumbers) {
      for (final x in info.seasons[s]!) {
        if (x.id == id) {
          _play(info, x);
          return;
        }
      }
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e, SeriesInfo? info) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final k = e.logicalKey;
    if (isBackKey(k)) {
      if (e is KeyDownEvent) Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    if (info == null || info.seasons.isEmpty) return KeyEventResult.handled;
    final seasons = info.seasonNumbers;
    final eps = info.seasons[seasons[_season]]!;
    final hasResume = _resume != null;
    final up = k == LogicalKeyboardKey.arrowUp;
    final down = k == LogicalKeyboardKey.arrowDown;
    final left = k == LogicalKeyboardKey.arrowLeft;
    final right = k == LogicalKeyboardKey.arrowRight;
    final ok = isSelectKey(k) && e is KeyDownEvent;
    setState(() {
      switch (_zone) {
        case _SZone.resume:
          if (right || down) _zone = _SZone.seasons;
          if (ok) _playResume(info);
        case _SZone.seasons:
          if (left) {
            if (_season > 0) {
              _season--;
              _ep = 0;
            } else if (hasResume) {
              _zone = _SZone.resume;
            }
          } else if (right && _season + 1 < seasons.length) {
            _season++;
            _ep = 0;
          } else if (down || ok) {
            _zone = _SZone.episodes;
          } else if (up && hasResume) {
            _zone = _SZone.resume;
          }
          WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
        case _SZone.episodes:
          if (up) {
            if (_ep == 0) {
              _zone = _SZone.seasons;
            } else {
              _ep--;
            }
          } else if (down) {
            _ep = (_ep + 1).clamp(0, eps.length - 1);
          } else if (left && hasResume) {
            _zone = _SZone.resume;
          } else if (ok && _ep < eps.length) {
            _play(info, eps[_ep]);
          }
          WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
      }
    });
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    context.watch<VodController>();
    final s = widget.item;
    final compact = MediaQuery.sizeOf(context).width < 900;
    return FutureBuilder<SeriesInfo>(
      future: _future,
      builder: (context, snap) {
        final info = snap.data;
        if (info != null) _place(info);
        final w = _resume;
        if (w == null && _zone == _SZone.resume) _zone = _SZone.seasons;
        return Focus(
          autofocus: true,
          onKeyEvent: (n, e) => _onKey(n, e, info),
          child: _Backdrop(
            url: info?.backdrop ?? s.poster,
            child: Padding(
              padding: EdgeInsets.all(compact ? 20 : 44),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: compact ? 230 : 340,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: compact ? 120 : 170,
                          child: AspectRatio(
                            aspectRatio: 2 / 3,
                            child: Poster(
                              url: s.poster,
                              title: s.title,
                              radius: 16,
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text('SERIE TV', style: AppText.overline),
                        const SizedBox(height: 8),
                        Text(
                          s.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.display.copyWith(
                            fontSize: compact ? 24 : 32,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _meta([
                            s.year?.toString(),
                            info == null
                                ? null
                                : '${info.seasons.length} '
                                      '${info.seasons.length == 1 ? 'stagione' : 'stagioni'}',
                            s.rating == null
                                ? null
                                : '★ ${s.rating!.toStringAsFixed(1)}',
                          ]),
                          style: AppText.label,
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: Text(
                            info?.plot ?? s.plot ?? '',
                            maxLines: compact ? 4 : 7,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.body,
                          ),
                        ),
                        if (w != null) ...[
                          Text(
                            w.label ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.label.copyWith(
                              color: Palette.textTertiary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          ProgressBar(value: w.fraction, height: 4),
                          const SizedBox(height: 10),
                          Pill(
                            label: 'Riprendi da ${formatClock(w.position)}',
                            icon: Icons.play_arrow_rounded,
                            primary: true,
                            focused: _zone == _SZone.resume,
                            onTap: info == null
                                ? null
                                : () {
                                    setState(() => _zone = _SZone.resume);
                                    _playResume(info);
                                  },
                          ),
                        ],
                      ],
                    ),
                  ),
                  SizedBox(width: compact ? 18 : 40),
                  Expanded(child: _episodes(info, snap, compact)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _episodes(SeriesInfo? info, AsyncSnapshot<SeriesInfo> snap, bool c) {
    if (info == null) {
      return const Center(
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          color: Palette.accent,
        ),
      );
    }
    if (info.seasons.isEmpty) {
      return Center(
        child: Text(
          'Nessun episodio disponibile per questa serie.',
          style: AppText.body.copyWith(fontSize: 16),
        ),
      );
    }
    final seasons = info.seasonNumbers;
    _season = _season.clamp(0, seasons.length - 1);
    final eps = info.seasons[seasons[_season]]!;
    _ep = _ep.clamp(0, eps.length - 1);
    final w = _vod.progressOf(_key);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (var i = 0; i < seasons.length; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Pill(
                    label: 'Stagione ${seasons[i]}',
                    compact: true,
                    active: i == _season,
                    focused: _zone == _SZone.seasons && i == _season,
                    onTap: () => setState(() {
                      _season = i;
                      _ep = 0;
                      _zone = _SZone.seasons;
                    }),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: ListView.builder(
            controller: _list,
            itemExtent: _rowH,
            itemCount: eps.length,
            itemBuilder: (context, i) {
              final e = eps[i];
              final f = _zone == _SZone.episodes && i == _ep;
              final pos = _vod.episodePosition(e.id);
              final dur = e.duration;
              final last = w?.episodeId == e.id;
              final frac = pos == null
                  ? null
                  : dur != null && dur.inSeconds > 0
                  ? pos.inSeconds / dur.inSeconds
                  : last && w!.duration.inSeconds > 0
                  ? w.fraction
                  : null;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  setState(() {
                    _zone = _SZone.episodes;
                    _ep = i;
                  });
                  _play(info, e);
                },
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 3),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: f
                        ? Colors.white.withValues(alpha: 0.16)
                        : Colors.white.withValues(alpha: 0.04),
                    border: Border.all(
                      width: f ? 2 : 1,
                      color: f
                          ? Palette.accent
                          : Colors.white.withValues(alpha: 0.06),
                    ),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 44,
                        child: Text(
                          '${e.number}',
                          style: AppText.display.copyWith(
                            fontSize: 24,
                            color: f
                                ? Palette.textPrimary
                                : Palette.textTertiary,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    e.title.isEmpty ? e.code : e.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppText.headline.copyWith(
                                      fontSize: 15.5,
                                    ),
                                  ),
                                ),
                                if (last)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 8),
                                    child: Text(
                                      'ULTIMO VISTO',
                                      style: AppText.overline.copyWith(
                                        color: Palette.accent,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ),
                                if (dur != null)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 10),
                                    child: Text(
                                      formatLength(dur),
                                      style: AppText.label.copyWith(
                                        color: Palette.textTertiary,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            if (e.plot != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                e.plot!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.label.copyWith(
                                  color: Palette.textTertiary,
                                ),
                              ),
                            ],
                            if (frac != null) ...[
                              const SizedBox(height: 7),
                              ProgressBar(value: frac, height: 3),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
