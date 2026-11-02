import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../state/reminder_controller.dart';
import '../format.dart';
import '../widgets/focus_tile.dart';
import '../widgets/glass.dart';
import '../widgets/glass_field.dart';

/// Mostra l'avviso sopra a tutto, con il focus su "Vai al canale": col
/// telecomando basta OK. Restituisce true se si va al canale.
Future<bool> showReminderDialog(BuildContext context, Reminder reminder) async {
  final go = await showGeneralDialog<bool>(
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
  return go ?? false;
}

class _ReminderDialog extends StatefulWidget {
  const _ReminderDialog({required this.reminder});
  final Reminder reminder;

  @override
  State<_ReminderDialog> createState() => _ReminderDialogState();
}

class _ReminderDialogState extends State<_ReminderDialog> {
  bool _closed = false;

  void _close(bool go) {
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
        if (mounted) _close(false);
      });
    }
    return Center(
      child: Material(
        type: MaterialType.transparency,
        child: ReminderPopup(
          reminder: widget.reminder,
          autofocus: true,
          onGo: () => _close(true),
          onDismiss: () => _close(false),
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
    this.autofocus = false,
  });

  final bool autofocus;
  final Reminder reminder;
  final VoidCallback onGo;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final r = reminder;
    final now = DateTime.now();
    final mins = r.startTime.difference(now).inMinutes;
    final when = mins > 0
        ? 'tra $mins min · ${hm(r.startTime)}'
        : 'iniziato alle ${hm(r.startTime)}';
    final width = MediaQuery.sizeOf(context).width;
    return SizedBox(
      width: width < 520 ? width - 24 : 440,
      child: Glass(
        strong: true,
        radius: 26,
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 18),
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
              style: AppText.headline.copyWith(fontSize: 19),
            ),
            const SizedBox(height: 6),
            Text(
              'Hai prenotato questo programma su ${r.channelName}, '
              'canale ${r.channelNumber}.',
              style: AppText.body.copyWith(color: Palette.textSecondary),
            ),
            const SizedBox(height: 16),
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
            const SizedBox(height: 12),
            const Wrap(
              spacing: 16,
              children: [
                KeyHint('← →', 'Scegli'),
                KeyHint('OK', 'Conferma'),
                KeyHint('Indietro', 'Continua a guardare'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
