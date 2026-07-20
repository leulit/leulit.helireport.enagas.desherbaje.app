import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:leulit_flutter_actionmanager/leulit_flutter_actionmanager.dart';

import '../data/services/json_loader_service.dart';
import '../domain/entities/imagen_segmento_entity.dart';

/// Payload de [AppTypedActions.mediaGisActivada]: la media que se acaba de
/// activar en el carrusel Antes/Después, con su `gis_json` y el contexto que
/// el mapa necesita para dibujar la georreferencia.
///
/// - [gisJson] null => la media no tiene GIS (el mapa debe limpiar).
/// - [clientId] vacío => no hay media activa (lista vacía) => limpiar.
@immutable
class MediaGisActivada {
  final String? gisJson;
  final TipoFoto tipo;
  final String clientId;
  final bool isVideo;

  const MediaGisActivada({
    required this.gisJson,
    required this.tipo,
    required this.clientId,
    required this.isVideo,
  });
}

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

  // ──────────────────── SegmentoDetallePage (barra de acciones) ─────────────

  /// El usuario pulsó "Guardar" en la barra global. Sin payload.
  static const guardarRequested =
      TypedAction<void>('SegDetalle.guardarRequested');

  /// El usuario confirmó "Eliminar" en la barra global. Solo se ofrece para
  /// segmentos que aún no existen en backend (id remoto null o 0). Sin payload.
  static const deleteSegmento = TypedAction<void>('SegDetalle.deleteSegmento');

  /// El usuario pulsó "Editar extremos" (tab Datos). Sin payload.
  static const editarExtremosRequested =
      TypedAction<void>('SegDetalle.editarExtremosRequested');

  /// El usuario pulsó "Añadir foto/vídeo". `data` = tipo (antes / después).
  static const capturaRequested =
      TypedAction<TipoFoto>('SegDetalle.capturaRequested');

  /// El controller notifica cambio de estado de guardado para el spinner de la
  /// barra. `data` = true mientras guarda.
  static const savingChanged = TypedAction<bool>('SegDetalle.savingChanged');

  /// El usuario pulsó "Centrar en mi ubicación" (mapa). Sin payload.
  static const centrarEnDispositivoRequested =
      TypedAction<void>('SegDetalle.centrarEnDispositivoRequested');

  /// Media activada en el carrusel (al abrir su pestaña o al cambiar de slide).
  /// `data` = [MediaGisActivada] (gis_json + contexto). La escucha el
  /// `MediaGisLayer` del mapa para dibujar la georreferencia de la captura.
  static const mediaGisActivada =
      TypedAction<MediaGisActivada>('SegDetalle.mediaGisActivada');

  /// El `MediaGisLayer` calculó los bounds de la georreferencia de la media
  /// activa. `data` = [LatLngBounds] a encuadrar. La escucha
  /// `SegmentoDetalleController` para ajustar la cámara del mapa con margen.
  static const mediaGisBoundsRequested =
      TypedAction<LatLngBounds>('SegDetalle.mediaGisBoundsRequested');
}
