import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:iptv_player/core/performance.dart';
import 'package:iptv_player/data/settings_store.dart';
import 'package:iptv_player/domain/channel.dart';
import 'package:iptv_player/player/playback_engine.dart';
import 'package:iptv_player/state/app_controller.dart';
import 'package:iptv_player/state/tuner_controller.dart';
import 'package:iptv_player/state/reminder_controller.dart';
import 'package:iptv_player/state/vod_controller.dart';
import 'package:iptv_player/ui/player/channel_keypad.dart';
import 'package:iptv_player/ui/player/player_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Engine implements PlaybackEngine {
  @override
  final state = ValueNotifier(const PlaybackSnapshot());
  @override
  final vod = ValueNotifier(const VodState());
  @override
  Future<void> open(String url) async {}
  @override
  Future<void> openVod(String url, {Duration? start}) async {}
  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> playOrPause() async {}
  @override
  Future<void> setAudioTrack(String id) async {}
  @override
  Future<void> setSubtitleTrack(String id) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> setMuted(bool muted) async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Widget buildView(BuildContext context) =>
      const ColoredBox(color: Colors.black);
  @override
  Future<void> dispose() async {}
}

/// Lista finta: nessun provider, gli indirizzi bastano per sintonizzare.
class _App extends AppController {
  _App(SettingsStore s, PerformanceProfile p) : super(settings: s, perf: p);

  @override
  String streamUrl(ChannelSource s) => 'http://test/${s.streamId}';
}

Channel _ch(int n, String name) => Channel(
  id: 'm$n',
  number: n,
  name: name,
  group: 'TV',
  sources: [ChannelSource(streamId: n, label: name)],
);

void main() {
  setUpAll(() async {
    await initializeDateFormatting('it_IT');
    Intl.defaultLocale = 'it_IT';
  });
  late TunerController tuner;
  var closed = 0;

  Future<void> pump(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    const perf = PerformanceProfile(PerformanceTier.full);
    final app = _App(SettingsStore(prefs), perf)
      ..channels = [
        _ch(1, 'Rai 1'),
        _ch(108, 'Sky Uno'),
        _ch(128, 'Rai Storia'),
      ];
    tuner = TunerController(app: app, engine: _Engine());
    closed = 0;
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<PerformanceProfile>.value(value: perf),
          ChangeNotifierProvider<TunerController>.value(value: tuner),
        ],
        child: MaterialApp(
          home: Scaffold(
            backgroundColor: Colors.black,
            body: ChannelKeypad(onClose: () => closed++),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> key(WidgetTester tester, LogicalKeyboardKey k) async {
    await tester.sendKeyEvent(k);
    await tester.pump();
  }

  testWidgets('col D-pad si compone il numero e ✓ sintonizza', (tester) async {
    await pump(tester);
    expect(find.text('Digita il numero'), findsOneWidget);
    // Si parte dal 5 e si compone 128 con frecce e OK.
    await key(tester, LogicalKeyboardKey.arrowUp); // 2
    await key(tester, LogicalKeyboardKey.arrowLeft); // 1
    await key(tester, LogicalKeyboardKey.select);
    await key(tester, LogicalKeyboardKey.arrowRight); // 2
    await key(tester, LogicalKeyboardKey.select);
    await key(tester, LogicalKeyboardKey.arrowDown); // 5
    await key(tester, LogicalKeyboardKey.arrowDown); // 8
    await key(tester, LogicalKeyboardKey.select);
    expect(find.text('Rai Storia'), findsOneWidget);
    await key(tester, LogicalKeyboardKey.arrowDown); // 0
    await key(tester, LogicalKeyboardKey.arrowRight); // ✓
    await key(tester, LogicalKeyboardKey.select);
    expect(tuner.current?.number, 128);
    expect(closed, 1);
    tuner.dispose();
    await tester.pump(const Duration(seconds: 30));
  });

  testWidgets('cifre del telecomando, ⌫ e Indietro', (tester) async {
    await pump(tester);
    await key(tester, LogicalKeyboardKey.digit1);
    await key(tester, LogicalKeyboardKey.digit0);
    // 10 non esiste: si propone il successivo, 108.
    expect(find.text('108 · Sky Uno'), findsOneWidget);
    await key(tester, LogicalKeyboardKey.backspace);
    expect(find.text('Rai 1'), findsOneWidget);
    // Le cifre non scadono come quelle del telecomando.
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('Rai 1'), findsOneWidget);
    expect(closed, 0);
    await key(tester, LogicalKeyboardKey.escape);
    expect(closed, 1);
    expect(tuner.current, isNull);
    tuner.dispose();
  });

  group('OK tenuto premuto sul player', () {
    late ReminderController reminders;

    Future<void> pumpPlayer(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      const perf = PerformanceProfile(PerformanceTier.full);
      final engine = _Engine();
      final app = _App(SettingsStore(prefs), perf)
        ..channels = [_ch(1, 'Rai 1'), _ch(128, 'Rai Storia')];
      tuner = TunerController(app: app, engine: engine);
      reminders = ReminderController(prefs);
      final vod = VodController(app: app, prefs: prefs);
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<PerformanceProfile>.value(value: perf),
            Provider<PlaybackEngine>.value(value: engine),
            ChangeNotifierProvider<AppController>.value(value: app),
            ChangeNotifierProvider<TunerController>.value(value: tuner),
            ChangeNotifierProvider<ReminderController>.value(value: reminders),
            ChangeNotifierProvider<VodController>.value(value: vod),
          ],
          child: const MaterialApp(home: PlayerScreen()),
        ),
      );
      await tester.pump();
      // Banner del primo canale: si lascia sparire.
      await tester.pump(const Duration(seconds: 6));
      await tester.pump(const Duration(seconds: 1));
    }

    Future<void> finish(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      tuner.dispose();
      reminders.dispose();
      await tester.pump(const Duration(seconds: 30));
    }

    testWidgets('pressione breve: informazioni come sempre', (tester) async {
      await pumpPlayer(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
      await tester.pump(const Duration(milliseconds: 150));
      expect(tuner.bannerVisible, isFalse); // si aspetta il rilascio
      await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(tuner.bannerVisible, isTrue);
      expect(tuner.infoMode, isTrue);
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(ChannelKeypad), findsNothing);
      await finish(tester);
    });

    testWidgets('pressione lunga: tastierino, poi ✓ sintonizza', (
      tester,
    ) async {
      await pumpPlayer(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
      await tester.pump(keypadHoldDuration + const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(ChannelKeypad), findsOneWidget);
      // Il rilascio di OK non preme il tasto del tastierino né apre altro.
      await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(
        find.descendant(
          of: find.byType(ChannelKeypad),
          matching: find.text('Digita il numero'),
        ),
        findsOneWidget,
      );
      expect(tuner.infoMode, isFalse);
      for (final k in [
        LogicalKeyboardKey.digit1,
        LogicalKeyboardKey.digit2,
        LogicalKeyboardKey.digit8,
      ]) {
        await tester.sendKeyEvent(k);
        await tester.pump();
      }
      // Su ✓ si arriva con ↓↓↓→ dal 5.
      for (final k in [
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.arrowRight,
      ]) {
        await tester.sendKeyEvent(k);
        await tester.pump();
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(tuner.current?.number, 128);
      expect(find.byType(ChannelKeypad), findsNothing);
      await finish(tester);
    });
  });
}
