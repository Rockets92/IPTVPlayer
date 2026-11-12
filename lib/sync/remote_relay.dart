import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../remote/remote_server.dart';

/// Telecomando unico: il telefono, con l'account, vede tutti i dispositivi
/// accesi e manda i comandi passando dal cloud (anche fuori casa).
///
/// Canali privati (accessibili solo all'account, vedi
/// `supabase/migrations/0002_remote_favorites_games.sql`):
/// - `remote:<utente>`: presenza, cioè quali dispositivi sono accesi;
/// - `remote:<utente>:<dispositivo>`: richieste (`req`) e risposte (`res`)
///   per un solo dispositivo, con gli stessi comandi del telecomando in
///   rete locale ([RemoteServer.remoteApi]).
class RemoteRelay {
  RemoteRelay(this.server);

  final RemoteServer server;

  SupabaseClient? _client;
  RealtimeChannel? _lobby;
  RealtimeChannel? _mine;

  bool get running => _mine != null;

  /// Stato del collegamento, mostrato in Impostazioni → Account.
  final status = ValueNotifier<String>('');

  void _status(String what, RealtimeSubscribeStatus s, Object? error) {
    status.value = switch (s) {
      RealtimeSubscribeStatus.subscribed => 'Telecomando unico attivo',
      RealtimeSubscribeStatus.timedOut =>
        'Telecomando unico: il cloud non risponde, riprovo…',
      RealtimeSubscribeStatus.channelError =>
        'Telecomando unico non disponibile ($what): ${error ?? 'errore'}',
      RealtimeSubscribeStatus.closed => '',
    };
    if (error != null) debugPrint('telecomando cloud $what: $s $error');
  }

  Future<void> start(
    SupabaseClient c, {
    required String deviceId,
    required String name,
    required String kind,
  }) async {
    await stop();
    final uid = c.auth.currentUser?.id;
    if (uid == null) return;
    _client = c;
    status.value = 'Telecomando unico: collegamento…';
    // I canali privati vogliono il token dell'utente già al primo ingresso.
    final token = c.auth.currentSession?.accessToken;
    if (token != null) await c.realtime.setAuth(token);
    final lobby = c.channel(
      'remote:$uid',
      opts: RealtimeChannelConfig(private: true, key: deviceId),
    );
    _lobby = lobby;
    lobby.subscribe((status, error) {
      if (status == RealtimeSubscribeStatus.subscribed) {
        unawaited(
          lobby
              .track({'device': deviceId, 'name': name, 'kind': kind})
              .catchError((Object _) => ChannelResponse.error),
        );
      }
      _status('presenza', status, error);
    });
    final mine = c.channel(
      'remote:$uid:$deviceId',
      opts: const RealtimeChannelConfig(private: true),
    );
    _mine = mine;
    mine
        .onBroadcast(event: 'req', callback: (m) => unawaited(_onRequest(m)))
        .subscribe((s, error) {
          if (s != RealtimeSubscribeStatus.subscribed) {
            _status('comandi', s, error);
          }
        });
  }

  Future<void> _onRequest(Map<String, dynamic> m) async {
    final raw = m['payload'];
    final p = raw is Map ? Map<String, dynamic>.from(raw) : m;
    final id = p['id'];
    final path = '${p['path'] ?? ''}';
    if (id == null || !RemoteServer.remotePaths.contains(path)) return;
    final q = p['query'];
    final b = p['body'];
    Object? out;
    try {
      out = await server.remoteApi(
        '${p['method'] ?? 'GET'}',
        path,
        query: q is Map
            ? q.map((k, v) => MapEntry('$k', '$v'))
            : const <String, String>{},
        body: b is Map
            ? b.map((k, v) => MapEntry('$k', v as Object?))
            : const <String, Object?>{},
      );
    } catch (e) {
      out = {'error': '$e'};
    }
    try {
      await _mine?.sendBroadcastMessage(
        event: 'res',
        payload: {'id': id, 'data': out},
      );
    } catch (_) {}
  }

  Future<void> stop() async {
    final c = _client;
    for (final ch in [_lobby, _mine]) {
      if (ch == null) continue;
      try {
        await c?.removeChannel(ch);
      } catch (_) {}
    }
    _lobby = null;
    _mine = null;
    _client = null;
    status.value = '';
  }
}
