import 'package:logger/logger.dart';

/// Facade estático sobre [Logger] (logger: ^2.7.0).
/// Usa niveles de log correctos en release — no depende de debugPrint.
/// Uso: AppLog.e('mensaje', error: e, stackTrace: s);
class AppLog {
  AppLog._();

  static final _logger = Logger(
    printer: PrettyPrinter(
      methodCount: 2,
      errorMethodCount: 8,
      lineLength: 120,
      colors: false,
      printEmojis: false,
    ),
  );

  static void i(String message, {Object? error, StackTrace? stackTrace}) =>
      _logger.i(message, error: error, stackTrace: stackTrace);

  static void w(String message, {Object? error, StackTrace? stackTrace}) =>
      _logger.w(message, error: error, stackTrace: stackTrace);

  static void e(String message, {Object? error, StackTrace? stackTrace}) =>
      _logger.e(message, error: error, stackTrace: stackTrace);

  static void d(String message, {Object? error, StackTrace? stackTrace}) =>
      _logger.d(message, error: error, stackTrace: stackTrace);
}
