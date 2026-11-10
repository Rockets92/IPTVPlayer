import 'dart:convert';
import 'dart:typed_data';

/// Helper tolleranti: i pannelli Xtream restituiscono spesso numeri come
/// stringhe, `null` come stringa vuota, booleani come "0"/"1".
int? asInt(Object? v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v.trim());
  return null;
}

String asString(Object? v, [String fallback = '']) {
  if (v == null) return fallback;
  if (v is String) return v;
  return v.toString();
}

String? asNonEmptyString(Object? v) {
  final s = asString(v).trim();
  return s.isEmpty ? null : s;
}

bool asBool(Object? v) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) return v == '1' || v.toLowerCase() == 'true';
  return false;
}

/// Scorre gli elementi di un array JSON di primo livello direttamente dai
/// byte UTF-8, decodificandone uno alla volta.
///
/// Gli elenchi dei pannelli (film, serie, canali) arrivano a decine di MB:
/// decodificarli in un colpo solo crea una copia testuale dell'intera
/// risposta e un albero di mappe molte volte più grande del file. Qui in
/// memoria resta soltanto l'elemento corrente: sui dispositivi da 1–2 GB
/// è la differenza tra caricare il catalogo ed essere chiusi dal sistema.
///
/// Se il documento non è un array, [onElement] riceve una sola volta il
/// valore decodificato per intero (stesso esito di `jsonDecode`) e la
/// funzione restituisce `false`.
bool forEachJsonArrayElement(
  Uint8List bytes,
  void Function(Object? element) onElement,
) {
  const decoder = Utf8Decoder(allowMalformed: true);
  final n = bytes.length;
  var i = 0;
  // BOM UTF-8 e spazi iniziali.
  if (n >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
    i = 3;
  }
  while (i < n && _isJsonSpace(bytes[i])) {
    i++;
  }
  if (i >= n || bytes[i] != 0x5B /* [ */ ) {
    onElement(jsonDecode(decoder.convert(bytes, i)));
    return false;
  }
  i++;
  var depth = 0;
  var inString = false;
  var start = -1;
  for (; i < n; i++) {
    final b = bytes[i];
    if (inString) {
      if (b == 0x5C /* \ */ ) {
        i++;
      } else if (b == 0x22 /* " */ ) {
        inString = false;
      }
      continue;
    }
    switch (b) {
      case 0x22:
        inString = true;
        if (start < 0) start = i;
      case 0x7B || 0x5B: // { [
        depth++;
        if (start < 0) start = i;
      case 0x7D || 0x5D: // } ]
        if (depth == 0) {
          // Fine dell'array di primo livello.
          if (b == 0x5D) {
            if (start >= 0) {
              onElement(jsonDecode(decoder.convert(bytes, start, i)));
            }
            return true;
          }
          throw const FormatException('JSON non valido');
        }
        depth--;
      case 0x2C: // ,
        if (depth == 0) {
          if (start < 0) throw const FormatException('JSON non valido');
          onElement(jsonDecode(decoder.convert(bytes, start, i)));
          start = -1;
        }
      default:
        if (start < 0 && !_isJsonSpace(b)) start = i;
    }
  }
  throw const FormatException('JSON troncato');
}

bool _isJsonSpace(int b) => b == 0x20 || b == 0x0A || b == 0x0D || b == 0x09;
