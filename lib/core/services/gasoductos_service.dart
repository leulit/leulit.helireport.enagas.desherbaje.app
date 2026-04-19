import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:get/get.dart';
import '../../data/repository/gasoductos_repository.dart';
import '../../domain/usecases/get_gasoductos_usecase.dart';

/// Servicio singleton que mantiene las trazas de gasoductos durante toda la sesión.
/// Las carga una sola vez desde el backend (o SQLite en offline) y las cachea en memoria.
/// Accesible desde cualquier pantalla via Get.find[GasoductosService]().
class GasoductosService extends GetxService {
  final _useCase = GetGasoductosUseCase(GasoductosRepository());

  final polylines = <Polyline>[].obs;
  final isLoading = false.obs;
  bool _loaded = false;

  bool get isLoaded => _loaded;

  /// Carga las trazas solo si no se han cargado aún en esta sesión.
  Future<void> ensureLoaded() async {
    if (_loaded || isLoading.value) return;
    isLoading.value = true;
    try {
      final result = await _useCase.execute();
      polylines.assignAll(result);
      _loaded = true;
      debugPrint('GasoductosService: ${result.length} polylines cargadas');
    } catch (e) {
      debugPrint('GasoductosService: error cargando trazas — $e');
    } finally {
      isLoading.value = false;
    }
  }

  /// Fuerza recarga desde red, ignorando la caché de sesión.
  Future<void> reload() async {
    _loaded = false;
    isLoading.value = true;
    try {
      final result = await _useCase.execute(forceRefresh: true);
      polylines.assignAll(result);
      _loaded = true;
    } catch (e) {
      debugPrint('GasoductosService: error recargando trazas — $e');
    } finally {
      isLoading.value = false;
    }
  }
}
