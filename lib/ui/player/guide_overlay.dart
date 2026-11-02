import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/performance.dart';
import '../../core/theme.dart';
import '../../data/epg/epg_models.dart';
import '../../domain/channel.dart';
import '../../state/app_controller.dart';
import '../../state/reminder_controller.dart';
import '../../state/tuner_controller.dart';
import '../format.dart';
import '../keys.dart';
import '../widgets/channel_logo.dart';
import '../widgets/epg_progress.dart';
import '../widgets/focus_tile.dart';
import '../widgets/glass.dart';
import '../widgets/now.dart';
import 'channel_list_overlay.dart';
import 'channel_row.dart';

/// Guida TV a due colonne: canali a sinistra, palinsesto a destra.
class GuideOverlay extends StatefulWidget {
  const GuideOverlay({super.key, required this.onClose});
  final VoidCallback onClose;

  @override
  State<GuideOverlay> createState() => _GuideOverlayState();
}

class _GuideOverlayState extends State<GuideOverlay> {
  final _chScroll = ScrollController();
  final _progScroll = ScrollController();
  final _focus = FocusNode(debugLabel: 'guide');
  int _ch = 0;
  int _prog = 0;
  bool _inProgrammes = false;
  int _group = 0;

  static const _rowExtent = ChannelRow.extent + 6;

  List<String> get _groups => context.read<AppController>().groups;

  /// Canali della categoria scelta (0 = tutti).
  List<Channel> get _channels {
    final all = context.read<AppController>().channels;
    if (_group == 0 || _group > _groups.length) return all;
    final g = _groups[_group - 1];
    return all.where((c) => c.group == g).toList();
  }

