import 'package:leulit_flutter_actionmanager/leulit_flutter_actionmanager.dart';

import '../data/services/json_loader_service.dart';

/// TypedActions globales del proyecto. Centralizar las constantes evita
/// colisiones de nombres y permite a Dart canonicalizar la misma referencia.
class AppTypedActions {
  AppTypedActions._();

  // ──────────────────── JsonLoaderService (descargas GeoJSON) ───────────────

  /// Disparada al iniciar la descarga de un lote. `data` = nº total de
  /// ficheros del lote.
  static const geoJsonLoadStarted =
      TypedAction<int>('AppActions.geoJsonLoadStarted');

  /// Por cada fichero descargado correctamente. `data` = resultado completo
  /// (incluye `originalFileData.group` para que el consumidor filtre).
  static const geoJsonLoaded =
      TypedAction<FileLoadGeoJsonResult>('AppActions.geoJsonLoaded');

  /// Cuando un fichero falla. `data` = payload vacío (puede usarse para
  /// telemetría / contadores).
  static const geoJsonLoadError =
      TypedAction<Map<String, dynamic>>('AppActions.geoJsonLoadError');

  /// Disparada una sola vez al terminar el lote (con éxito o error).
  static const geoJsonLoadCompleted =
      TypedAction<void>('AppActions.geoJsonLoadCompleted');
}
