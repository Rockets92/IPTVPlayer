import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/data/mapping/channel_mapping.dart';
import 'package:iptv_player/data/xtream/xtream_models.dart';
import 'package:iptv_player/domain/channel_matcher.dart';
import 'package:iptv_player/domain/name_normalizer.dart';

void main() {
  group('NameNormalizer.key', () {
    test('rimuove prefissi paese e qualità', () {
      expect(NameNormalizer.key('IT: Rai 1 HD'), 'rai1');
      expect(NameNormalizer.key('|IT| RAI 1 FHD'), 'rai1');
      expect(NameNormalizer.key('[ITA] Rai 1 (backup)'), 'rai1');
      expect(NameNormalizer.key('Rai 1 ᴴᴰ'), 'rai1');
    });

    test('mantiene le varianti significative', () {
      expect(NameNormalizer.key('IT: Sky Uno +1 HD'), 'sky1plus1');
      expect(
        NameNormalizer.key('Sky Uno'),
        isNot(NameNormalizer.key('Sky Uno +1')),
      );
      expect(NameNormalizer.key('Sky Cinema Uno +24'), 'skycinema1plus24');
    });

    test('non confonde Italia 1 con il prefisso paese', () {
      expect(NameNormalizer.key('Italia 1'), 'italia1');
      expect(NameNormalizer.key('IT: Italia 1 HD'), 'italia1');
    });

    test('accenti e simboli', () {
      expect(
        NameNormalizer.key('Crime+Investigation'),
        'crimeplusinvestigation',
      );
      expect(NameNormalizer.key('Caccia & Pesca'), 'cacciaandpesca');
    });
  });

  test('qualityScore preferisce FHD, nel profilo light preferisce HD', () {
    final fhd = NameNormalizer.qualityScore('Rai 1 FHD');
    final hd = NameNormalizer.qualityScore('Rai 1 HD');
    final uhd = NameNormalizer.qualityScore('Rai 1 4K');
    expect(fhd, greaterThan(hd));
    expect(
      NameNormalizer.qualityScore('Rai 1 HD', preferLighter: true),
      greaterThan(
        NameNormalizer.qualityScore('Rai 1 FHD', preferLighter: true),
      ),
    );
    expect(
      NameNormalizer.qualityScore('Rai 1 4K', preferLighter: true),
      lessThan(uhd),
    );
  });

  group('ChannelMatcher', () {
    final mapping = ChannelMapping.fromJson({
      'id': 'test',
      'name': 'Test',
      'logoBaseUrl': 'https://logo/',
      'unmappedChannels': {'show': true, 'startNumber': 1000},
      'channels': [
        {
          'number': 101,
          'name': 'Rai 1',
          'group': 'Intrattenimento',
          'logo': 'rai1.png',
          'epgId': 'Rai1.it',
          'aliases': ['Rai Uno'],
        },
        {'number': 108, 'name': 'Sky Uno', 'group': 'Intrattenimento'},
        {'number': 109, 'name': 'Sky Uno +1', 'group': 'Intrattenimento'},
        {'number': 200, 'name': 'Canale Assente', 'group': 'Sport'},
        {
          'number': 301,
          'name': 'Sky Cinema Uno',
          'group': 'Cinema',
          'streamId': 77,
        },
      ],
    });
    const streams = [
      XtreamLiveStream(streamId: 1, name: 'IT: RAI UNO SD', categoryId: '1'),
      XtreamLiveStream(
        streamId: 2,
        name: 'IT: Rai 1 FHD',
        categoryId: '1',
        epgChannelId: 'rai1.prov',
      ),
      XtreamLiveStream(streamId: 3, name: 'IT: Sky Uno HD', categoryId: '2'),
      XtreamLiveStream(streamId: 4, name: 'IT: Sky Uno +1', categoryId: '2'),
      XtreamLiveStream(streamId: 5, name: 'IT: Canale Locale', categoryId: '3'),
      XtreamLiveStream(
        streamId: 77,
        name: 'Cinema 1 (nome strano)',
        categoryId: '4',
      ),
    ];

    test('ordine, numerazione e scelta della sorgente migliore', () {
      final list = const ChannelMatcher().build(
        mapping: mapping,
        streams: streams,
        categoryNames: {'3': 'Locali'},
      );
      expect(list.map((c) => c.number), [101, 108, 109, 301, 1000]);
      final rai = list.first;
      expect(rai.sources.map((s) => s.streamId), [2, 1]);
      expect(rai.logoUrl, 'https://logo/rai1.png');
      expect(rai.epgIds, ['Rai1.it', 'rai1.prov']);
      expect(list[1].sources.single.streamId, 3);
      expect(list[2].sources.single.streamId, 4);
      expect(list[3].sources.single.streamId, 77);
      expect(list.last.name, 'Canale Locale');
      expect(list.last.group, 'Locali');
      expect(list.last.mapped, isFalse);
    });

    test('canali non mappati nascosti su richiesta', () {
      final list = const ChannelMatcher().build(
        mapping: mapping,
        streams: streams,
        showUnmapped: false,
      );
      expect(list.every((c) => c.mapped), isTrue);
    });
  });

  test('nomi decorati, numeri davanti e numeri in lettere', () {
    final rai1 = NameNormalizer.key('Rai 1');
    for (final n in [
      '𝐑𝐀𝐈 𝟏 𝐅𝐇𝐃',
      'ʀᴀɪ 1 ᴴᴰ',
      'ＲＡＩ １',
      'IT | RAI UNO',
      '101 - RAI 1 HD',
      '101 | IT: Rai 1',
      '🇮🇹 RAI 1',
      'Ⓡⓐⓘ 1',
    ]) {
      expect(NameNormalizer.key(n), rai1, reason: n);
    }
    expect(
      NameNormalizer.key('Sky Cinema Due'),
      NameNormalizer.key('Sky Cinema 2'),
    );
    expect(NameNormalizer.key('Rai 4'), isNot(NameNormalizer.key('Rai 1')));
  });

  test('prefisso di categoria riconosciuto come etichetta', () {
    final mapping = ChannelMapping.fromJson({
      'channels': [
        {'number': 101, 'name': 'Rai 1', 'group': 'A'},
        {'number': 102, 'name': 'Rai 2', 'group': 'A'},
        {'number': 103, 'name': 'Rai 3', 'group': 'A'},
      ],
    });
    final list = const ChannelMatcher().build(
      mapping: mapping,
      streams: const [
        XtreamLiveStream(streamId: 1, name: 'RAI | RAI 1 FHD'),
        XtreamLiveStream(streamId: 2, name: 'RAI | RAI 2 FHD'),
        XtreamLiveStream(streamId: 3, name: 'RAI | RAI 3 FHD'),
      ],
    );
    expect(list.map((c) => c.sources.single.streamId), [1, 2, 3]);
  });

  test('formato del provider: "Rai 1 HEVC ( hermes )"', () {
    final mapping = ChannelMapping.fromJson({
      'channels': [
        {'number': 101, 'name': 'Rai 1', 'group': 'A'},
        {'number': 102, 'name': 'Rai 2', 'group': 'A'},
      ],
    });
    final list = const ChannelMatcher().build(
      mapping: mapping,
      streams: const [
        XtreamLiveStream(streamId: 1, name: 'Rai 1 FHD'),
        XtreamLiveStream(streamId: 2, name: 'Rai 1 HEVC ( hermes )'),
        XtreamLiveStream(streamId: 3, name: 'Rai 1 ( hermes + )'),
        XtreamLiveStream(streamId: 4, name: 'Rai 2 HEVC ( hermes )'),
      ],
    );
    expect(list.map((c) => c.number), [101, 102]);
    expect(list[0].sources.map((s) => s.streamId), [3, 2, 1]);
    expect(list[1].sources.single.streamId, 4);
  });

  group('Fonti multiple', () {
    final mapping = ChannelMapping.fromJson({
      'channels': [
        {'number': 101, 'name': 'Rai 1', 'group': 'A'},
        {'number': 102, 'name': 'Rai 2', 'group': 'A'},
        {'number': 108, 'name': 'Sky Uno', 'group': 'A'},
        {'number': 109, 'name': 'Sky Uno +1', 'group': 'A'},
        {'number': 301, 'name': 'Sky Cinema Uno', 'group': 'B'},
      ],
    });
    const streams = [
      XtreamLiveStream(streamId: 1, name: 'IT: Rai 1 FHD'),
      XtreamLiveStream(streamId: 2, name: 'HERMES + RAI 1 HD'),
      XtreamLiveStream(streamId: 3, name: 'IT: Rai 2 HD'),
      XtreamLiveStream(streamId: 4, name: 'Hermes+ Rai 2'),
      XtreamLiveStream(streamId: 5, name: 'IT: Sky Uno FHD'),
      XtreamLiveStream(streamId: 6, name: 'HERMES + SKY UNO'),
      XtreamLiveStream(streamId: 7, name: 'IT: Sky Uno +1'),
      XtreamLiveStream(streamId: 8, name: 'DAZN | Sky Cinema Uno'),
      XtreamLiveStream(streamId: 9, name: 'HERMES + SKY CINEMA UNO 4K'),
      XtreamLiveStream(streamId: 10, name: 'Sky Uno Mix'),
    ];

    test('ogni canale compare una volta, con "hermes +" come principale', () {
      final list = const ChannelMatcher().build(
        mapping: mapping,
        streams: streams,
      );
      expect(list.map((c) => c.number), [101, 102, 108, 109, 301]);
      expect(list[0].sources.map((s) => s.streamId), [2, 1]);
      expect(list[0].sources.first.preferred, isTrue);
      expect(list[1].sources.map((s) => s.streamId), [4, 3]);
      expect(list[2].sources.map((s) => s.streamId), [6, 5]);
      // "+1" è un altro canale, non una fonte di Sky Uno.
      expect(list[3].sources.single.streamId, 7);
      expect(list[4].sources.first.streamId, 9);
    });

    test('lista rigida: niente canali fuori lista per impostazione', () {
      final list = const ChannelMatcher().build(
        mapping: mapping,
        streams: streams,
      );
      expect(list.every((c) => c.mapped), isTrue);
      expect(list.length, 5);
    });

    test('fuori lista, se attivati, senza doppioni', () {
      final list = const ChannelMatcher().build(
        mapping: mapping,
        streams: const [
          ...streams,
          XtreamLiveStream(streamId: 20, name: 'IT: Canale Locale HD'),
          XtreamLiveStream(streamId: 21, name: 'IT: Canale Locale SD'),
        ],
        showUnmapped: true,
      );
      final extra = list.where((c) => !c.mapped).map((c) => c.name).toList();
      expect(extra.where((n) => n.contains('Canale Locale')).length, 1);
    });
  });

  test('la lista integrata Sky è valida', () {
    final json = jsonDecode(
      File('assets/channels/sky_italia.json').readAsStringSync(),
    );
    final m = ChannelMapping.fromJson((json as Map).cast());
    expect(m.channels.length, greaterThan(100));
    expect(m.channels.first.number, 100);
    expect(m.channels.map((c) => c.number).toSet().length, m.channels.length);
    expect(
      m.channels.firstWhere((c) => c.number == 101).logo,
      startsWith('https://'),
    );
  });

  group('XtreamCredentials', () {
    test('normalizza il server', () {
      expect(
        XtreamCredentials.normalizeServer('dominio.tv:8080/'),
        'http://dominio.tv:8080',
      );
      expect(
        XtreamCredentials.normalizeServer('https://dominio.tv/player_api.php'),
        'https://dominio.tv',
      );
    });

    test('estrae credenziali da un link M3U', () {
      final c = XtreamCredentials.tryParseLink(
        'http://dominio.tv:8080/get.php?username=mario&password=segreta&type=m3u_plus',
      )!;
      expect(c.serverUrl, 'http://dominio.tv:8080');
      expect(c.username, 'mario');
      expect(c.password, 'segreta');
    });
  });
}
