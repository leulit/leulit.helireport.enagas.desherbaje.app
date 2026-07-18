// Tests for SegmentoRemoteAdapter — focus: the upsert body carries the fields
// declared in the backend contract (§3), notably `ctname` (el CT viaja por
// nombre, no por id).
import 'package:flutter_test/flutter_test.dart';

import 'package:helireport_desherbaje/core/sync/contracts/remote_adapter.dart';
import 'package:helireport_desherbaje/core/sync/contracts/sync_job.dart'
    show SyncOperation;
import 'package:helireport_desherbaje/data/network/network_response.dart';
import 'package:helireport_desherbaje/data/network/network_service.dart';
import 'package:helireport_desherbaje/data/sync/segmento_remote_adapter.dart';
import 'package:helireport_desherbaje/domain/entities/segmento_entity.dart';

/// Captures the POST body without hitting the network (skips Dio init).
class _FakeNetworkService extends NetworkService {
  @override
  // ignore: must_call_super
  void onInit() {}

  Object? capturedBody;
  String? capturedPath;

  @override
  Future<NetworkResponse<dynamic>> post(
    String path, {
    Object? body,
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
  }) async {
    capturedPath = path;
    capturedBody = body;
    return const NetworkResponse<dynamic>(statusCode: 200, data: {'id': 42});
  }
}

void main() {
  test('push(create) upsert body carries ctname and never ct_id (§3)', () async {
    final net = _FakeNetworkService();
    final adapter = SegmentoRemoteAdapter(net);
    final seg = SegmentoEntity(null, 'CT-BURGOS', TipoInstalacion.lineal, []);

    final outcome =
        await adapter.push(entity: seg, operation: SyncOperation.create);

    expect(outcome, isA<SyncSuccess<SegmentoEntity>>());
    final body = net.capturedBody as Map<String, dynamic>;
    expect(body['ctname'], equals('CT-BURGOS'));
    // El esquema antiguo (ct_id) NO debe viajar: el backend lo descartaría en
    // silencio y ocultaría el CT.
    expect(body.containsKey('ct_id'), isFalse);
  });
}
