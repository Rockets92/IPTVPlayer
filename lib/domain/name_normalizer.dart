/// Normalizzazione dei nomi canale per confrontare liste diverse.
///
/// `"IT: Sky Uno +1 FHD"` → `skyunoplus1`, `"|IT| RAI 1 HD"` → `rai1`.
abstract final class NameNormalizer {
  static final _prefix = RegExp(
    r'^\s*(?:[\[\(|]\s*)?(?:it|ita|italy|italia|ʟɪᴠᴇ)\s*(?:[\]\)|:\-▎•]\s*)+',
    caseSensitive: false,
  );
  static final _suffixCountry = RegExp(
    r'[\(\[]\s*(?:it|ita)\s*[\)\]]',
    caseSensitive: false,
  );
  static final _nonAlnum = RegExp(r'[^a-z0-9]+');

  /// Token che descrivono qualità/codec/varianti tecniche, non il canale.
  static const _noise = {
    'hd',
    'fhd',
    'uhd',
    'sd',
    'hq',
    'lq',
    '4k',
    '8k',
    'hdr',
    'hevc',
    'h264',
    'h265',
    'x265',
    '1080',
    '1080p',
    '720',
    '720p',
    '576p',
    '50fps',
    '60fps',
    'fps',
    'backup',
    'bk',
    'alt',
    'vip',
    'raw',
    'multi',
    'ita',
    'it',
    'live',
    'tv',
    'channel',
    'hdtv',
  };

  /// Simboli "fantasia" usati da alcuni provider (ᴴᴰ, ᶠᴴᴰ, ⁴ᴷ...).
  static final _fancy = RegExp(r'[ᴀ-ᶿʰ-˿⁰-₟]+');

  static const _accents = {
    'à': 'a',
    'á': 'a',
    'â': 'a',
    'ä': 'a',
    'è': 'e',
    'é': 'e',
    'ê': 'e',
    'ë': 'e',
    'ì': 'i',
    'í': 'i',
    'î': 'i',
    'ï': 'i',
    'ò': 'o',
    'ó': 'o',
    'ô': 'o',
    'ö': 'o',
    'ù': 'u',
    'ú': 'u',
    'û': 'u',
    'ü': 'u',
    'ç': 'c',
    'ñ': 'n',
  };

  /// Numero di canale del provider davanti al nome: "101 - RAI 1", "05. Rai 3".
  static final _leadingNumber = RegExp(r'^\s*\d{1,4}\s*[\-|.:)\]▎•]+\s*');

  /// Numeri scritti in lettere, così "Rai Uno" e "Rai 1" coincidono.
  static const _numberWords = {
    'uno': '1',
    'due': '2',
    'tre': '3',
    'quattro': '4',
    'cinque': '5',
  };

  /// Maiuscoletto Unicode (ʀᴀɪ) → lettere normali.
  static const _smallCaps = {
    0x1D00: 'a', 0x0299: 'b', 0x1D04: 'c', 0x1D05: 'd', 0x1D07: 'e', //
    0xA730: 'f', 0x0262: 'g', 0x029C: 'h', 0x026A: 'i', 0x1D0A: 'j', //
    0x1D0B: 'k', 0x029F: 'l', 0x1D0D: 'm', 0x0274: 'n', 0x1D0F: 'o', //
    0x1D18: 'p', 0x01EB: 'q', 0x0280: 'r', 0xA731: 's', 0x1D1B: 't', //
    0x1D1C: 'u', 0x1D20: 'v', 0x1D21: 'w', 0x028F: 'y', 0x1D22: 'z',
  };

  /// Riporta a lettere e cifre normali gli alfabeti "decorativi" che molti
  /// provider usano nei nomi: 𝐑𝐀𝐈, 𝙍𝘼𝙄, ＲＡＩ, Ⓡⓐⓘ, 🅁🄰🄸, ʀᴀɪ, 𝟏.
  static String fold(String raw) {
    final b = StringBuffer();
    for (final cp in raw.runes) {
      b.write(_foldRune(cp) ?? String.fromCharCode(cp));
    }
    return b.toString();
  }

