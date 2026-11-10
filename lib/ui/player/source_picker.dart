import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/performance.dart';
import '../../core/theme.dart';
import '../../domain/channel.dart';
import '../../player/playback_engine.dart';
import '../../state/tuner_controller.dart';
import '../keys.dart';
import '../widgets/focus_tile.dart';
import '../widgets/glass.dart';

/// Scelta della fonte del canale in visione (tasto S o verde).
///
/// Il canale resta uno solo: qui si sceglie quale stream del provider usare.
/// La scelta viene ricordata per quel canale.
class SourcePicker extends StatefulWidget {
  const SourcePicker({super.key, required this.onClose});
  final VoidCallback onClose;

  @override
  State<SourcePicker> createState() => _SourcePickerState();
}

class _SourcePickerState extends State<SourcePicker> {
  final _focus = FocusNode(debugLabel: 'sources');
  final _scroll = ScrollController();
  late int _sel = context.read<TunerController>().sourceIndex;

  static const _rowExtent = 64.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focus.requestFocus();
      _reveal(animate: false);
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  List<ChannelSource> get _sources =>
      context.read<TunerController>().activeSources;

  void _reveal({bool animate = true}) {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    final target =
        (_sel * _rowExtent - pos.viewportDimension / 2 + _rowExtent / 2).clamp(
          0.0,
          pos.maxScrollExtent,
        );
    final perf = context.read<PerformanceProfile>();
    if (!animate || perf.isLight) {
      _scroll.jumpTo(target);
    } else {
      _scroll.animateTo(
        target,
        duration: perf.fast,
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _move(int delta) {
    final n = _sources.length;
    if (n == 0) return;
    setState(() => _sel = ((_sel + delta) % n + n) % n);
    _reveal();
  }

  void _choose(int i) {
    context.read<TunerController>().selectSource(i);
    widget.onClose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowUp) {
      _move(-1);
    } else if (k == LogicalKeyboardKey.arrowDown) {
      _move(1);
    } else if (isSelectKey(k)) {
      if (_sources.isNotEmpty) _choose(_sel);
    } else if (isBackKey(k) ||
        k == LogicalKeyboardKey.keyS ||
        k == LogicalKeyboardKey.colorF1Green) {
      widget.onClose();
    } else if (digitForKey(k) case final d? when d >= 1) {
      if (d <= _sources.length) _choose(d - 1);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final tuner = context.watch<TunerController>();
    final channel = tuner.current;
    final sources = tuner.activeSources;
    final inUse = tuner.sourceIndex;
    final size = MediaQuery.sizeOf(context);
    final panelW = size.width < 600 ? size.width - 24 : 560.0;
    final listH = (sources.length * _rowExtent).clamp(
      _rowExtent,
      size.height * 0.55,
    );

    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onClose,
        child: Center(
          child: GestureDetector(
            onTap: () {},
            child: SizedBox(
              width: panelW,
              child: Glass(
                strong: true,
                radius: 30,
                padding: const EdgeInsets.fromLTRB(14, 22, 14, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'FONTE',
                            style: AppText.overline.copyWith(
                              color: Palette.accent,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            channel == null
                                ? 'Nessun canale'
                                : '${channel.number}  ${channel.name}${tuner.timeshift ? ' +1' : ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.title,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            sources.length == 1
                                ? 'Il provider offre una sola fonte per questo canale.'
                                : '${sources.length} fonti disponibili · la scelta resta per questo canale',
                            style: AppText.label.copyWith(
                              color: Palette.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: listH,
                      child: ListView.builder(
                        controller: _scroll,
                        itemExtent: _rowExtent,
                        itemCount: sources.length,
                        itemBuilder: (context, i) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: _SourceRow(
                            index: i,
                            source: sources[i],
                            focused: i == _sel,
                            inUse: i == inUse,
                            onTap: () => _choose(i),
                            onHover: () => setState(() => _sel = i),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Wrap(
                        spacing: 18,
                        runSpacing: 8,
                        children: [
                          KeyHint('↑↓', 'Scegli'),
                          KeyHint('1-9', 'Diretto'),
                          KeyHint('OK', 'Usa questa fonte'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({
    required this.index,
    required this.source,
    required this.focused,
    required this.inUse,
    required this.onTap,
    required this.onHover,
  });

  final int index;
  final ChannelSource source;
  final bool focused;
  final bool inUse;
  final VoidCallback onTap;
  final VoidCallback onHover;

  @override
  Widget build(BuildContext context) {
    final perf = context.read<PerformanceProfile>();
    final quality = source.quality;
    final engine = context.read<PlaybackEngine>();
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => onHover(),
      child: GestureDetector(
        onTap: onTap,
        child: CustomPaint(
          foregroundPainter: focused
              ? GlassEdgePainter(
                  radius: 18,
                  accent: Palette.accent.withValues(alpha: 0.85),
                )
              : null,
          child: AnimatedContainer(
            duration: perf.fast,
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: focused
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withValues(alpha: 0.20),
                        Colors.white.withValues(alpha: 0.08),
                      ],
                    )
                  : null,
              color: focused
                  ? null
                  : inUse
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.transparent,
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 26,
                  child: Text(
                    '${index + 1}',
                    style: AppText.mono.copyWith(
                      color: focused
                          ? Palette.textPrimary
                          : Palette.textTertiary,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    source.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.body.copyWith(
                      color: Palette.textPrimary,
                      fontWeight: inUse ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
                if (source.preferred) ...[
                  const SizedBox(width: 8),
                  const _Pill('PRINCIPALE', color: Palette.accent),
                ],
                if (quality != null) ...[
                  const SizedBox(width: 8),
                  _Pill(quality),
                ],
                const SizedBox(width: 10),
                SizedBox(
                  width: 22,
                  child: inUse
                      ? ValueListenableBuilder<PlaybackSnapshot>(
                          valueListenable: engine.state,
                          builder: (context, s, _) =>
                              s.status == PlaybackStatus.playing
                              ? const Icon(
                                  Icons.check_rounded,
                                  size: 18,
                                  color: Palette.accent,
                                )
                              : const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.6,
                                    color: Palette.textSecondary,
                                  ),
                                ),
                        )
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, {this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Palette.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.withValues(alpha: 0.4)),
      ),
      child: Text(
        text,
        style: AppText.overline.copyWith(
          fontSize: 10,
          letterSpacing: 0.8,
          color: c,
        ),
      ),
    );
  }
}
