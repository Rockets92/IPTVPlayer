import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/brand.dart';
import 'core/performance.dart';
import 'core/theme.dart';
import 'state/app_controller.dart';
import 'ui/player/player_screen.dart';
import 'ui/setup/setup_screen.dart';
import 'ui/widgets/ambient_background.dart';
import 'ui/widgets/glass.dart';
import 'ui/widgets/glass_field.dart';

class IptvApp extends StatelessWidget {
  const IptvApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: Brand.name,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const _Root(),
    );
  }
}

/// Instrada tra configurazione, caricamento e visione.
class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final phase = context.select<AppController, AppPhase>((a) => a.phase);
    final perf = context.read<PerformanceProfile>();
    return AnimatedSwitcher(
      duration: perf.slow,
      switchInCurve: Curves.easeOutCubic,
      child: switch (phase) {
        AppPhase.booting => const _Splash(key: ValueKey('boot')),
        AppPhase.setup => const SetupScreen(key: ValueKey('setup')),
        AppPhase.loading => const _Splash(
          key: ValueKey('loading'),
          showStatus: true,
        ),
        AppPhase.failed => const _Failure(key: ValueKey('failed')),
        AppPhase.ready => const PlayerScreen(key: ValueKey('player')),
      },
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash({super.key, this.showStatus = false});
  final bool showStatus;

  @override
  Widget build(BuildContext context) {
    final msg = context.select<AppController, String>((a) => a.loadingMessage);
    return Scaffold(
      body: AmbientBackground(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                Brand.name,
                style: AppText.display.copyWith(
                  fontSize: 40,
                  letterSpacing: -1.2,
                ),
              ),
              const SizedBox(height: 28),
              const SizedBox(
                width: 140,
                child: LinearProgressIndicator(
                  minHeight: 2,
                  color: Palette.accent,
                  backgroundColor: Color(0x22FFFFFF),
                ),
              ),
              const SizedBox(height: 18),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: showStatus ? 1 : 0,
                child: Text(
                  msg,
                  style: AppText.label.copyWith(color: Palette.textTertiary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Failure extends StatelessWidget {
  const _Failure({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    return Scaffold(
      body: AmbientBackground(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Glass(
                strong: true,
                radius: 28,
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Nessun segnale dal provider', style: AppText.title),
                    const SizedBox(height: 10),
                    Text(app.failure ?? '', style: AppText.body),
                    const SizedBox(height: 26),
                    GlassButton(
                      label: 'Riprova',
                      autofocus: true,
                      onPressed: app.retry,
                    ),
                    const SizedBox(height: 12),
                    GlassButton(
                      label: 'Modifica account',
                      primary: false,
                      onPressed: app.logout,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
