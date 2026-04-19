import 'dart:convert';
import 'segmento_entity.dart';

enum EstadoActividad {
  propuesta,
  validada,
  contratista,
  ejecucion,
  finalizada,
  cerrada;

  /// Valor enviado/recibido por la API (coincide con el ENUM del servidor).
  String get descripcion => switch (this) {
    EstadoActividad.propuesta  => 'Propuesta',
    EstadoActividad.validada   => 'Validada',
    EstadoActividad.contratista   => 'Contratista',
    EstadoActividad.ejecucion  => 'Ejecución',
    EstadoActividad.finalizada => 'Finalizada',
    EstadoActividad.cerrada    => 'Cerrada',
  };

  String get etiqueta => switch (this) {
    EstadoActividad.propuesta  => 'Propuesta',
    EstadoActividad.validada   => 'Validada',
    EstadoActividad.contratista   => 'Contratista',
    EstadoActividad.ejecucion  => 'En Ejecución',
    EstadoActividad.finalizada => 'Finalizada',
    EstadoActividad.cerrada    => 'Cerrada',
  };

  /// Tolerante a mayúsculas/minúsculas y tildes (ej. "Ejecución" → ejecucion).
  static EstadoActividad fromString(String? s) {
    if (s == null) return EstadoActividad.propuesta;
    final q = _normalize(s);
    return EstadoActividad.values.firstWhere(
      (e) => _normalize(e.descripcion) == q || _normalize(e.name) == q,
      orElse: () => EstadoActividad.propuesta,
    );
  }

  static String _normalize(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[áàäâ]'), 'a')
      .replaceAll(RegExp(r'[éèëê]'), 'e')
      .replaceAll(RegExp(r'[íìïî]'), 'i')
      .replaceAll(RegExp(r'[óòöô]'), 'o')
      .replaceAll(RegExp(r'[úùüû]'), 'u');
}

enum TipoActividad {
  desherbajeSelectivo,
  desbroceManual,
  desbroceMecanico,
  desratizacion;

  String get descripcion => switch (this) {
    TipoActividad.desherbajeSelectivo => 'desherbaje_selectivo',
    TipoActividad.desbroceManual      => 'desbroce_manual',
    TipoActividad.desbroceMecanico    => 'desbroce_mecanico',
    TipoActividad.desratizacion       => 'desratizacion',
  };

  String get etiqueta => switch (this) {
    TipoActividad.desherbajeSelectivo => 'Desherbaje Selectivo',
    TipoActividad.desbroceManual      => 'Desbroce Manual',
    TipoActividad.desbroceMecanico    => 'Desbroce Mecánico',
    TipoActividad.desratizacion       => 'Desratización',
  };

  static TipoActividad fromString(String? s) =>
    TipoActividad.values.firstWhere(
      (e) => e.descripcion == s,
      orElse: () => TipoActividad.desherbajeSelectivo,
    );
}

class ActividadEntity {
  final int id;
  final int posicionId;
  EstadoActividad estado;
  final String descripcion;
  final double superficieM2;
  final double costeEstimado;
  final DateTime fechaProgramada;
  final DateTime fechaInicio;
  final DateTime fechaFin;
  final List<SegmentoEntity> segmentos;

  ActividadEntity({
    required this.id,
    required this.posicionId,
    required this.estado,
    required this.descripcion,
    required this.superficieM2,
    required this.costeEstimado,
    required this.fechaProgramada,
    required this.fechaInicio,
    required this.fechaFin,
    required this.segmentos,
  });

  double get longitudTotal =>
    segmentos.fold(0.0, (sum, s) => sum + s.longitud);

  /// Etiqueta de tipo de actividad derivada de los segmentos.
  /// Si todos tienen el mismo tipo, devuelve su etiqueta; si hay varios, "Varios tipos".
  String get tipoLabel {
    if (segmentos.isEmpty) return '';
    final tipos = segmentos.map((s) => s.tipoActividad).toSet();
    if (tipos.length == 1) return tipos.first.etiqueta;
    return 'Varios tipos';
  }

  factory ActividadEntity.fromJson(Map<String, dynamic> json) {
    final segmentosRaw = json['segmentos'];
    List<SegmentoEntity> segs = [];
    if (segmentosRaw is String && segmentosRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(segmentosRaw) as List;
        segs = decoded
            .map((s) => SegmentoEntity.fromJson(s as Map<String, dynamic>))
            .toList();
      } catch (_) {}
    } else if (segmentosRaw is List) {
      segs = segmentosRaw
          .map((s) => SegmentoEntity.fromJson(s as Map<String, dynamic>))
          .toList();
    }
    return ActividadEntity(
      id: json['id'] as int? ?? 0,
      posicionId: json['posicion_id'] as int? ?? 0,
      estado: EstadoActividad.fromString(json['estado'] as String?),
      descripcion: json['descripcion'] as String? ?? '',
      superficieM2: (json['superficie_m2'] as num?)?.toDouble() ?? 0.0,
      costeEstimado: (json['coste_estimado'] as num?)?.toDouble() ?? 0.0,
      fechaProgramada: DateTime.tryParse(json['fecha_programada'] as String? ?? '') ?? DateTime.now(),
      fechaInicio: DateTime.tryParse(json['fecha_inicio'] as String? ?? '') ?? DateTime.now(),
      fechaFin: DateTime.tryParse(json['fecha_fin'] as String? ?? '') ?? DateTime.now(),
      segmentos: segs,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'posicion_id': posicionId,
    'estado': estado.descripcion,
    'descripcion': descripcion,
    'superficie_m2': superficieM2,
    'coste_estimado': costeEstimado,
    'fecha_programada': fechaProgramada.toIso8601String(),
    'fecha_inicio': fechaInicio.toIso8601String(),
    'fecha_fin': fechaFin.toIso8601String(),
    'segmentos': jsonEncode(segmentos.map((s) => s.toJson()).toList()),
  };
}
