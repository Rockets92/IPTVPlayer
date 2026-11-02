import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_player/data/m3u/m3u_client.dart';
import 'package:iptv_player/data/xtream/xtream_models.dart';

void main() {
  test('playlist M3U: canali live, gruppi, loghi e guida', () {
    const text = '''
#EXTM3U url-tvg="http://epg.example/guide.xml.gz"
#EXTINF:-1 tvg-id="Rai1.it" tvg-name="Rai 1" tvg-logo="http://l/rai1.png" group-title="Generalisti",Rai 1 HD
http://host/live/u/p/1.ts
#EXTINF:-1 tvg-id="" group-title="Sport, Calcio",DAZN 1, FHD
#EXTGRP:Ignorato
http://host/live/u/p/2.m3u8
#EXTINF:-1 group-title="Film",Il Gladiatore
http://host/movie/u/p/99.mkv
#EXTINF:-1,Senza gruppo
#EXTVLCOPT:http-user-agent=VLC
rtmp://host/app/stream
''';
    final p = M3uPlaylist.parse(text);
    expect(p.epgUrl, 'http://epg.example/guide.xml.gz');
    expect(p.streams.map((s) => s.name), [
      'Rai 1 HD',
      'DAZN 1, FHD',
      'Senza gruppo',
    ]);
    final rai = p.streams.first;
    expect(rai.epgChannelId, 'Rai1.it');
    expect(rai.icon, 'http://l/rai1.png');
    expect(rai.categoryId, 'Generalisti');
    expect(rai.url, 'http://host/live/u/p/1.ts');
    expect(p.streams[1].categoryId, 'Sport, Calcio');
    expect(p.streams[1].epgChannelId, isNull);
    expect(p.streams[2].categoryId, isNull);
    expect(p.streams[2].url, 'rtmp://host/app/stream');
    expect(p.streams.map((s) => s.streamId).toSet().length, 3);
  });

  test('credenziali M3U: salvataggio e ripristino', () {
    const c = XtreamCredentials.m3u(
      'http://host/list.m3u',
      epgUrl: 'http://host/epg.xml',
    );
    final back = XtreamCredentials.fromJson(c.toJson());
    expect(back, c);
    expect(back.isM3u, isTrue);
    expect(
      XtreamCredentials.fromJson(
        const XtreamCredentials(
          serverUrl: 'http://x',
          username: 'u',
          password: 'p',
        ).toJson(),
      ).isM3u,
      isFalse,
    );
  });
}
