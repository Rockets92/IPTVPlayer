import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:iptv_player/data/xtream/xtream_client.dart';
import 'package:iptv_player/data/xtream/xtream_models.dart';

void main() {
  test(
    '503 a un client sconosciuto: riprova con un altro User-Agent',
    () async {
      final seen = <String>[];
      final client = XtreamClient(
        const XtreamCredentials(
          serverUrl: 'http://example.test',
          username: 'u',
          password: 'p',
        ),
        httpClient: MockClient((req) async {
          final ua = req.headers['User-Agent'] ?? '';
          seen.add(ua);
          if (!ua.startsWith('okhttp')) return http.Response('', 503);
          return http.Response(
            '{"user_info":{"auth":1,"status":"Active"},"server_info":{}}',
            200,
          );
        }),
      );
      final info = await client.authenticate();
      expect(info.status, 'Active');
      expect(seen.last, startsWith('okhttp'));
      expect(XtreamClient.userAgent, startsWith('okhttp'));
    },
  );
}
