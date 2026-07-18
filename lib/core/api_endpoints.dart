import 'app_config.dart';

/// Catálogo único de URLs externas y endpoints del backend. Centralizar aquí
/// evita tener strings sueltos por la capa de datos y simplifica un futuro
/// cambio de host (basta con tocar `AppConfig.baseUrl`).
///
/// Convención: los endpoints del backend devuelven la URL completa (con
/// `apiBaseUrl`). El [_HmacInterceptor] del [NetworkService] elimina el `baseUrl`
/// antes de firmar HMAC, así la firma sigue calculándose sobre el path
/// relativo (compatibilidad backend).
class ApiEndpoints {
  ApiEndpoints._();

  static String get apiBaseUrl => AppConfig.apiBaseUrl;

  // ──────────────────────────── Externos ────────────────────────────

  static const String arcgisImagery =
      'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
  static const String arcgisImageryAlt =
      'https://services.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';

  /// IGN PNOA — orto-imagen de alta resolución (España).
  static const String pnoaWmts =
      'https://www.ign.es/wmts/pnoa-ma?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0'
      '&LAYER=OI.OrthoimageCoverage&STYLE=default'
      '&TILEMATRIXSET=GoogleMapsCompatible'
      '&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}&FORMAT=image/png';

  static const String googleConnectivityCheck = 'https://www.google.com';

  // ──────────────────────────── Auth ────────────────────────────

  static String get userLogin => '$apiBaseUrl/users/login';

  // ──────────────────────────── Segmentos ────────────────────────────

  static String segmentosByCt(String cts) => '$apiBaseUrl/segmentos/bycts/$cts';
  static String segmentoById(int id) => '$apiBaseUrl/segmentos/byid/$id';

  /// Descarga para contratista: segmentos en estado `propuesta` + `validada`
  /// de los CTs [cts] (CSV de nombres de CT, cada nombre URL-encoded, comas
  /// literales), enriquecidos con `imagenes[]` y `mensajes[]`. Los vídeos
  /// viajan como fila de `imagenes[]` con `mime_type` `video/*` (la app modela
  /// el vídeo como imagen con mime de vídeo — no hay array `videos[]` aparte).
  /// La identidad de cada hijo es su `id` entero; no existe `client_id`.
  /// `GET /api/enagas/v1/segmentos/contratista?cts=CT1,CT2`.
  /// La firma HMAC se calcula sobre el path CON querystring (§9 del contrato).
  static String segmentosContratista(String cts) =>
      '$apiBaseUrl/segmentos/contratista?cts=$cts';

  /// Insert-or-update: el backend decide crear o actualizar según el campo
  /// **`id`** en el body (0/null = insert, >0 = update). Sustituye a los
  /// antiguos `create`/`update/{id}`.
  static String get segmentoUpsert => '$apiBaseUrl/segmentos/upsert';
  static String get segmentosByEstado => '$apiBaseUrl/segmentos/byestado';
  static String mensajeAdd(int segmentoId) => '$apiBaseUrl/segmentos/mensajes/$segmentoId';
  static String deleteSegmento(int id) => '$apiBaseUrl/segmentos/delete/$id';

  /// Marca un segmento como "envío finalizado": el cliente ha subido con éxito
  /// todo su contenido (datos + imágenes + vídeos + mensajes). Idempotente por
  /// `id` y no destructivo: una segunda llamada sobre un segmento ya
  /// finalizado devuelve 2xx. **Sin body.**
  static String segmentoSyncComplete(int id) =>
      '$apiBaseUrl/segmentos/$id/sync-complete';

  // ──────────────────────────── CTs ────────────────────────────

  /// Lista de CTs (con perfil + visibilidad) asignados al usuario.
  /// Se invoca tras el login porque el endpoint de `/users/login` no los
  /// incluye.
  static String ctsByUser(int iduser) => '$apiBaseUrl/users/ctsbyuser/$iduser';

  /// JSON con la traza de gasoductos del CT identificado por [filename].
  static String gasoductosTrack(String filename) => '$apiBaseUrl/tracks/json/$filename-gasoductos.json';

  /// JSON con los puntos kilométricos (PKs) del CT identificado por [filename].
  static String pkTrack(String filename) => '$apiBaseUrl/tracks/json/$filename-pk.json';

