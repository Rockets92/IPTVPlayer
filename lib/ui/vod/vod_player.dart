import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/performance.dart';
import '../../core/theme.dart';
import '../../player/playback_engine.dart';
import '../../state/vod_controller.dart';
import '../widgets/focus_tile.dart';
import '../widgets/glass.dart';
import 'vod_widgets.dart';

/// Cosa riprodurre e come annotare dove si è arrivati.
class VodPlayback {
  const VodPlayback({
    required this.title,
    required this.url,
    required this.entry,
    this.subtitle,
    this.start,
    this.next,
  });

  final String title;
  final String? subtitle;
  final String url;
  final Duration? start;
  final WatchEntry Function(Duration position, Duration duration) entry;

  /// Episodio successivo, se c'è.
  final VodPlayback? Function()? next;
}

/// Riproduce a tutto schermo; torna quando si esce.
Future<void> playVod(BuildContext context, VodPlayback p) {
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      transitionDuration: context.read<PerformanceProfile>().fast,
      pageBuilder: (_, _, _) => VodPlayerScreen(playback: p),
      transitionsBuilder: (_, a, _, child) =>
          FadeTransition(opacity: a, child: child),
    ),
  );
}

class VodPlayerScreen extends StatefulWidget {
  const VodPlayerScreen({super.key, required this.playback});
  final VodPlayback playback;

  @override
  State<VodPlayerScreen> createState() => _VodPlayerScreenState();
}

class _VodPlayerScreenState extends State<VodPlayerScreen> {
  late final PlaybackEngine _engine = context.read<PlaybackEngine>();
  late final VodController _vod = context.read<VodController>();
  late VodPlayback _p = widget.playback;

  bool _controls = true;
  Timer? _hideTimer;
  Timer? _saveTimer;

  /// Spostamento in corso (←→ ripetuti): si applica dopo una breve pausa.
  Duration? _pendingSeek;
  Timer? _seekTimer;

  /// Menu tracce: colonna (0 audio, 1 sottotitoli) e riga.
  bool _tracks = false;
  int _trackCol = 0;
  int _trackRow = 0;

  /// Conto alla rovescia per l'episodio successivo.
  VodPlayback? _upNext;
  int _countdown = 0;
  Timer? _countdownTimer;
  bool _endedHandled = false;

  @override
  void initState() {
    super.initState();
    _start();
    _engine.vod.addListener(_onVod);
    _saveTimer = Timer.periodic(const Duration(seconds: 15), (_) => _save());
  }

  void _start() {
    _endedHandled = false;
    unawaited(_engine.openVod(_p.url, start: _p.start));
    _poke();
  }

