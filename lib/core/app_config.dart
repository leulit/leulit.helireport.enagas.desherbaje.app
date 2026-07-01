class AppConfig {
  /// Secret HMAC. Inyectar en build/run con `--dart-define=HMAC_SECRET=<secret real 64-hex>`.
  /// El placeholder por defecto NO valida contra el backend.
  static const String hmacSecret = String.fromEnvironment(
    'HMAC_SECRET',
    defaultValue: 'YOUR_HMAC_SECRET_HERE',
  );

  /// Host del backend. Usado para concatenar URLs de ficheros estáticos
  /// servidos en raíz y para el chequeo de conectividad (DNS lookup).
  static String get baseUrl => 'https://enagastool.helireport.com';

  /// Prefijo común de la API REST v1. El interceptor HMAC firma sobre el path
  /// que queda tras quitar [baseUrl] (host), por lo que la firma incluye
  /// `/api/enagas/v1` — consistente con el esquema HMAC de vídeo.
  static String get apiBaseUrl => '$baseUrl/api/enagas/v1';
}
