import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../state/tuner_controller.dart';
import '../widgets/channel_logo.dart';
import '../widgets/glass.dart';

/// Inserimento diretto del numero canale, in alto a destra.
///
/// Senza [digits] mostra le cifre digitate col telecomando; il tastierino a
/// schermo passa invece le sue.
class NumberEntry extends StatelessWidget {
  const NumberEntry({super.key, this.digits});

  final String? digits;

  @override
  Widget build(BuildContext context) {
    final tuner = context.watch<TunerController>();
    final digits = this.digits ?? tuner.digits;
    final n = int.tryParse(digits);
    final i = n == null ? null : tuner.indexForNumber(n);
    final target = i == null ? null : tuner.channels[i];
    final exact = target != null && '${target.number}' == digits;
    return Glass(
      radius: 26,
      padding: const EdgeInsets.fromLTRB(26, 20, 26, 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 220),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < 4; i++)
                  Container(
                    width: 42,
                    alignment: Alignment.center,
                    child: Text(
                      i < digits.length ? digits[i] : '–',
                      style: AppText.channelNumber.copyWith(
                        fontSize: 58,
                        color: i < digits.length
                            ? Palette.textPrimary
                            : Palette.textTertiary.withValues(alpha: 0.25),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 30,
              child: target == null
                  ? Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        digits.isEmpty ? 'Digita il numero' : 'Nessun canale',
                        style: AppText.label.copyWith(
                          color: Palette.textTertiary,
                        ),
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ChannelLogo(
                          channel: target,
                          width: 44,
                          height: 30,
                          radius: 8,
                          padding: 4,
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 220),
                            child: Text(
                              exact
                                  ? target.name
                                  : '${target.number} · ${target.name}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.headline.copyWith(
                                fontSize: 15,
                                color: exact
                                    ? Palette.textPrimary
                                    : Palette.textSecondary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
