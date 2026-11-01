import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/performance.dart';
import '../../core/theme.dart';
import '../../data/epg/epg_models.dart';
import '../../domain/channel.dart';
import '../../state/app_controller.dart';
import '../widgets/channel_logo.dart';
import '../widgets/epg_progress.dart';
import '../widgets/glass.dart';

/// Riga canale per lista e guida. Lo stato di focus è gestito dal
/// contenitore (indice selezionato), così la lista resta leggera anche con
/// migliaia di canali.
class ChannelRow extends StatefulWidget {
  const ChannelRow({
    super.key,
    required this.channel,
    required this.now,
    required this.focused,
    required this.onAir,
    required this.onTap,
    this.showProgramme = true,
  });

  static const double extent = 78;

  final Channel channel;
  final DateTime now;
  final bool focused;
  final bool onAir;
  final VoidCallback onTap;
  final bool showProgramme;

  @override
  State<ChannelRow> createState() => _ChannelRowState();
}

class _ChannelRowState extends State<ChannelRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final perf = context.read<PerformanceProfile>();
    final epg = context.select<AppController, EpgSchedule>((a) => a.epg);
    final c = widget.channel;
    final prog = widget.showProgramme ? epg.nowOn(c.id, widget.now) : null;
    final f = widget.focused;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          child: CustomPaint(
            foregroundPainter: f
                ? GlassEdgePainter(
                    radius: 16,
                    accent: Palette.accent.withValues(alpha: 0.75),
                  )
                : null,
            child: AnimatedContainer(
              duration: perf.fast,
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: f
                    ? LinearGradient(
                        colors: [
                          Colors.white.withValues(alpha: 0.20),
                          Colors.white.withValues(alpha: 0.07),
                        ],
                      )
                    : null,
                color: f
                    ? null
                    : Colors.white.withValues(alpha: _hover ? 0.06 : 0),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 50,
                    child: Text(
                      '${c.number}',
                      style: AppText.mono.copyWith(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: f ? Palette.textPrimary : Palette.textSecondary,
                      ),
                    ),
                  ),
                  ChannelLogo(
                    channel: c,
                    width: 58,
                    height: 40,
                    radius: 10,
                    padding: 5,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                c.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.headline.copyWith(
                                  fontSize: 15.5,
                                  color: f
                                      ? Palette.textPrimary
                                      : const Color(0xE6FFFFFF),
                                ),
                              ),
                            ),
                            if (widget.onAir) ...[
                              const SizedBox(width: 8),
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Palette.accent,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Palette.accent.withValues(
                                        alpha: 0.8,
                                      ),
                                      blurRadius: 8,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (prog != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            prog.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.label.copyWith(
                              color: f
                                  ? Palette.textSecondary
                                  : Palette.textTertiary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          SizedBox(
                            width: 120,
                            child: EpgProgress(
                              value: prog.progressAt(widget.now),
                              height: 2,
                            ),
                          ),
                        ],
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
