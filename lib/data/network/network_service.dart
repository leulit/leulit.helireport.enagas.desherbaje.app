import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:get/get.dart' hide Response, FormData, MultipartFile;

import '../../core/app_config.dart';
import '../../core/services/api_security_service.dart';
import 'network_error.dart';
import 'network_file.dart';
import 'network_response.dart';

/// Facade over the HTTP layer. No Dio type ever leaks out of this class.
class NetworkService extends GetxService {
  late final Dio _dio;

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
  }

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
        data: body,
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

  NetworkError _mapDioException(DioException e, [StackTrace? st]) {
    final status = e.response?.statusCode;
    final baseMessage =
        (e.response?.data is Map && (e.response!.data as Map)['message'] is String)
            ? (e.response!.data as Map)['message'] as String
            : e.message ?? 'Network error';

    NetworkErrorCategory category;
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
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
    // Si el caller pasó URL absoluta (ApiEndpoints), eliminamos el baseUrl
    // antes de firmar para que el backend reciba siempre HMAC sobre el path
    // relativo.
    final raw = options.path;
    final base = AppConfig.baseUrl;
    final pathStr =
        raw.startsWith(base) ? raw.substring(base.length) : raw;
    final headers = ApiSecurityService.buildHeaders(
      method,
      pathStr,
      isMultipart: options.data is FormData,
    );
    options.headers.addAll(headers);
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
