import 'dart:async';

/// Lavori pesanti in memoria (download e decodifica di elenchi grandi,
/// lettura e scrittura delle cache).
///
/// Nel profilo light vengono eseguiti uno alla volta: all'avvio, o aprendo
/// la Home che carica film e serie, più elenchi da decine di MB decodificati
/// insieme sommano i loro picchi di memoria e sui dispositivi da 1–2 GB il
/// sistema chiude l'app. In fila il risultato è identico, con un picco
/// pari al solo lavoro più grande.
abstract final class HeavyWork {
  /// Attivato all'avvio per il profilo light.
  static bool serialize = false;

  static Future<void> _tail = Future.value();

  static Future<T> run<T>(Future<T> Function() task) {
    if (!serialize) return task();
    final done = Completer<void>();
    final previous = _tail;
    _tail = done.future;
    return previous.then((_) => task()).whenComplete(done.complete);
  }
}