  static String? _foldRune(int cp) {
    if (cp < 0x80) return null;
    final sc = _smallCaps[cp];
    if (sc != null) return sc;
    String letter(int i) =>
        String.fromCharCode(i < 26 ? 0x41 + i : 0x61 + i - 26);
    // Lettere matematiche (grassetto, corsivo, sans, monospace...).
    if (cp >= 0x1D400 && cp <= 0x1D6A3) return letter((cp - 0x1D400) % 52);
    // Cifre matematiche.
    if (cp >= 0x1D7CE && cp <= 0x1D7FF) return '${(cp - 0x1D7CE) % 10}';
    // Larghezza piena.
    if (cp >= 0xFF01 && cp <= 0xFF5E) return String.fromCharCode(cp - 0xFEE0);
    // Lettere e cifre cerchiate.
    if (cp >= 0x24B6 && cp <= 0x24E9) return letter(cp - 0x24B6);
    if (cp >= 0x2460 && cp <= 0x2468) return '${cp - 0x2460 + 1}';
    if (cp == 0x24EA || cp == 0x24FF) return '0';
    if (cp >= 0x2776 && cp <= 0x277E) return '${cp - 0x2776 + 1}';
    // Lettere in quadrato o cerchio pieno (🄰 🅐 🅰).
    for (final base in const [0x1F130, 0x1F150, 0x1F170]) {
      if (cp >= base && cp < base + 26) return letter(cp - base);
    }
    // Bandiere (🇮🇹): non fanno parte del nome.
    if (cp >= 0x1F1E6 && cp <= 0x1F1FF) return ' ';
    return null;
  }

  static String _strip(String raw) {
    var s = fold(raw).toLowerCase();
    s = s.replaceAll(_fancy, ' ');
    for (var i = 0; i < 2; i++) {
      s = s.replaceFirst(_leadingNumber, '');
      s = s.replaceFirst(_prefix, '');
    }
    s = s.replaceAll(_suffixCountry, ' ');
    final b = StringBuffer();
    for (final rune in s.runes) {
      final ch = String.fromCharCode(rune);
      b.write(_accents[ch] ?? ch);
    }
    s = b.toString().replaceAll('+', ' plus ').replaceAll('&', ' and ');
    return s;
  }

  static List<String> tokens(String raw) =>
      _strip(raw)
          .split(_nonAlnum)
          .where((t) => t.isNotEmpty && !_noise.contains(t))
          .map((t) => _numberWords[t] ?? t)
          .toList();

  static final _trailingGroup = RegExp(r'\s*[\(\[][^\(\)\[\]]*[\)\]]\s*$');

  /// Nome senza le etichette finali tra parentesi, che nelle liste indicano
  /// quasi sempre la fonte: "Sky Cinema Uno FHD ( sat-stella )" →
  /// "Sky Cinema Uno FHD".
  static String baseName(String raw) {
    var s = raw;
    for (var i = 0; i < 3; i++) {
      final t = s.replaceFirst(_trailingGroup, '');
      if (t == s || t.trim().isEmpty) break;
      s = t;
    }
    return s;
  }

  /// Chiave compatta usata per i confronti.
  static String key(String raw) {
    final t = tokens(raw);
    if (t.isEmpty) {
      // Nome composto solo da "rumore" (es. "TV"): si usa la forma grezza.
      return _strip(raw).replaceAll(_nonAlnum, '');
    }
    return t.join();
  }

  /// Punteggio per ordinare le varianti di un canale (dopo le fonti
  /// preferite come "hermes"): FHD, poi HD, poi senza indicazione, poi SD.
  /// Il 4K va in cima, tranne sui dispositivi leggeri ([preferLighter]) dove
  /// finisce in fondo perché non riescono a decodificarlo.
  static int qualityScore(String raw, {bool preferLighter = false}) {
    final s = fold(raw).toLowerCase();
    final has4k = s.contains('4k') || s.contains('uhd') || s.contains('2160');
    final hasFhd = s.contains('fhd') || s.contains('1080');
    final hasHd =
        RegExp(r'(^|[^a-z])hd([^a-z]|$)').hasMatch(s) ||
        s.contains('720') ||
        s.contains('ᴴᴰ');
    final hasSd = RegExp(r'(^|[^a-z])sd([^a-z]|$)').hasMatch(s);
    var score = has4k
        ? (preferLighter ? 0 : 50)
        : hasFhd
        ? 40
        : hasHd
        ? 30
        : hasSd
        ? 10
        : 20;
    // Piccole correzioni che non scavalcano mai il livello di qualità.
    if (s.contains('backup') || RegExp(r'\bbk\b').hasMatch(s)) score -= 3;
    if (s.contains('hevc') || s.contains('h265')) {
      score += preferLighter ? -2 : 1;
    }
    return score;
  }
}
