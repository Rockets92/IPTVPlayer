import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/brand.dart';
import 'core/heavy_work.dart';
import 'core/performance.dart';
import 'core/theme.dart';
import 'data/settings_store.dart';
import 'player/media_kit_engine.dart';
import 'player/playback_engine.dart';
import 'remote/game_pads.dart';
import 'remote/remote_server.dart';
import 'core/form_factor.dart';
import 'state/app_controller.dart';
import 'state/reminder_controller.dart';
import 'state/tuner_controller.dart';
import 'state/vod_controller.dart';
import 'sync/account_config.dart';
import 'sync/account_controller.dart';
import 'sync/sync_engine.dart';
import 'ui/widgets/focus_tile.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  installBackKeyGuard();
  MediaKit.ensureInitialized();
  Intl.defaultLocale = 'it_IT';
  await initializeDateFormatting('it_IT');

  final settings = await SettingsStore.open();
  final perf = await PerformanceProfile.resolve(settings.performanceMode);
  final formFactor = await FormFactor.resolve();

  // Profilo light: elenchi e cache grandi si caricano uno alla volta.
  HeavyWork.serialize = perf.isLight;

  // Cache immagini dimensionata sul dispositivo (loghi).
  PaintingBinding.instance.imageCache
    ..maximumSizeBytes = perf.imageCacheBytes
    ..maximumSize = perf.imageCacheCount;

  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        title: Brand.name,
        minimumSize: Size(960, 540),
        size: Size(1600, 900),
        center: true,
        backgroundColor: Palette.ink,
        titleBarStyle: TitleBarStyle.normal,
      ),
      () async {
        await windowManager.show();
        await windowManager.focus();
      },
    );
  }

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Palette.ink,
    ),
  );

  final engine = MediaKitEngine(perf);
  final app = AppController(settings: settings, perf: perf);
  final tuner = TunerController(app: app, engine: engine);
  final reminders = ReminderController(settings.prefs);
  final vod = VodController(app: app, prefs: settings.prefs);
  final remote = RemoteServer(
    prefs: settings.prefs,
    app: app,
    tuner: tuner,
    reminders: reminders,
    vod: vod,
  );
  final account = AccountController(
    client: await _initSupabase(),
    prefs: settings.prefs,
    formFactor: formFactor,
    engineFor: (backend) => SyncEngine(
      backend: backend,
      prefs: settings.prefs,
      reminders: reminders,
      settings: settings,
      vod: vod,
      onPrefsApplied: (keys) async {
        app.settingsChanged();
        if (keys.contains(SettingsStore.keyMapping)) {
          await app.applyMapping();
        } else if (keys.contains(SettingsStore.keyExtraEpg) ||
            keys.contains(SettingsStore.keyProviderEpg)) {
          await app.refreshEpg();
        }
      },
    ),
  );
  remote.account = account;
  app.start();
  unawaited(remote.start());
  unawaited(account.start());

  // Android chiude l'attività (uscita, memoria, standby): il video va fermato
  // prima che il motore Flutter si stacchi, o i fotogrammi in arrivo fanno
  // chiudere l'app con "FlutterJNI is not attached to native".
  if (!kIsWeb && Platform.isAndroid) {
    AppLifecycleListener(onDetach: () => unawaited(engine.dispose()));
  }

  runApp(
    MultiProvider(
      providers: [
        Provider<PerformanceProfile>.value(value: perf),
        Provider<FormFactor>.value(value: formFactor),
        Provider<PlaybackEngine>.value(value: engine),
        ChangeNotifierProvider<AppController>.value(value: app),
        ChangeNotifierProvider<TunerController>.value(value: tuner),
        ChangeNotifierProvider<ReminderController>.value(value: reminders),
        ChangeNotifierProvider<VodController>.value(value: vod),
        ChangeNotifierProvider<RemoteServer>.value(value: remote),
        ChangeNotifierProvider<AccountController>.value(value: account),
        ChangeNotifierProvider<GamePads>.value(value: remote.pads),
      ],
      child: const IptvApp(),
    ),
  );
}

/// Servizio dell'account: se non parte (es. niente rete al primo avvio)
/// l'app funziona comunque, solo senza sincronizzazione.
Future<SupabaseClient?> _initSupabase() async {
  if (!AccountConfig.enabled) return null;
  try {
    final s = await Supabase.initialize(
      url: AccountConfig.url,
      publishableKey: AccountConfig.publishableKey,
      authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
      debug: false,
    ).timeout(const Duration(seconds: 8));
    return s.client;
  } catch (e) {
    debugPrint('account: servizio non disponibile ($e)');
    return null;
  }
}
