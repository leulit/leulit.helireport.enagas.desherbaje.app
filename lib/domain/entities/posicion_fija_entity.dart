import '../../core/sync/contracts/syncable.dart';
import '../../data/model/json_parsing_utils.dart';
import 'package:uuid/uuid.dart';

/// Nombres de campo JSON de [PosicionFijaEntity]. Mismo patrón que
/// `SegmentoEntityFieldNames`.
enum PosicionFijaEntityFieldNames {
  id('id'),
  clientId('client_id'),
  title('title'),
  latitud('latitud'),
  longitud('longitud'),
  fixedLatitude('fixed_latitude'),
  fixedLongitude('fixed_longitude'),
  ctname('ctname'),
  zona('zona'),
  tramo('tramo'),
  subtramo('subtramo'),
  tipoPunto('tipo_punto'),
  tipoVigilancia('tipovigilancia'),
  trazaname('trazaname'),
  fotos('fotos'),
  fecha('fecha'),
  iupdated('iupdated'),
  icreated('icreated'),
  updatedAt('updated_at');

  final String value;
  const PosicionFijaEntityFieldNames(this.value);
}

/// Posición fija (instalación / vigilancia) asociada a un CT. Entidad
/// **pull-only**: se descarga del backend y se muestra en el mapa, nunca se
/// sube. Implementa [Syncable] con identidad estable por [clientId] (UUID
/// v4); el `id` entero del backend viaja en [remoteId].
class PosicionFijaEntity implements Syncable {
  PosicionFijaEntity({
    this.id,
    String? clientId,
    required this.title,
    required this.ctname,
    this.latitud,
    this.longitud,
    this.fixedLatitude,
    this.fixedLongitude,
    this.zona,
    this.tramo,
    this.subtramo,
    this.tipoPunto,
    this.tipoVigilancia,
    this.trazaname,
    this.fotos,
    this.fecha,
    DateTime? updatedAt,
  })  : _clientId = clientId ?? const Uuid().v4(),
        _updatedAt = updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  final String _clientId;
  DateTime _updatedAt;

  final int? id;
  final String title;
  final String ctname;
  final double? latitud;
  final double? longitud;
  final double? fixedLatitude;
  final double? fixedLongitude;
  final String? zona;
  final String? tramo;
  final String? subtramo;
  final String? tipoPunto;
  final String? tipoVigilancia;
  final String? trazaname;
  final String? fotos;
  final DateTime? fecha;

  factory PosicionFijaEntity.fromJson(Map<String, dynamic> json) {
    final id = readJsonDataUtil<int?>(
      json,
      PosicionFijaEntityFieldNames.id.value,
      null,
    );
    final clientId = readJsonDataUtil<String?>(
      json,
      PosicionFijaEntityFieldNames.clientId.value,
      null,
    );
    final title = readJsonDataUtil<String>(
      json,
      PosicionFijaEntityFieldNames.title.value,
      '',
    );
    final ctname = readJsonDataUtil<String>(
      json,
      PosicionFijaEntityFieldNames.ctname.value,
      '',
    );
    final latitud =
        _parseCoord(json[PosicionFijaEntityFieldNames.latitud.value]);
    final longitud =
        _parseCoord(json[PosicionFijaEntityFieldNames.longitud.value]);
    final fixedLatitude =
        _parseCoord(json[PosicionFijaEntityFieldNames.fixedLatitude.value]);
    final fixedLongitude =
        _parseCoord(json[PosicionFijaEntityFieldNames.fixedLongitude.value]);
    final zona = readJsonDataUtil<String?>(
      json,
      PosicionFijaEntityFieldNames.zona.value,
      null,
    );
    final tramo = readJsonDataUtil<String?>(
      json,
      PosicionFijaEntityFieldNames.tramo.value,
      null,
    );
    final subtramo = readJsonDataUtil<String?>(
      json,
      PosicionFijaEntityFieldNames.subtramo.value,
      null,
    );
    final tipoPunto = readJsonDataUtil<String?>(
      json,
      PosicionFijaEntityFieldNames.tipoPunto.value,
      null,
    );
    final tipoVigilancia = readJsonDataUtil<String?>(
      json,
      PosicionFijaEntityFieldNames.tipoVigilancia.value,
      null,
    );
    final trazaname = readJsonDataUtil<String?>(
      json,
      PosicionFijaEntityFieldNames.trazaname.value,
      null,
    );
    final fotos = readJsonDataUtil<String?>(
      json,
      PosicionFijaEntityFieldNames.fotos.value,
      null,
    );

    final fechaRaw = readJsonDataUtil<String?>(
      json,
      PosicionFijaEntityFieldNames.fecha.value,
      null,
    );
    final fecha = fechaRaw != null ? DateTime.tryParse(fechaRaw) : null;

    final updatedAt = _resolveUpdatedAt(json, fecha);

    return PosicionFijaEntity(
      id: id,
      clientId: clientId,
      title: title,
      ctname: ctname,
      latitud: latitud,
      longitud: longitud,
      fixedLatitude: fixedLatitude,
      fixedLongitude: fixedLongitude,
      zona: zona,
      tramo: tramo,
      subtramo: subtramo,
      tipoPunto: tipoPunto,
      tipoVigilancia: tipoVigilancia,
      trazaname: trazaname,
      fotos: fotos,
      fecha: fecha,
      updatedAt: updatedAt,
    );
  }

