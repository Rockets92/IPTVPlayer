import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../data/epg/epg_models.dart';
import '../../domain/channel.dart';
import '../../player/playback_engine.dart';
import '../../state/app_controller.dart';
import '../../state/reminder_controller.dart';
import '../../state/tuner_controller.dart';
import '../format.dart';
import '../widgets/channel_logo.dart';
import '../widgets/epg_progress.dart';
import '../widgets/focus_tile.dart';
import '../widgets/glass.dart';
import '../widgets/now.dart';

/// Banner informativo in basso, mostrato a ogni cambio canale.
class ZapBanner extends StatelessWidget {
  const ZapBanner({super.key, required this.onAction, this.menuIndex});

  final void Function(BannerAction action) onAction;

  /// Azione evidenziata quando si naviga il menu con le frecce (telecomando).
  final int? menuIndex;

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
        // Sul +1 la guida è quella del canale spostata di un'ora.
        final shifted = tuner.timeshift && tuner.current?.id == channel.id;
        final at = shifted ? now.subtract(const Duration(hours: 1)) : now;
        EpgProgramme? later(EpgProgramme? p) => p == null || !shifted
            ? p
            : EpgProgramme(
                start: p.start + 3600,
                end: p.end + 3600,
                title: p.title,
                description: p.description,
                category: p.category,
              );
        var current = later(app.epg.nowOn(channel.id, at));
        var next = later(app.epg.nextOn(channel.id, at));
        // Info aperte con ←→: programma precedente o successivo.
        var shift = 0;
        if ((tuner.infoMode || tuner.browsing) && tuner.epgOffset != 0) {
          final list = app.epg.forChannel(channel.id);
          final base = app.epg.indexNear(channel.id, at);
          final i = base + tuner.epgOffset;
          if (base >= 0 && i >= 0 && i < list.length) {
            current = later(list[i]);
            next = i + 1 < list.length ? later(list[i + 1]) : null;
            shift = tuner.epgOffset;
          }
        }
        return Glass(
          radius: compact ? 22 : 30,
          padding: EdgeInsets.fromLTRB(
            compact ? 18 : 30,
            compact ? 16 : 26,
            compact ? 18 : 30,
            compact ? 16 : 24,
          ),
          child: compact
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Compact(
                      channel: channel,
                      now: now,
                      current: current,
                      next: next,
                      shift: shift,
                    ),
                    if (menuIndex != null) ...[
                      const SizedBox(height: 14),
                      Align(
                        alignment: Alignment.centerRight,
                        child: _ActionRow(
                          onAction: onAction,
                          menuIndex: menuIndex,
                        ),
                      ),
                    ],
                  ],
                )
              : _Wide(
                  channel: channel,
                  now: now,
                  current: current,
                  next: next,
                  shift: shift,
                  onAction: onAction,
                  menuIndex: menuIndex,
                ),
        );
      },
    );
  }
}

enum BannerAction {
  list,
  guide,
  keypad,
  favorite,
  home,
  settings,
  sources,
  plusOne,
}

/// Azioni mostrate nel banner, nell'ordine in cui le si percorre con ←→.
List<BannerAction> bannerActions(TunerController t) => [
  BannerAction.list,
  BannerAction.guide,
  BannerAction.keypad,
  if (t.current != null) BannerAction.favorite,
  BannerAction.home,
  if (t.canTogglePlusOne) BannerAction.plusOne,
  if (t.activeSources.length > 1) BannerAction.sources,
  BannerAction.settings,
];

class _Wide extends StatelessWidget {
  const _Wide({
    required this.channel,
    required this.now,
    required this.current,
    required this.next,
    required this.shift,
    required this.onAction,
    this.menuIndex,
  });

