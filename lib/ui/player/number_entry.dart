import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../state/tuner_controller.dart';
import '../widgets/channel_logo.dart';
import '../widgets/glass.dart';

/// Inserimento diretto del numero canale, in alto a destra.
class NumberEntry extends StatelessWidget {
  const NumberEntry({super.key});

  @override
  Widget build(BuildContext context) {
    final tuner = context.watch<TunerController>();
    final digits = tuner.digits;
    final target = tuner.digitsTarget;
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
                        'Nessun canale',
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
                        ConstrainedBox(
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
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