  /// Parsea coordenadas que el backend envía como `String` (p.ej.
  /// `"41.393712000"`). Desviación deliberada de `readJsonDataUtil<T>`: su
  /// rama de parseo numérico solo se activa cuando `T` es exactamente `int`/
  /// `double` (comparación de `Type`, no nullable) — con `T = double?` cae al
  /// cast genérico `value as T`, que lanza al intentar castear un `String` y
  /// devuelve `null` silenciosamente. Este helper parsea explícitamente
  /// `num`/`String` sin depender de esa rama.
  static double? _parseCoord(dynamic raw) {
    if (raw == null) return null;
    if (raw is num) return raw.toDouble();
    if (raw is String) return double.tryParse(raw.trim());
    return null;
  }

  /// Resuelve `updatedAt` con fallback determinista: `updated_at` (round-trip
  /// del motor) → `iupdated` → `icreated` → `fecha` → epoch 0. JAMÁS
  /// `DateTime.now()` — un timestamp corrupto no debe fabricar "ahora"
  /// (rompería LWW / orden de conflictos).
  static DateTime _resolveUpdatedAt(
    Map<String, dynamic> json,
    DateTime? fecha,
  ) {
    final updatedAtRaw = readJsonDataUtil<String?>(
      json,
      PosicionFijaEntityFieldNames.updatedAt.value,
      null,
    );
    if (updatedAtRaw != null) {
      final parsed = DateTime.tryParse(updatedAtRaw);
      if (parsed != null) return parsed;
    }

    final iupdatedRaw = readJsonDataUtil<String?>(
      json,
      PosicionFijaEntityFieldNames.iupdated.value,
      null,
    );
    if (iupdatedRaw != null) {
      final parsed = DateTime.tryParse(iupdatedRaw);
      if (parsed != null) return parsed;
    }

    final icreatedRaw = readJsonDataUtil<String?>(
      json,
      PosicionFijaEntityFieldNames.icreated.value,
      null,
    );
    if (icreatedRaw != null) {
      final parsed = DateTime.tryParse(icreatedRaw);
      if (parsed != null) return parsed;
    }

    if (fecha != null) return fecha;

    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      PosicionFijaEntityFieldNames.id.value: id,
      PosicionFijaEntityFieldNames.clientId.value: clientId,
      PosicionFijaEntityFieldNames.title.value: title,
      PosicionFijaEntityFieldNames.ctname.value: ctname,
      PosicionFijaEntityFieldNames.latitud.value: latitud,
      PosicionFijaEntityFieldNames.longitud.value: longitud,
      PosicionFijaEntityFieldNames.fixedLatitude.value: fixedLatitude,
      PosicionFijaEntityFieldNames.fixedLongitude.value: fixedLongitude,
      PosicionFijaEntityFieldNames.zona.value: zona,
      PosicionFijaEntityFieldNames.tramo.value: tramo,
      PosicionFijaEntityFieldNames.subtramo.value: subtramo,
      PosicionFijaEntityFieldNames.tipoPunto.value: tipoPunto,
      PosicionFijaEntityFieldNames.tipoVigilancia.value: tipoVigilancia,
      PosicionFijaEntityFieldNames.trazaname.value: trazaname,
      PosicionFijaEntityFieldNames.fotos.value: fotos,
      PosicionFijaEntityFieldNames.fecha.value: fecha?.toIso8601String(),
      PosicionFijaEntityFieldNames.updatedAt.value:
          updatedAt.toIso8601String(),
    };
  }

  // ──────────────────────────── Syncable ────────────────────────────

  @override
  String get clientId => _clientId;

  @override
  String? get remoteId => id?.toString();

  @override
  DateTime get updatedAt => _updatedAt;

  // ──────────────────────────── Derived (presentación) ────────────────────

  /// `true` si [lat]/[lng] son coordenadas válidas: no nulas, no NaN, no
  /// ambas ~0 (relleno inválido tipo `"0.000000000"`), y dentro de rango.
  static bool _isValidCoord(double? lat, double? lng) {
    if (lat == null || lng == null) return false;
    if (lat.isNaN || lng.isNaN) return false;
    if (lat.abs() < 1e-9 && lng.abs() < 1e-9) return false;
    if (lat < -90 || lat > 90) return false;
    if (lng < -180 || lng > 180) return false;
    return true;
  }

  /// Latitud a mostrar en mapa: prefiere `fixedLatitude` si es válida, si no
  /// cae a `latitud` si es válida, si no `null`.
  double? get displayLatitude {
    if (_isValidCoord(fixedLatitude, fixedLongitude)) return fixedLatitude;
    if (_isValidCoord(latitud, longitud)) return latitud;
    return null;
  }

  /// Longitud a mostrar en mapa — ver [displayLatitude].
  double? get displayLongitude {
    if (_isValidCoord(fixedLatitude, fixedLongitude)) return fixedLongitude;
    if (_isValidCoord(latitud, longitud)) return longitud;
    return null;
  }

  bool get hasValidPoint => displayLatitude != null;

  PosicionFijaEntity copyWith({
    int? id,
    String? title,
    String? ctname,
    double? latitud,
    double? longitud,
    double? fixedLatitude,
    double? fixedLongitude,
    String? zona,
    String? tramo,
    String? subtramo,
    String? tipoPunto,
    String? tipoVigilancia,
    String? trazaname,
    String? fotos,
    DateTime? fecha,
  }) {
    final copy = PosicionFijaEntity(
      id: id ?? this.id,
      clientId: _clientId,
      title: title ?? this.title,
      ctname: ctname ?? this.ctname,
      latitud: latitud ?? this.latitud,
      longitud: longitud ?? this.longitud,
      fixedLatitude: fixedLatitude ?? this.fixedLatitude,
      fixedLongitude: fixedLongitude ?? this.fixedLongitude,
      zona: zona ?? this.zona,
      tramo: tramo ?? this.tramo,
      subtramo: subtramo ?? this.subtramo,
      tipoPunto: tipoPunto ?? this.tipoPunto,
      tipoVigilancia: tipoVigilancia ?? this.tipoVigilancia,
      trazaname: trazaname ?? this.trazaname,
      fotos: fotos ?? this.fotos,
      fecha: fecha ?? this.fecha,
    );
    copy._updatedAt = _updatedAt;
    return copy;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PosicionFijaEntity && other._clientId == _clientId);

  @override
  int get hashCode => _clientId.hashCode;

  @override
  String toString() =>
      'PosicionFijaEntity(clientId: $_clientId, id: $id, title: $title, '
      'ctname: $ctname)';
}
