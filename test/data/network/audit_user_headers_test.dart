import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helireport_desherbaje/data/network/network_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Adaptador que no llega a la red: captura las cabeceras de la petición y
/// devuelve 200. Basta para verificar qué sale por el wire.
class _CapturingAdapter implements HttpClientAdapter {
  Map<String, dynamic>? capturedHeaders;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    capturedHeaders = Map<String, dynamic>.from(options.headers);
    return ResponseBody.fromString('{}', 200);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('buildAuditUserHeaders', () {
    test('emite X-User-Id y X-User-Login del usuario logueado', () async {
      SharedPreferences.setMockInitialValues(
        <String, Object>{'user_id': 7, 'user_usuario': 'jlopez'},
      );

      expect(await buildAuditUserHeaders(), <String, String>{
        'X-User-Id': '7',
        'X-User-Login': 'jlopez',
      });
    });

    test('sin sesión no emite ninguna cabecera', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      expect(await buildAuditUserHeaders(), isEmpty);
    });

    test('filtra el login a ASCII (una cabecera no-ASCII rompe la petición)',
        () async {
      SharedPreferences.setMockInitialValues(
        <String, Object>{'user_id': 7, 'user_usuario': 'josé ñuñez'},
      );

      expect((await buildAuditUserHeaders())['X-User-Login'], 'jos uez');
    });

    // X-User-Name no se manda a propósito: el backend resuelve el nombre con un
    // JOIN contra `usuarios` por user_id.
    test('no emite X-User-Name', () async {
      SharedPreferences.setMockInitialValues(
        <String, Object>{
          'user_id': 7,
          'user_usuario': 'jlopez',
          'user_name': 'Juan López'
        },
      );

      expect(await buildAuditUserHeaders(), isNot(contains('X-User-Name')));
    });
  });

  group('AuditUserInterceptor', () {
    test('añade las cabeceras a la petición real', () async {
      SharedPreferences.setMockInitialValues(
        <String, Object>{'user_id': 42, 'user_usuario': 'operario01'},
      );
      final adapter = _CapturingAdapter();
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
        ..httpClientAdapter = adapter
        ..interceptors.add(AuditUserInterceptor());

      await dio.post<dynamic>('/segmentos/upsert', data: <String, dynamic>{});

      expect(adapter.capturedHeaders?['X-User-Id'], '42');
      expect(adapter.capturedHeaders?['X-User-Login'], 'operario01');
    });
  });
}
