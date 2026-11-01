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
