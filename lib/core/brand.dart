/// Identità del prodotto. Cambiare qui nome e slogan dell'app.
abstract final class Brand {
  static const String name = 'B&B IPTV Player';

  /// Logo completo (TV, B&B e scritta) e icona quadrata.
  static const String logo = 'assets/brand/logo.png';
  static const String icon = 'assets/brand/icon.png';
  static const String tagline = 'La tua TV, senza attrito.';

  /// Misure reali dei file: decodificati per intero logo e icona occupano
  /// ~5,7 MB e ~1 MB di cache immagini, quindi si decodificano alla
  /// dimensione a cui compaiono (mai oltre l'originale).
  static const int logoWidth = 1400;
  static const int logoHeight = 1019;
  static const int iconSize = 512;

  /// Pixel fisici da decodificare per [logical] punti a schermo.
  static int decodeSize(double logical, double dpr, int max) =>
      (logical * dpr).ceil().clamp(1, max);
}
