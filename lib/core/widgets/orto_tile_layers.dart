import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../api_endpoints.dart';

/// Par de capas base de ortofoto, compartido por los 3 mapas de la app
/// (mapa global, detalle de segmento, edición de extremos).
///
/// Se apilan DOS `TileLayer` (respaldo debajo, PNOA encima) en vez de usar
/// `fallbackUrl` en una sola capa: `NetworkTileImageProvider.operator ==`
/// devuelve `false` siempre que `fallbackUrl != null` (ver
/// `flutter_map-8.3.1/lib/src/layer/tile_layer/tile_provider/network/image_provider/image_provider.dart`,
/// al final), lo que anula el `ImageCache` de Flutter — cada tile que
/// reaparece se redecodifica — y además el tile de respaldo nunca llega a
/// guardarse en la caché de disco. Apilando dos capas SIN `fallbackUrl` se
/// conserva la resistencia a huecos de cobertura de PNOA y se recuperan
/// ambas cachés (memoria + disco).
List<Widget> buildOrtoTileLayers() => [
      // Capa de respaldo (ArcGIS World Imagery): cobertura completa pero
      // resolución menor. Va debajo, se ve donde PNOA no tiene tile.
      TileLayer(
        urlTemplate: ApiEndpoints.arcgisImagery,
        maxNativeZoom: 15,
        tileDisplay: const TileDisplay.instantaneous(),
        userAgentPackageName: 'com.leulit.enagas.helireport_desherbaje',
      ),
      // Capa principal (PNOA WMTS): ortofoto oficial de España, mayor
      // resolución. Va encima.
      TileLayer(
        urlTemplate: ApiEndpoints.pnoaWmts,
        maxNativeZoom: 20,
        userAgentPackageName: 'com.leulit.enagas.helireport_desherbaje',
      ),
    ];

// ─────────────────────────── Caché de tiles ────────────────────────────────
//
// Parámetros centralizados aquí (único sitio) para que `AppDI._init()` y
// `SincronizacionController.resetAppData()` no repitan literales sueltos.

/// Techo de tamaño de la caché de tiles en disco.
const int _mapTileCacheMaxSize = 200 * 1024 * 1024;

/// Antigüedad máxima antes de considerar un tile "no fresco". Sin esto, un
/// tile viejo fuerza ida a red con `If-Modified-Since` y, sin cobertura, cae
/// a tile transparente. Con 365 días se sirve de disco offline; la ortofoto
/// PNOA se actualiza ~anualmente, así que un tile de hace meses sigue siendo
/// válido.
const Duration _mapTileCacheFreshAge = Duration(days: 365);

/// Configura (o recupera) el singleton de caché de tiles con los parámetros
/// del proyecto. Debe llamarse ANTES de que se pinte el primer mapa:
/// `getOrCreateInstance` solo respeta la configuración si aún no existe una
/// instancia (ver su docstring) — llamarlo tarde es un no-op silencioso.
void configureMapTileCache() {
  BuiltInMapCachingProvider.getOrCreateInstance(
    maxCacheSize: _mapTileCacheMaxSize,
    overrideFreshAge: _mapTileCacheFreshAge,
  );
}

/// Borra la caché de tiles en disco (usado por el Reset de superadmin).
///
/// `destroy()` no solo borra ficheros: dispara `resetSingleton`, que la
/// propia factory de `BuiltInMapCachingProvider` pasa como callback (ver
/// `built_in_caching_provider.dart`) y que pone la instancia interna a
/// `null`. La app NO se reinicia tras un Reset (solo navega a login), así
/// que el siguiente tile que se pida recrearía el singleton con los
/// DEFAULTS de flutter_map (1 GB, sin `overrideFreshAge`) si nadie
/// reconfigura antes. Por eso esta función vuelve a llamar a
/// [configureMapTileCache] justo después: NO QUITAR esa segunda llamada
/// aunque parezca redundante con `destroy`.
Future<void> resetMapTileCache() async {
  await BuiltInMapCachingProvider.getOrCreateInstance()
      .destroy(deleteCache: true);
  configureMapTileCache();
}
