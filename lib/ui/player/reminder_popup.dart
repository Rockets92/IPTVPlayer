import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../state/reminder_controller.dart';
import '../format.dart';
import '../widgets/focus_tile.dart';
import '../widgets/glass.dart';
import '../widgets/glass_field.dart';

/// Avviso che compare 5 minuti prima di un programma prenotato.
class ReminderPopup extends StatelessWidget {
  const ReminderPopup({
    super.key,
    required this.reminder,
    required this.onGo,
    required this.onDismiss,
  });

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
                  child: GlassButton(label: 'Vai al canale', onPressed: onGo),
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
                KeyHint('OK', 'Vai al canale'),
                KeyHint('Indietro', 'Continua a guardare'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