  void _setGroup(int g) {
    final count = _groups.length + 1;
    final current = context.read<TunerController>().current;
    setState(() {
      _group = (g % count + count) % count;
      final i = current == null ? -1 : _channels.indexOf(current);
      _ch = i < 0 ? 0 : i;
      _prog = 0;
      _inProgrammes = false;
    });
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _revealChannel(animate: false),
    );
    final list = _channels;
    if (list.isNotEmpty) context.read<AppController>().ensureEpg(list[_ch]);
  }

  @override
  void initState() {
    super.initState();
    final cur = context.read<TunerController>().current;
    final i = cur == null ? 0 : _channels.indexOf(cur);
    _ch = i < 0 ? 0 : i;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focus.requestFocus();
      _revealChannel(animate: false);
    });
  }

  @override
  void dispose() {
    _chScroll.dispose();
    _progScroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  List<EpgProgramme> _programmes() {
    if (_channels.isEmpty) return const [];
    final epg = context.read<AppController>().epg;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return epg.forChannel(_channels[_ch].id).where((p) => p.end > now).toList();
  }

  void _revealChannel({bool animate = true}) {
    if (!_chScroll.hasClients) return;
    final pos = _chScroll.position;
    final target =
        (_ch * _rowExtent - pos.viewportDimension / 2 + _rowExtent / 2).clamp(
          0.0,
          pos.maxScrollExtent,
        );
    final perf = context.read<PerformanceProfile>();
    if (!animate || perf.isLight || (target - pos.pixels).abs() > 2000) {
      _chScroll.jumpTo(target);
    } else {
      _chScroll.animateTo(
        target,
        duration: perf.fast,
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _moveChannel(int d) {
    final n = _channels.length;
    if (n == 0) return;
    setState(() {
      _ch = ((_ch + d) % n + n) % n;
      _prog = 0;
    });
    if (_progScroll.hasClients) _progScroll.jumpTo(0);
    _revealChannel();
    context.read<AppController>().ensureEpg(_channels[_ch]);
  }

  void _moveProgramme(int d) {
    final n = _programmes().length;
    if (n == 0) return;
    setState(() => _prog = (_prog + d).clamp(0, n - 1));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _progKeys[_prog]?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.3,
          duration: context.read<PerformanceProfile>().fast,
        );
      }
    });
  }

  final _progKeys = <int, GlobalKey>{};
  String _jump = '';
  DateTime _jumpAt = DateTime(0);

  /// Digitando un numero si salta al canale corrispondente nella guida.
  void _jumpDigit(int d) {
    final t = DateTime.now();
    if (t.difference(_jumpAt) > const Duration(milliseconds: 1200)) _jump = '';
    _jumpAt = t;
    _jump += '$d';
    final n = int.parse(_jump);
    var i = _channels.indexWhere((c) => c.number >= n);
    if (i < 0) i = _channels.length - 1;
    _moveChannel(i - _ch);
  }

  /// OK: su un programma futuro imposta o toglie il promemoria, altrimenti
  /// sintonizza il canale.
  void _select() {
    if (_inProgrammes) {
      final list = _programmes();
      if (_prog < list.length) {
        final p = list[_prog];
        if (p.startTime.isAfter(DateTime.now())) {
          context.read<ReminderController>().toggle(_channels[_ch], p);
          return;
        }
      }
    }
    _tuneSelected();
  }

  void _tuneSelected() {
    if (_channels.isEmpty) return;
    context.read<TunerController>().tuneTo(_channels[_ch]);
    widget.onClose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowUp) {
      _inProgrammes ? _moveProgramme(-1) : _moveChannel(-1);
    } else if (k == LogicalKeyboardKey.arrowDown) {
      _inProgrammes ? _moveProgramme(1) : _moveChannel(1);
    } else if (k == LogicalKeyboardKey.pageUp ||
        k == LogicalKeyboardKey.channelUp) {
      _moveChannel(-8);
    } else if (k == LogicalKeyboardKey.pageDown ||
        k == LogicalKeyboardKey.channelDown) {
      _moveChannel(8);
    } else if (k == LogicalKeyboardKey.arrowRight) {
      if (_programmes().isNotEmpty) setState(() => _inProgrammes = true);
    } else if (k == LogicalKeyboardKey.arrowLeft) {
      if (_inProgrammes) {
        setState(() => _inProgrammes = false);
      } else {
        _setGroup(_group - 1);
      }
    } else if (k == LogicalKeyboardKey.keyC ||
        k == LogicalKeyboardKey.colorF2Yellow) {
      _setGroup(_group + 1);
    } else if (isSelectKey(k)) {
      _select();
    } else if (isBackKey(k)) {
      if (_inProgrammes) {
        setState(() => _inProgrammes = false);
      } else {
        widget.onClose();
      }
    } else if (k == LogicalKeyboardKey.keyG || k == LogicalKeyboardKey.guide) {
      widget.onClose();
    } else {
      final d = digitForKey(k);
      if (d == null) return KeyEventResult.ignored;
      _jumpDigit(d);
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final tuner = context.watch<TunerController>();
    final channels = _channels;
    final groups = app.groups;
    if (channels.isEmpty) return const SizedBox.shrink();
    if (_ch >= channels.length) _ch = channels.length - 1;
    final size = MediaQuery.sizeOf(context);
    final narrow = size.width < 900;
    final selected = channels[_ch];

    return Focus(
      focusNode: _focus,
      onKeyEvent: _onKey,
      child: Padding(
        padding: EdgeInsets.all(narrow ? 12 : 28),
        child: Glass(
          strong: true,
          radius: 34,
          child: NowBuilder(
            builder: (context, now) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(32, 26, 32, 18),
                  child: Row(
                    children: [
                      Text('Guida TV', style: AppText.display),
                      const SizedBox(width: 18),
                      Text(
                        dayLong(now),
                        style: AppText.body.copyWith(
                          color: Palette.textTertiary,
                        ),
                      ),
                      const Spacer(),
                      if (app.epgLoading)
                        Padding(
                          padding: const EdgeInsets.only(right: 18),
                          child: Text(
                            app.epgStatus ?? '',
                            style: AppText.label.copyWith(
                              color: Palette.textTertiary,
                            ),
                          ),
                        ),
                      Text(
                        hm(now),
                        style: AppText.clock.copyWith(fontSize: 26),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
                  child: GroupStrip(
                    groups: ['Tutti', ...groups],
                    selected: _group,
                    onSelect: _setGroup,
                  ),
                ),
                Container(
                  height: 1,
                  color: Colors.white.withValues(alpha: 0.08),
                ),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: narrow ? size.width * 0.42 : 430,
                        child: ListView.builder(
                          controller: _chScroll,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          itemExtent: _rowExtent,
                          itemCount: channels.length,
                          itemBuilder: (context, i) => Opacity(
                            opacity: _inProgrammes && i != _ch ? 0.55 : 1,
                            child: ChannelRow(
                              channel: channels[i],
                              now: now,
                              focused: i == _ch,
                              onAir: tuner.current?.id == channels[i].id,
                              onTap: () {
                                if (i == _ch) {
                                  _tuneSelected();
                                } else {
                                  _moveChannel(i - _ch);
                                }
                              },
                            ),
                          ),
                        ),
                      ),
                      Container(
                        width: 1,
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                      Expanded(
                        child: _Schedule(
                          channel: selected,
                          programmes: app.epg
                              .forChannel(selected.id)
                              .where(
                                (p) =>
                                    p.end > now.millisecondsSinceEpoch ~/ 1000,
                              )
                              .toList(),
                          now: now,
                          focusedIndex: _inProgrammes ? _prog : -1,
                          scroll: _progScroll,
                          keys: _progKeys,
                          onTapProgramme: (i) => setState(() {
                            _inProgrammes = true;
                            _prog = i;
                          }),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  height: 1,
                  color: Colors.white.withValues(alpha: 0.08),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(32, 14, 32, 18),
                  child: Wrap(
                    spacing: 22,
                    runSpacing: 8,
                    children: [
                      KeyHint('↑↓', 'Canale'),
                      KeyHint('→', 'Palinsesto'),
                      KeyHint('←', 'Categoria'),
                      KeyHint(
                        'OK',
                        _inProgrammes && _prog > 0 ? 'Promemoria' : 'Guarda',
                      ),
                      KeyHint('G', 'Chiudi'),
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

class _Schedule extends StatelessWidget {
  const _Schedule({
    required this.channel,
    required this.programmes,
    required this.now,
    required this.focusedIndex,
    required this.scroll,
    required this.keys,
    required this.onTapProgramme,
  });

  final Channel channel;
  final List<EpgProgramme> programmes;
  final DateTime now;
  final int focusedIndex;
  final ScrollController scroll;
  final Map<int, GlobalKey> keys;
  final ValueChanged<int> onTapProgramme;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 24, 32, 12),
          child: Row(
            children: [
              ChannelLogo(
                channel: channel,
                width: 96,
                height: 64,
                radius: 14,
                padding: 9,
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${channel.number}',
                      style: AppText.mono.copyWith(
                        color: Palette.textTertiary,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      channel.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.title.copyWith(fontSize: 24),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: programmes.isEmpty
              ? Center(
                  child: Text(
                    'Nessun programma in guida per questo canale',
                    style: AppText.body.copyWith(color: Palette.textTertiary),
                  ),
                )
              : ListView.builder(
                  controller: scroll,
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                  itemCount: programmes.length,
                  itemBuilder: (context, i) {
                    final p = programmes[i];
                    final prevDay = i == 0
                        ? null
                        : relativeDay(programmes[i - 1].startTime, now);
                    final day = relativeDay(p.startTime, now);
                    return Column(
                      key: keys.putIfAbsent(i, GlobalKey.new),
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (prevDay != null && prevDay != day)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(14, 18, 14, 8),
                            child: Text(
                              day.toUpperCase(),
                              style: AppText.overline,
                            ),
                          ),
                        _ProgrammeTile(
                          programme: p,
                          reminded: context.watch<ReminderController>().isSet(
                            channel.id,
                            p,
                          ),
                          now: now,
                          focused: i == focusedIndex,
                          // Senza focus esplicito si mostra il dettaglio del programma in onda.
                          expanded:
                              i == focusedIndex || (focusedIndex < 0 && i == 0),
                          onTap: () => onTapProgramme(i),
                        ),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _ProgrammeTile extends StatelessWidget {
  const _ProgrammeTile({
    required this.programme,
    required this.reminded,
    required this.now,
    required this.focused,
    required this.expanded,
    required this.onTap,
  });

  final EpgProgramme programme;
  final bool reminded;
  final DateTime now;
  final bool focused;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final perf = context.read<PerformanceProfile>();
    final p = programme;
    final live = p.isLiveAt(now.millisecondsSinceEpoch ~/ 1000);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      // Il bordo di focus va disegnato attorno al riquadro intero, non
      // attorno al contenuto (altrimenti compare un secondo contorno spostato).
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: CustomPaint(
          foregroundPainter: focused
              ? GlassEdgePainter(
                  radius: 16,
                  accent: Palette.accent.withValues(alpha: 0.75),
                )
              : null,
          child: AnimatedContainer(
            duration: perf.fast,
            padding: const EdgeInsets.fromLTRB(14, 14, 18, 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: focused
                  ? Colors.white.withValues(alpha: 0.14)
                  : live
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.transparent,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 74,
                  child: Text(
                    hm(p.startTime),
                    style: AppText.mono.copyWith(
                      fontSize: 15,
                      color: live ? Palette.accent : Palette.textSecondary,
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              p.title,
                              maxLines: expanded ? 2 : 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.headline.copyWith(fontSize: 16.5),
                            ),
                          ),
                          if (reminded) ...[
                            const SizedBox(width: 10),
                            const Icon(
                              Icons.notifications_active_rounded,
                              size: 16,
                              color: Palette.warm,
                            ),
                          ],
                          const SizedBox(width: 12),
                          Text(
                            durationLabel(p.duration),
                            style: AppText.mono.copyWith(
                              color: Palette.textTertiary,
                            ),
                          ),
                        ],
                      ),
                      if (live) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Text(
                              'IN ONDA',
                              style: AppText.overline.copyWith(
                                color: Palette.accent,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: EpgProgress(value: p.progressAt(now)),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              remaining(p.remainingAt(now)),
                              style: AppText.mono.copyWith(
                                color: Palette.textTertiary,
                              ),
                            ),
                          ],
                        ),
                      ],
                      AnimatedSize(
                        duration: perf.fast,
                        curve: Curves.easeOutCubic,
                        alignment: Alignment.topCenter,
                        child:
                            expanded &&
                                (p.description != null || p.category != null)
                            ? Padding(
                                padding: const EdgeInsets.only(top: 10),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (p.category != null)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 6,
                                        ),
                                        child: Text(
                                          p.category!.toUpperCase(),
                                          style: AppText.overline,
                                        ),
                                      ),
                                    if (p.description != null)
                                      Text(
                                        p.description!,
                                        maxLines: 4,
                                        overflow: TextOverflow.ellipsis,
                                        style: AppText.body,
                                      ),
                                  ],
                                ),
                              )
                            : const SizedBox(width: double.infinity),
                      ),
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
