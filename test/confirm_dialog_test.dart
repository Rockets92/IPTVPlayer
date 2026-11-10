import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/core/performance.dart';
import 'package:iptv_player/ui/widgets/confirm_dialog.dart';
import 'package:provider/provider.dart';

Future<bool?> ask(WidgetTester t, List<LogicalKeyboardKey> keys) async {
  bool? answer;
  await t.pumpWidget(
    Provider.value(
      value: const PerformanceProfile(PerformanceTier.light),
      child: MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => answer = await showConfirmDialog(
              context,
              title: 'Vuoi uscire?',
            ),
            child: const Text('apri'),
          ),
        ),
      ),
    ),
  );
  await t.tap(find.text('apri'));
  await t.pumpAndSettle();
  for (final k in keys) {
    await t.sendKeyEvent(k);
    await t.pumpAndSettle();
  }
  return answer;
}

void main() {
  testWidgets('telecomando: ← e OK scelgono Sì', (t) async {
    expect(
      await ask(t, [LogicalKeyboardKey.arrowLeft, LogicalKeyboardKey.select]),
      isTrue,
    );
  });
  testWidgets('telecomando: OK subito = No', (t) async {
    expect(await ask(t, [LogicalKeyboardKey.select]), isFalse);
  });
  testWidgets('telecomando: ← → OK = No, Indietro = No', (t) async {
    expect(
      await ask(t, [
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.enter,
      ]),
      isFalse,
    );
    expect(await ask(t, [LogicalKeyboardKey.escape]), isFalse);
  });
}
