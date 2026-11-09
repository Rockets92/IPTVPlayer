import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/data/mapping/channel_mapping.dart';
import 'package:iptv_player/data/xtream/xtream_models.dart';
import 'package:iptv_player/domain/channel_matcher.dart';

/// L'abbinamento canali gira in un isolate all'avvio: lista integrata,
/// stream e canali risultanti devono poter passare da un isolate all'altro.
void main() {
  test('abbinamento in isolate uguale a quello diretto', () async {
    final mapping = ChannelMapping.fromJson(
      jsonDecode(File('assets/channels/sky_italia.json').readAsStringSync())
          as Map<String, Object?>,
    );
    var id = 1;
    final streams = [
      for (final c in mapping.channels.take(60))
        for (final src in ['hermes', 'sat-stella'])
          XtreamLiveStream(
            streamId: id++,
            name: '${c.name} FHD ( $src )',
            categoryId: '1',
          ),
      const XtreamLiveStream(streamId: 9999, name: 'Altro', categoryId: '2'),
    ];
    const cats = {'1': '★ TV SAT FHD', '2': 'Varie'};
    final direct = ChannelMatcher().build(
      mapping: mapping,
      streams: streams,
      categoryNames: cats,
    );
    final viaIsolate = await Isolate.run(
      () => ChannelMatcher().build(
        mapping: mapping,
        streams: streams,
        categoryNames: cats,
      ),
    );
    expect(viaIsolate, isNotEmpty);
    expect(
      [for (final c in viaIsolate) '${c.number} ${c.id} ${c.sources.length}'],
      [for (final c in direct) '${c.number} ${c.id} ${c.sources.length}'],
    );
  });
}