  final Channel channel;
  final DateTime now;
  final EpgProgramme? current;
  final EpgProgramme? next;
  final int shift;
  final void Function(BannerAction) onAction;
  final int? menuIndex;

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
              shift: shift,
            ),
          ),
          const SizedBox(width: 28),
          _ClockColumn(now: now, onAction: onAction, menuIndex: menuIndex),
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
    required this.shift,
  });

  final Channel channel;
  final DateTime now;
  final EpgProgramme? current;
  final EpgProgramme? next;
  final int shift;

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
        _NowNext(
          now: now,
          current: current,
          next: next,
          shift: shift,
          compact: true,
        ),
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
    required this.shift,
  });

  final Channel channel;
  final DateTime now;
  final EpgProgramme? current;
  final EpgProgramme? next;
  final int shift;

  @override
  Widget build(BuildContext context) {
    final tuner = context.watch<TunerController>();
    final isLive = tuner.current?.id == channel.id;
    final programme = tuner.infoProgramme;
    final reminded =
        programme != null &&
        context.watch<ReminderController>().isSet(channel.id, programme);
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
            if (isLive && tuner.timeshift) ...[
              const SizedBox(width: 10),
              const _Badge('+1', accent: true),
            ],
            const SizedBox(width: 14),
            if (isLive) const _SignalBadges(),
            if (tuner.browsingOther) const _Badge('ANTEPRIMA', accent: true),
            if (reminded) ...[
              const SizedBox(width: 10),
              const _Badge(
                'PRENOTATO',
                icon: Icons.notifications_active_rounded,
                accent: true,
              ),
            ],
          ],
        ),
        // I tasti utili su una riga a parte, sempre della stessa grandezza.
        if (tuner.browsing || tuner.infoMode) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              if (tuner.browsing) ...[
                const KeyHint('← →', 'Canali'),
                const KeyHint('↑ ↓', 'Programmi'),
              ] else
                const KeyHint('← →', 'Programmi'),
              if (programme != null)
                KeyHint('OK', reminded ? 'Annulla' : 'Promemoria')
              else if (tuner.browsingOther)
                const KeyHint('OK', 'Guarda'),
              if (tuner.infoMode && !tuner.browsing) const KeyHint('↓', 'Menu'),
            ],
          ),
        ],
        const SizedBox(height: 16),
        _NowNext(now: now, current: current, next: next, shift: shift),
      ],
    );
  }
}

class _NowNext extends StatelessWidget {
  const _NowNext({
    required this.now,
    required this.current,
    required this.next,
    this.shift = 0,
    this.compact = false,
  });

  final DateTime now;
  final EpgProgramme? current;
  final EpgProgramme? next;

