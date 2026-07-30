import 'package:sqflite/sqflite.dart';

import '../../core/app_di.dart';
import '../../core/sync/database/offline_database.dart';

/// Qué le falta a un sobre (segmento + sus hijos) para estar en la nube.
///
/// Dos categorías distintas, y hay que reportarlas por separado porque exigen
/// acciones distintas:
///
/// - `falta*`: nunca salió del móvil (job `pending`/`syncing`/`rejected`).
/// - `sinCerrar*`: SÍ subió, pero en un intento que ningún `sync-complete`
///   cerró, así que el backend lo tiene en `estadotransmision='pending'` y el
///   próximo `upsert` lo borrará. Basta con cerrar; solo hay que reenviarlo si
///   además sale un `upsert` en el mismo ciclo.
class PendingEnvelope {
  PendingEnvelope(this.segmentoClientId);

  final String segmentoClientId;

  bool faltaSegmento = false;
  int faltaImagenes = 0;
  int faltaVideos = 0;
  int faltaMensajes = 0;

  bool sinCerrarSegmento = false;
  int sinCerrarImagenes = 0;
  int sinCerrarVideos = 0;
  int sinCerrarMensajes = 0;

  /// Hay algo que subir. Lo `sinCerrar` no cuenta: esos bytes ya están arriba.
  bool get tieneCosasQueSubir =>
      faltaSegmento || faltaImagenes > 0 || faltaVideos > 0 || faltaMensajes > 0;

  /// El sobre subió entero pero nadie confirmó el cierre — sigue habiendo
  /// trabajo (el `sync-complete`), aunque no haya un solo byte que enviar.
  bool get necesitaCierre =>
      sinCerrarSegmento ||
      sinCerrarImagenes > 0 ||
      sinCerrarVideos > 0 ||
      sinCerrarMensajes > 0;

  /// Etiquetas legibles de lo que queda por hacer, en el orden en que se envía.
  List<String> get resumen {
    final out = <String>[];
    if (faltaSegmento) out.add('Datos');
    if (faltaImagenes > 0) out.add(_plural(faltaImagenes, 'foto', 'fotos'));
    if (faltaVideos > 0) out.add(_plural(faltaVideos, 'vídeo', 'vídeos'));
    if (faltaMensajes > 0) {
      out.add(_plural(faltaMensajes, 'mensaje', 'mensajes'));
    }
    if (out.isEmpty && necesitaCierre) out.add('Falta confirmar el cierre');
    return out;
  }

  static String _plural(int n, String uno, String varios) =>
      '$n ${n == 1 ? uno : varios}';
}

/// Lee de un tirón qué sobres tienen trabajo pendiente.
///
/// Una sola consulta en vez de tres por segmento: la pantalla se abre con
/// cientos de segmentos en local y el coste de `3N + 3` viajes al method
/// channel de sqflite se paga en el primer frame.
class PendingEnvelopesQuery {
  PendingEnvelopesQuery({Database? db}) : _db = db ?? AppDI.database;

  final Database _db;

  static const _queue = OfflineDatabase.syncQueueTable;

  /// El sobre entero como filas `(segmento, tipo, client_id del elemento)`.
  /// El segmento se incluye a sí mismo: su `upsert` es un job más.
  static const _sobre = '''
    SELECT client_id AS seg, 'segmento' AS tipo, client_id AS cid
      FROM segmentos
    UNION ALL
    SELECT segmento_client_id, 'imagen', client_id
      FROM imagenes_segmento WHERE segmento_client_id IS NOT NULL
    UNION ALL
    SELECT segmento_client_id, 'video', client_id
      FROM videos_segmento WHERE segmento_client_id IS NOT NULL
    UNION ALL
    SELECT segmento_client_id, 'mensaje', client_id
      FROM mensajes_segmento WHERE segmento_client_id IS NOT NULL
  ''';

  /// Sobres con algo pendiente, indexados por `clientId` del segmento. Los
  /// sobres cerrados y limpios no aparecen.
  ///
  /// `operation <> 'delete'`: un borrado no representa dato de campo sin subir
  /// (misma regla que `PurgeSyncedSegmentoUseCase.readUnsyncedSets`).
  Future<Map<String, PendingEnvelope>> read() async {
    final rows = await _db.rawQuery('''
      SELECT e.seg AS seg,
             e.tipo AS tipo,
             COUNT(DISTINCT CASE
               WHEN q.status IN ('pending', 'syncing', 'rejected')
               THEN e.cid END) AS falta,
             COUNT(DISTINCT CASE
               WHEN q.status = 'synced'
                AND q.synced_at IS NOT NULL
                AND (s.sync_confirmed_at IS NULL
                     OR q.synced_at > s.sync_confirmed_at)
               THEN e.cid END) AS sin_cerrar
        FROM ($_sobre) e
        JOIN $_queue q
          ON q.entity_type = e.tipo
         AND q.client_id = e.cid
         AND q.operation <> 'delete'
        JOIN segmentos s ON s.client_id = e.seg
       GROUP BY e.seg, e.tipo
      HAVING falta > 0 OR sin_cerrar > 0
    ''');

    final acc = <String, PendingEnvelope>{};
    for (final row in rows) {
      final seg = row['seg'] as String;
      final falta = (row['falta'] as int?) ?? 0;
      final sinCerrar = (row['sin_cerrar'] as int?) ?? 0;
      final envelope = acc.putIfAbsent(seg, () => PendingEnvelope(seg));
      switch (row['tipo'] as String) {
        case 'segmento':
          envelope.faltaSegmento = falta > 0;
          envelope.sinCerrarSegmento = sinCerrar > 0;
        case 'imagen':
          envelope.faltaImagenes = falta;
          envelope.sinCerrarImagenes = sinCerrar;
        case 'video':
          envelope.faltaVideos = falta;
          envelope.sinCerrarVideos = sinCerrar;
        case 'mensaje':
          envelope.faltaMensajes = falta;
          envelope.sinCerrarMensajes = sinCerrar;
      }
    }
    return acc;
  }
}
