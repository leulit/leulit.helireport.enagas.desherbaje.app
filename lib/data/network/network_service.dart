import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart' hide Response, FormData, MultipartFile;

import '../../core/api_endpoints.dart';
import '../../core/app_config.dart';
import '../../core/services/api_security_service.dart';
import 'network_error.dart';
import 'network_file.dart';
import 'network_response.dart';

/// Facade over the HTTP layer. No Dio type ever leaks out of this class.
///
/// Two separate Dio instances, ambos usando el mismo esquema HMAC unificado
/// ([ApiSecurityService.buildHmacHeaders]):
/// - [_dio]: instancia principal con `_HmacInterceptor` + `_RetryInterceptor`
///   (segmento/imagen/mensaje/positions y cualquier endpoint REST v1).
/// - [_videoDio]: instancia separada SIN interceptores ni reintentos automáticos;
///   cada método de vídeo firma manualmente con [ApiSecurityService.buildHmacHeaders]
///   y usa timeouts de 4 min (send/receive) para chunks binarios grandes sin
///   superar la ventana anti-replay de ±5 min del servidor.
class NetworkService extends GetxService {
  late Dio _dio;
  // Non-final to allow injection in tests.
  late Dio _videoDio;

  @override
  void onInit() {
    super.onInit();
    _dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.baseUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 30),
      ),
    );
    _dio.interceptors.add(_HmacInterceptor());
    _dio.interceptors.add(_RetryInterceptor(_dio));

    // Video Dio: no HMAC interceptor, no retry (adapter handles per-chunk retry).
    // sendTimeout/receiveTimeout set to 4 min so a 5 MB chunk on a slow field
    // connection finishes before the 5-min HMAC anti-replay window expires.
    _videoDio = Dio(
      BaseOptions(
        baseUrl: AppConfig.baseUrl,
        connectTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(minutes: 4),
        receiveTimeout: const Duration(minutes: 4),
      ),
    );
  }

  /// Injects a [Dio] instance for the video path. Only for unit tests.
  @visibleForTesting
  void injectVideoDio(Dio dio) => _videoDio = dio;

  Future<NetworkResponse<dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
  }) async {
    try {
      final response = await _dio.get<dynamic>(
        path,
        queryParameters: queryParameters,
        options: Options(headers: headers),
      );
      return _toNetworkResponse(response);
    } on DioException catch (e, st) {
      throw _mapDioException(e, st);
    }
  }

  Future<NetworkResponse<dynamic>> post(
    String path, {
    Object? body,
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
  }) async {
    try {
      final response = await _dio.post<dynamic>(
        path,
        // Fastify rechaza con 400 `FST_ERR_CTP_EMPTY_JSON_BODY` todo POST que
        // declare `application/json` y llegue con cuerpo vacío. Como el
        // content-type se fija siempre aquí, un endpoint cuyo id viaja en el
        // path (p.ej. `sync-complete`) se llamaba sin `body` y era rechazado
        // SIEMPRE. Se manda `{}`: JSON válido, y ajv descarta lo no declarado.
        data: body ?? const <String, dynamic>{},
        queryParameters: queryParameters,
        options: Options(
          headers: headers,
          contentType: 'application/json',
        ),
      );
      return _toNetworkResponse(response);
    } on DioException catch (e, st) {
      throw _mapDioException(e, st);
    }
  }

  Future<NetworkResponse<dynamic>> postMultipart(
    String path, {
    required Map<String, dynamic> fields,
    required List<NetworkFile> files,
    Map<String, String>? headers,
    void Function(int sent, int total)? onSendProgress,
  }) async {
    try {
      final formMap = <String, dynamic>{};
      fields.forEach((key, value) {
        formMap[key] = value;
      });
      for (final f in files) {
        formMap[f.fieldName] = await MultipartFile.fromFile(
          f.filePath,
          filename: f.filename,
          contentType:
              f.contentType == null ? null : DioMediaType.parse(f.contentType!),
        );
      }
      final formData = FormData.fromMap(formMap);

      final response = await _dio.post<dynamic>(
        path,
        data: formData,
        options: Options(headers: headers),
        onSendProgress: onSendProgress,
      );
      return _toNetworkResponse(response);
    } on DioException catch (e, st) {
      throw _mapDioException(e, st);
    }
  }

  // ──────────────────────────── Video upload (new protocol) ────────────────

  /// Inicia una nueva sesión de subida chunked.
  /// `POST /api/enagas/v1/videos/upload`
  /// [body] must include `originalFilename`, `totalBytes`, `mimeType`.
  /// Returns `201 { uploadId, offset, segmentoId }`.
  Future<NetworkResponse<dynamic>> initVideoUpload(
    Map<String, dynamic> body,
  ) async {
    final fullUrl = ApiEndpoints.videosUploadInit;
    final path = _videoSigningPath(fullUrl);
    final hmacHeaders = ApiSecurityService.buildHmacHeaders('POST', path);
    try {
      final resp = await _videoDio.post<dynamic>(
        fullUrl,
        data: body,
        options: Options(
          headers: {
            ...hmacHeaders,
            HttpHeaders.contentTypeHeader: 'application/json',
          },
        ),
      );
      return _toNetworkResponse(resp);
    } on DioException catch (e, st) {
      throw _mapDioException(e, st);
    }
  }

  /// Sends a raw binary chunk to an active upload session.
  /// `POST /api/enagas/v1/videos/upload/{uploadId}`
  /// [uploadOffset] = bytes already confirmed on the server.
  /// Returns `200 { offset }` with the new accumulated offset, o `409 { offset }`
  /// (§6.2 del contrato: señal de reanudación, sin clave `error`).
  Future<NetworkResponse<dynamic>> postVideoChunk({
    required String uploadId,
    required int uploadOffset,
    required Uint8List bytes,
  }) async {
    final fullUrl = ApiEndpoints.videoUpload(uploadId);
    final path = _videoSigningPath(fullUrl);
    // Timestamp must be fresh on every request (anti-replay ±5 min).
    final hmacHeaders = ApiSecurityService.buildHmacHeaders('POST', path);
    try {
      final resp = await _videoDio.post<dynamic>(
        fullUrl,
        data: bytes,
        options: Options(
          headers: {
            ...hmacHeaders,
            HttpHeaders.contentTypeHeader: 'application/octet-stream',
            'Upload-Offset': uploadOffset.toString(),
          },
          responseType: ResponseType.json,
          validateStatus: _videoResumeValidateStatus,
        ),
      );
      return _toNetworkResponse(resp);
    } on DioException catch (e, st) {
      throw _mapDioException(e, st);
    }
  }

  /// Queries an upload session status.
  /// `GET /api/enagas/v1/videos/upload/{uploadId}`
  /// Returns `200 { uploadId, offset, totalBytes, mimeType, originalFilename, complete }`.
  /// Throws [NetworkError] with statusCode 404 when the session is not found.
  Future<NetworkResponse<dynamic>> getVideoStatus(String uploadId) async {
    final fullUrl = ApiEndpoints.videoUpload(uploadId);
    final path = _videoSigningPath(fullUrl);
    final hmacHeaders = ApiSecurityService.buildHmacHeaders('GET', path);
    try {
      final resp = await _videoDio.get<dynamic>(
        fullUrl,
        options: Options(headers: hmacHeaders),
      );
      return _toNetworkResponse(resp);
    } on DioException catch (e, st) {
      throw _mapDioException(e, st);
    }
  }

  /// Signals that all chunks have been sent; triggers async MOV→MP4 conversion.
  /// `POST /api/enagas/v1/videos/upload/{uploadId}/complete`
  /// Returns `200 { uploadId, id, status }`, o `409 { offset, totalBytes }`
  /// (§6.4 del contrato: faltan bytes, señal de reanudación sin clave `error`).
  Future<NetworkResponse<dynamic>> completeVideoUpload(String uploadId) async {
    final fullUrl = ApiEndpoints.videoUploadComplete(uploadId);
    final path = _videoSigningPath(fullUrl);
    final hmacHeaders =
        ApiSecurityService.buildHmacHeaders('POST', path);
    try {
      final resp = await _videoDio.post<dynamic>(
        fullUrl,
        // Cuerpo `{}` obligatorio: declara `application/json`, y Fastify
        // rechaza con 400 `FST_ERR_CTP_EMPTY_JSON_BODY` un JSON vacío. El
        // uploadId viaja en el path, así que no hay nada más que enviar.
        data: const <String, dynamic>{},
        options: Options(
          headers: {
            ...hmacHeaders,
            HttpHeaders.contentTypeHeader: 'application/json',
          },
          validateStatus: _videoResumeValidateStatus,
        ),
      );
      return _toNetworkResponse(resp);
    } on DioException catch (e, st) {
      throw _mapDioException(e, st);
    }
  }

  /// El `409` de las rutas de vídeo no es un fallo: transporta el `offset` desde
  /// el que hay que reanudar. Se entrega como respuesta normal para que el
  /// adapter lea el body; el resto de códigos siguen el mapeo estándar.
  static bool _videoResumeValidateStatus(int? status) =>
      status != null && (status < 400 || status == 409);

  /// Extracts the relative path (including query) from a full URL by stripping
  /// [AppConfig.baseUrl]. Falls back to [Uri.path] if the URL does not start
  /// with the base.
  String _videoSigningPath(String fullUrl) {
    final base = AppConfig.baseUrl;
    if (fullUrl.startsWith(base)) return fullUrl.substring(base.length);
    try {
      return Uri.parse(fullUrl).path;
    } catch (_) {
      return fullUrl;
    }
  }

  // ──────────────────────────── Download ───────────────────────────────────

  Future<NetworkResponse<List<int>>> download(
    String path, {
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
  }) async {
    try {
      final response = await _dio.get<List<int>>(
        path,
        queryParameters: queryParameters,
        options: Options(
          headers: headers,
          responseType: ResponseType.bytes,
        ),
      );
      return NetworkResponse<List<int>>(
        statusCode: response.statusCode ?? 0,
        data: response.data,
        headers: _extractHeaders(response),
      );
    } on DioException catch (e, st) {
      throw _mapDioException(e, st);
    }
  }

  NetworkResponse<dynamic> _toNetworkResponse(Response<dynamic> r) {
    return NetworkResponse<dynamic>(
      statusCode: r.statusCode ?? 0,
      data: r.data,
      headers: _extractHeaders(r),
    );
  }

  Map<String, List<String>> _extractHeaders(Response<dynamic> r) {
    final map = <String, List<String>>{};
    r.headers.map.forEach((k, v) => map[k] = List<String>.from(v));
    return map;
  }

  /// Tope del cuerpo de respuesta que se adjunta al mensaje de error. La
  /// columna `last_error` del outbox y los logs se leen en campo: un volcado
  /// completo los haría inservibles.
  static const int _maxErrorBodyChars = 500;

  NetworkError _mapDioException(DioException e, [StackTrace? st]) {
    final status = e.response?.statusCode;
    final data = e.response?.data;
    final baseMessage = (data is Map && data['message'] is String)
        ? data['message'] as String
        : _messageWithBody(e, data);

    NetworkErrorCategory category;
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.transformTimeout:
        category = NetworkErrorCategory.timeout;
        break;
      case DioExceptionType.connectionError:
        category = NetworkErrorCategory.offline;
        break;
      case DioExceptionType.badCertificate:
      case DioExceptionType.cancel:
      case DioExceptionType.unknown:
      case DioExceptionType.badResponse:
        category = _categoryForStatus(status);
        break;
    }

    if (e.error is SocketException) {
      category = NetworkErrorCategory.offline;
    }

    return NetworkError(
      category: category,
      statusCode: status,
      message: baseMessage,
      cause: e,
      stackTrace: st ?? e.stackTrace,
    );
  }

  /// Mensaje de error cuando el cuerpo NO trae un `message` legible.
  ///
  /// `e.message` es texto genérico de Dio ("Http status error [400]") que no
  /// dice nada de la causa y acaba tal cual en el outbox: un 400 se vuelve
  /// indiagnosticable. Se adjunta el cuerpo crudo recortado para conservar la
  /// razón real del rechazo.
  String _messageWithBody(DioException e, Object? data) {
    final fallback = e.message ?? 'Network error';
    if (data == null) return fallback;

    String body;
    if (data is Map || data is List) {
      // Un cuerpo no serializable (referencias cíclicas, tipos raros) jamás
      // debe hacer estallar el mapeador de errores: se degrada a toString().
      try {
        body = jsonEncode(data);
      } catch (_) {
        body = data.toString();
      }
    } else {
      body = data.toString();
    }

    if (body.isEmpty) return fallback;
    if (body.length > _maxErrorBodyChars) {
      body = '${body.substring(0, _maxErrorBodyChars)}…';
    }
    return '$fallback — respuesta: $body';
  }

  NetworkErrorCategory _categoryForStatus(int? status) {
    if (status == null) return NetworkErrorCategory.unrecoverable;
    if (status == 401 || status == 403) return NetworkErrorCategory.unauthorized;
    if (status == 409 || status == 412) return NetworkErrorCategory.conflict;
    if (status == 408 || status == 429) return NetworkErrorCategory.retryable;
    if (status >= 500 && status < 600) return NetworkErrorCategory.retryable;
    if (status >= 400 && status < 500) return NetworkErrorCategory.unrecoverable;
    return NetworkErrorCategory.unrecoverable;
  }
}

