import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../domain/entities/segmento_entity.dart';

/// Proveedor inyectable de los CTs del usuario logueado. Para resolver
/// `ctId` a partir del `ct` (texto) que viaja en el hitValue del polyline.
/// Cada record es `(ct: String, ctid: int)` — compatible con `UserCt`.
typedef LoggedUserCtsProvider = List<({String ct, int ctid})> Function();

/// Segmento resultante de un corte entre dos líneas sobre un gasoducto.
///
/// Se construye con la polyline original y los puntos extraídos. Los
/// metadatos (`name`, `ctId`, `traza`) se intentan resolver leyendo
/// `polyline.hitValue` por dynamic dispatch — si el hitValue no expone
/// `ct`/`name` los campos caen a sus defaults.
class PolylineSegment {
  PolylineSegment({
    required this.id,
    required this.points,
    required this.originalPolyline,
    required LoggedUserCtsProvider ctsProvider,
    String? name,
    int? ctId,
    String? ctname,
    String? traza,
    this.description = '',
    this.selected = false,
    TipoActividad? tipoActividad,
    EstadoActividad? estado,
  })  : ctId = ctId ?? _extractCtId(originalPolyline, ctsProvider),
        ctname = ctname ?? _extractCtName(originalPolyline),
        traza = traza ?? _extractTraza(originalPolyline),
        name = name ?? _extractName(originalPolyline),
        tipoActividad = tipoActividad ?? TipoActividad.desherbajeSelectivo,
        estado = estado ?? EstadoActividad.propuesta;

  final int id;
  final String name;
  final int ctId;

  /// Nombre del CT, leído del `hitValue` del polyline de gasoducto
  /// (`GasoductoHitData.ct`). Es el valor que se persiste en el segmento: su
  /// CT viaja por NOMBRE, no por id (contrato §3/§8).
  final String ctname;
  final String traza;
  final List<LatLng> points;
  final Polyline originalPolyline;

  bool selected;
  String description;
  TipoActividad tipoActividad;
  EstadoActividad estado;

  double get lengthInMeters {
    if (points.length < 2) return 0;
    const d = Distance();
    double total = 0;
    for (var i = 0; i < points.length - 1; i++) {
      total += d.as(LengthUnit.Meter, points[i], points[i + 1]);
    }
    return total;
  }

  LatLng get centerPoint {
    if (points.isEmpty) return const LatLng(0, 0);
    if (points.length == 1) return points[0];
    return points[points.length ~/ 2];
  }

  Polyline toPolyline({Color? color, double? strokeWidth}) => Polyline(
        points: points,
        color: color ?? originalPolyline.color,
        strokeWidth: strokeWidth ?? originalPolyline.strokeWidth,
        borderColor: originalPolyline.borderColor,
        borderStrokeWidth: originalPolyline.borderStrokeWidth,
      );

  // ─────────────────────────── Extractores ───────────────────────────

  static int _extractCtId(Polyline p, LoggedUserCtsProvider ctsProvider) {
    try {
      final hit = p.hitValue;
      if (hit == null) return 0;
      final ctName = (hit as dynamic).ct?.toString() ?? '';
      final direct = (hit as dynamic).ctId;
      if (direct is int && direct > 0) return direct;
      final cts = ctsProvider();
      if (cts.isEmpty) return 0;
      final match = cts.firstWhere(
        (c) => c.ct == ctName,
        orElse: () => cts.first,
      );
      return match.ctid;
    } catch (e) {
      debugPrint('PolylineSegment._extractCtId: $e');
    }
    return 0;
  }

  static String _extractCtName(Polyline p) {
    try {
      final hit = p.hitValue;
      if (hit != null) return (hit as dynamic).ct?.toString() ?? '';
    } catch (_) {}
    return '';
  }

  static String _extractTraza(Polyline p) {
    try {
      final hit = p.hitValue;
      if (hit != null) return (hit as dynamic).name?.toString() ?? '';
    } catch (_) {}
    return '';
  }

  static String _extractName(Polyline p) {
    try {
      final hit = p.hitValue;
      if (hit != null) {
        final ct = (hit as dynamic).ct?.toString() ?? '';
        final nm = (hit as dynamic).name?.toString() ?? '';
        if (ct.isNotEmpty && nm.isNotEmpty) return '$ct · $nm';
        if (nm.isNotEmpty) return nm;
        if (ct.isNotEmpty) return ct;
      }
    } catch (_) {}
    return 'Segmento sin nombre';
  }
}
