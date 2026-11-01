/// Normalizzazione dei nomi canale per confrontare liste diverse.
///
/// `"IT: Sky Uno +1 FHD"` → `skyunoplus1`, `"|IT| RAI 1 HD"` → `rai1`.
abstract final class NameNormalizer {
  static final _prefix = RegExp(
    r'^\s*(?:[\[\(|]\s*)?(?:it|ita|italy|italia|ʟɪᴠᴇ)\s*(?:[\]\)|:\-▎•]\s*)+',
    caseSensitive: false,
  );
  static final _suffixCountry = RegExp(r'[\(\[]\s*(?:it|ita)\s*[\)\]]', caseSensitive: false);
  static final _nonAlnum = RegExp(r'[^a-z0-9]+');

  /// Token che descrivono qualità/codec/varianti tecniche, non il canale.
  static const _noise = {
    'hd', 'fhd', 'uhd', 'sd', 'hq', 'lq', '4k', '8k', 'hdr', 'hevc', 'h264',
    'h265', 'x265', '1080', '1080p', '720', '720p', '576p', '50fps', '60fps',
    'fps', 'backup', 'bk', 'alt', 'vip', 'raw', 'multi', 'ita', 'it',
    'live', 'tv', 'channel', 'hdtv',
  };

  /// Simboli "fantasia" usati da alcuni provider (ᴴᴰ, ᶠᴴᴰ, ⁴ᴷ...).
  static final _fancy = RegExp(r'[ᴀ-ᶿʰ-˿⁰-₟]+');

  static const _accents = {
    'à': 'a', 'á': 'a', 'â': 'a', 'ä': 'a', 'è': 'e', 'é': 'e', 'ê': 'e',
    'ë': 'e', 'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ò': 'o', 'ó': 'o',
    'ô': 'o', 'ö': 'o', 'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ç': 'c',
    'ñ': 'n',
  };

  static String _strip(String raw) {
    var s = raw.toLowerCase();
    s = s.replaceAll(_fancy, ' ');
    s = s.replaceFirst(_prefix, '');
    s = s.replaceAll(_suffixCountry, ' ');
    final b = StringBuffer();
    for (final rune in s.runes) {
      final ch = String.fromCharCode(rune);
      b.write(_accents[ch] ?? ch);
    }
    s = b.toString().replaceAll('+', ' plus ').replaceAll('&', ' and ');
    return s;
  }

  static List<String> tokens(String raw) => _strip(raw)
      .split(_nonAlnum)
      .where((t) => t.isNotEmpty && !_noise.contains(t))
      .toList();

  /// Chiave compatta usata per i confronti.
  static String key(String raw) {
    final t = tokens(raw);
    if (t.isEmpty) {
      // Nome composto solo da "rumore" (es. "TV"): si usa la forma grezza.
      return _strip(raw).replaceAll(_nonAlnum, '');
    }
    return t.join();
  }

  /// Punteggio per scegliere lo stream migliore tra più varianti.
  static int qualityScore(String raw, {bool preferLighter = false}) {
    final s = raw.toLowerCase();
    var score = 0;
    final has4k = s.contains('4k') || s.contains('uhd') || s.contains('2160');
    final hasFhd = s.contains('fhd') || s.contains('1080');
    final hasHd = RegExp(r'(^|[^a-z])hd([^a-z]|$)').hasMatch(s) ||
        s.contains('720') ||
        s.contains('ᴴᴰ');
    final hasSd = RegExp(r'(^|[^a-z])sd([^a-z]|$)').hasMatch(s);
    if (has4k) {
      score += preferLighter ? -20 : 15;
    } else if (hasFhd) {
      score += preferLighter ? 22 : 30;
    } else if (hasHd) {
      score += preferLighter ? 30 : 24;
    } else if (hasSd) {
      score += preferLighter ? 18 : 8;
    } else {
      score += 16;
    }
    if (s.contains('backup') || RegExp(r'\bbk\b').hasMatch(s)) score -= 6;
    if (s.contains('hevc') || s.contains('h265')) score += preferLighter ? -8 : 2;
    return score;
  }
}
