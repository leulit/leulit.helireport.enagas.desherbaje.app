import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supercluster/supercluster.dart';

/// Capa de marcadores con clustering espacial + culling por viewport.
///
/// Indexa TODOS los puntos una sola vez en `SuperclusterImmutable` y en cada
/// cambio de cámara pide solo los del `visibleBounds` al zoom actual. Sin esto
/// un `MarkerLayer` crudo construye un widget por punto: con los ~48.000 hitos
/// del operador el frame no llega a completarse y la capa se ve vacía.
///
/// El índice se reconstruye únicamente cuando cambia la lista de puntos
/// (identidad o longitud), no en cada pan.
class ClusteredMarkerLayer<T> extends StatefulWidget {
  /// Puntos a representar (dominio, no widgets).
  final List<T> points;

  /// Posición geográfica de un punto.
  final LatLng Function(T point) getPosition;

  /// Widget del marcador individual.
  final Widget Function(T point) buildMarker;

  /// Ancho del marcador individual, en píxeles.
  final double Function(T point) markerWidth;

  /// Alto del marcador individual, en píxeles.
  final double markerHeight;

  /// Alineación del marcador individual respecto a su punto.
  ///
  /// `topCenter` dibuja la etiqueta ENCIMA del punto, de modo que el pico
  /// inferior de [PointLabelMarker] apunta a la coordenada exacta. Con
  /// `bottomCenter` la etiqueta cae debajo y el pico queda desplazado
  /// [markerHeight] píxeles al sur.
  final Alignment markerAlignment;

  /// Color del globo de cluster.
  final Color clusterColor;

  /// Por debajo de este zoom la capa no pinta nada.
  final double minZoom;

  /// Zoom mínimo con el que se construye el índice `SuperclusterImmutable`.
  ///
  /// `search` solo se invoca con `camera.zoom.ceil()` cuando
  /// `camera.zoom >= minZoom` ([build] corta antes con `SizedBox.shrink`),
  /// así que el índice nunca necesita niveles por debajo de ese umbral. Por
  /// defecto se calcula como `minZoom.floor() - 1`: el margen de un nivel
  /// absorbe el redondeo `floor`/`ceil` justo en el borde del umbral (p.ej.
  /// `minZoom: 14.0` exacto → primer `zoom.ceil()` posible es 14). Un valor
  /// más bajo del necesario solo construye KD-trees de más (coste de índice,
  /// no de frame); uno más alto que el zoom realmente consultado SÍ sería un
  /// bug — `SuperclusterImmutable._limitZoom` clampa hacia arriba, así que
  /// devolvería el nivel de agregación equivocado (de más) en vez de lanzar.
  final int? indexMinZoom;

  /// Invocado en cada búsqueda real sobre el índice (cache miss). Solo para
  /// instrumentación de tests — no se usa en producción.
  @visibleForTesting
  final VoidCallback? onSearchPerformed;

  const ClusteredMarkerLayer({
    super.key,
    required this.points,
    required this.getPosition,
    required this.buildMarker,
    required this.markerWidth,
    required this.clusterColor,
    this.markerHeight = 30,
    this.markerAlignment = Alignment.topCenter,
    this.minZoom = 14,
    this.indexMinZoom,
    this.onSearchPerformed,
  });

  @override
  State<ClusteredMarkerLayer<T>> createState() =>
      _ClusteredMarkerLayerState<T>();
}

class _ClusteredMarkerLayerState<T> extends State<ClusteredMarkerLayer<T>> {
  /// Cuánto se acolcha el `visibleBounds` de una búsqueda, como fracción del
  /// ancho/alto visible a cada lado. Con 0.35 un pan pequeño (el caso normal
  /// entre dos frames) sigue CONTENIDO en el colchón y no dispara una
  /// búsqueda nueva; solo cruzar ese margen (o cambiar de nivel de zoom
  /// entero) rehace `index.search` y reconstruye el `MarkerLayer`.
  static const double _boundsPadding = 0.35;

  SuperclusterImmutable<T>? _index;

  // Memo de la última búsqueda: mientras la cámara se mueva dentro de
  // [_cachedSearchBounds] y no cambie el zoom entero, se devuelve la MISMA
  // instancia de [MarkerLayer]. Reusar la instancia es lo que importa: si
  // `didUpdateWidget` de `MarkerLayer` no ve un widget nuevo no invalida su
  // caché de proyección (`_projectedPoints`), que es el coste real evitado.
  LatLngBounds? _cachedSearchBounds;
  int? _cachedZoom;
  MarkerLayer? _cachedLayer;

  @override
  void initState() {
    super.initState();
    _rebuildIndex();
  }

