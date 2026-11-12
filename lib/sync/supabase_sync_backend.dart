import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'sync_backend.dart';

/// [SyncBackend] su Supabase: tabella `sync_rows` (vedi
/// `supabase/migrations/0001_account_sync.sql`), protetta riga per riga così
/// che ogni account veda solo i propri dati.
class SupabaseSyncBackend implements SyncBackend {
  SupabaseSyncBackend(this._client);

  final SupabaseClient _client;
  RealtimeChannel? _channel;
  StreamController<SyncRecord>? _changes;

  static const _table = 'sync_rows';

  String get _uid => _client.auth.currentUser!.id;

  static SyncTable? _tableOf(Object? name) =>
      SyncTable.values.where((t) => t.name == name).firstOrNull;

  static SyncRecord? _record(Map<String, dynamic> row) {
    final t = _tableOf(row['table_name']);
    final id = row['id'];
    final u = row['updated_at'];
    if (t == null || id is! String || u is! num) return null;
    return SyncRecord(
      table: t,
      id: id,
      updatedAt: u.toInt(),
      data: row['data'],
      deleted: row['deleted'] == true,
    );
  }

  @override
  Future<({List<SyncRecord> records, int cursor})> pull({
    int cursor = 0,
  }) async {
    // Qualche secondo di margine: una riga scritta in contemporanea può
    // avere un orario appena precedente. I doppioni non fanno danni.
    final since = DateTime.fromMicrosecondsSinceEpoch(
      cursor > 5000000 ? cursor - 5000000 : 0,
      isUtc: true,
    ).toIso8601String();
    final out = <SyncRecord>[];
    var next = cursor;
    const page = 500;
    var from = 0;
    while (true) {
      final rows = await _client
          .from(_table)
          .select()
          .gt('server_at', since)
          .order('server_at')
          .range(from, from + page - 1);
      for (final row in rows) {
        final r = _record(row);
        if (r != null) out.add(r);
        final at = DateTime.tryParse('${row['server_at']}');
        if (at != null && at.microsecondsSinceEpoch > next) {
          next = at.microsecondsSinceEpoch;
        }
      }
      if (rows.length < page) break;
      from += page;
    }
    return (records: out, cursor: next);
  }

  @override
  Future<void> push(List<SyncRecord> records) async {
    final uid = _uid;
    for (var i = 0; i < records.length; i += 200) {
      final chunk = records.skip(i).take(200);
      await _client.from(_table).upsert([
        for (final r in chunk)
          {
            'user_id': uid,
            'table_name': r.table.name,
            'id': r.id,
            'data': r.deleted ? null : r.data,
            'deleted': r.deleted,
            'updated_at': r.updatedAt,
          },
      ], onConflict: 'user_id,table_name,id');
    }
  }

  @override
  Stream<SyncRecord> get changes {
    final c = _changes ??= StreamController<SyncRecord>.broadcast(
      onListen: _subscribe,
      onCancel: _unsubscribe,
    );
    return c.stream;
  }

  void _subscribe() {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return;
    _channel = _client
        .channel('sync:$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: _table,
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: uid,
          ),
          callback: (p) {
            final r = _record(p.newRecord);
            if (r != null) _changes?.add(r);
          },
        )
        .subscribe();
  }

  void _unsubscribe() {
    final ch = _channel;
    _channel = null;
    if (ch != null) unawaited(_client.removeChannel(ch));
  }
}
