// lib/utils/json_parsing_utils.dart

import 'dart:convert';

import '../../core/extensions.dart'; // Necesario si jsonDecode se usa aquí

// Asumo que tienes una extensión String.datetimeParser()


// Tu logger, si lo usas
// import 'package:tu_app/core/app_di.dart'; // Ajusta la ruta a tu AppDI.log

T readJsonDataUtil<T>(
  Map<dynamic, dynamic> parsedJson,
  String label,
  T defaultValue,
) {
  try {
    if (parsedJson.containsKey(label) && parsedJson[label] != null) {
      dynamic value = parsedJson[label];

      if (T == int) {
        if (value is int) {
          return value as T;
        } else if (value is double) {
          return value.toInt() as T;
        } else if (value is String) {
          return int.tryParse(value) as T ?? defaultValue;
        }
      } else if (T == double) {
        if (value is double) {
          return value as T;
        } else if (value is int) {
          return value.toDouble() as T;
        } else if (value is String) {
          return double.tryParse(value) as T ?? defaultValue;
        }
      } else if (T == String) {
        return value.toString() as T;
      } else if (T == bool) { // Es importante manejar bool si esperas 0/1
        if (value is bool) return value as T;
        if (value is int) return (value == 1) as T;
        if (value is String) return (value == '1' || value.toLowerCase() == 'true') as T;
      }
      // Considera si necesitas manejar otros tipos, como List o Map, aquí genéricamente.
      // Para Map y List, jsonDecode es más común en el fromJson del modelo.

      // Intento de conversión genérica (cuidado con esto, puede fallar si los tipos no coinciden)
      return value as T;
    }
  } catch (e) {
    // AppDI.log.e('Error en readJsonData para "$label": ${e.toString()}'); // Usa tu logger
  }
  return defaultValue;
}

DateTime readJsonDateTimeUtil(
  Map<dynamic, dynamic> parsedJson,
  String label,
  DateTime defaultValue,
) {
  try {
    if (parsedJson.containsKey(label) && parsedJson[label] != null) {
      final value = parsedJson[label];
      final s = value.toString().datetimeParser(
        formato: "yyyy-MM-ddThh:mm:ssZ", // Primer intento con formato ISO
      );
      if (s == null) {
        final s1 = value.toString().datetimeParser(
          formato: "yyyy-MM-dd hh:mm:ss", // Segundo intento
        );
        if (s1 == null) {
          return defaultValue;
        }
        return s1;
      }
      return s;
    }
  } catch (e) {
    // AppDI.log.e('Error en readJsonDateTime para "$label": ${e.toString()}'); // Usa tu logger
  }
  return defaultValue;
}

// Opcional: una función para parsear Map<String, dynamic> si es un JSON string
Map<String, dynamic> parseJsonMap(String? jsonString) {
  if (jsonString == null || jsonString.isEmpty) {
    return {};
  }
  try {
    return jsonDecode(jsonString) as Map<String, dynamic>;
  } catch (e) {
    return {};
  }
}

// Opcional: una función para parsear List<Map<String, dynamic>> si es un JSON string
List<Map<String, dynamic>> parseJsonList(String? jsonString) {
  if (jsonString == null || jsonString.isEmpty) {
    return [];
  }
  try {
    final decoded = jsonDecode(jsonString);
    if (decoded is List) {
      return decoded.cast<Map<String, dynamic>>(); // O mapear si los elementos no son Map<String, dynamic> directamente
    }
    return [];
  } catch (e) {
    return [];
  }
}