  @override
  void didUpdateWidget(covariant ClusteredMarkerLayer<T> old) {
    super.didUpdateWidget(old);
    // `RxList` reasigna contenido conservando la instancia, así que comparar
    // solo por identidad dejaría el índice obsoleto tras cargar de caché.
    if (!identical(old.points, widget.points) ||
        old.points.length != widget.points.length) {
      _rebuildIndex();
    }
    // Cualquier prop nueva (color, builder, alineación...) invalida el memo:
    // es la única forma de garantizar que el `MarkerLayer` cacheado sigue
    // reflejando lo que este `build` pintaría de cero.
    _invalidateMemo();
  }

  void _rebuildIndex() {
    if (widget.points.isEmpty) {
      _index = null;
      _invalidateMemo();
      return;
    }
    final index = SuperclusterImmutable<T>(
      getX: (p) => widget.getPosition(p).longitude,
      getY: (p) => widget.getPosition(p).latitude,
      minZoom: widget.indexMinZoom ?? math.max(0, widget.minZoom.floor() - 1),
      maxZoom: 20,
      radius: 80,
      extent: 512,
      minPoints: 2,
    )..load(widget.points);
    _index = index;
    _invalidateMemo();
  }

  void _invalidateMemo() {
    _cachedSearchBounds = null;
    _cachedZoom = null;
    _cachedLayer = null;
  }

  /// [bounds] acolchado con [_boundsPadding] a cada lado. Clampado a los
  /// límites válidos de lat/lng — `LatLngBounds.unsafe` no los recorta solo.
  LatLngBounds _padBounds(LatLngBounds bounds) {
    final latPad = (bounds.north - bounds.south) * _boundsPadding;
    final lngPad = (bounds.east - bounds.west) * _boundsPadding;
    return LatLngBounds.unsafe(
      north: math.min(90.0, bounds.north + latPad),
      south: math.max(-90.0, bounds.south - latPad),
      east: math.min(180.0, bounds.east + lngPad),
      west: math.max(-180.0, bounds.west - lngPad),
    );
  }

  @override
  Widget build(BuildContext context) {
    final index = _index;
    if (index == null) return const SizedBox.shrink();

    final camera = MapCamera.of(context);
    if (camera.zoom < widget.minZoom) return const SizedBox.shrink();

    final visibleBounds = camera.visibleBounds;
    final zoom = camera.zoom.ceil();

    final cachedLayer = _cachedLayer;
    final cachedSearchBounds = _cachedSearchBounds;
    if (cachedLayer != null &&
        cachedSearchBounds != null &&
        _cachedZoom == zoom &&
        cachedSearchBounds.containsBounds(visibleBounds)) {
      // `MarkerLayer` ya hace su propio culling por `pixelBounds` en cada
      // frame, así que devolver la misma instancia (con marcadores del
      // colchón fuera de pantalla) es correcto visualmente: nada de lo que
      // el usuario ve cambia por reusarla.
      return cachedLayer;
    }

    final searchBounds = _padBounds(visibleBounds);
    widget.onSearchPerformed?.call();
    final elements = index.search(
      searchBounds.west,
      searchBounds.south,
      searchBounds.east,
      searchBounds.north,
      zoom,
    );

    final markers = <Marker>[];
    for (final element in elements) {
      if (element is ImmutableLayerCluster<T>) {
        final position = LatLng(element.latitude, element.longitude);
        markers.add(Marker(
          key: ValueKey(element.id),
          point: position,
          width: 44,
          height: 44,
          child: _ClusterBubble(
            count: element.numPoints,
            color: widget.clusterColor,
            onTap: () => MapController.of(context)
                .move(position, (element.highestZoom + 3).toDouble()),
          ),
        ));
      } else if (element is ImmutableLayerPoint<T>) {
        final point = element.originalPoint;
        markers.add(Marker(
          point: widget.getPosition(point),
          width: widget.markerWidth(point),
          height: widget.markerHeight,
          alignment: widget.markerAlignment,
          child: widget.buildMarker(point),
        ));
      }
    }

    final layer = MarkerLayer(markers: markers);
    _cachedSearchBounds = searchBounds;
    _cachedZoom = zoom;
    _cachedLayer = layer;
    return layer;
  }
}

class _ClusterBubble extends StatelessWidget {
  final int count;
  final Color color;
  final VoidCallback onTap;

  const _ClusterBubble({
    required this.count,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFF263238), width: 1.5),
          boxShadow: const [
            BoxShadow(color: Colors.black38, blurRadius: 3, offset: Offset(0, 1)),
          ],
        ),
        child: Text(
          '$count',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: Colors.black,
          ),
        ),
      ),
    );
  }
}
