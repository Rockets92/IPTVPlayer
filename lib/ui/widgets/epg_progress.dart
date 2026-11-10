import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Barra di avanzamento sottile con estremità luminosa.
class EpgProgress extends StatelessWidget {
  const EpgProgress({
    super.key,
    required this.value,
    this.height = 3,
    this.track = const Color(0x24FFFFFF),
  });

  final double value;
  final double height;
  final Color track;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth * value.clamp(0.0, 1.0);
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: track,
                    borderRadius: BorderRadius.circular(height),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: w,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: Palette.progress,
                    borderRadius: BorderRadius.circular(height),
                    boxShadow: [
                      BoxShadow(
                        color: Palette.accent.withValues(alpha: 0.45),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
