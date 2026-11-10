import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../state/tuner_controller.dart';
import '../widgets/glass.dart';

/// Indicatore del volume, come sul televisore: compare quando cambia.
class VolumeIndicator extends StatefulWidget {
  const VolumeIndicator({super.key});

  @override
  State<VolumeIndicator> createState() => _VolumeIndicatorState();
}

class _VolumeIndicatorState extends State<VolumeIndicator> {
  DateTime? _seen;
  bool _visible = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.watch<TunerController>();
    final at = t.volumeChangedAt;
    if (at != null && at != _seen) {
      _seen = at;
      _visible = true;
      _timer?.cancel();
      _timer = Timer(const Duration(milliseconds: 1800), () {
        if (mounted) setState(() => _visible = false);
      });
    }
    final level = t.muted ? 0 : t.volume;
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: _visible ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        child: Glass(
          strong: true,
          radius: 22,
          padding: const EdgeInsets.fromLTRB(18, 14, 20, 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                t.muted || level == 0
                    ? Icons.volume_off_rounded
                    : level < 50
                    ? Icons.volume_down_rounded
                    : Icons.volume_up_rounded,
                size: 22,
                color: t.muted ? Palette.warm : Palette.textPrimary,
              ),
              const SizedBox(width: 14),
              SizedBox(
                width: 180,
                height: 6,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: Stack(
                    children: [
                      Container(color: Colors.white.withValues(alpha: 0.14)),
                      FractionallySizedBox(
                        widthFactor: level / 100,
                        child: Container(
                          decoration: const BoxDecoration(
                            gradient: Palette.progress,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 14),
              SizedBox(
                width: 34,
                child: Text(
                  t.muted ? 'MUTO' : '$level',
                  textAlign: TextAlign.right,
                  style: AppText.mono.copyWith(
                    color: t.muted ? Palette.warm : Palette.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
