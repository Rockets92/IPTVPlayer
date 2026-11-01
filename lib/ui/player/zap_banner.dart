import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../data/epg/epg_models.dart';
import '../../domain/channel.dart';
import '../../player/playback_engine.dart';
import '../../state/app_controller.dart';
import '../../state/tuner_controller.dart';
import '../format.dart';
import '../widgets/channel_logo.dart';
import '../widgets/epg_progress.dart';
import '../widgets/glass.dart';
import '../widgets/now.dart';

/// Banner informativo in basso, mostrato a ogni cambio canale.
class ZapBanner extends StatelessWidget {
  const ZapBanner({super.key, required this.onAction});

  final void Function(BannerAction action) onAction;

  @override
  Widget build(BuildContext context) {
    final tuner = context.watch<TunerController>();
    final app = context.watch<AppController>();
    final channel = tuner.displayed;
    if (channel == null) return const SizedBox.shrink();
    final compact = MediaQuery.sizeOf(context).width < 760;

    return NowBuilder(
      everySecond: false,
      builder: (context, now) {
        final current = app.epg.nowOn(channel.id, now);
        final next = app.epg.nextOn(channel.id, now);
        return Glass(
          radius: compact ? 22 : 30,
          padding: EdgeInsets.fromLTRB(
            compact ? 18 : 30,
            compact ? 16 : 26,
            compact ? 18 : 30,
            compact ? 16 : 24,
          ),
          child: compact
              ? _Compact(
                  channel: channel,
                  now: now,
                  current: current,
                  next: next,
                )
              : _Wide(
                  channel: channel,
                  now: now,
                  current: current,
                  next: next,
                  onAction: onAction,
                ),
        );
      },
    );
  }
}

enum BannerAction { list, guide, settings, sources }

class _Wide extends StatelessWidget {
  const _Wide({
    required this.channel,
    required this.now,
    required this.current,
    required this.next,
    required this.onAction,
  });

  final Channel channel;
  final DateTime now;
  final EpgProgramme? current;
  final EpgProgramme? next;
  final void Function(BannerAction) onAction;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Numero canale: l'elemento più "decoder" di tutti.
          SizedBox(
            width: 150,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${channel.number}',
                    style: AppText.channelNumber,
                  ),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Text(
                    channel.group.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.overline.copyWith(letterSpacing: 1.2),
                  ),
                ),
              ],
            ),
          ),
          const _VDivider(),
          Center(
            child: ChannelLogo(
              channel: channel,
              width: 128,
              height: 84,
              radius: 18,
              padding: 12,
            ),
          ),
          const SizedBox(width: 28),
          Expanded(
            child: _Programmes(
              channel: channel,
              now: now,
              current: current,
              next: next,
            ),
          ),
          const SizedBox(width: 28),
          _ClockColumn(now: now, onAction: onAction),
        ],
      ),
    );
  }
}

class _Compact extends StatelessWidget {
  const _Compact({
    required this.channel,
    required this.now,
    required this.current,
    required this.next,
  });

  final Channel channel;
  final DateTime now;
  final EpgProgramme? current;
  final EpgProgramme? next;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              '${channel.number}',
              style: AppText.channelNumber.copyWith(
                fontSize: 40,
                letterSpacing: -1,
              ),
            ),
            const SizedBox(width: 16),
            ChannelLogo(channel: channel, width: 72, height: 48),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                channel.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.title,
              ),
            ),
            Text(hm(now), style: AppText.clock.copyWith(fontSize: 20)),
          ],
        ),
        const SizedBox(height: 14),
        _NowNext(now: now, current: current, next: next, compact: true),
      ],
    );
  }
}

class _Programmes extends StatelessWidget {
  const _Programmes({
    required this.channel,
    required this.now,
    required this.current,
    required this.next,
  });

  final Channel channel;
  final DateTime now;
  final EpgProgramme? current;
  final EpgProgramme? next;

  @override
  Widget build(BuildContext context) {
    final tuner = context.watch<TunerController>();
    final isLive = tuner.current?.id == channel.id;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                channel.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.title.copyWith(fontSize: 25),
              ),
            ),
            const SizedBox(width: 14),
            if (isLive) const _SignalBadges(),
          ],
        ),
        const SizedBox(height: 16),
        _NowNext(now: now, current: current, next: next),
      ],
    );
  }
}

class _NowNext extends StatelessWidget {
  const _NowNext({
    required this.now,
    required this.current,
    required this.next,
    this.compact = false,
  });

