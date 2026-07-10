import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:get/get.dart';
import 'package:latlong2/latlong.dart';

import '../../core/app_typed_actions.dart';
import '../../core/gis/media_gis_map_geometry.dart';
import '../../core/my_getx_controller.dart';

/// Modo de la banda de dirección de vídeo:
/// - `true`  → trapecios robustos (RDP + polígonos por segmento). Sin agujeros.
/// - `false` → primera versión (`directionBandPolygon`, un único polígono; con
///   GPS ruidoso se auto-corta y muestra agujeros). Poner en `false` para
///   volver a la v1 sin tocar el resto del código.
const bool kMediaBandTrapezoids = true;

/// Snapshot inmutable de la geometría a pintar para la media activa. Un único
/// objeto agrupa las tres capas para que un cambio = un solo rebuild.
@immutable
class MediaGisGeometry {
  final List<Polygon> polygons;
  final List<Polyline> polylines;
  final List<Marker> markers;

  const MediaGisGeometry({
    required this.polygons,
    required this.polylines,
    required this.markers,
  });

  const MediaGisGeometry.empty()
      : polygons = const [],
        polylines = const [],
        markers = const [];
}

/// Controller del [MediaGisLayer]: escucha el TypedAction
/// [AppTypedActions.mediaGisActivada] y traduce el `gis_json` de la media
/// activa a geometría de mapa (marker + flecha de dirección para foto;
/// polyline de traza + banda de dirección para vídeo).
///
/// Reactividad con primitiva Flutter ([ValueNotifier]/[ValueListenableBuilder]):
/// un único snapshot [geometry] => un solo rebuild de las tres capas. Es
/// `MyGetxController` solo para el ciclo de vida del handler ([onTypedAction],
/// desconectado en `onClose`) y su resolución por DI.
class MediaGisLayerController extends MyGetxController {
  final geometry =
      ValueNotifier<MediaGisGeometry>(const MediaGisGeometry.empty());

  @override
  void myOnInit() {
    onTypedAction<MediaGisActivada>(
      AppTypedActions.mediaGisActivada,
      (event) => _rebuild(event.data),
    );
  }

  @override
  void onClose() {
    geometry.dispose();
    super.onClose();
  }

  /// Reconstruye la geometría a partir de la media activa. gis_json null/vacío
  /// (media sin GIS o lista vacía) => limpia el layer. Si hay geometría, emite
  /// [AppTypedActions.mediaGisBoundsRequested] con los bounds a encuadrar.
  void _rebuild(MediaGisActivada? data) {
    final markers = <Marker>[];
    final polylines = <Polyline>[];
    final polygons = <Polygon>[];
    final focus = <LatLng>[];

    final gis = data?.gisJson;
    if (gis != null && gis.isNotEmpty) {
      if (data!.isVideo) {
        _buildVideo(gis, markers, polylines, polygons, focus);
      } else {
        _buildPhoto(gis, markers, polylines, focus);
      }
    }

    geometry.value = MediaGisGeometry(
      polygons: polygons,
      polylines: polylines,
      markers: markers,
    );

    if (focus.isNotEmpty) {
      AppTypedActions.mediaGisBoundsRequested
          .dispatch(data: LatLngBounds.fromPoints(focus));
    }
  }

  void _buildVideo(String gis, List<Marker> markers, List<Polyline> polylines,
      List<Polygon> polygons, List<LatLng> focus) {
    final track = parseVideoTrack(gis);
    if (track.isEmpty) return;
    final pts = [for (final v in track) v.point];

    // Banda de dirección de cámara (relleno semitransparente, bajo la traza).
    if (kMediaBandTrapezoids) {
      for (final quad in directionBandTrapezoids(track)) {
        polygons.add(_bandPoly(quad));
        focus.addAll(quad);
      }
    } else {
      final band = directionBandPolygon(track); // v1 (fallback)
      if (band.isNotEmpty) {
        polygons.add(_bandPoly(band));
        focus.addAll(band);
      }
    }

    if (pts.length >= 2) {
      polylines.add(Polyline(
        points: pts,
        color: Colors.deepPurpleAccent,
        strokeWidth: 4,
        borderColor: Colors.white,
        borderStrokeWidth: 1,
      ));
    }
    markers.add(_pin(pts.first, Colors.deepPurpleAccent));
    focus.addAll(pts);
  }

  Polygon _bandPoly(List<LatLng> ring) => Polygon(
        points: ring,
        color: Colors.deepPurpleAccent.withValues(alpha: 0.5),
        borderColor: Colors.transparent,
        borderStrokeWidth: 0,
      );

  void _buildPhoto(String gis, List<Marker> markers, List<Polyline> polylines,
      List<LatLng> focus) {
    final photo = parsePhotoGis(gis);
    if (photo == null) return;
    markers.add(_pin(photo.point, Colors.redAccent));
    focus.add(photo.point);
    final heading = photo.heading;
    if (heading != null) {
      final arrow = arrowGeometry(photo.point, heading);
      polylines.add(Polyline(
        points: arrow.shaft,
        color: Colors.redAccent,
        strokeWidth: 3,
      ));
      polylines.add(Polyline(
        points: arrow.head,
        color: Colors.redAccent,
        strokeWidth: 3,
      ));
      focus
        ..addAll(arrow.shaft)
        ..addAll(arrow.head);
    }
  }

  /// Marcador de punto: círculo de color con borde blanco (estilo
  /// `MyCurrentLocationLayer`). El color distingue foto (rojo) de vídeo
  /// (púrpura), sin colisionar con el azul de la capa de ubicación.
  Marker _pin(LatLng point, Color color) {
    return Marker(
      point: point,
      width: 18,
      height: 18,
      child: Container(
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 3)],
        ),
      ),
    );
  }
}

/// Layer custom de flutter_map que pinta la georreferencia de la media activa
/// del carrusel Antes/Después. Reacciona al TypedAction
/// [AppTypedActions.mediaGisActivada]. Debe colocarse como hijo de [FlutterMap].
///
/// `StatelessWidget` + `GetView`: la suscripción al action vive en
/// [MediaGisLayerController] (registrado en el binding); el render reacciona
/// con [ValueListenableBuilder] sobre un único snapshot.
class MediaGisLayer extends GetView<MediaGisLayerController> {
  const MediaGisLayer({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<MediaGisGeometry>(
      valueListenable: controller.geometry,
      builder: (_, g, __) => Stack(
        children: [
          PolygonLayer(polygons: g.polygons),
          PolylineLayer(polylines: g.polylines),
          MarkerLayer(markers: g.markers),
        ],
      ),
    );
  }
}