  @override
  void dispose() {
    _save();
    _engine.vod.removeListener(_onVod);
    _hideTimer?.cancel();
    _saveTimer?.cancel();
    _seekTimer?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _save({bool finished = false}) {
    final v = _engine.vod.value;
    if (v.duration <= Duration.zero) return;
    _vod.remember(_p.entry(finished ? v.duration : v.position, v.duration));
  }

  void _onVod() {
    final v = _engine.vod.value;
    if (v.ended && !_endedHandled) {
      _endedHandled = true;
      _save(finished: true);
      final next = _p.next?.call();
      if (next == null) {
        if (mounted) Navigator.of(context).maybePop();
        return;
      }
      setState(() {
        _upNext = next;
        _countdown = 10;
        _controls = false;
      });
      _countdownTimer?.cancel();
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) return t.cancel();
        if (--_countdown <= 0) {
          t.cancel();
          _playNext();
        } else {
          setState(() {});
        }
      });
    }
  }

  void _playNext() {
    final n = _upNext;
    if (n == null) return;
    _countdownTimer?.cancel();
    setState(() {
      _p = n;
      _upNext = null;
      _pendingSeek = null;
    });
    _start();
  }

  void _poke() {
    if (!_controls) setState(() => _controls = true);
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      final v = _engine.vod.value;
      if (mounted && v.playing && !_tracks) {
        setState(() => _controls = false);
      }
    });
  }

  void _seekBy(Duration d) {
    final v = _engine.vod.value;
    final base = _pendingSeek ?? v.position;
    var t = base + d;
    if (t < Duration.zero) t = Duration.zero;
    if (v.duration > Duration.zero &&
        t > v.duration - const Duration(seconds: 3)) {
      t = v.duration - const Duration(seconds: 3);
    }
    setState(() => _pendingSeek = t);
    _poke();
    _seekTimer?.cancel();
    _seekTimer = Timer(const Duration(milliseconds: 450), () {
      final s = _pendingSeek;
      if (s == null) return;
      unawaited(
        _engine.seek(s).whenComplete(() {
          if (mounted) setState(() => _pendingSeek = null);
        }),
      );
    });
  }

  List<List<TrackOption>> get _trackLists {
    final v = _engine.vod.value;
    return [
      v.audio,
      [const TrackOption('no', 'Disattivati'), ...v.subtitles],
    ];
  }

  void _openTracks() {
    final v = _engine.vod.value;
    final lists = _trackLists;
    setState(() {
      _tracks = true;
      _trackCol = lists[0].length > 1 || lists[1].length <= 1 ? 0 : 1;
      final cur = _trackCol == 0 ? v.audioId : (v.subtitleId ?? 'no');
      _trackRow = lists[_trackCol]
          .indexWhere((t) => t.id == cur)
          .clamp(0, 1 << 20);
    });
    _poke();
  }

  void _pickTrack(int col, int row) {
    final lists = _trackLists;
    if (row >= lists[col].length) return;
    final id = lists[col][row].id;
    if (col == 0) {
      unawaited(_engine.setAudioTrack(id));
    } else {
      unawaited(_engine.setSubtitleTrack(id));
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final k = e.logicalKey;
    final repeat = e is KeyRepeatEvent;
    final back = isBackKey(k) && !repeat;

    if (_upNext != null) {
      if (isSelectKey(k) && !repeat) {
        _playNext();
      } else if (back) {
        _countdownTimer?.cancel();
        Navigator.of(context).pop();
      }
      return KeyEventResult.handled;
    }

    if (_tracks) {
      final lists = _trackLists;
      if (k == LogicalKeyboardKey.arrowLeft ||
          k == LogicalKeyboardKey.arrowRight) {
        final c = k == LogicalKeyboardKey.arrowRight ? 1 : 0;
        if (lists[c].isNotEmpty) {
          setState(() {
            _trackCol = c;
            _trackRow = _trackRow.clamp(0, lists[c].length - 1);
          });
        }
      } else if (k == LogicalKeyboardKey.arrowUp) {
        setState(() => _trackRow = (_trackRow - 1).clamp(0, 1 << 20));
      } else if (k == LogicalKeyboardKey.arrowDown) {
        setState(
          () =>
              _trackRow = (_trackRow + 1).clamp(0, lists[_trackCol].length - 1),
        );
      } else if (isSelectKey(k) && !repeat) {
        _pickTrack(_trackCol, _trackRow);
      } else if (back) {
        setState(() => _tracks = false);
      }
      _poke();
      return KeyEventResult.handled;
    }

    if (k == LogicalKeyboardKey.arrowLeft ||
        k == LogicalKeyboardKey.mediaRewind) {
      _seekBy(Duration(seconds: repeat ? -30 : -10));
    } else if (k == LogicalKeyboardKey.arrowRight ||
        k == LogicalKeyboardKey.mediaFastForward) {
      _seekBy(Duration(seconds: repeat ? 30 : 10));
    } else if (repeat) {
      return KeyEventResult.handled;
    } else if (isSelectKey(k) ||
        k == LogicalKeyboardKey.mediaPlayPause ||
        k == LogicalKeyboardKey.mediaPlay ||
        k == LogicalKeyboardKey.mediaPause) {
      if (!_controls && isSelectKey(k)) {
        _poke();
      } else {
        unawaited(_engine.playOrPause());
        _poke();
      }
    } else if (k == LogicalKeyboardKey.arrowDown ||
        k == LogicalKeyboardKey.keyA ||
        k == LogicalKeyboardKey.colorF2Yellow) {
      if (_controls) {
        _openTracks();
      } else {
        _poke();
      }
    } else if (k == LogicalKeyboardKey.arrowUp ||
        k == LogicalKeyboardKey.info ||
        k == LogicalKeyboardKey.keyI) {
      _poke();
    } else if (k == LogicalKeyboardKey.mediaStop || back) {
      if (back && _controls && _engine.vod.value.playing) {
        setState(() => _controls = false);
        return KeyEventResult.handled;
      }
      Navigator.of(context).pop();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final perf = context.read<PerformanceProfile>();
    final compact = MediaQuery.sizeOf(context).width < 900;
    final pad = compact ? 18.0 : 40.0;
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) return;
        // Prima di fermare: poi il motore azzera posizione e durata.
        _save();
        unawaited(_engine.stop());
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Focus(
          autofocus: true,
          onKeyEvent: _onKey,
          child: MouseRegion(
            onHover: (_) => _poke(),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                if (_controls) {
                  unawaited(_engine.playOrPause());
                }
                _poke();
              },
              onDoubleTapDown: (d) {
                final w = MediaQuery.sizeOf(context).width;
                _seekBy(
                  Duration(seconds: d.globalPosition.dx < w / 2 ? -10 : 10),
                );
              },
              onDoubleTap: () {},
              child: Stack(
                fit: StackFit.expand,
                children: [
                  RepaintBoundary(child: _engine.buildView(context)),
                  ValueListenableBuilder<PlaybackSnapshot>(
                    valueListenable: _engine.state,
                    builder: (context, s, _) {
                      if (s.status == PlaybackStatus.failed) {
                        return Center(
                          child: Glass(
                            padding: const EdgeInsets.all(26),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Impossibile riprodurre questo titolo',
                                  style: AppText.title,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Il server della lista non lo sta inviando. Riprova più tardi.',
                                  style: AppText.body,
                                ),
                                const SizedBox(height: 14),
                                const KeyHint('Indietro', 'Esci'),
                              ],
                            ),
                          ),
                        );
                      }
                      if (s.status == PlaybackStatus.connecting ||
                          s.buffering) {
                        return const Center(
                          child: SizedBox(
                            width: 44,
                            height: 44,
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              color: Palette.accent,
                            ),
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                  IgnorePointer(
                    ignoring: !_controls,
                    child: AnimatedOpacity(
                      duration: perf.medium,
                      opacity: _controls ? 1 : 0,
                      child: _overlay(pad, compact),
                    ),
                  ),
                  if (_upNext != null) _upNextCard(pad),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _overlay(double pad, bool compact) {
    return ValueListenableBuilder<VodState>(
      valueListenable: _engine.vod,
      builder: (context, v, _) {
        final pos = _pendingSeek ?? v.position;
        final dur = v.duration;
        final frac = dur.inMilliseconds <= 0
            ? 0.0
            : pos.inMilliseconds / dur.inMilliseconds;
        return DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [0, 0.25, 0.6, 1],
              colors: [
                Color(0xAA000000),
                Color(0x00000000),
                Color(0x00000000),
                Color(0xCC000000),
              ],
            ),
          ),
          child: Padding(
            padding: EdgeInsets.all(pad),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _p.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.display.copyWith(fontSize: compact ? 22 : 30),
                ),
                if (_p.subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      _p.subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.headline.copyWith(
                        color: Palette.textSecondary,
                      ),
                    ),
                  ),
                const Spacer(),
                if (_tracks)
                  Align(
                    alignment: Alignment.bottomRight,
                    child: _tracksMenu(v),
                  ),
                if (_tracks) const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(
                      v.playing
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      size: 34,
                      color: Palette.textPrimary,
                    ),
                    const SizedBox(width: 14),
                    Text(
                      formatClock(pos),
                      style: AppText.mono.copyWith(
                        fontSize: 15,
                        color: Palette.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(child: ProgressBar(value: frac, height: 6)),
                    const SizedBox(width: 14),
                    Text(
                      dur > Duration.zero
                          ? '-${formatClock(dur - pos)}'
                          : '--:--',
                      style: AppText.mono.copyWith(fontSize: 15),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 18,
                  runSpacing: 8,
                  children: [
                    KeyHint('OK', v.playing ? 'Pausa' : 'Riprendi'),
                    const KeyHint('← →', '10 secondi (tieni premuto: 30)'),
                    if (v.audio.length > 1 || v.subtitles.isNotEmpty)
                      const KeyHint('↓', 'Audio e sottotitoli'),
                    const KeyHint('Indietro', 'Esci'),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _tracksMenu(VodState v) {
    final lists = _trackLists;
    Widget column(int col, String title, List<TrackOption> items, String? cur) {
      return SizedBox(
        width: 250,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: AppText.overline),
            const SizedBox(height: 8),
            if (items.isEmpty)
              Text('Nessuna traccia', style: AppText.label)
            else
              for (var i = 0; i < items.length && i < 8; i++)
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _trackCol = col;
                      _trackRow = i;
                    });
                    _pickTrack(col, i);
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      gradient: _trackCol == col && _trackRow == i
                          ? Palette.neon
                          : null,
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 22,
                          child: items[i].id == cur
                              ? Icon(
                                  Icons.check_rounded,
                                  size: 17,
                                  color: _trackCol == col && _trackRow == i
                                      ? Palette.textPrimary
                                      : Palette.accent,
                                )
                              : null,
                        ),
                        Expanded(
                          child: Text(
                            items[i].label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.label.copyWith(
                              fontSize: 14,
                              color: _trackCol == col && _trackRow == i
                                  ? Palette.textPrimary
                                  : Palette.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      );
    }

    return Glass(
      strong: true,
      radius: 22,
      padding: const EdgeInsets.all(18),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          column(0, 'AUDIO', lists[0], v.audioId),
          const SizedBox(width: 18),
          column(1, 'SOTTOTITOLI', lists[1], v.subtitleId ?? 'no'),
        ],
      ),
    );
  }

  Widget _upNextCard(double pad) {
    final n = _upNext!;
    return Positioned(
      right: pad,
      bottom: pad,
      child: Glass(
        strong: true,
        radius: 22,
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('PROSSIMO EPISODIO TRA $_countdown', style: AppText.overline),
            const SizedBox(height: 8),
            Text(n.subtitle ?? n.title, style: AppText.headline),
            const SizedBox(height: 14),
            const Wrap(
              spacing: 16,
              children: [
                KeyHint('OK', 'Guarda ora'),
                KeyHint('Indietro', 'Esci'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
