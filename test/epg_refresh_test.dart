import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/core/performance.dart';
import 'package:iptv_player/data/epg/epg_models.dart';
import 'package:iptv_player/data/epg/epg_repository.dart';
import 'package:iptv_player/data/settings_store.dart';
import 'package:iptv_player/domain/channel.dart';
import 'package:iptv_player/state/app_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Fonte finta: i primi `failures` scaricamenti falliscono (rete assente).
class _Repo extends EpgRepository {
  _Repo({this.failures = 0});
  int failures;
  int calls = 0;

  @override
  Future<EpgSchedule?> loadCache(String signature) async => null;

  @override
  Future<(EpgSchedule, List<EpgSourceReport>)> fetch({
    required List<String> sources,
    required List<Channel> channels,
    required PerformanceProfile perf,
    required String signature,
    void Function(String message)? onProgress,
  }) async {
    calls++;
    if (failures > 0) {
      failures--;
      return (
        EpgSchedule({}, fetchedAt: DateTime.now()),
        [for (final s in sources) EpgSourceReport(s, error: 'offline')],
      );
    }
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return (
      EpgSchedule({
        'm1': [EpgProgramme(start: now - 60, end: now + 3600, title: 'Tg1')],
      }, fetchedAt: DateTime.now()),
      [for (final s in sources) EpgSourceReport(s, channels: 1)],
    );
  }
}

Future<AppController> _app(_Repo repo, {bool light = true}) async {
  SharedPreferences.setMockInitialValues({});
  final settings = SettingsStore(await SharedPreferences.getInstance());
  await settings.setExtraEpgSources(['http://guida.test/epg.xml']);
  return AppController(
      settings: settings,
      perf: PerformanceProfile(
        light ? PerformanceTier.light : PerformanceTier.full,
      ),
      epgRepository: repo,
    )
    ..channels = [
      Channel(
        id: 'm1',
        number: 1,
        name: 'Rai 1',
        group: 'TV',
        sources: const [ChannelSource(streamId: 1, label: 'Rai 1')],
      ),
    ];
}

void main() {
  testWidgets('guida non scaricata: si riprova da sola finché arriva', (
    tester,
  ) async {
    final repo = _Repo(failures: 3);
    final app = await _app(repo);
    await app.refreshEpg();
    expect(repo.calls, 1);
    expect(app.epg.isEmpty, isTrue);
    expect(app.epgStatus, 'Guida non disponibile');
    expect(app.epgRetryAt, isNotNull);

    await tester.pump(const Duration(seconds: 21)); // 2° tentativo
    expect(repo.calls, 2);
    await tester.pump(const Duration(minutes: 1, seconds: 1)); // 3°
    expect(repo.calls, 3);
    await tester.pump(const Duration(minutes: 2, seconds: 1)); // 4°: riesce
    expect(repo.calls, 4);
    expect(app.epg.has('m1'), isTrue);
    expect(app.epgStatus, 'Guida aggiornata');
    expect(app.epgRetryAt, isNull);
    app.dispose();
  });

  testWidgets('con l\'app sempre aperta la guida si rinnova da sola', (
    tester,
  ) async {
    final repo = _Repo();
    final app = await _app(repo);
    await app.refreshEpg();
    expect(repo.calls, 1);
    await tester.pump(const Duration(hours: 5));
    expect(repo.calls, 1);
    await tester.pump(const Duration(hours: 1, minutes: 1));
    expect(repo.calls, 2);
    app.dispose();
  });

  testWidgets('aggiornamento chiesto durante un download: non va perso', (
    tester,
  ) async {
    final repo = _Repo();
    final app = await _app(repo);
    final first = app.refreshEpg();
    expect(app.epgLoading, isTrue);
    await app.refreshEpg(); // prima veniva ignorato
    await first;
    await tester.pump();
    expect(repo.calls, 2);
    app.dispose();
  });
}