class _HmacInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final method = options.method.toUpperCase();
    // Esquema HMAC unificado de la API /api/enagas/v1: X-HMAC-Signature +
    // X-Timestamp(ms), payload "${ts}:${METHOD}:${path}", sin nonce. Se firma
    // el path relativo (host quitado), incluyendo querystring si la hubiera.
    final base = AppConfig.baseUrl;
    final raw = options.uri.toString();
    final path =
        raw.startsWith(base) ? raw.substring(base.length) : options.uri.path;
    options.headers.addAll(ApiSecurityService.buildHmacHeaders(method, path));
    handler.next(options);
  }
}

/// Retries on 5xx, 408, 429, and connect/receive/send timeouts.
/// Max 2 retries with backoff: 500ms, then 1500ms.
class _RetryInterceptor extends Interceptor {
  static const int _maxRetries = 2;
  static const List<Duration> _backoff = [
    Duration(milliseconds: 500),
    Duration(milliseconds: 1500),
  ];

  final Dio _dio;

  _RetryInterceptor(this._dio);

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final attempt = (err.requestOptions.extra['__retry_attempt'] as int?) ?? 0;

    if (!_shouldRetry(err) || attempt >= _maxRetries) {
      return handler.next(err);
    }

    // FormData is not resendable — skip retry for multipart.
    if (err.requestOptions.data is FormData) {
      return handler.next(err);
    }

    await Future<void>.delayed(_backoff[attempt]);

    final nextOptions = err.requestOptions
      ..extra['__retry_attempt'] = attempt + 1;

    try {
      final response = await _dio.fetch<dynamic>(nextOptions);
      return handler.resolve(response);
    } on DioException catch (e) {
      return handler.next(e);
    }
  }

  bool _shouldRetry(DioException err) {
    switch (err.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.transformTimeout:
        return true;
      case DioExceptionType.connectionError:
        return false; // offline — let the caller handle/enqueue.
      case DioExceptionType.badCertificate:
      case DioExceptionType.cancel:
        return false;
      case DioExceptionType.unknown:
      case DioExceptionType.badResponse:
        final s = err.response?.statusCode;
        if (s == null) return false;
        if (s == 408 || s == 429) return true;
        if (s >= 500 && s < 600) return true;
        return false;
    }
  }
}
