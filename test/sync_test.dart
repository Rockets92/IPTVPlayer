import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/data/epg/epg_models.dart';
import 'package:iptv_player/data/settings_store.dart';
import 'package:iptv_player/data/xtream/xtream_client.dart';
import 'package:iptv_player/data/xtream/xtream_models.dart';
import 'package:iptv_player/domain/channel.dart';
import 'package:iptv_player/state/reminder_controller.dart';
import 'package:iptv_player/state/vod_controller.dart';
import 'package:iptv_player/sync/sync_backend.dart';
import 'package:iptv_player/sync/sync_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

const ch = Channel(
  id: 'm101',
  number: 101,
  name: 'Rai 1',
  group: 'A',
  sources: [],
);

Future<SharedPreferences> freshPrefs([Map<String, Object> v = const {}]) async {
  SharedPreferences.setMockInitialValues(v);
  return SharedPreferences.getInstance();
}

EpgProgramme prog(int inSeconds, [String title = 'Film']) {
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  return EpgProgramme(
    start: now + inSeconds,
    end: now + inSeconds + 3600,
    title: title,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('promemoria', () {
    test('i vecchi promemoria ricevono un id stabile al primo salvataggio', () async {
      final p = prog(7200);
      final prefs = await freshPrefs({
        'reminders.v1':
            '[{"c":"m101","n":101,"name":"Rai 1","t":"Tg1","s":${p.start},"r":"daily"}]',
      });
      final rc = ReminderController(prefs);
      final r = rc.items.single;
      expect(r.id, 'm101@${p.start}');
      expect(r.updatedAt, 0);
      // La ripetizione sposta l'orario ma l'id resta quello.
      final moved = r.copyWith(start: p.start + 86400);
      expect(moved.id, r.id);
      expect(Reminder.fromJson(moved.toJson())!.id, r.id);
      rc.dispose();
    });

    test(
      'lo stesso programma prenotato su due dispositivi ha lo stesso id',
      () async {
        final p = prog(7200);
        final a = ReminderController(await freshPrefs());
        a.toggle(ch, p);
        final fromA = a.items.single;
        a.dispose();

        final b = ReminderController(await freshPrefs());
        b.toggle(ch, p);
        b.mergeRemote(upserts: [fromA]);
        expect(b.items, hasLength(1));
        expect(b.items.single.id, fromA.id);
        b.dispose();
      },
    );

    test(
      'vince la modifica più recente e le cancellazioni si propagano',
      () async {
        final p = prog(7200);
        final rc = ReminderController(await freshPrefs());
        var local = 0;
        rc.onLocalChange = () => local++;
        var t = 1000;
        rc.clock = () => t;
        rc.toggle(ch, p);
        expect(local, 1);
        final mine = rc.items.single;
        expect(mine.updatedAt, 1000);

        // Una modifica più vecchia arrivata da fuori non vince.
        rc.mergeRemote(
          upserts: [
            mine.copyWith(repeat: ReminderRepeat.daily, updatedAt: 500),
          ],
        );
        expect(rc.items.single.repeat, ReminderRepeat.once);

        // Una più recente sì, senza contare come modifica locale.
        rc.mergeRemote(
          upserts: [
            mine.copyWith(repeat: ReminderRepeat.weekly, updatedAt: 2000),
          ],
        );
        expect(rc.items.single.repeat, ReminderRepeat.weekly);
        expect(local, 1);

        // Cancellato su un altro dispositivo.
        rc.mergeRemote(deletions: {mine.id: 3000});
        expect(rc.items, isEmpty);
        // La copia vecchia di un dispositivo rimasto spento non lo resuscita.
        rc.mergeRemote(upserts: [mine.copyWith(updatedAt: 2500)]);
        expect(rc.items, isEmpty);

        // Cancellato qui: resta la lapide da inviare.
        t = 4000;
        rc.toggle(ch, p);
        rc.remove(rc.items.single);
        expect(rc.deletions[mine.id], 4000);
        expect(local, 3);
        rc.dispose();
      },
    );

    test('le lapidi restano salvate e scadono dopo 60 giorni', () async {
      final prefs = await freshPrefs();
      final rc = ReminderController(prefs);
      rc.toggle(ch, prog(7200));
      rc.remove(rc.items.single);
      rc.dispose();
      final again = ReminderController(prefs);
      expect(again.deletions, hasLength(1));
      again.clock = () =>
          DateTime.now().add(const Duration(days: 61)).millisecondsSinceEpoch;
      again.toggle(ch, prog(9000));
      expect(again.deletions, isEmpty);
      again.dispose();
    });
  });

  group('continua a guardare', () {
    XtreamClient client() => XtreamClient(
      const XtreamCredentials(
        serverUrl: 'http://x',
        username: 'u',
        password: 'p',
      ),
    );

    WatchEntry entry(int seconds, DateTime at) => WatchEntry(
      key: 'm:42',
      position: Duration(seconds: seconds),
      duration: const Duration(hours: 2),
      at: at,
      title: 'Film',
    );

    test('vince la posizione più recente, le rimozioni si propagano', () async {
      final vc = VodController.withClient(client(), prefs: await freshPrefs());
      var local = 0;
      vc.onLocalChange = () => local++;
      vc.remember(entry(600, DateTime(2026, 11, 1, 10)));
      expect(local, 1);

      vc.mergeRemote(upserts: [entry(100, DateTime(2026, 11, 1, 9))]);
      expect(vc.progressOf('m:42')!.position.inSeconds, 600);
      vc.mergeRemote(upserts: [entry(1800, DateTime(2026, 11, 1, 11))]);
      expect(vc.progressOf('m:42')!.position.inSeconds, 1800);
      expect(local, 1);

      vc.forget('m:42');
      expect(vc.forgotten.keys, ['m:42']);
      vc.mergeRemote(upserts: [entry(1900, DateTime(2026, 11, 1, 11, 30))]);
      expect(vc.progressOf('m:42'), isNull);
      vc.dispose();
    });
  });

  group('preferenze', () {
    test('il PIN in chiaro diventa impronta', () async {
      final prefs = await freshPrefs({
        'channels.adultMode': 'pin',
        'channels.adultPin': '1234',
      });
      final s = SettingsStore(prefs);
      await Future<void>.delayed(Duration.zero);
      expect(prefs.getString('channels.adultPin'), isNull);
      expect(prefs.getString('channels.adultPinHash'), isNot('1234'));
      expect(s.checkAdultPin('1234'), isTrue);
      expect(s.checkAdultPin('0000'), isFalse);
    });

    test(
      'solo le preferenze personali si sincronizzano, vince la più recente',
      () async {
        final a = SettingsStore(await freshPrefs());
        a.clock = () => 1000;
        await a.setExtraEpgSources(['http://epg.example/it.xml']);
        await a.setAdultMode(AdultMode.pin, pin: '4321');
        await a.setUiScale(UiScale.small); // del dispositivo
        final out = a.syncedPrefs;
        expect(out.keys, isNot(contains('ui.scale')));
        expect(out['epg.extraSources']!.updatedAt, 1000);

        final b = SettingsStore(await freshPrefs());
        b.clock = () => 500;
        await b.setExtraEpgSources(['http://vecchia']);
        expect(await b.applyRemotePrefs(out), contains('epg.extraSources'));
        expect(b.extraEpgSources, ['http://epg.example/it.xml']);
        expect(b.adultMode, AdultMode.pin);
        expect(b.checkAdultPin('4321'), isTrue);
        expect(b.uiScale, UiScale.auto);
        // Una seconda volta non cambia nulla.
        expect(await b.applyRemotePrefs(out), isEmpty);
      },
    );
  });

  test(
    'backend in memoria: vince la più recente, cursore del server',
    () async {
      final be = MemorySyncBackend();
      await be.push([
        const SyncRecord(table: SyncTable.reminders, id: 'a', updatedAt: 10),
      ]);
      final first = await be.pull();
      expect(first.records, hasLength(1));
      await be.push([
        const SyncRecord(table: SyncTable.reminders, id: 'a', updatedAt: 5),
        const SyncRecord(
          table: SyncTable.reminders,
          id: 'b',
          updatedAt: 1,
          deleted: true,
        ),
      ]);
      final next = await be.pull(cursor: first.cursor);
      expect(next.records.map((r) => r.id), ['b']);
      await be.close();
    },
  );

  test('due dispositivi: promemoria e preferenze viaggiano, anche le cancellazioni', () async {
    final cloud = MemorySyncBackend();
    final p = prog(7200);

    // Dispositivo A: un promemoria salvato prima di avere l'account.
    final prefsA = await freshPrefs();
    final remA = ReminderController(prefsA);
    final setA = SettingsStore(prefsA);
    remA.toggle(ch, p);
    await setA.setExtraEpgSources(['http://epg.example/a.xml']);
    final engA = SyncEngine(
      backend: cloud,
      prefs: prefsA,
      reminders: remA,
      settings: setA,
      pushDelay: Duration.zero,
    );
    await engA.start();

    // Dispositivo B: accede dopo e ritrova tutto.
    final prefsB = await freshPrefs();
    final remB = ReminderController(prefsB);
    final setB = SettingsStore(prefsB);
    Set<String>? applied;
    final engB = SyncEngine(
      backend: cloud,
      prefs: prefsB,
      reminders: remB,
      settings: setB,
      pushDelay: Duration.zero,
      onPrefsApplied: (k) async => applied = k,
    );
    await engB.start();
    expect(remB.items.single.title, 'Film');
    expect(setB.extraEpgSources, ['http://epg.example/a.xml']);
    expect(applied, contains('epg.extraSources'));

    // Cancellato su B: sparisce anche da A, in tempo reale.
    remB.remove(remB.items.single);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(remA.items, isEmpty);

    // Prenotato su A: compare su B.
    remA.toggle(ch, prog(9000, 'Partita'));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(remB.items.single.title, 'Partita');

    await engA.stop();
    await engB.stop();
    remA.dispose();
    remB.dispose();
    await cloud.close();
  });
}
