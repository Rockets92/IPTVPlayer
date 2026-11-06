import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/performance.dart';
import '../../core/theme.dart';
import '../../state/tuner_controller.dart';
import '../../state/vod_controller.dart';
import '../widgets/focus_tile.dart';

/// Le quattro sezioni dell'app.
enum HomeChoice { live, movies, series, games }

/// Schermata di scelta: TV in diretta, Film, Serie TV, Giochi.
class HomeHub extends StatefulWidget {
  const HomeHub({super.key, required this.onPick, required this.onClose});

  final ValueChanged<HomeChoice> onPick;
  final VoidCallback onClose;

  @override
  State<HomeHub> createState() => _HomeHubState();
}

class _HomeHubState extends State<HomeHub> {
  final _focus = FocusNode(debugLabel: 'home');
  int _sel = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _pick(int i) {
    final c = HomeChoice.values[i];
    final vodOk = context.read<VodController>().available;
    if ((c == HomeChoice.movies || c == HomeChoice.series) && !vodOk) return;
    widget.onPick(c);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowLeft) {
      setState(() => _sel = (_sel - 1).clamp(0, 3));
    } else if (k == LogicalKeyboardKey.arrowRight) {
      setState(() => _sel = (_sel + 1).clamp(0, 3));
    } else if (e is KeyRepeatEvent) {
      return KeyEventResult.handled;
    } else if (isSelectKey(k)) {
      _pick(_sel);
    } else if (isBackKey(k)) {
      widget.onClose();
    } else if (k == LogicalKeyboardKey.arrowUp ||
        k == LogicalKeyboardKey.arrowDown) {
      return KeyEventResult.handled;
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final vod = context.watch<VodController>();
    final tuner = context.watch<TunerController>();
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 900;
    final current = tuner.current;
    final vodOk = vod.available;
    String count(VodKind k, String one, String many) {
      final n = vod.catalog(k).items.length;
      if (!vodOk) return 'Solo con liste Xtream';
      if (n == 0) return 'Sfoglia il catalogo';
      return '$n ${n == 1 ? one : many}';
    }

    final cards = [
      (
        'TV in diretta',
        current == null
            ? 'Torna ai canali'
            : '${current.number}  ${current.name}',
        Icons.live_tv_rounded,
        const [Color(0xFF2B5BD7), Color(0xFF0E1E4D)],
        true,
      ),
      (
        'Film',
        count(VodKind.movies, 'film', 'film'),
        Icons.movie_outlined,
        const [Color(0xFFD2453F), Color(0xFF4A1020)],
        vodOk,
      ),
      (
        'Serie TV',
        count(VodKind.series, 'serie', 'serie'),
        Icons.video_library_outlined,
        const [Color(0xFF8A4BD6), Color(0xFF26114A)],
        vodOk,
      ),
      (
        'Giochi',
        'Da soli o in compagnia',
        Icons.sports_esports_rounded,
        const [Color(0xFF1FA36B), Color(0xFF0A3325)],
        true,
      ),
    ];

    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: ColoredBox(
        color: Palette.ink,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -1.2),
              radius: 1.5,
              colors: [Color(0xFF14213D), Palette.ink],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: EdgeInsets.all(compact ? 20 : 48),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Cosa guardiamo?',
                    textAlign: TextAlign.center,
                    style: AppText.display.copyWith(
                      fontSize: compact ? 28 : 38,
                    ),
                  ),
                  SizedBox(height: compact ? 22 : 40),
                  SizedBox(
                    height: compact ? 210 : 300,
                    child: Row(
                      children: [
                        for (var i = 0; i < cards.length; i++) ...[
                          if (i > 0) SizedBox(width: compact ? 12 : 22),
                          Expanded(
                            child: _Card(
                              title: cards[i].$1,
                              subtitle: cards[i].$2,
                              icon: cards[i].$3,
                              colors: cards[i].$4,
                              enabled: cards[i].$5,
                              focused: i == _sel,
                              onTap: () {
                                setState(() => _sel = i);
                                _pick(i);
                              },
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  SizedBox(height: compact ? 20 : 36),
                  const Center(
                    child: Wrap(
                      spacing: 22,
                      children: [
                        KeyHint('← →', 'Scegli'),
                        KeyHint('OK', 'Apri'),
                        KeyHint('Indietro', 'Torna alla TV'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.colors,
    required this.enabled,
    required this.focused,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> colors;
  final bool enabled;
  final bool focused;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final perf = context.read<PerformanceProfile>();
    final compact = MediaQuery.sizeOf(context).width < 900;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedScale(
        duration: perf.fast,
        curve: Curves.easeOutCubic,
        scale: focused ? 1.06 : 1,
        child: Opacity(
          opacity: enabled ? 1 : 0.45,
          child: Container(
            padding: EdgeInsets.all(compact ? 16 : 26),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(compact ? 20 : 28),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: colors,
              ),
              border: Border.all(
                width: focused ? 3 : 1,
                color: focused
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.12),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  icon,
                  size: compact ? 40 : 60,
                  color: Colors.white.withValues(alpha: 0.92),
                ),
                const Spacer(),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.display.copyWith(fontSize: compact ? 20 : 28),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.label.copyWith(
                    fontSize: compact ? 12 : 14,
                    color: Colors.white.withValues(alpha: 0.75),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
