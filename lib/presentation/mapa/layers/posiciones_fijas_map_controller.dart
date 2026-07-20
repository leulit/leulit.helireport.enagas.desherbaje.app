import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:latlong2/latlong.dart';
import 'package:leulit_flutter_dependency_injection/leulit_flutter_dependency_injection.dart';

import '../../../core/app_log.dart';
import '../../../data/sync/posicion_fija_local_store.dart';
import '../../../domain/entities/posicion_fija_entity.dart';

/// Marcador de mapa derivado de una [PosicionFijaEntity] con coordenadas
/// válidas.
class PosicionFijaMarkerInfo {
  final PosicionFijaEntity posicionFija;
  final LatLng point;

  const PosicionFijaMarkerInfo({
    required this.posicionFija,
    required this.point,
  });

  String get label => posicionFija.title;
}

/// Controller de presentación para la capa de posiciones fijas del mapa
/// global. Entidad **pull-only**: solo lee de [PosicionFijaLocalStore], nunca
/// llama a red — el pull real lo dispara la página de sincronización.
class PosicionesFijasMapController extends GetxController {
  PosicionesFijasMapController({PosicionFijaLocalStore? store})
      : _store = store ?? DI.get<PosicionFijaLocalStore>();

  final PosicionFijaLocalStore _store;

  final ValueNotifier<List<PosicionFijaMarkerInfo>> marcadores =
      ValueNotifier<List<PosicionFijaMarkerInfo>>(const []);
  final isLoading = false.obs;
  final error = Rx<String?>(null);

  Future<void> load() async {
    isLoading.value = true;
    error.value = null;
    try {
      final fetched = await _store.findAll();
      final mapped = <PosicionFijaMarkerInfo>[];
      for (final p in fetched) {
        if (!p.hasValidPoint) continue;
        mapped.add(PosicionFijaMarkerInfo(
          posicionFija: p,
          point: LatLng(p.displayLatitude!, p.displayLongitude!),
        ));
      }
      marcadores.value = List<PosicionFijaMarkerInfo>.unmodifiable(mapped);
    } catch (e, st) {
      error.value = 'Error cargando posiciones fijas';
      AppLog.w(
        'PosicionesFijasMapController.load: error',
        error: e,
        stackTrace: st,
      );
    } finally {
      isLoading.value = false;
    }
  }
}
