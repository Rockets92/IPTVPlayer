import 'epg/epg_models.dart';
import 'm3u/m3u_client.dart';
import 'xtream/xtream_client.dart';
import 'xtream/xtream_models.dart';

/// Fonte dei canali live: pannello Xtream Codes o playlist M3U.
abstract interface class LiveSource {
  /// Verifica che la lista sia raggiungibile e valida.
  Future<XtreamAccountInfo> authenticate();
  Future<List<XtreamCategory>> liveCategories();
  Future<List<XtreamLiveStream>> liveStreams();

  /// Guida XMLTV della lista, se esiste.
  Uri? get xmltvUri;

  /// Indirizzo del flusso (per le M3U ogni stream ha già il suo).
  String liveUrl(int streamId, {String extension = 'ts'});

  /// Guida breve di un canale (solo Xtream).
  Future<List<EpgProgramme>> shortEpg(int streamId, {int limit = 6});

  void close();

  static LiveSource create(XtreamCredentials c) =>
      c.isM3u ? M3uClient(c) : XtreamClient(c);
}