  final DateTime now;
  final EpgProgramme? current;
  final EpgProgramme? next;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cur = current;
    final nxt = next;
    final epgLoading = context.select<AppController, bool>((a) => a.epgLoading);
    if (cur == null && nxt == null) {
      return Text(
        epgLoading
            ? 'Caricamento guida…'
            : 'Informazioni di guida non disponibili',
        style: AppText.body.copyWith(color: Palette.textTertiary),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (cur != null) ...[
          Row(
            children: [
              Text(
                'ORA',
                style: AppText.overline.copyWith(color: Palette.accent),
              ),
              const SizedBox(width: 10),
              Text(
                timeRange(cur.startTime, cur.endTime),
                style: AppText.mono.copyWith(color: Palette.textTertiary),
              ),
              const Spacer(),
              Text(
                remaining(cur.remainingAt(now)),
                style: AppText.mono.copyWith(color: Palette.textTertiary),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            cur.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.headline.copyWith(fontSize: compact ? 16 : 19),
          ),
          const SizedBox(height: 11),
          EpgProgress(value: cur.progressAt(now)),
        ],
        if (nxt != null) ...[
          SizedBox(height: cur == null ? 0 : 14),
          Row(
            children: [
              Text('DOPO', style: AppText.overline),
              const SizedBox(width: 10),
              Text(
                hm(nxt.startTime),
                style: AppText.mono.copyWith(color: Palette.textTertiary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  nxt.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.body.copyWith(color: Palette.textSecondary),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Badge tecnici del segnale reale (risoluzione rilevata dal decoder video).
class _SignalBadges extends StatelessWidget {
  const _SignalBadges();

  @override
  Widget build(BuildContext context) {
    final engine = context.read<PlaybackEngine>();
    return ValueListenableBuilder<PlaybackSnapshot>(
      valueListenable: engine.state,
      builder: (context, s, _) {
        final res = s.resolutionBadge;
        final muted = context.select<TunerController, bool>((t) => t.muted);
        final (src, total) = context.select<TunerController, (int, int)>(
          (t) => (t.sourceIndex, t.current?.sources.length ?? 0),
        );
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (res != null) _Badge(res),
            if (total > 1) ...[
              if (res != null) const SizedBox(width: 6),
              _Badge('FONTE ${src + 1}/$total'),
            ],
            if (muted) ...[
              const SizedBox(width: 6),
              const _Badge('MUTO', icon: Icons.volume_off_rounded),
            ],
          ],
        );
      },
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text, {this.icon});
  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: Palette.textSecondary),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: AppText.overline.copyWith(
              fontSize: 10,
              letterSpacing: 0.8,
              color: Palette.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ClockColumn extends StatelessWidget {
  const _ClockColumn({required this.now, required this.onAction});
  final DateTime now;
  final void Function(BannerAction) onAction;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(hm(now), style: AppText.clock),
            const SizedBox(height: 6),
            Text(
              dayLong(now),
              style: AppText.label.copyWith(color: Palette.textTertiary),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _RoundAction(
              icon: Icons.format_list_bulleted_rounded,
              tooltip: 'Canali (OK)',
              onTap: () => onAction(BannerAction.list),
            ),
            const SizedBox(width: 8),
            _RoundAction(
              icon: Icons.calendar_view_day_rounded,
              tooltip: 'Guida (G)',
              onTap: () => onAction(BannerAction.guide),
            ),
            if ((context.select<TunerController, int>(
                  (t) => t.current?.sources.length ?? 0,
                )) >
                1) ...[
              const SizedBox(width: 8),
              _RoundAction(
                icon: Icons.swap_horiz_rounded,
                tooltip: 'Fonte (S)',
                onTap: () => onAction(BannerAction.sources),
              ),
            ],
            const SizedBox(width: 8),
            _RoundAction(
              icon: Icons.tune_rounded,
              tooltip: 'Impostazioni (M)',
              onTap: () => onAction(BannerAction.settings),
            ),
          ],
        ),
      ],
    );
  }
}

/// Azioni rapide per mouse e tocco (con telecomando si usano i tasti).
class _RoundAction extends StatefulWidget {
  const _RoundAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  State<_RoundAction> createState() => _RoundActionState();
}

class _RoundActionState extends State<_RoundAction> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: _hover ? 0.18 : 0.08),
              border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
            ),
            child: Icon(widget.icon, size: 18, color: Palette.textPrimary),
          ),
        ),
      ),
    );
  }
}

class _VDivider extends StatelessWidget {
  const _VDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      margin: const EdgeInsets.only(right: 28, top: 4, bottom: 4),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00FFFFFF), Color(0x33FFFFFF), Color(0x00FFFFFF)],
        ),
      ),
    );
  }
}
