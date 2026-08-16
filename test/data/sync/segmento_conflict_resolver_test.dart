// Tests for SegmentoConflictResolver — business fields survive from `local`,
// imagenes/mensajes come from `remote`, updatedAt stays local's.
import 'package:flutter_test/flutter_test.dart';

import 'package:helireport_desherbaje/data/sync/segmento_conflict_resolver.dart';
import 'package:helireport_desherbaje/domain/entities/segmento_entity.dart';

SegmentoEntity _seg({
  required String clientId,
  required DateTime updatedAt,
  required List<Map<String, dynamic>> imagenes,
  required List<Map<String, dynamic>> mensajes,
  String estado = 'ejecucion',
  String descripcion = 'descripción local',
}) =>
    SegmentoEntity.fromJson({
      'client_id': clientId,
      'ctname': 'CT15',
      'nombre': 'Segmento Norte',
      'descripcion': descripcion,
      'tipo_instalacion': 'lineal',
      'tipo_actividad': 'desbroce_manual',
      'estado': estado,
      'imagenes': imagenes,
      'mensajes': mensajes,
      'updated_at': updatedAt.toIso8601String(),
    });

void main() {
  const resolver = SegmentoConflictResolver();

  test('imagenes/mensajes come from remote', () {
    final local = _seg(
      clientId: 'c1',
      updatedAt: DateTime(2026, 1, 1),
      imagenes: [
        {'client_id': 'img-local', 'segmento_id': 0, 'tipo_foto': 'antes'},
      ],
      mensajes: [
        {'client_id': 'msg-local', 'segmento_id': 0, 'mensaje': 'hola local'},
      ],
    );
    final remote = _seg(
      clientId: 'c1',
      updatedAt: DateTime(2026, 2, 1),
      imagenes: [
        {'client_id': 'img-remote', 'segmento_id': 0, 'tipo_foto': 'antes'},
      ],
      mensajes: [
        {
          'client_id': 'msg-remote',
          'segmento_id': 0,
          'mensaje': 'hola remoto',
        },
      ],
    );

    final resolved = resolver.resolve(local: local, remote: remote);

    expect(resolved.imagenes.map((i) => i.clientId), ['img-remote']);
    expect(resolved.mensajes.map((m) => m.clientId), ['msg-remote']);
  });

  test('business fields survive from local (estado, descripcion, ctname…)',
      () {
    final local = _seg(
      clientId: 'c1',
      updatedAt: DateTime(2026, 1, 1),
      imagenes: const [],
      mensajes: const [],
      estado: 'ejecucion',
      descripcion: 'edición offline del operario',
    );
    final remote = _seg(
      clientId: 'c1',
      updatedAt: DateTime(2026, 2, 1),
      imagenes: const [],
      mensajes: const [],
      estado: 'validada',
      descripcion: 'lo que hay en la nube',
    );

    final resolved = resolver.resolve(local: local, remote: remote);

    expect(resolved.estado, EstadoActividad.ejecucion);
    expect(resolved.descripcion, 'edición offline del operario');
    expect(resolved.ctname, local.ctname);
    expect(resolved.nombre, local.nombre);
    expect(resolved.tipoActividad, local.tipoActividad);
  });

  test('updatedAt stays local\'s — the local edit still has not been pushed',
      () {
    final localUpdatedAt = DateTime(2026, 1, 1);
    final local = _seg(
      clientId: 'c1',
      updatedAt: localUpdatedAt,
      imagenes: const [],
      mensajes: const [],
    );
    final remote = _seg(
      clientId: 'c1',
      updatedAt: DateTime(2026, 6, 1),
      imagenes: const [],
      mensajes: const [],
    );

    final resolved = resolver.resolve(local: local, remote: remote);

    expect(resolved.updatedAt, localUpdatedAt);
  });

  test('never returns null (deterministic merge, no user hand-off)', () {
    final local = _seg(
      clientId: 'c1',
      updatedAt: DateTime(2026, 1, 1),
      imagenes: const [],
      mensajes: const [],
    );
    final remote = _seg(
      clientId: 'c1',
      updatedAt: DateTime(2026, 1, 2),
      imagenes: const [],
      mensajes: const [],
    );

    expect(resolver.resolve(local: local, remote: remote), isNotNull);
  });
}
