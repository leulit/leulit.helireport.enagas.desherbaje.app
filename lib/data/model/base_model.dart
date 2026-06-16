

import 'json_parsing_utils.dart';
mixin BaseModelMixin {
  T readJsonData<T>(
    Map<dynamic, dynamic> parsedJson,
    String label,
    T defaultValue,
  ) {
    return readJsonDataUtil<T>(
      parsedJson,
      label,
      defaultValue,
    );
  }


  DateTime readJsonDateTime(
    Map<dynamic, dynamic> parsedJson,
    String label,
    DateTime defaultValue,
  ) {    
    return readJsonDateTimeUtil(
      parsedJson,
      label,
      defaultValue,
    );
  }

  void setValueInMap(Map<String, dynamic> mapa, String propiedad, dynamic valor) {
    try {
      mapa[propiedad] = valor;
    } catch (_) {
      // Ignore assignment errors — field may not exist in map.
    }
  }
}


abstract class AbsBaseModel {}