  /// Diverso da 0 quando si sfoglia la guida: [current] non è in onda.
  final int shift;
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
                shift == 0
                    ? 'ORA'
                    : (cur.endTime.isBefore(now)
                          ? 'GIÀ ANDATO'
                          : (cur.startTime.isAfter(now) ? 'PIÙ TARDI' : 'ORA')),
                style: AppText.overline.copyWith(
                  color: shift > 0 ? Palette.warm : Palette.accent,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                shift == 0
                    ? timeRange(cur.startTime, cur.endTime)
                    : '${relativeDay(cur.startTime, now)}  '
                          '${timeRange(cur.startTime, cur.endTime)}',
                style: AppText.mono.copyWith(color: Palette.textTertiary),
              ),
              const Spacer(),
              Text(
                shift == 0
                    ? remaining(cur.remainingAt(now))
                    : durationLabel(cur.duration),
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
          if (shift == 0)
            EpgProgress(value: cur.progressAt(now))
          else
            Text(
              (cur.description ?? '').trim().isEmpty
                  ? (cur.category ?? '')
                  : cur.description!.trim(),
              maxLines: compact ? 1 : 2,
              overflow: TextOverflow.ellipsis,
              style: AppText.label.copyWith(color: Palette.textSecondary),
            ),
        ],
        if (nxt != null) ...[
          SizedBox(height: cur == null ? 0 : 14),
          Row(
            children: [
              Text(shift == 0 ? 'DOPO' : 'POI', style: AppText.overline),
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
          (t) => (t.sourceIndex, t.activeSources.length),
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
  const _Badge(this.text, {this.icon, this.accent = false});
  final String text;
  final IconData? icon;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final color = accent ? Palette.accent : Palette.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: accent
              ? Palette.accent.withValues(alpha: 0.5)
              : Colors.white.withValues(alpha: 0.28),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: AppText.overline.copyWith(
              fontSize: 10,
              letterSpacing: 0.8,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _ClockColumn extends StatelessWidget {
  const _ClockColumn({
    required this.now,
    required this.onAction,
    this.menuIndex,
  });
  final DateTime now;
  final void Function(BannerAction) onAction;
  final int? menuIndex;

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
        _ActionRow(onAction: onAction, menuIndex: menuIndex),
      ],
    );
  }
}

/// Pulsanti rapidi: si toccano col mouse o col dito, oppure col telecomando
/// (↓ dalle informazioni, ←→ per scegliere, OK per aprire).
class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.onAction, this.menuIndex});
  final void Function(BannerAction) onAction;
  final int? menuIndex;

  @override
  Widget build(BuildContext context) {
    final tuner = context.watch<TunerController>();
    final actions = bannerActions(tuner);
    final onPlusOne = tuner.timeshift || tuner.current?.baseChannelId != null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < actions.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          switch (actions[i]) {
            BannerAction.list => _RoundAction(
              icon: Icons.format_list_bulleted_rounded,
              tooltip: 'Canali',
              focused: menuIndex == i,
              onTap: () => onAction(BannerAction.list),
            ),
            BannerAction.guide => _RoundAction(
              icon: Icons.calendar_view_day_rounded,
              tooltip: 'Guida TV',
              focused: menuIndex == i,
              onTap: () => onAction(BannerAction.guide),
            ),
            BannerAction.keypad => _RoundAction(
              icon: Icons.dialpad_rounded,
              tooltip: 'Tastierino',
              focused: menuIndex == i,
              onTap: () => onAction(BannerAction.keypad),
            ),
            BannerAction.favorite => _RoundAction(
              icon:
                  context.select<AppController, bool>(
                    (a) => a.isFavorite(tuner.current?.id ?? ''),
                  )
                  ? Icons.star_rounded
                  : Icons.star_outline_rounded,
              tooltip: 'Preferito',
              focused: menuIndex == i,
              onTap: () => onAction(BannerAction.favorite),
            ),
            BannerAction.plusOne => _RoundAction(
              label: onPlusOne ? 'LIVE' : '+1',
              tooltip: 'Versione +1',
              focused: menuIndex == i,
              onTap: () => onAction(BannerAction.plusOne),
            ),
            BannerAction.sources => _RoundAction(
              icon: Icons.swap_horiz_rounded,
              tooltip: 'Fonte',
              focused: menuIndex == i,
              onTap: () => onAction(BannerAction.sources),
            ),
            BannerAction.home => _RoundAction(
              icon: Icons.grid_view_rounded,
              tooltip: 'TV, film, serie e giochi',
              focused: menuIndex == i,
              onTap: () => onAction(BannerAction.home),
            ),
            BannerAction.settings => _RoundAction(
              icon: Icons.tune_rounded,
              tooltip: 'Impostazioni',
              focused: menuIndex == i,
              onTap: () => onAction(BannerAction.settings),
            ),
          },
        ],
      ],
    );
  }
}

/// Azioni rapide per mouse e tocco (con telecomando si usano i tasti).
class _RoundAction extends StatefulWidget {
  const _RoundAction({
    this.icon,
    this.label,
    required this.tooltip,
    required this.onTap,
    this.focused = false,
  });
  final bool focused;
  final IconData? icon;
  final String? label;
  final String tooltip;
  final VoidCallback onTap;

  @override
  State<_RoundAction> createState() => _RoundActionState();
}

class _RoundActionState extends State<_RoundAction> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final f = widget.focused;
    final circle = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: f ? 44 : 38,
      height: f ? 44 : 38,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: f ? Palette.neon : null,
        color: f ? null : Colors.white.withValues(alpha: _hover ? 0.18 : 0.08),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        boxShadow: f
            ? [
                BoxShadow(
                  color: Palette.accent.withValues(alpha: 0.45),
                  blurRadius: 18,
                ),
              ]
            : null,
      ),
      alignment: Alignment.center,
      child: widget.icon != null
          ? Icon(widget.icon, size: f ? 20 : 18, color: Palette.textPrimary)
          : Text(
              widget.label ?? '',
              style: AppText.overline.copyWith(
                fontSize: (widget.label ?? '').length > 2 ? 9 : 12,
                letterSpacing: 0.2,
                color: Palette.textPrimary,
              ),
            ),
    );
    // Col telecomando il nome dell'azione scelta compare sotto il tasto.
    if (f) {
      return SizedBox(
        width: 44,
        height: 44,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            circle,
            Positioned(
              top: -26,
              child: Text(
                widget.tooltip,
                maxLines: 1,
                softWrap: false,
                style: AppText.label.copyWith(color: Palette.textPrimary),
              ),
            ),
          ],
        ),
      );
    }
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(onTap: widget.onTap, child: circle),
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
