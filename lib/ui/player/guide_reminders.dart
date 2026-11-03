import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../state/reminder_controller.dart';
import '../format.dart';

/// Voci del pannello di modifica di un promemoria, nell'ordine in cui si
/// scorrono con ↑↓.
enum ReminderEditRow { repeat, days, delete }

/// Righe del pannello di modifica per un promemoria: le quattro ripetizioni,
/// i giorni (solo se settimanale) ed "Elimina".
List<(ReminderEditRow, int)> reminderEditRows(Reminder r) => [
  for (var i = 0; i < ReminderRepeat.values.length; i++)
    (ReminderEditRow.repeat, i),
  if (r.repeat == ReminderRepeat.weekly) (ReminderEditRow.days, 0),
  (ReminderEditRow.delete, 0),
];

/// Sezione "I tuoi promemoria" della guida TV: elenco a sinistra, modifica
/// della ripetizione a destra.
class GuideReminders extends StatelessWidget {
  const GuideReminders({
    super.key,
    required this.items,
    required this.selected,
    required this.listFocused,
    required this.editRow,
    required this.dayCursor,
    required this.listWidth,
    required this.onTapItem,
    required this.onTapRepeat,
    required this.onTapDay,
    required this.onTapDelete,
  });

  final List<Reminder> items;
  final int selected;

  /// Il focus è sull'elenco (non sul pannello di modifica né sulle categorie).
  final bool listFocused;

  /// Riga evidenziata nel pannello di modifica (-1: nessuna).
  final int editRow;
  final int dayCursor;
  final double listWidth;
  final ValueChanged<int> onTapItem;
  final ValueChanged<ReminderRepeat> onTapRepeat;
  final ValueChanged<int> onTapDay;
  final VoidCallback onTapDelete;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.notifications_none_rounded,
                size: 40,
                color: Palette.textTertiary,
              ),
              const SizedBox(height: 14),
              Text('Nessun promemoria', style: AppText.title),
              const SizedBox(height: 8),
              Text(
                'Premi OK su un programma futuro, qui nella guida o nel '
                'banner dei canali, per farti avvisare 5 minuti prima.',
                textAlign: TextAlign.center,
                style: AppText.body.copyWith(color: Palette.textTertiary),
              ),
            ],
          ),
        ),
      );
    }
    final sel = items[selected.clamp(0, items.length - 1)];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: listWidth,
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 12),
            itemCount: items.length,
            itemBuilder: (context, i) => _ReminderRow(
              reminder: items[i],
              focused: i == selected && listFocused,
              selected: i == selected,
              onTap: () => onTapItem(i),
            ),
          ),
        ),
        Container(width: 1, color: Colors.white.withValues(alpha: 0.08)),
        Expanded(
          child: _Editor(
            reminder: sel,
            row: editRow,
            dayCursor: dayCursor,
            onTapRepeat: onTapRepeat,
            onTapDay: onTapDay,
            onTapDelete: onTapDelete,
          ),
        ),
      ],
    );
  }
}

String _when(DateTime t, DateTime now) {
  final d = relativeDay(t, now);
  return '${d[0].toUpperCase()}${d.substring(1)} · ${hm(t)}';
}

class _ReminderRow extends StatelessWidget {
  const _ReminderRow({
    required this.reminder,
    required this.focused,
    required this.selected,
    required this.onTap,
  });

