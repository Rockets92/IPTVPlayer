import '../data/vod/vod_models.dart';
import '../state/vod_controller.dart';

/// Agganci registrati dalle schermate aperte, usati dal telecomando sul
/// telefono per ciò che non è un semplice tasto.
abstract final class RemoteHooks {
  /// Riprende un film o una serie dalla schermata del player.
  static void Function(VodKind kind, VodItem item)? resume;

  /// Ricerca nel catalogo Film / Serie, registrata finché è aperto.
  static void Function(String query)? search;
}
