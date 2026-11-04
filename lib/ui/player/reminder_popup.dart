import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../state/reminder_controller.dart';
import '../format.dart';
import '../widgets/focus_tile.dart';
import '../widgets/glass.dart';
import '../widgets/glass_field.dart';

/// Risposta all'avviso di un promemoria.
enum ReminderAnswer { go, snooze, dismiss }

/// Mostra l'avviso sopra a tutto, con il focus su "Vai al canale": col
/// telecomando basta OK.
Future<ReminderAnswer> showReminderDialog(
  BuildContext context,
  Reminder reminder,
) async {
  final go = await showGeneralDialog<ReminderAnswer>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Promemoria',
    barrierColor: Colors.black.withValues(alpha: 0.45),
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (context, _, _) => _ReminderDialog(reminder: reminder),
    transitionBuilder: (context, a, _, child) => FadeTransition(
      opacity: a,
      child: ScaleTransition(
        scale: Tween(
          begin: 0.97,
          end: 1.0,
        ).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
        child: child,
      ),
    ),
  );
  return go ?? ReminderAnswer.dismiss;
}

class _ReminderDialog extends StatefulWidget {
  const _ReminderDialog({required this.reminder});
  final Reminder reminder;

  @override
  State<_ReminderDialog> createState() => _ReminderDialogState();
}

class _ReminderDialogState extends State<_ReminderDialog> {
  bool _closed = false;

  void _close(ReminderAnswer go) {
    if (_closed) return;
    _closed = true;
    Navigator.of(context).pop(go);
  }

  @override
  Widget build(BuildContext context) {
    // Risolto altrove (dal telefono o scaduto): l'avviso si chiude da solo.
    final due = context.select<ReminderController, Reminder?>((r) => r.due);
    if (!identical(due, widget.reminder) && !_closed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _close(ReminderAnswer.dismiss);
      });
    }
    return Center(
      child: Material(
        type: MaterialType.transparency,
        child: ReminderPopup(
          reminder: widget.reminder,
          autofocus: true,
          onGo: () => _close(ReminderAnswer.go),
          onSnooze: () => _close(ReminderAnswer.snooze),
          onDismiss: () => _close(ReminderAnswer.dismiss),
        ),
      ),
    );
  }
}

/// Avviso che compare 5 minuti prima di un programma prenotato.
class ReminderPopup extends StatelessWidget {
  const ReminderPopup({
    super.key,
    required this.reminder,
    required this.onGo,
    required this.onDismiss,
    this.onSnooze,
    this.autofocus = false,
  });

  final bool autofocus;
  final Reminder reminder;
  final VoidCallback onGo;
  final VoidCallback onDismiss;

  /// "Avvisami 1 minuto prima dell'inizio".
  final VoidCallback? onSnooze;

  @override
  Widget build(BuildContext context) {
    final r = reminder;
    final now = DateTime.now();
    final secs = r.startTime.difference(now).inSeconds;
    final when = secs > 0
        ? 'tra ${(secs / 60).ceil()} min · ${hm(r.startTime)}'
        : 'iniziato alle ${hm(r.startTime)}';
    final canSnooze = onSnooze != null && ReminderController.canSnooze(r);
    final width = MediaQuery.sizeOf(context).width;
    final meta = AppText.body.copyWith(color: Palette.textSecondary);
    return SizedBox(
      width: width < 540 ? width - 24 : 480,
      child: Glass(
        strong: true,
        radius: 26,
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.notifications_active_rounded,
                  size: 16,
                  color: Palette.warm,
                ),
                const SizedBox(width: 8),
                Text(
                  'PROMEMORIA',
                  style: AppText.overline.copyWith(color: Palette.warm),
                ),
                const Spacer(),
                Text(
                  when,
                  style: AppText.mono.copyWith(color: Palette.textTertiary),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              r.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppText.headline.copyWith(fontSize: 21),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(
                  Icons.live_tv_rounded,
                  size: 16,
                  color: Palette.textTertiary,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    '${r.channelName} · canale ${r.channelNumber}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: meta,
                  ),
                ),
              ],
            ),
            if (r.recurring) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(
                    Icons.repeat_rounded,
                    size: 16,
                    color: Palette.textTertiary,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      r.repeatLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: meta,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: GlassButton(
                    label: 'Vai al canale',
                    autofocus: autofocus,
                    onPressed: onGo,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GlassButton(
                    label: 'Annulla',
                    primary: false,
                    onPressed: onDismiss,
                  ),
                ),
              ],
            ),
            if (canSnooze) ...[
              const SizedBox(height: 10),
              GlassButton(
                label: 'Avvisami 1 minuto prima dell\'inizio',
                icon: Icons.alarm_rounded,
                primary: false,
                onPressed: onSnooze,
              ),
            ],
            const SizedBox(height: 14),
            Container(height: 1, color: Colors.white.withValues(alpha: 0.08)),
            const SizedBox(height: 12),
            const Center(
              child: Wrap(
                spacing: 22,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  KeyHint('← → ↓', 'Scegli'),
                  KeyHint('OK', 'Conferma'),
                  KeyHint('Indietro', 'Chiudi'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
