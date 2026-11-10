import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/ui/widgets/focus_tile.dart';

void main() {
  setUpAll(installBackKeyGuard);

  Future<void> pump(WidgetTester tester, {required bool handles}) =>
      tester.pumpWidget(
        MaterialApp(
          home: Focus(
            autofocus: true,
            onKeyEvent: (_, e) =>
                handles && e is KeyDownEvent && isBackKey(e.logicalKey)
                ? KeyEventResult.handled
                : KeyEventResult.ignored,
            child: const SizedBox(),
          ),
        ),
      );

  testWidgets('Indietro già gestito: il rilascio non arriva al sistema', (
    tester,
  ) async {
    await pump(tester, handles: true);
    await tester.pump();
    expect(await tester.sendKeyDownEvent(LogicalKeyboardKey.escape), isTrue);
    expect(await tester.sendKeyUpEvent(LogicalKeyboardKey.escape), isTrue);
  });

  testWidgets('Indietro non gestito: il sistema lo riceve come sempre', (
    tester,
  ) async {
    await pump(tester, handles: false);
    await tester.pump();
    expect(await tester.sendKeyDownEvent(LogicalKeyboardKey.escape), isFalse);
    expect(await tester.sendKeyUpEvent(LogicalKeyboardKey.escape), isFalse);
  });
}
