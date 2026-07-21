// Tests for ImagenRemoteAdapter multipart payload.
//
// Covers:
//   - push(create): `gis_json` travels verbatim when the capture has GIS
//   - push(create): `gis_json` key is absent when the capture has no GIS
//   - push(create): the always-present contract fields are still sent
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:helireport_desherbaje/core/sync/contracts/remote_adapter.dart';
import 'package:helireport_desherbaje/core/sync/contracts/sync_job.dart'
    show SyncOperation;
import 'package:helireport_desherbaje/data/network/network_file.dart';
import 'package:helireport_desherbaje/data/network/network_response.dart';
import 'package:helireport_desherbaje/data/network/network_service.dart';
import 'package:helireport_desherbaje/data/sync/imagen_remote_adapter.dart';
import 'package:helireport_desherbaje/domain/entities/imagen_segmento_entity.dart';

// ─── Fake NetworkService ─────────────────────────────────────────────────────
//
// Subclasses NetworkService (skipping Dio init) and captures the multipart
// payload so each test can assert on the exact fields sent.

class _FakeNetworkService extends NetworkService {
  @override
  // ignore: must_call_super
  void onInit() {}

  final List<Map<String, dynamic>> capturedFields = [];
  final List<String> capturedPaths = [];

  @override
  Future<NetworkResponse<dynamic>> postMultipart(
    String path, {
    required Map<String, dynamic> fields,
    required List<NetworkFile> files,
    Map<String, String>? headers,
    void Function(int sent, int total)? onSendProgress,
  }) async {
    capturedPaths.add(path);
    capturedFields.add(fields);
    return const NetworkResponse<dynamic>(
      statusCode: 201,
      data: {'id': 42, 'url': '/segmentos/thumbdb/42/0/0'},
    );
  }
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

/// JPEG magic bytes so MIME detection succeeds without a real photo.
final _jpegBytes = [0xFF, 0xD8, 0xFF, 0xE0, 0, 0, 0, 0, 0, 0, 0, 0];

Future<File> _tmpFile() async {
  final f = File(
    '${Directory.systemTemp.path}'
    '/img_test_${DateTime.now().microsecondsSinceEpoch}.jpg',
  );
  await f.writeAsBytes(_jpegBytes);
  return f;
}

ImagenSegmentoEntity _entity({required String ruta, String? gisJson}) {
  return ImagenSegmentoEntity(
    actividadId: 1,
    segmentoId: 5,
    tipoFoto: TipoFoto.antes,
    filename: 'foto.jpg',
    ruta: ruta,
    capturadaAt: DateTime.utc(2026, 1, 1),
  )..gisJson = gisJson;
}

const _gis = '{"type":"FeatureCollection","features":[{"type":"Feature",'
    '"geometry":{"type":"Point","coordinates":[-3.7,40.4]},'
    '"properties":{"heading":123.4}}]}';

// ─── Tests ───────────────────────────────────────────────────────────────────

void main() {
  late _FakeNetworkService network;
  late ImagenRemoteAdapter adapter;
  late File f;

  setUpAll(() => TestWidgetsFlutterBinding.ensureInitialized());

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    network = _FakeNetworkService();
    adapter = ImagenRemoteAdapter(network);
    f = await _tmpFile();
  });

  tearDown(() async {
    if (f.existsSync()) await f.delete();
  });

  group('push(create) — multipart fields', () {
    test('gis_json viaja tal cual cuando la captura tiene GIS', () async {
      final outcome = await adapter.push(
        entity: _entity(ruta: f.path, gisJson: _gis),
        operation: SyncOperation.create,
      );

      expect(outcome, isA<SyncSuccess<ImagenSegmentoEntity>>());
      expect(network.capturedFields.first['gis_json'], equals(_gis));
    });

    test('gis_json ausente cuando la captura no tiene GIS', () async {
      await adapter.push(
        entity: _entity(ruta: f.path, gisJson: null),
        operation: SyncOperation.create,
      );

      // Ausente: ni string vacío ni "null" — el backend guardaría GIS falso.
      expect(network.capturedFields.first.containsKey('gis_json'), isFalse);
    });

    test('los campos fijos del contrato siguen presentes', () async {
      await adapter.push(
        entity: _entity(ruta: f.path, gisJson: _gis),
        operation: SyncOperation.create,
      );

      final fields = network.capturedFields.first;
      expect(fields['tipoFoto'], equals('antes'));
      expect(fields['capturada_at'], equals('2026-01-01T00:00:00.000Z'));
    });
  });
}
