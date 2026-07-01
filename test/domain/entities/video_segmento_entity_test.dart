import 'package:flutter_test/flutter_test.dart';

import 'package:helireport_desherbaje/domain/entities/video_segmento_entity.dart';

VideoSegmentoEntity _makeVideo({
  String? clientId,
  TipoVideo tipo = TipoVideo.antes,
  int segmentoId = 42,
  int uploadOffset = 0,
}) {
  final v = VideoSegmentoEntity(
    actividadId: 1,
    segmentoId: segmentoId,
    tipoVideo: tipo,
    filename: 'video.mp4',
    ruta: '/tmp/video.mp4',
    capturadaAt: DateTime.utc(2026, 1, 15, 10, 0, 0),
    clientId: clientId,
  )..uploadOffset = uploadOffset;
  return v;
}

void main() {
  group('TipoVideo', () {
    test('fromString known values', () {
      expect(TipoVideo.fromString('antes'), TipoVideo.antes);
      expect(TipoVideo.fromString('despues'), TipoVideo.despues);
    });

    test('fromString unknown falls back to antes', () {
      expect(TipoVideo.fromString(null), TipoVideo.antes);
      expect(TipoVideo.fromString('unknown'), TipoVideo.antes);
    });

    test('valor/etiqueta round-trip', () {
      for (final t in TipoVideo.values) {
        expect(TipoVideo.fromString(t.valor), t);
      }
    });
  });

  group('VideoSegmentoEntity clientId', () {
    test('clientId is stable across multiple accesses', () {
      final v = _makeVideo();
      final id1 = v.clientId;
      final id2 = v.clientId;
      expect(id1, equals(id2));
    });

    test('explicit clientId is preserved', () {
      const expected = 'my-stable-uuid';
      final v = _makeVideo(clientId: expected);
      expect(v.clientId, equals(expected));
    });

    test('two entities without clientId have different IDs', () {
      final v1 = _makeVideo();
      final v2 = _makeVideo();
      expect(v1.clientId, isNot(equals(v2.clientId)));
    });
  });

  group('toMap / fromMap round-trip', () {
    test('all scalar fields preserved including uploadOffset', () {
      final v = _makeVideo(clientId: 'cid-1', uploadOffset: 1234567);
      v.id = 99;
      v.mimeType = 'video/quicktime';
      v.tamanyoBytes = 50000000;
      v.latitud = 40.416;
      v.longitud = -3.703;

      final map = v.toMap();
      final restored = VideoSegmentoEntity.fromMap(map);

      expect(restored.clientId, equals('cid-1'));
      expect(restored.id, equals(99));
      expect(restored.segmentoId, equals(42));
      expect(restored.tipoVideo, equals(TipoVideo.antes));
      expect(restored.mimeType, equals('video/quicktime'));
      expect(restored.tamanyoBytes, equals(50000000));
      expect(restored.latitud, closeTo(40.416, 1e-6));
      expect(restored.longitud, closeTo(-3.703, 1e-6));
      expect(restored.uploadOffset, equals(1234567));
    });

    test('uploadOffset defaults to 0 when absent from row', () {
      final v = _makeVideo(clientId: 'cid-2');
      final map = Map<String, Object?>.from(v.toMap())
        ..remove('upload_offset');
      final restored = VideoSegmentoEntity.fromMap(map);
      expect(restored.uploadOffset, equals(0));
    });

    test('needsSync=false is reflected in map', () {
      final v = _makeVideo(clientId: 'cid-3');
      final map = v.toMap(needsSync: false);
      expect(map['needs_sync'], equals(0));
    });

    test('uploadId round-trip through toMap/fromMap', () {
      final v = _makeVideo(clientId: 'cid-uid');
      v.uploadId = 'server-uuid-xyz';

      final restored = VideoSegmentoEntity.fromMap(v.toMap());
      expect(restored.uploadId, equals('server-uuid-xyz'));
    });

    test('uploadId defaults to null when absent from row', () {
      final v = _makeVideo(clientId: 'cid-no-uid');
      final map = Map<String, Object?>.from(v.toMap())
        ..remove('upload_id');
      final restored = VideoSegmentoEntity.fromMap(map);
      expect(restored.uploadId, isNull);
    });
  });

  group('toJson / fromJson round-trip (backend)', () {
    test('uploadOffset is NOT present in toJson', () {
      final v = _makeVideo(clientId: 'cid-4', uploadOffset: 999);
      final json = v.toJson();
      expect(json.containsKey('upload_offset'), isFalse);
    });

    test('uploadId is NOT present in toJson (internal field only)', () {
      final v = _makeVideo(clientId: 'cid-4b');
      v.uploadId = 'some-server-id';
      final json = v.toJson();
      expect(json.containsKey('upload_id'), isFalse);
    });

    test('fromJson restores scalar fields', () {
      final original = _makeVideo(clientId: 'cid-5');
      original.id = 7;
      original.url = 'https://example.com/video.mp4';
      original.tamanyoBytes = 12345;

      final json = original.toJson();
      final restored = VideoSegmentoEntity.fromJson(
        json.cast<String, dynamic>(),
      );

      expect(restored.clientId, equals('cid-5'));
      expect(restored.id, equals(7));
      expect(restored.url, equals('https://example.com/video.mp4'));
      expect(restored.tamanyoBytes, equals(12345));
      // uploadOffset always 0 from JSON (field does not exist in payload)
      expect(restored.uploadOffset, equals(0));
    });
  });

  group('tamanyoLegible', () {
    test('bytes', () {
      final v = _makeVideo()..tamanyoBytes = 512;
      expect(v.tamanyoLegible, equals('512 B'));
    });

    test('kilobytes', () {
      final v = _makeVideo()..tamanyoBytes = 2048;
      expect(v.tamanyoLegible, equals('2.0 KB'));
    });

    test('megabytes', () {
      final v = _makeVideo()..tamanyoBytes = 5242880; // 5 MB
      expect(v.tamanyoLegible, equals('5.0 MB'));
    });

    test('null returns Desconocido', () {
      final v = _makeVideo()..tamanyoBytes = null;
      expect(v.tamanyoLegible, equals('Desconocido'));
    });
  });

  group('equality', () {
    test('same clientId → equal', () {
      final v1 = _makeVideo(clientId: 'same');
      final v2 = _makeVideo(clientId: 'same');
      expect(v1, equals(v2));
    });

    test('different clientId → not equal', () {
      final v1 = _makeVideo(clientId: 'a');
      final v2 = _makeVideo(clientId: 'b');
      expect(v1, isNot(equals(v2)));
    });
  });

  group('copyWith', () {
    test('preserves clientId', () {
      final v = _makeVideo(clientId: 'orig');
      final copy = v.copyWith(tamanyoBytes: 99);
      expect(copy.clientId, equals('orig'));
    });

    test('updates uploadOffset', () {
      final v = _makeVideo(uploadOffset: 0);
      final copy = v.copyWith(uploadOffset: 500);
      expect(copy.uploadOffset, equals(500));
    });

    test('copyWith preserves uploadId when not provided', () {
      final v = _makeVideo(clientId: 'cid')..uploadId = 'u-id';
      final copy = v.copyWith(tamanyoBytes: 42);
      expect(copy.uploadId, equals('u-id'));
    });

    test('copyWith can set a new uploadId', () {
      final v = _makeVideo(clientId: 'cid')..uploadId = null;
      final copy = v.copyWith(uploadId: 'new-upload-id');
      expect(copy.uploadId, equals('new-upload-id'));
    });
  });

  group('remoteId', () {
    test('remoteId returns uploadId when set', () {
      final v = _makeVideo(clientId: 'cid')..uploadId = 'server-uuid';
      expect(v.remoteId, equals('server-uuid'));
    });

    test('remoteId falls back to id.toString when uploadId is null', () {
      final v = _makeVideo(clientId: 'cid');
      v.id = 77;
      v.uploadId = null;
      expect(v.remoteId, equals('77'));
    });

    test('remoteId is null when both uploadId and id are null', () {
      final v = _makeVideo(clientId: 'cid');
      v.uploadId = null;
      v.id = null;
      expect(v.remoteId, isNull);
    });
  });
}
