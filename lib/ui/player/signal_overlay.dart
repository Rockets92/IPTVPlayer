import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../player/playback_engine.dart';
import '../../state/tuner_controller.dart';
import '../widgets/glass.dart';

/// Stato del segnale al centro dello schermo: anello sottile durante la
/// sintonizzazione, scheda di vetro quando il canale non risponde.
class SignalOverlay extends StatelessWidget {
  const SignalOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final tuner = context.watch<TunerController>();
    final engine = context.read<PlaybackEngine>();
    return ValueListenableBuilder<PlaybackSnapshot>(
      valueListenable: engine.state,
      builder: (context, s, _) {
        final msg = tuner.signalMessage;
        final Widget child;
        if (msg != null) {
          final dead = msg == 'Canale non disponibile';
          child = Glass(
            key: ValueKey(msg),
            radius: 24,
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 22),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (dead)
                  const Icon(Icons.signal_cellular_connected_no_internet_0_bar_rounded,
                      color: Palette.textSecondary, size: 26)
                else
                  const _Ring(size: 24),
                const SizedBox(width: 18),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(msg, style: AppText.headline),
                    const SizedBox(height: 4),
                    Text(
                      dead
                          ? 'Premi OK per riprovare o cambia canale'
                          : 'Proviamo una sorgente alternativa',
                      style: AppText.label.copyWith(color: Palette.textTertiary),
                    ),
                  ],
                ),
              ],
            ),
          );
        } else if (s.status == PlaybackStatus.connecting ||
            (s.status == PlaybackStatus.playing && s.buffering)) {
          child = const _DelayedRing(key: ValueKey('ring'));
        } else {
          child = const SizedBox.shrink(key: ValueKey('none'));
        }
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: child,
        );
      },
    );
  }
}

/// L'anello compare solo se l'attesa supera mezzo secondo: niente sfarfallii
/// durante lo zapping veloce.
class _DelayedRing extends StatefulWidget {
  const _DelayedRing({super.key});

  @override
  State<_DelayedRing> createState() => _DelayedRingState();
}

class _DelayedRingState extends State<_DelayedRing> {
  bool _show = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 550), () {
      if (mounted) setState(() => _show = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _show ? 1 : 0,
      duration: const Duration(milliseconds: 260),
      child: const _Ring(size: 46),
    );
  }
}

class _Ring extends StatelessWidget {
  const _Ring({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        strokeWidth: size > 30 ? 2.2 : 2,
        strokeCap: StrokeCap.round,
        color: Colors.white.withValues(alpha: 0.85),
        backgroundColor: Colors.white.withValues(alpha: 0.08),
      ),
    );
  }
}
