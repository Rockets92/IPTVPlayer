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

  test('qualityScore: FHD, poi HD, poi senza indicazione, poi SD', () {
    for (final light in [false, true]) {
      int q(String n) => NameNormalizer.qualityScore(n, preferLighter: light);
      expect(q('Rai 1 FHD'), greaterThan(q('Rai 1 HD')));
      expect(q('Rai 1 HEVC FHD'), greaterThan(q('Rai 1 HD')));
      expect(q('Rai 1 HD'), greaterThan(q('Rai 1')));
      expect(q('Rai 1'), greaterThan(q('Rai 1 SD')));
    }
    // Il 4K va in cima, ma non sui dispositivi leggeri.
    expect(
      NameNormalizer.qualityScore('Rai 1 4K'),
      greaterThan(NameNormalizer.qualityScore('Rai 1 FHD')),
    );
    expect(
      NameNormalizer.qualityScore('Rai 1 4K', preferLighter: true),
      lessThan(NameNormalizer.qualityScore('Rai 1 SD', preferLighter: true)),
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

  test('vetrina: canali al loro posto, con i canali collegati', () {
    final mapping = ChannelMapping.fromJson({
      'channels': [
        {'number': 101, 'name': 'Rai 1', 'group': 'A'},
      ],
      'unmappedChannels': {'show': true},
      'dynamicGroups': [
        {
          'name': 'Eventi',
          'startNumber': 800,
          'keywords': ['eventi'],
        },
        {
          'name': 'Vetrina',
          'startNumber': 870,
          'keywords': ['vetrina'],
        },
      ],
    });
    final list = const ChannelMatcher().build(
      mapping: mapping,
      streams: const [
        XtreamLiveStream(streamId: 1, name: 'Rai 1 FHD'),
        XtreamLiveStream(streamId: 2, name: 'Altro Canale'),
        XtreamLiveStream(streamId: 3, name: 'Vetrina Natura Cinematica FHD'),
        XtreamLiveStream(
          streamId: 4,
          name: 'Natura Cinematica 2 FHD ( hermes )',
        ),
        XtreamLiveStream(
          streamId: 5,
          name: 'Natura Cinematica 1 FHD ( hermes )',
        ),
        XtreamLiveStream(streamId: 6, name: 'Natura Cinematica 1 HD'),
        XtreamLiveStream(streamId: 7, name: 'Natura Cinematica Extra Show'),
        XtreamLiveStream(
          streamId: 8,
          name: 'Vetrina Natura Cinematica HD ( hermes )',
        ),
      ],
    );
    // Numeri nell'ordine della lista del provider, senza salti alla 870.
    expect(list.map((c) => c.number), [101, 1000, 1001, 1002, 1003, 1004]);
    final v = list.firstWhere((c) => c.inGroup('Vetrina'));
    expect(v.number, 1001);
    expect(v.sources.map((s) => s.streamId), [8, 3]);
    final linked = [
      for (final id in v.linked) list.firstWhere((c) => c.id == id),
    ];
    expect(linked.map((c) => c.name), [
      'Natura Cinematica 1',
      'Natura Cinematica 2',
    ]);
    expect(linked.first.sources.map((s) => s.streamId), [5, 6]);
    // Un nome che continua con altre parole non è collegato.
    expect(list.any((c) => c.name == 'Natura Cinematica Extra Show'), isTrue);
  });

  test('canali evento dall\'800: prima DAZN, poi "eventi", senza doppioni', () {
    final mapping = ChannelMapping.fromJson({
      'channels': [
        {'number': 101, 'name': 'Rai 1', 'group': 'A'},
        {'number': 214, 'name': 'Zona DAZN', 'group': 'Sport'},
      ],
    });
    final list = const ChannelMatcher().build(
      mapping: mapping,
      streams: const [
        XtreamLiveStream(streamId: 1, name: 'Rai 1 FHD'),
        XtreamLiveStream(streamId: 2, name: 'Zona DAZN HD'),
        XtreamLiveStream(streamId: 3, name: 'EVENTI 2 HD'),
        XtreamLiveStream(streamId: 4, name: 'DAZN 10 FHD'),
        XtreamLiveStream(streamId: 5, name: 'DAZN 2 HEVC ( hermes )'),
        XtreamLiveStream(streamId: 6, name: 'DAZN 2 FHD'),
        XtreamLiveStream(streamId: 7, name: 'Eventi 1 ( hermes )'),
        XtreamLiveStream(streamId: 8, name: 'Canale Locale'),
        XtreamLiveStream(streamId: 9, name: 'Benevento TV ( hermes )'),
        XtreamLiveStream(streamId: 10, name: 'Sport Events 3'),
        XtreamLiveStream(streamId: 11, name: 'Vetrina 2 HD'),
        XtreamLiveStream(streamId: 12, name: 'VETRINA 1 ( hermes )'),
      ],
    );
    // Le vetrine non vengono rinumerate: restano fuori lista (dal 1000)
    // e compaiono anche nella categoria Vetrina.
    final vt = list.where((c) => c.inGroup('Vetrina')).toList();
    expect(vt.every((c) => c.number >= 1000 && c.group != 'Vetrina'), isTrue);
    expect(vt.length, 2);
    final ev = list.where((c) => c.group == 'Eventi').toList();
    expect(ev.map((c) => c.number), [800, 801, 802, 803, 804]);
    expect(ev.map((c) => c.name), [
      'DAZN 2',
      'DAZN 10',
      'Eventi 1',
      'EVENTI 2',
      'Sport Events 3',
    ]);
    // "event" dentro una parola (Benevento) non conta.
    expect(ev.any((c) => c.name.contains('Benevento')), isFalse);
    expect(ev.first.sources.map((s) => s.streamId), [5, 6]);
    // Zona DAZN resta al suo numero, non finisce negli eventi.
    expect(list.firstWhere((c) => c.number == 214).sources.single.streamId, 2);
    expect(list.any((c) => c.name == 'Canale Locale'), isFalse);
  });

  test('nome del canale tra categoria e fonte', () {
    final mapping = ChannelMapping.fromJson({
      'dynamicGroups': [],
      'channels': [
        {'number': 301, 'name': 'Sky Cinema Uno', 'group': 'Cinema'},
        {'number': 302, 'name': 'Sky Cinema Due', 'group': 'Cinema'},
        {'number': 305, 'name': 'Sky Cinema Action', 'group': 'Cinema'},
        {'number': 310, 'name': 'Sky Cinema Uno +24', 'group': 'Cinema'},
      ],
    });
    final list = const ChannelMatcher().build(
      mapping: mapping,
      streams: const [
        XtreamLiveStream(
          streamId: 1,
          name: 'CINEMA | SKY CINEMA UNO ( hermes )',
        ),
        XtreamLiveStream(
          streamId: 2,
          name: 'CINEMA | SKY CINEMA DUE ( hermes )',
        ),
        XtreamLiveStream(
          streamId: 3,
          name: 'CINEMA | Sky Cinema Action HEVC ( hermes )',
        ),
        XtreamLiveStream(
          streamId: 4,
          name: 'CINEMA | Sky Cinema Uno +24 ( hermes )',
        ),
      ],
    );
    expect(list.map((c) => c.number), [301, 302, 305, 310]);
    expect(list.map((c) => c.sources.single.streamId), [1, 2, 3, 4]);
  });

  test('fonti tra parentesi diverse e alias con asterisco', () {
    final mapping = ChannelMapping.fromJson({
      'dynamicGroups': [],
      'channels': [
        {'number': 301, 'name': 'Sky Cinema Uno', 'group': 'Cinema'},
        {
          'number': 303,
          'name': 'Sky Cinema Collection',
          'group': 'Cinema',
          'aliases': ['Sky Cinema * Collection'],
        },
        {'number': 312, 'name': 'Sky Cinema Stories', 'group': 'Cinema'},
      ],
    });
    final list = const ChannelMatcher().build(
      mapping: mapping,
      streams: const [
        XtreamLiveStream(
          streamId: 1,
          name: 'Sky Cinema Uno FHD ( sat-stella )',
        ),
        XtreamLiveStream(streamId: 2, name: 'Sky Cinema Uno FHD ( hermes )'),
        XtreamLiveStream(
          streamId: 3,
          name: 'Sky Cinema Oscar Collection FHD ( sat-stella )',
        ),
        XtreamLiveStream(
          streamId: 4,
          name: 'Sky Cinema Stories FHD ( stellina )',
        ),
        XtreamLiveStream(
          streamId: 5,
          name: 'Sky Cinema Stories FHD ( sat-stella )',
        ),
        XtreamLiveStream(
          streamId: 6,
          name: 'Sky Cinema Stories FHD ( garantito )',
        ),
        XtreamLiveStream(streamId: 7, name: 'Telepace 3 FHD ( fls )'),
      ],
    );
    expect(list.map((c) => c.number), [301, 303, 312]);
    expect(list[0].sources.map((s) => s.streamId), [2, 1]);
    expect(list[1].sources.single.streamId, 3);
    expect(list[2].sources.length, 3);
  });

  test('versioni +1 fuori elenco collegate al canale originale', () {
    final mapping = ChannelMapping.fromJson({
      'dynamicGroups': [],
      'channels': [
        {'number': 105, 'name': 'Canale 5', 'group': 'A'},
        {'number': 108, 'name': 'Sky Uno', 'group': 'A'},
        {'number': 109, 'name': 'Sky Uno +1', 'group': 'A'},
        {'number': 301, 'name': 'Sky Cinema Uno', 'group': 'B'},
      ],
    });
    final list = const ChannelMatcher().build(
      mapping: mapping,
      showUnmapped: true,
      streams: const [
        XtreamLiveStream(streamId: 1, name: 'Canale 5 FHD ( sat-stella )'),
        XtreamLiveStream(streamId: 2, name: 'Canale 5 +1 FHD ( sat-stella )'),
        XtreamLiveStream(streamId: 3, name: 'Canale 5 +1 HD ( hermes )'),
        XtreamLiveStream(streamId: 4, name: 'Sky Uno FHD'),
        XtreamLiveStream(streamId: 5, name: 'Sky Uno +1 FHD'),
        XtreamLiveStream(streamId: 6, name: 'Sky Cinema Uno FHD'),
      ],
    );
    expect(list.map((c) => c.number), [105, 108, 109, 301]);
    final c5 = list[0];
    expect(c5.sources.single.streamId, 1);
    expect(c5.plusOne.map((s) => s.streamId), [3, 2]);
    expect(list[1].plusOneChannelId, 'm109');
    expect(list[2].baseChannelId, 'm108');
    expect(list[3].hasPlusOne, isFalse);
  });

  group('Fonti multiple', () {
    final mapping = ChannelMapping.fromJson({
      'dynamicGroups': [],
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

    test('fonti: prima hermes, poi FHD, HD e SD', () {
      for (final light in [false, true]) {
        final list = ChannelMatcher(preferLighterStreams: light).build(
          mapping: mapping,
          streams: const [
            XtreamLiveStream(streamId: 1, name: 'Rai 1 SD ( sat-stella )'),
            XtreamLiveStream(streamId: 2, name: 'Rai 1 HD ( stellina )'),
            XtreamLiveStream(streamId: 3, name: 'Rai 1 SD ( hermes )'),
            XtreamLiveStream(streamId: 4, name: 'Rai 1 FHD ( garantito )'),
            XtreamLiveStream(streamId: 5, name: 'Rai 1 FHD ( hermes )'),
            XtreamLiveStream(streamId: 6, name: 'Rai 1 HEVC FHD ( fls )'),
          ],
        );
        final rai1 = list.firstWhere((c) => c.number == 101);
        // Tra due FHD l'HEVC passa avanti solo sui dispositivi potenti.
        expect(
          rai1.sources.map((s) => s.streamId),
          light ? [5, 3, 4, 6, 2, 1] : [5, 3, 6, 4, 2, 1],
        );
      }
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

  group('canali per adulti', () {
    final mapping = ChannelMapping.fromJson({
      'channels': [
        {'number': 101, 'name': 'Rai 1', 'group': 'A'},
      ],
    });
    const streams = [
      XtreamLiveStream(streamId: 1, name: 'Rai 1 FHD', categoryId: '1'),
      XtreamLiveStream(streamId: 2, name: 'Hot Club HD', categoryId: '9'),
      XtreamLiveStream(
        streamId: 3,
        name: 'Hot Club FHD ( hermes )',
        categoryId: '9',
      ),
      XtreamLiveStream(streamId: 4, name: 'Eventi XXX 1', categoryId: '9'),
      XtreamLiveStream(streamId: 5, name: 'Eventi 1', categoryId: '1'),
    ];
    const cats = {'1': 'TV SAT FHD', '9': '★ XXX | ADULTI'};

    test('nascosti per impostazione predefinita', () {
      final list = const ChannelMatcher().build(
        mapping: mapping,
        streams: streams,
        categoryNames: cats,
        showUnmapped: true,
      );
      expect(list.any((c) => c.adult), isFalse);
      expect(
        list.expand((c) => c.sources).map((s) => s.streamId),
        isNot(anyOf(contains(2), contains(3), contains(4))),
      );
    });

    test('attivi: categoria XXX dal 900, una volta per canale', () {
      final list = const ChannelMatcher().build(
        mapping: mapping,
        streams: streams,
        categoryNames: cats,
        includeAdult: true,
      );
      final xxx = list.where((c) => c.group == 'XXX').toList();
      expect(xxx.every((c) => c.adult), isTrue);
      expect(xxx.first.number, 900);
      expect(xxx.map((c) => c.name), containsAll(['Hot Club', 'Eventi XXX 1']));
      expect(
        xxx
            .firstWhere((c) => c.name == 'Hot Club')
            .sources
            .map((s) => s.streamId),
        [3, 2],
      );
      // Gli stream XXX non finiscono negli Eventi.
      final ev = list.where((c) => c.group == 'Eventi');
      expect(ev.map((c) => c.name), ['Eventi 1']);
    });

    test('riconosce i nomi di categoria', () {
      expect(ChannelMatcher.isAdultCategory('XXX'), isTrue);
      expect(ChannelMatcher.isAdultCategory('IT | Adulti'), isTrue);
      expect(ChannelMatcher.isAdultCategory('Adult 18+'), isTrue);
      expect(ChannelMatcher.isAdultCategory('Sport'), isFalse);
      expect(ChannelMatcher.isAdultCategory(null), isFalse);
    });
  });
}
