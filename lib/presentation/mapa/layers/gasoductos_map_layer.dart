import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:get/get.dart';

import '../../../core/app_di.dart';

/// Capa de polylines de gasoductos.
///
/// `service.polylines` es un `RxList`, pero envolver `PolylineLayer` en un
/// `Obx` que hace `.toList()` en cada build crea una `List` NUEVA cada vez
/// que este widget se reconstruye — incluso si los datos no cambiaron
/// (p.ej. por un rebuild de un ancestro no relacionado). Eso produce una
/// instancia nueva de `PolylineLayer` en cada frame y Flutter invoca
/// `didUpdateWidget`, que invalida INCONDICIONALMENTE la caché de
/// proyección y de simplificación Douglas-Peucker de TODAS las polylines
/// (`flutter_map` 8.3.1, `layer_projection_simplification/state.dart:52-59`).
///
/// Aquí cacheamos el widget `PolylineLayer` completo y solo lo
/// reconstruimos cuando el servicio publica datos nuevos (vía `ever`), de
/// modo que en el resto de frames `build()` devuelve la MISMA instancia de
/// widget: Flutter la detecta idéntica (`Element.updateChild`) y ni
/// siquiera llama a `didUpdateWidget`.
class GasoductosMapLayer extends StatefulWidget {
  const GasoductosMapLayer({super.key});

  @override
  State<GasoductosMapLayer> createState() => _GasoductosMapLayerState();
}

class _GasoductosMapLayerState extends State<GasoductosMapLayer> {
  late Widget _layer;
  Worker? _worker;

  @override
  void initState() {
    super.initState();
    final service = AppDI.gasoductosService;
    _layer = PolylineLayer(polylines: service.polylines.toList());
    _worker = ever<List<Polyline>>(service.polylines, (lines) {
      setState(() => _layer = PolylineLayer(polylines: lines.toList()));
    });
  }

  @override
  void dispose() {
    _worker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _layer;
}
