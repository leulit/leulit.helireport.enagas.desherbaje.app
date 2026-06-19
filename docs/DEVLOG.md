# DEVLOG

## 2026-06-18 — Matriz de transiciones de estado de segmento (app campo)

Portado el patrón de la webapp: SSOT de transiciones en el enum `EstadoActividad`
+ defensa en profundidad (dropdown filtrado + guard antes de guardar).

**Decisiones del responsable (no las decidió Claude):**
- Matriz **adaptada a operario** (no la verbatim de la webapp): `contratista→ejecución`,
  `ejecución→finalizada`, `finalizada→{cerrada, ejecución}`. `propuesta`/`validada`/`cerrada`
  sin transición de salida ⇒ solo lectura desde la app de campo (los gestiona el gestor;
  `cerrada` es terminal). Permanecer en el mismo estado siempre es válido.
- Serialización: se **mantiene** `EstadoActividad.contratista.descripcion = 'contratista'`
  (no se alinea a `'contratita'` de la webapp). ⚠️ Pendiente confirmar con backend si comparten
  BD: `fromString` normaliza tildes pero no la `s` que falta, así que un `contratita` del
  backend caería a `propuesta`.

**Cambios:**
- `lib/domain/entities/segmento_entity.dart` — `transicionesPermitidas`, `esEditableDesdeApp`,
  `puedeIrA` en `EstadoActividad` (SSOT). Cambiar la matriz = tocar solo este getter.
- `lib/presentation/detalle/segmento_detalle_page.dart` — `_estadosEditables(origen)` filtra
  por `origen.puedeIrA` sobre el **estado original** (`controller.segmento.estado`), no el editable.
  Eliminada la lista fija `_estadosEditablesBase`.
- `lib/presentation/detalle/segmento_detalle_controller.dart` — `_validateEstado()` reemplaza a
  `_validateEstadoEditable()`; diálogos `_dialogEstadoBloqueado` / `_dialogTransicionInvalida`.
- Tests: grupo de matriz en `test/domain/entities/segmento_entity_test.dart`.

**Supuesto a validar:** `propuesta`/`validada`/`cerrada` se tratan como solo lectura **total**
(igual que el comportamiento previo): `guardar()` aborta con diálogo. Si se prefiere el patrón
webapp puro (editar descripción/fotos en esos estados y bloquear solo el cambio de estado),
relajar el primer branch de `_validateEstado()`.

Verificación: `flutter analyze` limpio; `flutter test` afectados 47/47 OK.
