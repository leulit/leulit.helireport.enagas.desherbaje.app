import 'package:flutter_test/flutter_test.dart';
import 'package:helireport_desherbaje/core/sync/contracts/syncable.dart';
import 'package:helireport_desherbaje/domain/entities/actividad_entity.dart';
import 'package:helireport_desherbaje/domain/entities/imagen_segmento_entity.dart';

void main() {
  group('ActividadEntity Syncable conformance', () {
    final entity = ActividadEntity(
      id: 42,
      posicionId: 7,
      estado: EstadoActividad.ejecucion,
      descripcion: 'Test',
      superficieM2: 100.0,
      costeEstimado: 500.0,
      fechaProgramada: DateTime(2026, 1, 15),
      fechaInicio: DateTime(2026, 2, 1),
      fechaFin: DateTime(2026, 3, 10),
      segmentos: const [],
    );

    test('is assignable to Syncable', () {
      final Syncable syncable = entity;
      expect(syncable, isA<Syncable>());
    });

    test('clientId is "act-<id>"', () {
      expect(entity.clientId, 'act-42');
    });

    test('remoteId equals id.toString()', () {
      expect(entity.remoteId, '42');
    });

    test('updatedAt is non-null and matches fechaFin', () {
      expect(entity.updatedAt, isNotNull);
      expect(entity.updatedAt, DateTime(2026, 3, 10));
    });

    test('toJson() returns a Map<String, dynamic>', () {
      final Syncable syncable = entity;
      final json = syncable.toJson();
      expect(json, isA<Map<String, dynamic>>());
      expect(json['id'], 42);
    });
  });

  group('ImagenSegmentoEntity Syncable conformance', () {
    final captured = DateTime(2026, 4, 19, 10, 30);

    final withRemote = ImagenSegmentoEntity(
      localId: '550e8400-e29b-41d4-a716-446655440000',
      remoteIntId: 99,
      actividadId: 42,
      localPath: '/tmp/photo.jpg',
      tipoFoto: TipoFoto.antes,
      capturedAt: captured,
    );

    final withoutRemote = ImagenSegmentoEntity(
      localId: 'local-only-id',
      actividadId: 42,
      localPath: '/tmp/photo2.jpg',
      tipoFoto: TipoFoto.despues,
      capturedAt: captured,
    );

    test('is assignable to Syncable', () {
      final Syncable syncable = withRemote;
      expect(syncable, isA<Syncable>());
    });

    test('clientId equals localId', () {
      expect(withRemote.clientId, '550e8400-e29b-41d4-a716-446655440000');
      expect(withoutRemote.clientId, 'local-only-id');
    });

    test('remoteId is String conversion of remoteIntId when present', () {
      expect(withRemote.remoteId, '99');
    });

    test('remoteId is null when remoteIntId is null', () {
      expect(withoutRemote.remoteId, isNull);
    });

    test('updatedAt equals capturedAt', () {
      expect(withRemote.updatedAt, captured);
      expect(withoutRemote.updatedAt, captured);
    });

    test('toJson() aliases toMap()', () {
      expect(withRemote.toJson(), withRemote.toMap());
    });
  });
}