  final Reminder reminder;
  final bool focused;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final r = reminder;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: focused
                ? Colors.white.withValues(alpha: 0.16)
                : selected
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.transparent,
            border: Border.all(
              width: focused ? 2 : 1,
              color: focused
                  ? Palette.accent.withValues(alpha: 0.75)
                  : Colors.transparent,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    _when(r.startTime, DateTime.now()),
                    style: AppText.mono.copyWith(color: Palette.accent),
                  ),
                  const Spacer(),
                  if (r.recurring)
                    const Icon(
                      Icons.repeat_rounded,
                      size: 16,
                      color: Palette.warm,
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                r.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.title.copyWith(fontSize: 17),
              ),
              const SizedBox(height: 2),
              Text(
                '${r.channelNumber} · ${r.channelName}'
                '${r.recurring ? ' · ${r.repeatLabel}' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.label.copyWith(color: Palette.textTertiary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final _focusKey = GlobalKey(debugLabel: 'reminder-edit-row');

class _Editor extends StatelessWidget {
  const _Editor({
    required this.reminder,
    required this.row,
    required this.dayCursor,
    required this.onTapRepeat,
    required this.onTapDay,
    required this.onTapDelete,
  });

  final Reminder reminder;
  final int row;
  final int dayCursor;
  final ValueChanged<ReminderRepeat> onTapRepeat;
  final ValueChanged<int> onTapDay;
  final VoidCallback onTapDelete;

  @override
  Widget build(BuildContext context) {
    final r = reminder;
    final rows = reminderEditRows(r);
    Widget option({
      required int index,
      required Widget child,
      required VoidCallback onTap,
      bool on = false,
    }) {
      final f = index == row;
      if (f) {
        // La riga evidenziata resta sempre visibile (schermi bassi).
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final ctx = _focusKey.currentContext;
          if (ctx != null && ctx.mounted) {
            Scrollable.ensureVisible(
              ctx,
              alignment: 0.5,
              duration: const Duration(milliseconds: 160),
            );
          }
        });
      }
      return GestureDetector(
        key: f ? _focusKey : null,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: f
                ? Colors.white.withValues(alpha: 0.16)
                : Colors.white.withValues(alpha: on ? 0.08 : 0.03),
            border: Border.all(
              width: f ? 2 : 1,
              color: f
                  ? Palette.accent.withValues(alpha: 0.75)
                  : Colors.white.withValues(alpha: 0.08),
            ),
          ),
          child: child,
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 22, 28, 22),
      children: [
        Text(
          'RIPETIZIONE',
          style: AppText.overline.copyWith(color: Palette.textTertiary),
        ),
        const SizedBox(height: 10),
        for (final (i, (kind, v)) in rows.indexed)
          switch (kind) {
            ReminderEditRow.repeat => option(
              index: i,
              on: r.repeat == ReminderRepeat.values[v],
              onTap: () => onTapRepeat(ReminderRepeat.values[v]),
              child: Row(
                children: [
                  Icon(
                    r.repeat == ReminderRepeat.values[v]
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_off_rounded,
                    size: 18,
                    color: r.repeat == ReminderRepeat.values[v]
                        ? Palette.accent
                        : Palette.textTertiary,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    ReminderRepeat.values[v].label,
                    style: AppText.body.copyWith(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            ReminderEditRow.days => option(
              index: i,
              onTap: () {},
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var d = 1; d <= 7; d++)
                    GestureDetector(
                      onTap: () => onTapDay(d),
                      child: _DayChip(
                        label: Reminder.weekdayShort[d - 1],
                        on: r.weekDays.contains(d),
                        cursor: i == row && dayCursor == d - 1,
                      ),
                    ),
                ],
              ),
            ),
            ReminderEditRow.delete => Padding(
              padding: const EdgeInsets.only(top: 10),
              child: option(
                index: i,
                onTap: onTapDelete,
                child: Row(
                  children: [
                    const Icon(
                      Icons.delete_outline_rounded,
                      size: 18,
                      color: Palette.danger,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Elimina promemoria',
                      style: AppText.body.copyWith(
                        fontWeight: FontWeight.w600,
                        color: Palette.danger,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          },
        const SizedBox(height: 8),
        Text(
          r.recurring
              ? 'Ti avviso 5 minuti prima, alle ${hm(r.startTime.subtract(ReminderController.lead))}, '
                    'su ${r.channelName} (${r.repeatLabel.toLowerCase()}).'
              : 'Ti avviso 5 minuti prima, una sola volta.',
          style: AppText.label.copyWith(color: Palette.textTertiary),
        ),
      ],
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({required this.label, required this.on, required this.cursor});
  final String label;
  final bool on;
  final bool cursor;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      width: 46,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(17),
        color: on
            ? Colors.white.withValues(alpha: 0.9)
            : Colors.white.withValues(alpha: 0.06),
        border: Border.all(
          width: cursor ? 2 : 1,
          color: cursor
              ? Palette.accent
              : Colors.white.withValues(alpha: on ? 0 : 0.12),
        ),
      ),
      child: Text(
        label,
        style: AppText.label.copyWith(
          fontWeight: FontWeight.w600,
          color: on ? Palette.ink : Palette.textSecondary,
        ),
      ),
    );
  }
}
