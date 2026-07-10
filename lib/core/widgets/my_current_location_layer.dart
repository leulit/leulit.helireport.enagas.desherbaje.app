import 'package:flutter/material.dart';
import 'package:flutter_map_location_marker/flutter_map_location_marker.dart';

class MyCurrentLocationLayer extends StatelessWidget {
  final AlignOnUpdate alignPositionOnUpdate;
  final AlignOnUpdate alignDirectionOnUpdate;

  /// Empuja un evento (zoom) para recentrar el marcador en la posición actual.
  final Stream<double?>? alignPositionStream;

  const MyCurrentLocationLayer({
    super.key,
    this.alignPositionOnUpdate = AlignOnUpdate.never,
    this.alignDirectionOnUpdate = AlignOnUpdate.never,
    this.alignPositionStream,
  });

  @override
  Widget build(BuildContext context) {
    final nsize = 15.0;
    final size = Size(nsize, nsize);
    return CurrentLocationLayer(
      alignPositionStream: alignPositionStream,
      alignPositionOnUpdate: AlignOnUpdate.never,
      alignDirectionOnUpdate: AlignOnUpdate.never,
      style: LocationMarkerStyle(
        marker: DefaultLocationMarker(
          child: Icon(
            Icons.navigation,
            color: Colors.white,
            size: nsize * 0.5,
          ),
        ),
        markerSize: size,
        markerDirection: MarkerDirection.heading,
      ),
    );
  }
}
