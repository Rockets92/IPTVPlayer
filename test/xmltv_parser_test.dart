import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/data/epg/epg_models.dart';
import 'package:iptv_player/data/epg/xmltv_parser.dart';

const _xml = '''<?xml version="1.0" encoding="UTF-8"?>
<tv>
  <channel id="Rai1.it"><display-name>Rai 1</display-name></channel>
  <channel id="skyuno.x"><display-name lang="it">Sky Uno HD</display-name></channel>
  <channel id="other"><display-name>Altro</display-name></channel>
  <programme start="20261101180000 +0100" stop="20261101200000 +0100" channel="Rai1.it">
    <title lang="it">L&apos;Eredità</title>
    <desc lang="it">Quiz preserale.</desc>
    <category lang="it">Intrattenimento</category>
  </programme>
  <programme start="20261101200000 +0100" stop="20261101203000 +0100" channel="Rai1.it">
    <title><![CDATA[TG1]]></title>
  </programme>
  <programme start="20261101190000 +0100" stop="20261101210000 +0100" channel="skyuno.x">
    <title>MasterChef Italia</title>
  </programme>
  <programme start="20261101190000 +0100" stop="20261101210000 +0100" channel="other">
    <title>Ignorato</title>
  </programme>
  <programme start="20261201190000 +0100" stop="20261201210000 +0100" channel="Rai1.it">
    <title>Fuori finestra</title>
  </programme>
</tv>''';

void main() {
  test('parseXmltvTime gestisce il fuso', () {
    final t = parseXmltvTime('20261101180000 +0100')!;
    expect(
      DateTime.fromMillisecondsSinceEpoch(t * 1000, isUtc: true),
      DateTime.utc(2026, 11, 1, 17),
    );
    expect(
      parseXmltvTime('202611011800'),
      DateTime.utc(2026, 11, 1, 18).millisecondsSinceEpoch ~/ 1000,
    );
  });

  XmltvRequest req({Set<String> skip = const {}}) => XmltvRequest(
    idIndex: const {
      'rai1.it': ['m101'],
    },
    nameIndex: const {
      'sky1': ['m108'],
      'rai1': ['m101'],
    },
    windowStart: DateTime.utc(2026, 11, 1).millisecondsSinceEpoch ~/ 1000,
    windowEnd: DateTime.utc(2026, 11, 3).millisecondsSinceEpoch ~/ 1000,
    skip: skip,
  );

  test('associa per id e per display-name, rispetta la finestra', () async {
    final out = await parseXmltv(Stream.value(utf8.encode(_xml)), req());
    expect(out.keys.toSet(), {'m101', 'm108'});
    final rai = out['m101']!;
    expect(rai.map((p) => p.title), ["L'Eredità", 'TG1']);
    expect(rai.first.description, 'Quiz preserale.');
    expect(rai.first.category, 'Intrattenimento');
    expect(out['m108']!.single.title, 'MasterChef Italia');

    final schedule = EpgSchedule(out);
    final at = DateTime.utc(2026, 11, 1, 18, 30).toLocal();
    expect(schedule.nowOn('m101', at)!.title, "L'Eredità");
    expect(schedule.nextOn('m101', at)!.title, 'TG1');
  });

  test('legge file gzip e salta i canali già coperti', () async {
    final gz = gzip.encode(utf8.encode(_xml));
    final out = await parseXmltv(Stream.value(gz), req(skip: {'m101'}));
    expect(out.keys, ['m108']);
  });
}
