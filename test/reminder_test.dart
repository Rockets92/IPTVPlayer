import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/data/epg/epg_models.dart';
import 'package:iptv_player/domain/channel.dart';
import 'package:iptv_player/state/reminder_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('prenota, scatta 5 minuti prima e si risolve', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final rc = ReminderController(prefs);
    const ch = Channel(
      id: 'm101',
      number: 101,
      name: 'Rai 1',
      group: 'A',
      sources: [],
    );
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final far = EpgProgramme(start: now + 3600, end: now + 7200, title: 'Film');
    final soon = EpgProgramme(start: now + 120, end: now + 3600, title: 'Tg1');

    expect(rc.toggle(ch, far), isTrue);
    expect(rc.isSet('m101', far), isTrue);
    expect(rc.due, isNull);

    expect(rc.toggle(ch, soon), isTrue);
    expect(rc.due?.title, 'Tg1');

    // Persistenza.
    final again = ReminderController(prefs);
    expect(again.items.length, 2);
    again.dispose();

    rc.resolve();
    expect(rc.due, isNull);
    expect(rc.items.single.title, 'Film');
    expect(rc.toggle(ch, far), isFalse);
    expect(rc.items, isEmpty);
    rc.dispose();
  });
}
