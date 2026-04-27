import 'package:flutter/material.dart';
import 'package:flutter_map_location_marker/flutter_map_location_marker.dart';

class MyCurrentLocationLayer extends StatelessWidget {
  const MyCurrentLocationLayer({super.key});

  @override
  Widget build(BuildContext context) {
    final nsize = 15.0;
    final size = Size(nsize, nsize);
    return CurrentLocationLayer(
      alignPositionOnUpdate: AlignOnUpdate.never,
      alignDirectionOnUpdate: AlignOnUpdate.never,
      style: LocationMarkerStyle(
        marker: DefaultLocationMarker(
          child: Icon(
            Icons.navigation,
            color: Colors.white,
            size: nsize*0.5, 
          ),
        ),
        markerSize: size,
        markerDirection: MarkerDirection.heading,
      ),
    );
  }
}