  /// JSON con los hitos del CT identificado por [filename].
  static String hitosTrack(String filename) => '$apiBaseUrl/tracks/json/$filename-hitos.json';

  // ──────────────────────────── Imágenes ────────────────────────────

  /// Subida multipart de imágenes — legacy `/operador/additem`. SOLO
  /// incidencias de operador; para fotos de segmento usar [segmentoImagenes].
  static String get imagenAdd => '$apiBaseUrl/operador/additem';

  /// Subida multipart de una foto ligada a un segmento (contrato backend).
  /// `POST /api/enagas/v1/segmentos/{id}/imagenes`. Campos: file, tipoFoto
  /// (antes|despues), capturada_at?, subida_por?. Respuesta `{id, url}`.
  static String segmentoImagenes(int id) => '$apiBaseUrl/segmentos/$id/imagenes';

  // ──────────────────────────── Media (fotos + vídeos) ────────────────────────────

  /// Endpoint ÚNICO de media: sirve tanto fotos como vídeos (§9 del contrato).
  /// `GET /api/enagas/v1/segmentos/thumbdb/{id}/{width}/{height}`.
  ///
  /// - `width=0, height=0` → fichero original sin procesar.
  /// - Otros valores → thumbnail JPEG (solo fotos).
  ///
  /// Los vídeos se sirven con `Range`, así el reproductor hace seek sin bajar
  /// el fichero entero. Siempre exige credencial: HMAC en cabeceras para
  /// peticiones de la app, o firma en query
  /// (`ApiSecurityService.buildSignedMediaUrl`) para una URL que se entrega a
  /// un reproductor.
  static String segmentoThumb(int id, int width, int height) =>
      '$apiBaseUrl/segmentos/thumbdb/$id/$width/$height';

  // ──────────────────────────── Vídeos ────────────────────────────

  /// Inicia una nueva sesión de subida chunked.
  /// `POST /api/enagas/v1/videos/upload`
  /// Body JSON (camelCase exacto): `{ originalFilename, totalBytes, mimeType,
  /// segmentoId, tipoFoto?, usuariologged?, idusuariologged? }`.
  /// Devuelve `201 { uploadId, offset, segmentoId }`.
  static String get videosUploadInit => '$apiBaseUrl/videos/upload';

  /// Consulta estado (GET) o envía chunk (POST) de una sesión en curso.
  /// `GET /api/enagas/v1/videos/upload/{uploadId}`
  ///   → `200 { uploadId, offset, totalBytes, mimeType, originalFilename, complete }`.
  /// `POST /api/enagas/v1/videos/upload/{uploadId}`
  ///   Header `Upload-Offset: <bytesYaEnServidor>`, body = bytes raw.
  ///   → `200 { offset }`.
  static String videoUpload(String uploadId) => '$apiBaseUrl/videos/upload/$uploadId';

  /// Completa la sesión de subida (activa la conversión MOV→MP4 asíncrona).
  /// `POST /api/enagas/v1/videos/upload/{uploadId}/complete`
  /// → `200 { uploadId, id, status: "recibido" }`. El `id` es la fila de
  /// `imagenes_segmento`: con él se construye la URL de reproducción vía
  /// [segmentoThumb]. `/videos/download/{uploadId}.mp4` está RETIRADO.
  static String videoUploadComplete(String uploadId) => '$apiBaseUrl/videos/upload/$uploadId/complete';

  // ──────────────────────────── Posiciones GPS ────────────────────────────

  /// Subida en lote de puntos GPS. Idempotente por `batch_client_id`.
  /// Documentado en `docs/BACKEND_SYNC_CONTRACT.md` §8.
  static String get positionsBatch => '$apiBaseUrl/positions/batch';

  /// Thumbnail de incidencia (mock data en `captura_fotos_controller`).
  static String incidenciaThumb(int id, int width, int height) => '$apiBaseUrl/incidencias/thumbdb/$id/$width/$height';

  // ──────────────────────────── Posiciones fijas ────────────────────────────

  /// Posiciones fijas asociadas a los CTs del usuario, filtradas por nombre
  /// de CT (mismo esquema que [segmentosByCt]).
  static String posicionesFijasByCts(String cts) => '$apiBaseUrl/incidencias/posicionesfijasbycts/$cts';
}
