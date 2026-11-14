import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/core/performance.dart';
import 'package:iptv_player/data/settings_store.dart';
import 'package:iptv_player/domain/channel.dart';
import 'package:iptv_player/player/playback_engine.dart';
import 'package:iptv_player/remote/remote_server.dart';
import 'package:iptv_player/state/app_controller.dart';
import 'package:iptv_player/state/reminder_controller.dart';
import 'package:iptv_player/state/tuner_controller.dart';
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

Channel _ch(int n, String name) => Channel(
  id: 'm$n',
  number: n,
  name: name,
  group: 'TV',
  sources: [ChannelSource(streamId: n, label: name)],
);

/// Elenco canali del telecomando: la parte fissa viaggia solo quando cambia.
void main() {
  test(
    'elenco canali: con la versione giusta arrivano solo i titoli',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final app = AppController(
        settings: SettingsStore(prefs),
        perf: const PerformanceProfile(PerformanceTier.full),
      )..channels = [_ch(1, 'Rai 1'), _ch(2, 'Rai 2')];
      final server = RemoteServer(
        prefs: prefs,
        app: app,
        tuner: TunerController(app: app, engine: _Engine()),
        reminders: ReminderController(prefs),
      );

      final full = (await server.remoteApi('GET', '/api/channels'))! as Map;
      final v = full['v'] as String;
      expect(v, isNotEmpty);
      expect((full['channels'] as List).length, 2);
      expect(full['nowById'], isA<Map>());

      final light =
          (await server.remoteApi('GET', '/api/channels', query: {'v': v}))!
              as Map;
      expect(light['same'], isTrue);
      expect(light.containsKey('channels'), isFalse);
      expect(light['v'], v);

      // Cambia l'elenco (un preferito): torna tutto, con una versione nuova.
      await app.toggleFavorite(app.channels.first);
      final again =
          (await server.remoteApi('GET', '/api/channels', query: {'v': v}))!
              as Map;
      expect(again['same'], isNull);
      expect(again['v'], isNot(v));
      expect(again['groups'], contains(RemoteServer.favoritesGroup));
    },
  );
}
