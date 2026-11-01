import 'package:flutter/foundation.dart';

import '../json_utils.dart';

@immutable
class XtreamCredentials {
  const XtreamCredentials({
    required this.serverUrl,
    required this.username,
    required this.password,
  });

  /// URL base normalizzato, es. `http://dominio.tv:8080` (senza slash finale).
  final String serverUrl;
  final String username;
  final String password;

  Map<String, Object?> toJson() => {
    'serverUrl': serverUrl,
    'username': username,
    'password': password,
  };

  factory XtreamCredentials.fromJson(Map<String, Object?> json) =>
      XtreamCredentials(
        serverUrl: asString(json['serverUrl']),
        username: asString(json['username']),
        password: asString(json['password']),
      );

  /// Normalizza ciò che l'utente digita come server.
  ///
  /// Accetta `dominio:8080`, `http://dominio:8080/`, oppure un link completo
  /// `.../player_api.php?...` / `.../get.php?...`.
  static String normalizeServer(String input) {
    var s = input.trim();
    if (s.isEmpty) return s;
    if (!s.contains('://')) s = 'http://$s';
    final uri = Uri.tryParse(s);
    if (uri == null || uri.host.isEmpty) return s;
    final segments = uri.pathSegments.where((p) => p.isNotEmpty).toList();
    if (segments.isNotEmpty &&
        const {
          'player_api.php',
          'get.php',
          'xmltv.php',
          'panel_api.php',
        }.contains(segments.last)) {
      segments.removeLast();
    }
    final path = segments.isEmpty ? '' : '/${segments.join('/')}';
    final port = uri.hasPort ? ':${uri.port}' : '';
    return '${uri.scheme}://${uri.host}$port$path';
  }

  /// Estrae credenziali da un link M3U/Xtream completo, se presenti.
  static XtreamCredentials? tryParseLink(String input) {
    final s = input.trim();
    if (!s.contains('username=') || !s.contains('password=')) return null;
    final uri = Uri.tryParse(s.contains('://') ? s : 'http://$s');
    if (uri == null) return null;
    final user = uri.queryParameters['username'];
    final pass = uri.queryParameters['password'];
    if (user == null || pass == null || user.isEmpty) return null;
    return XtreamCredentials(
      serverUrl: normalizeServer(s.split('?').first),
      username: user,
      password: pass,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is XtreamCredentials &&
      other.serverUrl == serverUrl &&
      other.username == username &&
      other.password == password;

  @override
  int get hashCode => Object.hash(serverUrl, username, password);
}

@immutable
class XtreamAccountInfo {
  const XtreamAccountInfo({
    required this.status,
    this.expiresAt,
    this.maxConnections,
    this.activeConnections,
    this.allowedFormats = const [],
    this.isTrial = false,
  });

  final String status;
  final DateTime? expiresAt;
  final int? maxConnections;
  final int? activeConnections;
  final List<String> allowedFormats;
  final bool isTrial;

  bool get isActive => status.toLowerCase() == 'active';

  factory XtreamAccountInfo.fromJson(Map<String, Object?> json) {
    final exp = asInt(json['exp_date']);
    final formats = json['allowed_output_formats'];
    return XtreamAccountInfo(
      status: asString(json['status'], 'Unknown'),
      expiresAt: exp == null || exp == 0
          ? null
          : DateTime.fromMillisecondsSinceEpoch(exp * 1000),
      maxConnections: asInt(json['max_connections']),
      activeConnections: asInt(json['active_cons']),
      allowedFormats: formats is List
          ? formats.map((e) => asString(e)).toList()
          : const [],
      isTrial: asBool(json['is_trial']),
    );
  }

  Map<String, Object?> toJson() => {
    'status': status,
    'exp_date': expiresAt == null
        ? null
        : expiresAt!.millisecondsSinceEpoch ~/ 1000,
    'max_connections': maxConnections,
    'active_cons': activeConnections,
    'allowed_output_formats': allowedFormats,
    'is_trial': isTrial ? '1' : '0',
  };
}

@immutable
class XtreamCategory {
  const XtreamCategory(this.id, this.name);
  final String id;
  final String name;

  factory XtreamCategory.fromJson(Map<String, Object?> json) => XtreamCategory(
    asString(json['category_id']),
    asString(json['category_name']).trim(),
  );
}

@immutable
class XtreamLiveStream {
  const XtreamLiveStream({
    required this.streamId,
    required this.name,
    this.icon,
    this.epgChannelId,
    this.categoryId,
    this.number,
  });

  final int streamId;
  final String name;
  final String? icon;
  final String? epgChannelId;
  final String? categoryId;
  final int? number;

  static XtreamLiveStream? tryFromJson(Map<String, Object?> json) {
    final id = asInt(json['stream_id']);
    if (id == null) return null;
    return XtreamLiveStream(
      streamId: id,
      name: asString(json['name']).trim(),
      icon: asNonEmptyString(json['stream_icon']),
      epgChannelId: asNonEmptyString(json['epg_channel_id']),
      categoryId: asNonEmptyString(json['category_id']),
      number: asInt(json['num']),
    );
  }
}

class XtreamException implements Exception {
  const XtreamException(this.message);
  final String message;
  @override
  String toString() => message;
}
