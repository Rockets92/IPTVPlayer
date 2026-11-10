import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/core/form_factor.dart';
import 'package:iptv_player/core/performance.dart';
import 'package:iptv_player/data/settings_store.dart';
import 'package:iptv_player/state/app_controller.dart';
import 'package:iptv_player/ui/settings/settings_panel.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Col solo telecomando (frecce su/giù) si deve poter arrivare a ogni voce
/// delle impostazioni, comandi in fondo compresi, e tornare in cima.
void main() {
  for (final tier in PerformanceTier.values) {
    for (final form in [FormFactor.tv, FormFactor.desktop]) {
      testWidgets('frecce: tutte le voci raggiungibili ($tier, $form)', (
        tester,
      ) async {
        // Schermo piccolo come una Chromecast a 540p.
        tester.view.physicalSize = const Size(960, 540);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        SharedPreferences.setMockInitialValues({});
        final settings = SettingsStore(await SharedPreferences.getInstance());
        final perf = PerformanceProfile(tier);
        final app = AppController(settings: settings, perf: perf);

        // Il font dei test (quadratini larghi) fa sforare di qualche pixel le
        // scelte a 4 opzioni: non riguarda la navigazione, si ignora.
        final onError = FlutterError.onError;
        FlutterError.onError = (d) {
          if (d.exception is FlutterError &&
              d.exceptionAsString().contains('overflowed')) {
            return;
          }
          onError?.call(d);
        };
        addTearDown(() => FlutterError.onError = onError);

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: app),
              Provider.value(value: perf),
              Provider.value(value: form),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: SettingsPanel(onClose: () {}, onToast: (_) {}),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final scroll = tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position;
        final visited = <FocusNode>{};
        FocusNode? last;
        for (var i = 0; i < 80; i++) {
          final f = FocusManager.instance.primaryFocus!;
          visited.add(f);
          if (f == last && scroll.pixels >= scroll.maxScrollExtent) break;
          last = f;
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await tester.pumpAndSettle();
        }

        // L'ultimo comando ha il focus e la lista è in fondo (logo visibile).
        final focused = FocusManager.instance.primaryFocus!.context!;
        expect(
          find.descendant(
            of: find.byWidget(focused.widget),
            matching: find.textContaining('Schermo intero'),
          ),
          findsOneWidget,
        );
        expect(scroll.pixels, scroll.maxScrollExtent);
        expect(visited.length, greaterThan(20));

        // E si torna in cima.
        for (var i = 0; i < 80 && scroll.pixels > 0; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
          await tester.pumpAndSettle();
        }
        expect(scroll.pixels, 0);
      });
    }
  }
}
