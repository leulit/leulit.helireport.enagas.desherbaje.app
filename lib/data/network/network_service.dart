import 'package:dio/dio.dart';
import 'package:get/get.dart' hide Response, FormData;
import '../../core/app_config.dart';
import '../../core/services/api_security_service.dart';

class NetworkService extends GetxService {
  late final Dio _dio;

  Dio get dio => _dio;

  @override
  void onInit() {
    super.onInit();
    _dio = Dio(BaseOptions(
      baseUrl: AppConfig.baseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
    ));
    _dio.interceptors.add(_HmacInterceptor());
  }
}

class _HmacInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final method = options.method.toUpperCase();
    final pathStr = options.path;
    final headers = ApiSecurityService.buildHeaders(
      method,
      pathStr,
      isMultipart: options.data is FormData,
    );
    options.headers.addAll(headers);
    handler.next(options);
  }
}
