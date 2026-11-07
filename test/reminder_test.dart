import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/data/epg/epg_models.dart';
import 'package:iptv_player/domain/channel.dart';
import 'package:iptv_player/state/reminder_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

Reminder at(DateTime t, ReminderRepeat r, [List<int> days = const []]) =>
    Reminder(
      channelId: 'c',
      channelNumber: 1,
      channelName: 'Rai 1',
      title: 'Tg1',
      start: t.millisecondsSinceEpoch ~/ 1000,
      repeat: r,
      days: days,
    );

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

  test(
    'ricordamelo tra 1 minuto, poi il ricorrente passa alla volta dopo',
    () async {
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
      final soon = EpgProgramme(
        start: now + 120,
        end: now + 3600,
        title: 'Tg1',
      );
      rc.toggle(ch, soon);
      expect(rc.due, isNotNull);
      rc.snooze();
      expect(rc.due, isNull);
      // Nuovo avviso 1 minuto prima dell'inizio.
      expect(rc.items.single.snooze, soon.start - 60);

      final r = rc.setRepeat(rc.items.single, ReminderRepeat.daily)!;
      expect(r.repeat, ReminderRepeat.daily);
      rc.snooze();
      // Avviso ricorrente risolto: resta, il giorno dopo alla stessa ora.
      rc.due = rc.items.single;
      rc.resolve();
      final next = rc.items.single;
      expect(next.startTime, r.startTime.add(const Duration(days: 1)));
      expect(next.snooze, isNull);
      rc.dispose();
    },
  );

  group('ripetizione', () {
    // Lunedì 2 novembre 2026, 20:00.
    final mon = DateTime(2026, 11, 2, 20);

    test('una volta: nessuna ripetizione', () {
      expect(at(mon, ReminderRepeat.once).nextAfter(mon), isNull);
    });

    test('giornaliero: il giorno dopo alla stessa ora', () {
      expect(
        at(mon, ReminderRepeat.daily).nextAfter(mon),
        DateTime(2026, 11, 3, 20),
      );
    });

    test('settimanale: i giorni scelti', () {
      final r = at(mon, ReminderRepeat.weekly, [1, 3, 5]);
      expect(r.nextAfter(mon), DateTime(2026, 11, 4, 20));
      expect(r.nextAfter(DateTime(2026, 11, 6, 21)), DateTime(2026, 11, 9, 20));
      expect(r.repeatLabel, 'Ogni settimana · lun, mer, ven');
      // Senza giorni: quello del programma.
      expect(
        at(mon, ReminderRepeat.weekly).nextAfter(mon),
        DateTime(2026, 11, 9, 20),
      );
    });

    test('mensile: stesso giorno, o l\'ultimo del mese', () {
      expect(
        at(mon, ReminderRepeat.monthly).nextAfter(mon),
        DateTime(2026, 12, 2, 20),
      );
      final end = DateTime(2027, 1, 31, 9);
      expect(
        at(end, ReminderRepeat.monthly).nextAfter(end),
        DateTime(2027, 2, 28, 9),
      );
    });

    test('json conserva ripetizione, giorni e rinvio', () {
      final r = at(mon, ReminderRepeat.weekly, [
        2,
        4,
      ]).copyWith(snooze: () => 5);
      final b = Reminder.fromJson(r.toJson())!;
      expect(b.repeat, ReminderRepeat.weekly);
      expect(b.days, [2, 4]);
      expect(b.snooze, 5);
    });
  });
}
