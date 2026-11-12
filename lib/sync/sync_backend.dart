import 'dart:async';

/// Tabelle sincronizzate con l'account.
enum SyncTable {
  /// Promemoria dei programmi (id = [Reminder.id]).
  reminders,

  /// "Continua a guardare" di film e serie (id = `m:<id>` / `s:<id>`).
  vodProgress,

  /// Preferenze personali (id = chiave della preferenza).
  prefs,
}

/// Una riga sincronizzata: il contenuto è il JSON già usato in locale.
/// Una riga cancellata resta come "lapide" ([deleted]) con la sua data,
/// così la cancellazione raggiunge anche i dispositivi spenti.
class SyncRecord {
  const SyncRecord({
    required this.table,
    required this.id,
    required this.updatedAt,
    this.data,
    this.deleted = false,
  });

  final SyncTable table;
  final String id;

  /// Ultima modifica, millisecondi epoch: vince la più recente.
  final int updatedAt;
  final Object? data;
  final bool deleted;

  @override
  String toString() =>
      'SyncRecord(${table.name}/$id @$updatedAt${deleted ? ' deleted' : ''})';
}

/// Il servizio cloud che conserva i dati dell'account. L'app parla solo con
/// questa interfaccia: oggi Supabase, domani eventualmente un server proprio
/// (es. PocketBase) senza toccare il resto del codice.
abstract interface class SyncBackend {
  /// Righe arrivate al server dopo [cursor] (0 = tutto) e il nuovo cursore
  /// da passare alla richiesta successiva. Il cursore è l'orologio del
  /// server, non quello del dispositivo: un orologio sbagliato su una TV non
  /// fa perdere modifiche.
  Future<({List<SyncRecord> records, int cursor})> pull({int cursor = 0});

  /// Invia le modifiche fatte su questo dispositivo. Il server tiene, per
  /// ogni riga, la versione con [SyncRecord.updatedAt] più recente.
  Future<void> push(List<SyncRecord> records);

  /// Modifiche fatte dagli altri dispositivi, in tempo reale.
  Stream<SyncRecord> get changes;
}

/// Backend in memoria, per i test e per provare la sincronizzazione senza
/// rete: più dispositivi possono condividere la stessa istanza.
class MemorySyncBackend implements SyncBackend {
  final _rows = <(SyncTable, String), (SyncRecord, int)>{};
  final _controller = StreamController<SyncRecord>.broadcast();
  int _seq = 0;

  @override
  Future<({List<SyncRecord> records, int cursor})> pull({
    int cursor = 0,
  }) async => (
    records: [
      for (final (r, seq) in _rows.values)
        if (seq > cursor) r,
    ],
    cursor: _seq,
  );

  @override
  Future<void> push(List<SyncRecord> records) async {
    for (final r in records) {
      final k = (r.table, r.id);
      final old = _rows[k];
      if (old != null && old.$1.updatedAt >= r.updatedAt) continue;
      _rows[k] = (r, ++_seq);
      _controller.add(r);
    }
  }

  @override
  Stream<SyncRecord> get changes => _controller.stream;

  Future<void> close() => _controller.close();
}
