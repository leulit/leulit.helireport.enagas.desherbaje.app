/// Metadatos mínimos que se adjuntan como `hitValue` a cada Polyline de
/// gasoducto para que el motor de corte pueda resolver el CT y la traza del
/// segmento resultante.
///
/// Los campos [ct] y [name] se leen por dynamic dispatch desde el extractor
/// de `PolylineSegment` (compat con el contrato de la webapp).
class GasoductoHitData {
  const GasoductoHitData({
    required this.id,
    required this.ctId,
    required this.ct,
    required this.name,
  });

  final String id;
  final int ctId;
  final String ct;
  final String name;

  @override
  String toString() => id;
}
