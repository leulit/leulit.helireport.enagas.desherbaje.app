import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import 'app_log.dart';

/// Estado de UI de una pantalla, persistido entre navegaciones en
/// SharedPreferences. Cada pantalla decide qué claves guarda; el `scope`
/// las namespacea para que no colisionen entre pantallas.
class ScreenState {
  ScreenState(this.scope);

  final String scope;

  static const _debounce = Duration(milliseconds: 400);

  SharedPreferences? _prefs;
  Timer? _saveTimer;
  Map<String, Object?> Function()? _pending;

  String _key(String key) => '$scope.$key';

  /// Carga y cachea la instancia de [SharedPreferences]. Los getters
  /// devuelven `null` mientras no se haya llamado (o si falla la carga).
  Future<void> load() async {
    try {
      _prefs = await SharedPreferences.getInstance();
    } catch (e, s) {
      AppLog.e('ScreenState($scope): fallo al cargar SharedPreferences',
          error: e, stackTrace: s);
    }
  }

  bool? boolean(String key) {
    try {
      return _prefs?.getBool(_key(key));
    } catch (e, s) {
      AppLog.e('ScreenState($scope): fallo leyendo bool "$key"',
          error: e, stackTrace: s);
      return null;
    }
  }

  double? number(String key) {
    try {
      return _prefs?.getDouble(_key(key));
    } catch (e, s) {
      AppLog.e('ScreenState($scope): fallo leyendo double "$key"',
          error: e, stackTrace: s);
      return null;
    }
  }

  String? text(String key) {
    try {
      return _prefs?.getString(_key(key));
    } catch (e, s) {
      AppLog.e('ScreenState($scope): fallo leyendo String "$key"',
          error: e, stackTrace: s);
      return null;
    }
  }

  /// Programa la persistencia de [snapshot] con debounce de 400ms — cada
  /// llamada cancela la anterior y re-arma el timer (última gana). El closure
  /// se evalúa AL ESCRIBIR (al vencer el debounce), no al llamar a [save].
  void save(Map<String, Object?> Function() snapshot) {
    _saveTimer?.cancel();
    _pending = snapshot;
    _saveTimer = Timer(_debounce, _flush);
  }

  void _flush() {
    final snapshot = _pending;
    if (snapshot == null) return;
    _pending = null;
    // El closure lee estado vivo de la pantalla (cámara del mapa, notifiers).
    // En el flush de `dispose()` ese estado puede estar ya desmontado.
    try {
      unawaited(_write(snapshot()));
    } catch (e, s) {
      AppLog.e('ScreenState($scope): fallo al evaluar el estado a guardar',
          error: e, stackTrace: s);
    }
  }

  Future<void> _write(Map<String, Object?> data) async {
    final prefs = _prefs;
    if (prefs == null) return;
    try {
      for (final entry in data.entries) {
        final fullKey = _key(entry.key);
        final value = entry.value;
        switch (value) {
          case null:
            await prefs.remove(fullKey);
          case bool v:
            await prefs.setBool(fullKey, v);
          case int v:
            await prefs.setInt(fullKey, v);
          case double v:
            await prefs.setDouble(fullKey, v);
          case String v:
            await prefs.setString(fullKey, v);
          default:
            AppLog.w(
                'ScreenState($scope): tipo no soportado para "${entry.key}" '
                '(${value.runtimeType}), se omite');
        }
      }
    } catch (e, s) {
      AppLog.e('ScreenState($scope): fallo al escribir estado',
          error: e, stackTrace: s);
    }
  }

  /// Escribe el guardado pendiente y cancela el timer. Llamar desde `onClose`:
  /// sin esto, salir de la pantalla antes de que venza el debounce perdería el
  /// último cambio — justo el que el usuario acaba de hacer.
  void dispose() {
    _saveTimer?.cancel();
    _flush();
  }
}
