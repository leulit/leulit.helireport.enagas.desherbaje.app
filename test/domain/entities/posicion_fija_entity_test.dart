// Tests for PosicionFijaEntity — fromJson/toJson round-trip, deterministic
// updatedAt fallback chain (never DateTime.now()), and display-coordinate
// resolution (fixed_* preferred, falls back to latitud/longitud, invalid
// "0.000000000" sentinel rejected).
import 'package:flutter_test/flutter_test.dart';

import 'package:helireport_desherbaje/domain/entities/posicion_fija_entity.dart';

const _sampleJson = {
  'id': 284512,
  'iupdated': '2025-05-02T16:20:45.000Z',
  'icreated': '2025-04-14T09:32:11.000Z',
  'ctname': 'CT1',
  'zona': 'ZONA NORTE',
  'tramo': 'TRAMO 03',
  'subtramo': 'SUBTRAMO 03-B',
  'fixed_latitude': '41.393712000',
  'fixed_longitude': '2.154980000',
  'latitud': '41.393705120',
  'longitud': '2.154978340',
  'tipo_punto': 'instalacion',
  'tipovigilancia': 'VH',
  'fecha': '2025-04-14T09:31:58.000Z',
  'title': 'Posición fija PK 123+400',
  'trazaname': 'GASODUCTO BARCELONA-VALENCIA',
  'fotos': '284512_1744623118.jpg',
};

void main() {
  group('fromJson', () {
    test('parses String lat/lng into double', () {
      final e = PosicionFijaEntity.fromJson(_sampleJson);
      expect(e.id, equals(284512));
      expect(e.title, equals('Posición fija PK 123+400'));
      expect(e.ctname, equals('CT1'));
      expect(e.fixedLatitude, closeTo(41.393712000, 1e-9));
      expect(e.fixedLongitude, closeTo(2.154980000, 1e-9));
      expect(e.latitud, closeTo(41.393705120, 1e-9));
      expect(e.longitud, closeTo(2.154978340, 1e-9));
      expect(e.subtramo, equals('SUBTRAMO 03-B'));
    });

    test('subtramo null is tolerated', () {
      final json = {..._sampleJson}..remove('subtramo');
      final e = PosicionFijaEntity.fromJson(json);
      expect(e.subtramo, isNull);
    });

    test('updatedAt falls back to iupdated when updated_at is absent', () {
      final e = PosicionFijaEntity.fromJson(_sampleJson);
      expect(e.updatedAt, equals(DateTime.parse('2025-05-02T16:20:45.000Z')));
    });

    test('updatedAt falls back to icreated when iupdated is absent', () {
      final json = {..._sampleJson}..remove('iupdated');
      final e = PosicionFijaEntity.fromJson(json);
      expect(e.updatedAt, equals(DateTime.parse('2025-04-14T09:32:11.000Z')));
    });

    test('updatedAt falls back to fecha when iupdated/icreated are absent',
        () {
      final json = {..._sampleJson}
        ..remove('iupdated')
        ..remove('icreated');
      final e = PosicionFijaEntity.fromJson(json);
      expect(e.updatedAt, equals(DateTime.parse('2025-04-14T09:31:58.000Z')));
    });

    test(
      'updatedAt falls back to epoch 0 (NEVER DateTime.now()) when nothing parses',
      () {
        final json = {..._sampleJson}
          ..remove('iupdated')
          ..remove('icreated')
          ..remove('fecha');
        final e = PosicionFijaEntity.fromJson(json);
        expect(e.updatedAt, equals(DateTime.fromMillisecondsSinceEpoch(0)));
      },
    );
  });

  group('round-trip toJson → fromJson', () {
    test('preserves clientId and all fields', () {
      final original = PosicionFijaEntity.fromJson(_sampleJson);
      final rebuilt = PosicionFijaEntity.fromJson(original.toJson());

      expect(rebuilt.clientId, equals(original.clientId));
      expect(rebuilt.id, equals(original.id));
      expect(rebuilt.title, equals(original.title));
      expect(rebuilt.ctname, equals(original.ctname));
      expect(rebuilt.latitud, equals(original.latitud));
      expect(rebuilt.longitud, equals(original.longitud));
      expect(rebuilt.fixedLatitude, equals(original.fixedLatitude));
      expect(rebuilt.fixedLongitude, equals(original.fixedLongitude));
      expect(rebuilt.zona, equals(original.zona));
      expect(rebuilt.tramo, equals(original.tramo));
      expect(rebuilt.subtramo, equals(original.subtramo));
      expect(rebuilt.tipoPunto, equals(original.tipoPunto));
      expect(rebuilt.tipoVigilancia, equals(original.tipoVigilancia));
      expect(rebuilt.trazaname, equals(original.trazaname));
      expect(rebuilt.fotos, equals(original.fotos));
      expect(rebuilt.updatedAt, equals(original.updatedAt));
    });

    test('toJson emits client_id key (motor identity re-binding contract)', () {
      final e = PosicionFijaEntity.fromJson(_sampleJson);
      final json = e.toJson();
      expect(json['client_id'], equals(e.clientId));
    });
  });

  group('displayLatitude / displayLongitude', () {
    test('prefers fixed_latitude/fixed_longitude when valid', () {
      final e = PosicionFijaEntity.fromJson(_sampleJson);
      expect(e.displayLatitude, equals(e.fixedLatitude));
      expect(e.displayLongitude, equals(e.fixedLongitude));
    });

    test('falls back to latitud/longitud when fixed is "0.000000000"', () {
      final json = {
        ..._sampleJson,
        'fixed_latitude': '0.000000000',
        'fixed_longitude': '0.000000000',
      };
      final e = PosicionFijaEntity.fromJson(json);
      expect(e.displayLatitude, equals(e.latitud));
      expect(e.displayLongitude, equals(e.longitud));
      expect(e.hasValidPoint, isTrue);
    });

    test('hasValidPoint is false when all coordinates are invalid', () {
      final json = {
        ..._sampleJson,
        'fixed_latitude': '0.000000000',
        'fixed_longitude': '0.000000000',
        'latitud': '0.000000000',
        'longitud': '0.000000000',
      };
      final e = PosicionFijaEntity.fromJson(json);
      expect(e.hasValidPoint, isFalse);
      expect(e.displayLatitude, isNull);
      expect(e.displayLongitude, isNull);
    });

    test('hasValidPoint is false when coordinates are missing entirely', () {
      final json = {..._sampleJson}
        ..remove('fixed_latitude')
        ..remove('fixed_longitude')
        ..remove('latitud')
        ..remove('longitud');
      final e = PosicionFijaEntity.fromJson(json);
      expect(e.hasValidPoint, isFalse);
    });
  });
}
