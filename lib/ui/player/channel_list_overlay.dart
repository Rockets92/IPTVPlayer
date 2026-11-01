import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/performance.dart';
import '../../core/theme.dart';
import '../../domain/channel.dart';
import '../../state/app_controller.dart';
import '../../state/tuner_controller.dart';
import '../keys.dart';
import '../widgets/focus_tile.dart';
import '../widgets/glass.dart';
import '../widgets/now.dart';
import 'channel_row.dart';

/// Elenco canali laterale (tasto OK), il video resta visibile a destra.
class ChannelListOverlay extends StatefulWidget {
  const ChannelListOverlay({super.key, required this.onClose});
  final VoidCallback onClose;

  @override
  State<ChannelListOverlay> createState() => _ChannelListOverlayState();
}

class _ChannelListOverlayState extends State<ChannelListOverlay> {
  final _scroll = ScrollController();
  final _focus = FocusNode();
  int _group = 0;
  int _sel = 0;
  String _jump = '';
  Timer? _jumpTimer;

  static const _rowExtent = ChannelRow.extent + 6;

  List<String> get _groups => context.read<AppController>().groups;

  List<Channel> get _items {
    final all = context.read<AppController>().channels;
    if (_group == 0) return all;
    final g = _groups[_group - 1];
    return all.where((c) => c.group == g).toList();
  }

  @override
  void initState() {
    super.initState();
    final current = context.read<TunerController>().current;
    final i = current == null ? 0 : _items.indexOf(current);
    _sel = i < 0 ? 0 : i;
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(animate: false));
  }

  @override
  void dispose() {
    _scroll.dispose();
    _focus.dispose();
    _jumpTimer?.cancel();
    super.dispose();
  }

  void _reveal({bool animate = true}) {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    final target = (_sel * _rowExtent - pos.viewportDimension / 2 + _rowExtent / 2)
        .clamp(0.0, pos.maxScrollExtent);
    final perf = context.read<PerformanceProfile>();
    if (!animate || perf.isLight || (target - pos.pixels).abs() > 2000) {
      _scroll.jumpTo(target);
    } else {
      _scroll.animateTo(target, duration: perf.fast, curve: Curves.easeOutCubic);
    }
  }

  void _move(int delta) {
    final n = _items.length;
    if (n == 0) return;
    setState(() => _sel = ((_sel + delta) % n + n) % n);
    _reveal();
  }

  void _setGroup(int g) {
    final count = _groups.length + 1;
    final current = context.read<TunerController>().current;
    setState(() {
      _group = (g % count + count) % count;
      final i = current == null ? -1 : _items.indexOf(current);
      _sel = i < 0 ? 0 : i;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(animate: false));
  }

  void _tune(Channel c) {
    context.read<TunerController>().tuneTo(c);
    widget.onClose();
  }

  void _jumpDigit(int d) {
    _jump += '$d';
    _jumpTimer?.cancel();
    _jumpTimer = Timer(const Duration(milliseconds: 1200), () => _jump = '');
    final n = int.parse(_jump);
    final items = _items;
    var i = items.indexWhere((c) => c.number >= n);
    if (i < 0) i = items.length - 1;
    setState(() => _sel = i);
    _reveal();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowUp) {
      _move(-1);
    } else if (k == LogicalKeyboardKey.arrowDown) {
      _move(1);
    } else if (k == LogicalKeyboardKey.pageUp || k == LogicalKeyboardKey.channelUp) {
      _move(-8);
    } else if (k == LogicalKeyboardKey.pageDown || k == LogicalKeyboardKey.channelDown) {
      _move(8);
    } else if (k == LogicalKeyboardKey.arrowLeft) {
      _setGroup(_group - 1);
    } else if (k == LogicalKeyboardKey.arrowRight) {
      _setGroup(_group + 1);
    } else if (isSelectKey(k)) {
      final items = _items;
      if (items.isNotEmpty) _tune(items[_sel]);
    } else if (isBackKey(k)) {
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
    final items = _items;
    if (_sel >= items.length) _sel = items.isEmpty ? 0 : items.length - 1;
    final width = MediaQuery.sizeOf(context).width;
    final panelW = width < 560 ? width - 24 : 460.0;
    final groups = app.groups;

    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.all(12) + const EdgeInsets.only(left: 12),
          child: SizedBox(
            width: panelW,
            child: Glass(
              strong: true,
              radius: 30,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(26, 26, 26, 14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text('Canali', style: AppText.display.copyWith(fontSize: 26)),
                        const Spacer(),
                        Text(
                          '${items.length}',
                          style: AppText.mono.copyWith(color: Palette.textTertiary),
                        ),
                      ],
                    ),
                  ),
                  _GroupStrip(
                    groups: ['Tutti', ...groups],
                    selected: _group,
                    onSelect: _setGroup,
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: ShaderMask(
                      shaderCallback: (r) => const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: [0, 0.03, 0.95, 1],
                        colors: [Colors.transparent, Colors.black, Colors.black, Colors.transparent],
                      ).createShader(r),
                      blendMode: BlendMode.dstIn,
                      child: NowBuilder(
                        builder: (context, now) => ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemExtent: _rowExtent,
                          itemCount: items.length,
                          itemBuilder: (context, i) {
                            final c = items[i];
                            return ChannelRow(
                              channel: c,
                              now: now,
                              focused: i == _sel,
                              onAir: tuner.current?.id == c.id,
                              onTap: () {
                                if (i == _sel) {
                                  _tune(c);
                                } else {
                                  setState(() => _sel = i);
                                }
                              },
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(26, 10, 26, 22),
                    child: Wrap(
                      spacing: 18,
                      runSpacing: 8,
                      children: [
                        KeyHint('↑↓', 'Scorri'),
                        KeyHint('←→', 'Categoria'),
                        KeyHint('OK', 'Guarda'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GroupStrip extends StatefulWidget {
  const _GroupStrip({
    required this.groups,
    required this.selected,
    required this.onSelect,
  });

  final List<String> groups;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  State<_GroupStrip> createState() => _GroupStripState();
}

class _GroupStripState extends State<_GroupStrip> {
  final _keys = <int, GlobalKey>{};

  @override
  void didUpdateWidget(_GroupStrip old) {
    super.didUpdateWidget(old);
    if (old.selected != widget.selected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _keys[widget.selected]?.currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(
            ctx,
            alignment: 0.5,
            duration: const Duration(milliseconds: 200),
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 22),
        itemCount: widget.groups.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final sel = i == widget.selected;
          return GestureDetector(
            key: _keys.putIfAbsent(i, GlobalKey.new),
            onTap: () => widget.onSelect(i),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  color: sel
                      ? Colors.white.withValues(alpha: 0.92)
                      : Colors.white.withValues(alpha: 0.07),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: sel ? 0 : 0.12),
                  ),
                ),
                child: Text(
                  widget.groups[i],
                  style: AppText.label.copyWith(
                    fontWeight: FontWeight.w600,
                    color: sel ? Palette.ink : Palette.textSecondary,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
