import 'app_config.dart';

/// Catálogo único de URLs externas y endpoints del backend. Centralizar aquí
/// evita tener strings sueltos por la capa de datos y simplifica un futuro
/// cambio de host (basta con tocar `AppConfig.baseUrl`).
///
/// Convención: los endpoints del backend devuelven la URL completa (con
/// `baseUrl`). El [_HmacInterceptor] del [NetworkService] elimina el `baseUrl`
/// antes de firmar HMAC, así la firma sigue calculándose sobre el path
/// relativo (compatibilidad backend).
class ApiEndpoints {
  ApiEndpoints._();

  static String get baseUrl => AppConfig.baseUrl;

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

  static String get userLogin => '$baseUrl/users/login';

  // ──────────────────────────── Segmentos ────────────────────────────

  static String segmentosByCt(String cts) => '$baseUrl/segmentos/bycts/$cts';
  static String segmentoById(int id) => '$baseUrl/segmentos/byid/$id';
  static String segmentoUpd(int id) => '$baseUrl/segmentos/update/$id';
  static String get segmentoAdd => '$baseUrl/segmentos/create';
  static String get segmentosByEstado => '$baseUrl/segmentos/byestado';
  static String mensajesBySegmento(int id) => '$baseUrl/segmentos/mensajes/$id';
  static String deleteSegmento(int id) => '$baseUrl/segmentos/delete/$id';

  // ──────────────────────────── CTs ────────────────────────────

  /// Lista de CTs (con perfil + visibilidad) asignados al usuario.
  /// Se invoca tras el login porque el endpoint de `/users/login` no los
  /// incluye.
  static String ctsByUser(int iduser) => '$baseUrl/users/ctsbyuser/$iduser';

  /// JSON con la traza de gasoductos del CT identificado por [filename].
  static String gasoductosTrack(String filename) =>
      '$baseUrl/tracks/json/$filename-gasoductos.json';

  // ──────────────────────────── Imágenes ────────────────────────────

  /// Subida multipart de imágenes (legacy: `/operador/additem`).
  static String get imagenAdd => '$baseUrl/operador/additem';

  /// Thumbnail de incidencia (mock data en `captura_fotos_controller`).
  static String incidenciaThumb(int id, int width, int height) =>
      '$baseUrl/incidencias/thumbdb/$id/$width/$height';
}
