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
  });

  @override
  State<ClusteredMarkerLayer<T>> createState() =>
      _ClusteredMarkerLayerState<T>();
}

class _ClusteredMarkerLayerState<T> extends State<ClusteredMarkerLayer<T>> {
  SuperclusterImmutable<T>? _index;

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
  }

  void _rebuildIndex() {
    if (widget.points.isEmpty) {
      _index = null;
      return;
    }
    final index = SuperclusterImmutable<T>(
      getX: (p) => widget.getPosition(p).longitude,
      getY: (p) => widget.getPosition(p).latitude,
      minZoom: 1,
      maxZoom: 20,
      radius: 80,
      extent: 512,
      minPoints: 2,
    )..load(widget.points);
    _index = index;
  }

  @override
  Widget build(BuildContext context) {
    final index = _index;
    if (index == null) return const SizedBox.shrink();

    final camera = MapCamera.of(context);
    if (camera.zoom < widget.minZoom) return const SizedBox.shrink();

    final bounds = camera.visibleBounds;
    final elements = index.search(
      bounds.west,
      bounds.south,
      bounds.east,
      bounds.north,
      camera.zoom.ceil(),
    );

    final markers = <Marker>[];
    for (final element in elements) {
      if (element is ImmutableLayerCluster<T>) {
        final position = LatLng(element.latitude, element.longitude);
        markers.add(Marker(
          key: ValueKey('cluster-${element.latitude}-${element.longitude}'),
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

    return MarkerLayer(markers: markers);
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
