import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'channel_mapping.dart';

/// Carica la mappatura canali.
///
/// Oggi la sorgente predefinita è il JSON integrato; impostando un URL
/// (http/https) o un percorso locale la stessa struttura viene letta da lì.
/// L'ultima versione remota valida viene salvata in cache così l'app
/// parte anche offline.
class MappingRepository {
  MappingRepository({http.Client? httpClient}) : _http = httpClient ?? http.Client();

  static const bundledAsset = 'assets/channels/sky_italia.json';

  /// URL predefinito impostabile in build: `--dart-define=MAPPING_URL=...`.
  static const defaultRemoteUrl = String.fromEnvironment('MAPPING_URL');

  final http.Client _http;

  Future<File> _cacheFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}channel_mapping.json');
  }

  Future<ChannelMapping> load({String? source}) async {
    final src = (source == null || source.trim().isEmpty)
        ? defaultRemoteUrl
        : source.trim();
    if (src.isNotEmpty) {
      try {
        final text = await _readSource(src);
        final mapping = _parse(text);
        await _writeCache(text);
        final isRemote = src.startsWith('http');
        return mapping.withOrigin(isRemote ? 'remota' : 'file locale');
      } catch (_) {
        final cached = await _readCache();
        if (cached != null) return cached.withOrigin('cache (sorgente non raggiungibile)');
      }
    }
    final text = await rootBundle.loadString(bundledAsset);
    return _parse(text).withOrigin('integrata');
  }

  Future<String> _readSource(String src) async {
    if (src.startsWith('http://') || src.startsWith('https://')) {
      final res = await _http
          .get(Uri.parse(src))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) {
        throw HttpException('HTTP ${res.statusCode}');
      }
      return utf8.decode(res.bodyBytes);
    }
    final path = src.startsWith('file://') ? Uri.parse(src).toFilePath() : src;
    return File(path).readAsString();
  }

  ChannelMapping _parse(String text) {
    final json = jsonDecode(text);
    if (json is! Map) throw const FormatException('JSON non valido');
    return ChannelMapping.fromJson(json.cast<String, Object?>());
  }

  Future<void> _writeCache(String text) async {
    try {
      final f = await _cacheFile();
      await f.parent.create(recursive: true);
      await f.writeAsString(text, flush: true);
    } catch (_) {}
  }

  Future<ChannelMapping?> _readCache() async {
    try {
      final f = await _cacheFile();
      if (!await f.exists()) return null;
      return _parse(await f.readAsString());
    } catch (_) {
      return null;
    }
  }
}
