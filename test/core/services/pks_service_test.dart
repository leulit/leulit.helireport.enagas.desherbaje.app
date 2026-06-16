// Tests for PksService — WS5 (NF-12, NF-14) mirror of gasoductos_service_test.
//
// Coverage:
//   (a) offline → MasterDataSource.cache, loader not called
//   (b) online + loader throws → reload RETHROWS (NF-12)
//   (c) ensureLoaded when already loaded → no-op
//   (d) online + network path → MasterDataSource.network
//
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:helireport_desherbaje/core/services/connectivity_service.dart';
import 'package:helireport_desherbaje/core/services/master_data_load_result.dart';
import 'package:helireport_desherbaje/core/services/pks_service.dart';
import 'package:helireport_desherbaje/data/services/json_loader_service.dart';

// ─── Mocks ───────────────────────────────────────────────────────────────────

class MockConnectivityService extends Mock implements ConnectivityService {}

class MockJsonLoaderService extends Mock implements JsonLoaderService {}

// ─── Helpers ─────────────────────────────────────────────────────────────────

const _userJsonNoCts =
    '{"id":1,"usuario":"op","nombre":"Operador","token":"tok","cts":[]}';

const _userJsonOneCt =
    '{"id":1,"usuario":"op","nombre":"Operador","token":"tok","cts":['
    '{"ctid":10,"ct":"CT10","gasoductos_url":"http://fake/g.json",'
    '"pk_url":"http://fake/pk.json"}'
    ']}';

// ─── Tests ───────────────────────────────────────────────────────────────────

void main() {
  late MockConnectivityService mockConn;
  late MockJsonLoaderService mockLoader;
  late PksService service;

  setUp(() async {
    Get.reset();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    mockConn = MockConnectivityService();
    mockLoader = MockJsonLoaderService();
  });

  tearDown(() {
    try {
      service.onClose();
    } catch (_) {}
    Get.reset();
  });

  // ─── (a) Offline → cache, loader not called ──────────────────────────────

  test('(a) offline → cache source, loader never called', () async {
    SharedPreferences.setMockInitialValues({'user_json': _userJsonNoCts});
    when(() => mockConn.isConnected).thenReturn(false);

    service = PksService(conn: mockConn, loader: mockLoader);
    service.onInit();

    final result = await service.reload();

    expect(result.source, equals(MasterDataSource.cache));
    verifyNever(
      () => mockLoader.loadFiles(any(), token: any(named: 'token')),
    );
  });

  // ─── (b) Online + loader throws → rethrows ───────────────────────────────

  test('(b) online + loader throws → reload rethrows (NF-12)', () async {
    SharedPreferences.setMockInitialValues({'user_json': _userJsonOneCt});
    when(() => mockConn.isConnected).thenReturn(true);
    when(() => mockLoader.loadFiles(any(), token: any(named: 'token')))
        .thenThrow(Exception('network error'));

    service = PksService(conn: mockConn, loader: mockLoader);
    service.onInit();

    await expectLater(
      () => service.reload(),
      throwsA(isA<Exception>()),
    );
  });

  // ─── (c) Already loaded → ensureLoaded is a no-op ────────────────────────

  test('(c) ensureLoaded when already loaded → no loader call', () async {
    SharedPreferences.setMockInitialValues({'user_json': _userJsonNoCts});
    when(() => mockConn.isConnected).thenReturn(false);

    service = PksService(conn: mockConn, loader: mockLoader);
    service.onInit();

    await service.reload();
    expect(service.isLoaded, isTrue);

    clearInteractions(mockLoader);

    await service.ensureLoaded();

    verifyNever(
      () => mockLoader.loadFiles(any(), token: any(named: 'token')),
    );
  });

  // ─── (d) Online + network path → MasterDataSource.network ────────────────

  test('(d) online + network fetch → MasterDataSource.network', () async {
    SharedPreferences.setMockInitialValues({'user_json': _userJsonOneCt});
    when(() => mockConn.isConnected).thenReturn(true);
    when(() => mockLoader.loadFiles(any(), token: any(named: 'token')))
        .thenAnswer((_) async {
      // No GeoJSON events → buffer empty → itemCount = 0.
      // 1s timeout in _runOnce unblocks the completer.
    });

    service = PksService(conn: mockConn, loader: mockLoader);
    service.onInit();

    final result = await service.reload();

    expect(result.source, equals(MasterDataSource.network));
    expect(result.itemCount, equals(0));
  });
}
