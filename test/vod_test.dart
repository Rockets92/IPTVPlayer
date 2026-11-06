import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:iptv_player/data/vod/vod_models.dart';
import 'package:iptv_player/data/xtream/xtream_client.dart';
import 'package:iptv_player/data/xtream/xtream_models.dart';
import 'package:iptv_player/state/vod_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

XtreamClient _client() => XtreamClient(
  const XtreamCredentials(
    serverUrl: 'http://example.test',
    username: 'u',
    password: 'p',
  ),
  httpClient: MockClient((req) async {
    final a = req.url.queryParameters['action'];
    final body = switch (a) {
      'get_vod_categories' => [
        {'category_id': '1', 'category_name': 'IT | Azione'},
        {'category_id': '2', 'category_name': 'IT | Commedia'},
      ],
      'get_vod_streams' => [
        {
          'stream_id': 10,
          'name': 'IT: Il Faro del Nord (2019)',
          'category_id': '1',
          'added': '300',
          'rating': '7.1',
          'container_extension': 'mkv',
        },
        {
          'stream_id': 11,
          'name': '|IT| Città d\'Autunno',
          'category_id': '2',
          'added': '500',
          'rating': '6',
        },
        {
          'stream_id': 12,
          'name': 'IT: Ombra Perduta',
          'category_id': '1',
          'added': '100',
          'rating': '8.4',
        },
      ],
      'get_series_info' => {
        'info': {'plot': 'Trama'},
        'episodes': {
          '2': [
            {
              'id': '22',
              'episode_num': 1,
              'season': 2,
              'title': 'Serie - S02E01 - Ritorno',
            },
          ],
          '1': [
            {'id': '12', 'episode_num': 2, 'season': 1, 'title': 'S01E02'},
            {
              'id': '11',
              'episode_num': 1,
              'season': 1,
              'title': 'Serie - S01E01 - Pilota',
              'info': {'duration_secs': 2700},
            },
          ],
        },
      },
      _ => {
        'user_info': {'auth': 1},
      },
    };
    return http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }),
);

void main() {
  test('titoli puliti da prefissi e anno', () {
    expect(VodItem.cleanTitle('IT: Il Faro (2019)'), 'Il Faro');
    expect(VodItem.cleanTitle('|IT| Il Faro'), 'Il Faro');
    expect(VodItem.cleanTitle('[EN] Lighthouse'), 'Lighthouse');
    expect(Episode.cleanTitle('Serie - S01E03 - La lettera'), 'La lettera');
  });

  test('catalogo: categorie, ricerca senza accenti e ordinamento', () async {
    SharedPreferences.setMockInitialValues({});
    final vod = VodController.withClient(
      _client(),
      prefs: await SharedPreferences.getInstance(),
    );
    await vod.load(VodKind.movies);
    final c = vod.catalog(VodKind.movies);
    expect(c.categories.length, 2);
    expect(c.items.first.year, 2019);
    expect(c.items.first.extension, 'mkv');

    List<int> ids(List<VodItem> l) => [for (final i in l) i.id];
    expect(ids(vod.query(VodKind.movies, category: VodCategories.all)), [
      11,
      10,
      12,
    ]);
    expect(ids(vod.query(VodKind.movies, category: '1')), [10, 12]);
    expect(
      ids(
        vod.query(
          VodKind.movies,
          category: VodCategories.all,
          sort: VodSort.rating,
        ),
      ),
      [12, 10, 11],
    );
    expect(ids(vod.query(VodKind.movies, category: '*all', search: 'citta')), [
      11,
    ]);
    expect(
      ids(vod.query(VodKind.movies, category: '*all', search: 'faro nord')),
      [10],
    );
    expect(vod.counts(VodKind.movies), {'1': 2, '2': 1});
  });

  test('stagioni ed episodi in ordine', () async {
    final info = await _client().seriesInfo(5);
    expect(info.seasonNumbers, [1, 2]);
    expect([for (final e in info.seasons[1]!) e.number], [1, 2]);
    expect(info.seasons[1]!.first.title, 'Pilota');
    expect(info.seasons[1]!.first.duration, const Duration(minutes: 45));
    expect(info.seasons[1]!.first.code, 'S01E01');
  });

  test('continua a guardare: si salva, si ricarica, i finiti escono', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final vod = VodController.withClient(_client(), prefs: prefs);
    await vod.load(VodKind.movies);
    vod.remember(
      WatchEntry(
        key: 'm:12',
        position: const Duration(minutes: 30),
        duration: const Duration(minutes: 100),
        at: DateTime(2026, 11, 5),
        title: 'Ombra Perduta',
      ),
    );
    vod.remember(
      WatchEntry(
        key: 'm:10',
        position: const Duration(minutes: 99),
        duration: const Duration(minutes: 100),
        at: DateTime(2026, 11, 6),
        title: 'Il Faro del Nord',
      ),
    );
    // Pochi secondi: non conta come iniziato.
    vod.remember(
      WatchEntry(
        key: 'm:11',
        position: const Duration(seconds: 5),
        duration: const Duration(minutes: 100),
        at: DateTime(2026, 11, 6),
        title: 'Città',
      ),
    );
    expect(
      [for (final w in vod.continueWatching(VodKind.movies)) w.key],
      ['m:12'],
    );
    expect(
      [
        for (final i in vod.query(
          VodKind.movies,
          category: VodCategories.continueWatching,
        ))
          i.id,
      ],
      [12],
    );
    await Future<void>.delayed(const Duration(milliseconds: 2100));
    final again = VodController.withClient(_client(), prefs: prefs);
    expect(again.progressOf('m:12')?.position, const Duration(minutes: 30));
    expect(again.progressOf('m:10')?.finished, isTrue);
  });
}
