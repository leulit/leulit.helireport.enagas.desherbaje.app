import 'package:get/get.dart';

/// Registra en el binding de un `GetPage` el controller de esa pantalla.
///
/// Usar SIEMPRE esto en vez de `Get.lazyPut` para controllers de pantalla.
/// `Get.offAllNamed` EMPUJA la ruta nueva antes de destruir las viejas
/// (Flutter no libera una ruta marcada para borrado mientras la de arriba
/// está animando: `navigator.dart`, `_RouteLifecycle.removing` +
/// `canRemoveOrAdd`), así que el binding de la ruta nueva corre ANTES de que
/// muera la vieja. Y el borrado por ruta de GetX es por TIPO
/// (`_removeDependencyByRoute` → `delete(key: 'XController')`): al morir la
/// ruta vieja se lleva por delante el controller RECIÉN creado. Resultado:
/// `onClose()` ejecutado sobre la pantalla visible —"A TextEditingController
/// was used after being disposed", workers muertos— y una instancia zombi que
/// queda registrada y se reutiliza en el siguiente acceso (se ven los datos
/// de la visita anterior).
///
/// GetX ya tiene el mecanismo para absorber ese borrado tardío (`lateRemove`:
/// si el factory está `isDirty`, `delete` mata la instancia ANTERIOR y respeta
/// la nueva), pero `_insert` crea el factory de reemplazo con
/// `isDirty = false` (get 4.7.3, `get_instance.dart`), así que nunca se arma.
/// `markAsDirty` lo arma.
void putScreenController<T>(InstanceBuilderCallback<T> builder) {
  Get.lazyPut<T>(builder);
  GetInstance().markAsDirty<T>();
}
