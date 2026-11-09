import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/core/heavy_work.dart';
import 'package:iptv_player/data/xtream/xtream_client.dart';
import 'package:iptv_player/data/xtream/xtream_models.dart';

/// Con un vero client HTTP (non finto) l'elenco si decodifica in un isolate:
/// la chiusura non deve trascinarsi dietro il client, che non è inviabile.
void main() {
  late HttpServer server;
  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((r) {
      final action = r.uri.queryParameters['action'];
      final body = switch (action) {
        'get_live_streams' => [
          {'stream_id': 1, 'name': 'Rai 1 HEVC ( hermes )', 'category_id': '1'},
          {'stream_id': 2, 'name': 'Rai 2', 'category_id': '1'},
        ],
        'get_vod_streams' => [
          {'stream_id': 7, 'name': 'IT: Film (2020)', 'category_id': '3'},
        ],
        'get_series' => [
          {'series_id': 9, 'name': 'Serie', 'category_id': '4'},
        ],
        _ => <Object>[],
      };
      r.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(body))
        ..close();
    });
  });
  tearDown(() => server.close(force: true));

  for (final serialize in [false, true]) {
    test('canali, film e serie (in fila: $serialize)', () async {
      HeavyWork.serialize = serialize;
      addTearDown(() => HeavyWork.serialize = false);
      final client = XtreamClient(
        XtreamCredentials(
          serverUrl: 'http://127.0.0.1:${server.port}',
          username: 'u',
          password: 'p',
        ),
      );
      addTearDown(client.close);
      final live = await client.liveStreams();
      expect(live.map((s) => s.streamId), [1, 2]);
      final films = await client.vodStreams();
      expect(films.single.id, 7);
      final series = await client.series();
      expect(series.single.id, 9);
    });
  }
}
