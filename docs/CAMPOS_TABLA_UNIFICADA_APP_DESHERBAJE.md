# Campos de `tabla_unificada` que usa (y que no usa) la app de desherbaje

> **Alcance:** solo `leulit_helireport_enagas_desherbaje_app`. Backend, webapp y app
> Helireport quedan fuera. Fecha del análisis: 2026-07-29.

---

## Resumen

La app toca `tabla_unificada` por **un único sitio**: la descarga de **posiciones fijas**
(`GET /api/enagas/v1/incidencias/posicionesfijasbycts/{cts}`), que se pinta como capa de
marcadores verdes en el mapa global. **Nunca escribe** en esa tabla.

De las **56 columnas**:

| | Columnas | Qué significa |
|---|---:|---|
| **Se usan de verdad** | 7 | Llegan a la app y alguien las lee |
| **Uso solo técnico** | 3 | Solo sirven para calcular la fecha de sincronización |
| **Llegan pero nadie las lee** | 7 | Se parsean y se guardan en SQLite; ninguna pantalla las consulta |
| **La app nunca las ve** | 39 | Ni se parsean ni existen para la app |

**39 de 56 columnas (70 %) no existen para esta app. Otras 7 llegan y se tiran.**

---

## 1. Columnas que se usan de verdad (7)

| Columna | Para qué la usa la app |
|---|---|
| `id` | Identidad remota del marcador (`remoteId`), deduplicación en el pull |
| `title` | Texto de la etiqueta del marcador en el mapa |
| `fixed_latitude` | Coordenada **preferente** del marcador |
| `fixed_longitude` | Coordenada **preferente** del marcador |
| `latitud` | Coordenada de respaldo si `fixed_*` es inválida (nula, NaN o 0,0) |
| `longitud` | Coordenada de respaldo, igual que arriba |
| `ctname` | Filtra qué posiciones descarga cada operario; se guarda e indexa en local |

Eso es todo lo que necesita la capa: un punto y una etiqueta.

## 2. Columnas de uso solo técnico (3)

No se muestran en ninguna pantalla. Solo alimentan el `updated_at` que el motor offline
usa para resolver conflictos, con esta cascada de respaldo:

`updated_at` → `iupdated` → `icreated` → `fecha` → época 0

| Columna | Papel |
|---|---|
| `iupdated` | 2.º respaldo de la fecha de sincronización |
| `icreated` | 3.er respaldo |
| `fecha` | 4.º y último respaldo |

## 3. Columnas que llegan pero nadie lee (7)

Se parsean, se escriben en la tabla local `posiciones_fijas` de SQLite y **ninguna
pantalla las consulta**. Son peso muerto en el móvil.

| Columna | Estado |
|---|---|
| `zona` | Parseada y guardada, nunca leída |
| `tramo` | Parseada y guardada, nunca leída |
| `subtramo` | Parseada y guardada, nunca leída |
| `tipo_punto` | Parseada y guardada, nunca leída |
| `tipovigilancia` | Parseada y guardada, nunca leída |
| `trazaname` | Parseada y guardada, nunca leída |
| `fotos` | Parseada y guardada, nunca leída |

## 4. Columnas que la app nunca ve (39)

Ni se parsean ni aparecen en ningún sitio del código de la app.

**Ciclo de vida y auditoría (12)**
`tipo`, `status`, `deleted`, `idusuario`, `revisada`, `archivada`, `publicada`,
`noaplica`, `operador`, `app_origen`, `origen`, `external_id`

**Gestión y comunicación (5)**
`operadorgestor`, `infogestor`, `gestoroperador`, `feedback`, `comentario_it`

**Clasificación (6)**
`clasificacion_primaria`, `clasificacion`, `tipomedia`, `satelite_classification`,
`satelite_entity_type`, `anomalia`

**Geografía y traza (9)**
`videopolylineencoded`, `geometry`, `pipeline_name`, `distancia_traza`, `coordId`,
`bearing`, `fk_idGPSFiles`, `gerencia`, `diametro`

**Medición técnica (2)**
`proteccion_catodica`, `medicion_gas`

**Relaciones (3)**
`padre`, `fk_inspeccion`, `fk_contrato`

**Otros (2)**
`exifDateTime`, `cosmic_eye_url`

---

## 5. Lo que este documento NO dice

- **No dice que estas columnas se puedan borrar.** La app de desherbaje es un consumidor
  de los muchos que tiene `tabla_unificada` (webapp, app Helireport, informes, crons).
  Para decidir un borrado hace falta el mismo análisis sobre esos consumidores.
- **No dice qué envía realmente el backend.** El análisis mira qué claves *lee* la app.
  Si el endpoint devuelve columnas de más, la app las ignora en silencio; verificarlo es
  trabajo del proyecto de backend.
- **Los hitos, PKs y gasoductos quedan aparte.** Llegan como ficheros GeoJSON estáticos
  (`/tracks/json/{ct}-…json`) y sus `properties` no llevan nombres de columna de
  `tabla_unificada`. De dónde salen esos ficheros no se puede saber desde la app.

## 6. Hallazgos colaterales (código muerto en la app)

Encontrados durante el análisis. **No se ha tocado nada**: son cambios de funcionalidad
que requieren tu visto bueno.

| Qué | Dónde | Estado |
|---|---|---|
| `ApiEndpoints.imagenAdd` (`/operador/additem`) | `lib/core/api_endpoints.dart:103` | Declarado, nunca llamado. Era la única vía de **escritura** a `tabla_unificada` |
| `ApiEndpoints.incidenciaThumb` | `lib/core/api_endpoints.dart:161` | Declarado, nunca llamado. El comentario dice "mock data en `captura_fotos_controller`" — ese uso ya no existe |
| `PosicionFijaLocalStore.findByCtNames` | `lib/data/sync/posicion_fija_local_store.dart:181` | Definido, nunca llamado (el mapa usa `findAll`) |
| 7 columnas sobrantes en SQLite local | `posiciones_fijas` (mismo fichero, líneas 26-47) | Las de la §3: se escriben en cada pull y no las lee nadie |

## 7. Cómo se ha comprobado

| Paso | Fichero |
|---|---|
| Único endpoint de `incidencias` que se llama | `lib/data/sync/posicion_fija_remote_fetcher.dart:42` |
| Claves JSON que se parsean (16) | `lib/domain/entities/posicion_fija_entity.dart:7-30` |
| Columnas que se persisten en local | `lib/data/sync/posicion_fija_local_store.dart:26-47` |
| Campos que consume la interfaz | `lib/presentation/mapa/layers/posiciones_fijas_map_controller.dart:45-48`<br>`lib/presentation/mapa/layers/posiciones_fijas_map_layer.dart:23-24` |
| Búsqueda del resto de nombres de columna en `lib/` | Sin coincidencias (los aciertos de `geometry` y `fotos` son GeoJSON propio y textos de interfaz, no la tabla) |
