import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:helireport_desherbaje/domain/entities/segmento_entity.dart';

// ─── Helpers ──────────────────────────────────────────────────────────────────

Map<String, dynamic> _minimalJson({String clientId = 'test-client-id'}) => {
      'client_id': clientId,
      'ctname': 'CT12',
      'tipo_instalacion': 'lineal',
      'estado': 'propuesta',
      'tipo_actividad': 'posicion_desherbaje_traza',
      'descripcion': '',
    };

Map<String, dynamic> _fullJson() => {
      'id': 42,
      'client_id': 'fixed-uuid',
      'ctname': 'CT15',
      'nombre': 'Segmento Norte',
      'descripcion': 'Tramo principal',
      'traza': 'G-123',
      'tipo_instalacion': 'concentrada',
      'pk_inicio': 10.5,
      'pk_fin': 12.0,
      'lat_inicio': 40.1,
      'lng_inicio': -3.7,
      'lat_fin': 40.2,
      'lng_fin': -3.6,
      'ubicacion_gis': {
        'type': 'LineString',
        'coordinates': [
          [-3.7, 40.1],
          [-3.65, 40.15],
          [-3.6, 40.2],
        ],
      },
      'tipo_actividad': 'desbroce_manual',
      'estado': 'validada',
      'imagenes': [],
      'mensajes': [],
      'created_at': '2024-01-15T10:00:00.000Z',
      'fecha_inico': '2024-03-01T08:00:00.000Z',
      'fecha_fin': '2024-04-30T18:00:00.000Z',
      'updated_at': '2024-04-10T12:00:00.000Z',
    };

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  group('SegmentoEntity.fromJson', () {
    test('parses all scalar fields from full JSON', () {
      final entity = SegmentoEntity.fromJson(_fullJson());

      expect(entity.id, equals(42));
      expect(entity.clientId, equals('fixed-uuid'));
      expect(entity.ctname, equals('CT15'));
      expect(entity.nombre, equals('Segmento Norte'));
      expect(entity.descripcion, equals('Tramo principal'));
      expect(entity.traza, equals('G-123'));
      expect(entity.tipoInstalacion, equals(TipoInstalacion.concentrada));
      expect(entity.pkInicio, equals(10.5));
      expect(entity.pkFin, equals(12.0));
      expect(entity.latInicio, equals(40.1));
      expect(entity.lngInicio, equals(-3.7));
      expect(entity.latFin, equals(40.2));
      expect(entity.lngFin, equals(-3.6));
      expect(entity.tipoActividad, equals(TipoActividad.desbroceManual));
      expect(entity.estado, equals(EstadoActividad.validada));
    });

    test('reads ctname from the contractor download payload (§8)', () {
      // El backend identifica el CT por NOMBRE (contrato §3/§8), no por id.
      final entity = SegmentoEntity.fromJson({
        'id': 7,
        'ctname': 'CT-BURGOS',
        'estado': 'propuesta',
        'imagenes': [],
        'mensajes': [],
      });
      expect(entity.ctname, equals('CT-BURGOS'));
    });

    test('defaults ctname to empty string when absent', () {
      final json = _minimalJson()..remove('ctname');
      final entity = SegmentoEntity.fromJson(json);
      expect(entity.ctname, isEmpty);
    });

    test('parses GeoJSON LineString coordinates in [lng, lat] order', () {
      final entity = SegmentoEntity.fromJson(_fullJson());

      expect(entity.ubicacionGis, hasLength(3));
      expect(entity.ubicacionGis[0].latitude, closeTo(40.1, 1e-6));
      expect(entity.ubicacionGis[0].longitude, closeTo(-3.7, 1e-6));
      expect(entity.ubicacionGis[2].latitude, closeTo(40.2, 1e-6));
      expect(entity.ubicacionGis[2].longitude, closeTo(-3.6, 1e-6));
    });

    test('parses GeoJSON when ubicacion_gis is a JSON-encoded string', () {
      final json = _minimalJson()
        ..['ubicacion_gis'] = jsonEncode({
          'type': 'LineString',
          'coordinates': [
            [-3.7, 40.1],
            [-3.6, 40.2],
          ],
        });
      final entity = SegmentoEntity.fromJson(json);
      expect(entity.ubicacionGis, hasLength(2));
    });

    test('leaves ubicacionGis empty when field is absent', () {
      final entity = SegmentoEntity.fromJson(_minimalJson());
      expect(entity.ubicacionGis, isEmpty);
    });

    test('preserves clientId from JSON', () {
      final entity = SegmentoEntity.fromJson(_minimalJson(clientId: 'my-uuid'));
      expect(entity.clientId, equals('my-uuid'));
    });

    test('generates a new UUID when clientId is absent', () {
      final json = _minimalJson()..remove('client_id');
      final entity = SegmentoEntity.fromJson(json);
      expect(entity.clientId, isNotEmpty);
      expect(entity.clientId, matches(RegExp(r'^[0-9a-f-]{36}$')));
    });

    test('parses dates correctly', () {
      final entity = SegmentoEntity.fromJson(_fullJson());
      expect(
          entity.createdAt, equals(DateTime.parse('2024-01-15T10:00:00.000Z')));
      expect(
          entity.updatedAt, equals(DateTime.parse('2024-04-10T12:00:00.000Z')));
    });

    test('leaves optional dates null when absent', () {
      final entity = SegmentoEntity.fromJson(_minimalJson());
      expect(entity.createdAt, isNull);
      expect(entity.fechaInicio, isNull);
      expect(entity.fechaFin, isNull);
    });

    test('remoteId is null when id is null', () {
      final entity = SegmentoEntity.fromJson(_minimalJson());
      expect(entity.remoteId, isNull);
    });

    test('remoteId is id.toString() when id is present', () {
      final entity = SegmentoEntity.fromJson(_fullJson());
      expect(entity.remoteId, equals('42'));
    });
  });

  group('SegmentoEntity.toJson', () {
    test('roundtrip preserves clientId and core fields', () {
      final original = SegmentoEntity.fromJson(_fullJson());
      final json = original.toJson();
      final restored = SegmentoEntity.fromJson(
        Map<String, dynamic>.from(json),
      );

      expect(restored.clientId, equals(original.clientId));
      expect(restored.id, equals(original.id));
      expect(restored.ctname, equals(original.ctname));
      expect(restored.nombre, equals(original.nombre));
      expect(restored.estado, equals(original.estado));
      expect(restored.tipoActividad, equals(original.tipoActividad));
    });

    test('serializes ubicacionGis as GeoJSON with [lng, lat] order', () {
      final entity = SegmentoEntity.fromJson(_fullJson());
      final json = entity.toJson();

      final gis = json['ubicacion_gis'] as Map<String, dynamic>;
      expect(gis['type'], equals('LineString'));
      final coords = gis['coordinates'] as List;
      expect(coords.first[0], closeTo(-3.7, 1e-6)); // longitude first
      expect(coords.first[1], closeTo(40.1, 1e-6)); // latitude second
    });

    test('serializes estado using descripcion (not enum name)', () {
      final entity = SegmentoEntity.fromJson(_minimalJson());
      entity.estado = EstadoActividad.ejecucion;
      final json = entity.toJson();
      expect(json['estado'], equals('ejecución'));
    });
  });

  group('EstadoActividad.fromString', () {
    test(
        'parses propuesta',
        () => expect(EstadoActividad.fromString('propuesta'),
            equals(EstadoActividad.propuesta)));

    test(
        'parses validada',
        () => expect(EstadoActividad.fromString('validada'),
            equals(EstadoActividad.validada)));

    test(
        'parses ejecución with accent',
        () => expect(EstadoActividad.fromString('ejecución'),
            equals(EstadoActividad.ejecucion)));

    test(
        'parses ejecucion without accent',
        () => expect(EstadoActividad.fromString('ejecucion'),
            equals(EstadoActividad.ejecucion)));

    test(
        'parses finalizada',
        () => expect(EstadoActividad.fromString('finalizada'),
            equals(EstadoActividad.finalizada)));

    test(
        'parses cerrada',
        () => expect(EstadoActividad.fromString('cerrada'),
            equals(EstadoActividad.cerrada)));

    test(
        'defaults to propuesta for null',
        () => expect(EstadoActividad.fromString(null),
            equals(EstadoActividad.propuesta)));

    test(
        'defaults to propuesta for unknown string',
        () => expect(EstadoActividad.fromString('unknown'),
            equals(EstadoActividad.propuesta)));

    test(
        'is case-insensitive',
        () => expect(EstadoActividad.fromString('VALIDADA'),
            equals(EstadoActividad.validada)));
  });

  group('EstadoActividad.puedeIrA — matriz de transiciones (app campo)', () {
    test('permanecer en el mismo estado siempre es válido', () {
      for (final e in EstadoActividad.values) {
        expect(e.puedeIrA(e), isTrue, reason: '$e debe permitir permanecer');
      }
    });

    test('matriz de transiciones permitidas', () {
      expect(EstadoActividad.contratista.transicionesPermitidas,
          {EstadoActividad.ejecucion});
      expect(EstadoActividad.ejecucion.transicionesPermitidas,
          {EstadoActividad.finalizada});
      expect(EstadoActividad.finalizada.transicionesPermitidas,
          {EstadoActividad.cerrada, EstadoActividad.ejecucion});
      expect(EstadoActividad.propuesta.transicionesPermitidas, isEmpty);
      expect(EstadoActividad.validada.transicionesPermitidas, isEmpty);
      expect(EstadoActividad.cerrada.transicionesPermitidas, isEmpty);
    });

    test('transiciones válidas e inválidas', () {
      expect(
          EstadoActividad.finalizada.puedeIrA(EstadoActividad.cerrada), isTrue);
      expect(EstadoActividad.finalizada.puedeIrA(EstadoActividad.ejecucion),
          isTrue);
      expect(EstadoActividad.contratista.puedeIrA(EstadoActividad.finalizada),
          isFalse);
      expect(EstadoActividad.propuesta.puedeIrA(EstadoActividad.contratista),
          isFalse);
      expect(
          EstadoActividad.cerrada.puedeIrA(EstadoActividad.ejecucion), isFalse);
    });

    test('esEditableDesdeApp', () {
      expect(EstadoActividad.contratista.esEditableDesdeApp, isTrue);
      expect(EstadoActividad.ejecucion.esEditableDesdeApp, isTrue);
      expect(EstadoActividad.finalizada.esEditableDesdeApp, isTrue);
      expect(EstadoActividad.propuesta.esEditableDesdeApp, isFalse);
      expect(EstadoActividad.validada.esEditableDesdeApp, isFalse);
      expect(EstadoActividad.cerrada.esEditableDesdeApp, isFalse);
    });
  });

  group('TipoActividad.fromString', () {
    test(
        'parses desbroce_manual',
        () => expect(TipoActividad.fromString('desbroce_manual'),
            equals(TipoActividad.desbroceManual)));

    test(
        'parses posicion_desherbaje_traza',
        () => expect(TipoActividad.fromString('posicion_desherbaje_traza'),
            equals(TipoActividad.posicionDesherbajeTraza)));

    test(
        'defaults to posicionDesherbajeTraza for null',
        () => expect(TipoActividad.fromString(null),
            equals(TipoActividad.posicionDesherbajeTraza)));

    test(
        'defaults to posicionDesherbajeTraza for unknown',
        () => expect(TipoActividad.fromString('???'),
            equals(TipoActividad.posicionDesherbajeTraza)));
  });

  group('TipoInstalacion.fromString', () {
    test(
        'parses concentrada',
        () => expect(TipoInstalacion.fromString('concentrada'),
            equals(TipoInstalacion.concentrada)));

    test(
        'parses lineal',
        () => expect(TipoInstalacion.fromString('lineal'),
            equals(TipoInstalacion.lineal)));

    test(
        'defaults to lineal for null',
        () => expect(
            TipoInstalacion.fromString(null), equals(TipoInstalacion.lineal)));

    test(
        'defaults to lineal for unknown',
        () => expect(TipoInstalacion.fromString('unknown'),
            equals(TipoInstalacion.lineal)));
  });

  group('SegmentoEntity.copyWith', () {
    test('preserves clientId', () {
      final original = SegmentoEntity.fromJson(_fullJson());
      final copy = original.copyWith(nombre: 'Nuevo nombre');
      expect(copy.clientId, equals(original.clientId));
    });

    test('updates only specified fields', () {
      final original = SegmentoEntity.fromJson(_fullJson());
      final copy = original.copyWith(estado: EstadoActividad.finalizada);
      expect(copy.estado, equals(EstadoActividad.finalizada));
      expect(copy.nombre, equals(original.nombre));
      expect(copy.ctname, equals(original.ctname));
    });

    test('equality is based on clientId', () {
      final original = SegmentoEntity.fromJson(_fullJson());
      final copy = original.copyWith(estado: EstadoActividad.cerrada);
      expect(copy, equals(original));
    });
  });

  group('SegmentoEntity.longitud', () {
    test('returns 0 for empty ubicacionGis', () {
      final entity = SegmentoEntity.fromJson(_minimalJson());
      expect(entity.longitud, equals(0.0));
    });

    test('returns 0 for single-point ubicacionGis', () {
      final json = _minimalJson()
        ..['ubicacion_gis'] = {
          'type': 'LineString',
          'coordinates': [
            [-3.7, 40.1]
          ],
        };
      final entity = SegmentoEntity.fromJson(json);
      expect(entity.longitud, equals(0.0));
    });

    test('returns positive value for 2-point segment', () {
      final entity = SegmentoEntity.fromJson(_fullJson());
      expect(entity.longitud, greaterThan(0));
      expect(entity.longitudKm, closeTo(entity.longitud / 1000, 1e-6));
    });
  });

  group('SegmentoEntity.displayName', () {
    test('joins nombre and traza when both present', () {
      final entity = SegmentoEntity.fromJson(_fullJson());
      expect(entity.displayName, equals('Segmento Norte - G-123'));
    });

    test('returns only nombre when traza is null', () {
      final json = _fullJson()..remove('traza');
      final entity = SegmentoEntity.fromJson(json);
      expect(entity.displayName, equals('Segmento Norte'));
    });

    test('returns empty string when both are null/empty', () {
      final entity = SegmentoEntity.fromJson(_minimalJson());
      expect(entity.displayName, isEmpty);
    });
  });
}
