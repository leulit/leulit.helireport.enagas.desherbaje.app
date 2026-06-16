// Tests for GasoductosService — WS5 (NF-12, NF-14).
//
// Coverage:
//   (a) offline → MasterDataSource.cache, loader not called
//   (b) online + loader throws → reload RETHROWS (NF-12)
//   (c) online + cache-hit (no forceRefresh) → MasterDataSource.cache
//       [tested via the _loaded flag path: once loaded, ensureLoaded is no-op]
//   (d) online + network path → MasterDataSource.network with itemCount
//
// Note: GasoductosService uses LocalDatabase.instance.database (singleton)
// which wraps getDatabasesPath() — a native call. We use sqflite_common_ffi
// to override the factory so the in-memory DB is used in tests. The offline
// path (a) avoids DB calls entirely; the rethrow path (b) also avoids them.
// For (d) we stub loadFiles to fire no events → itemCount == 0.
//
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:helireport_desherbaje/core/services/connectivity_service.dart';
import 'package:helireport_desherbaje/core/services/gasoductos_service.dart';
import 'package:helireport_desherbaje/core/services/master_data_load_result.dart';
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
  late GasoductosService service;

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
    // With empty CTs, _loadFromCache gets empty list → polylines stay empty.
    SharedPreferences.setMockInitialValues({'user_json': _userJsonNoCts});
    when(() => mockConn.isConnected).thenReturn(false);

    service = GasoductosService(conn: mockConn, loader: mockLoader);
    service.onInit();

    final result = await service.reload();

    expect(result.source, equals(MasterDataSource.cache));
    verifyNever(
      () => mockLoader.loadFiles(any(), token: any(named: 'token')),
    );
  });

  // ─── (b) Online + loader throws → rethrows ───────────────────────────────

  test('(b) online + loader throws → reload rethrows (NF-12)', () async {
    // Need at least 1 CT so the service reaches the loader call.
    // With empty CTs it falls through offline/cache checks early.
    // We use a CT with an online path but mock loader to throw.
    SharedPreferences.setMockInitialValues({'user_json': _userJsonOneCt});
    when(() => mockConn.isConnected).thenReturn(true);
    when(() => mockLoader.loadFiles(any(), token: any(named: 'token')))
        .thenThrow(Exception('network error'));

    service = GasoductosService(conn: mockConn, loader: mockLoader);
    service.onInit();

    // reload must propagate the exception (not swallow it).
    await expectLater(
      () => service.reload(),
      throwsA(isA<Exception>()),
    );
  });

  // ─── (c) Already loaded → ensureLoaded is a no-op ────────────────────────
  // Tests the "cache-hit" behaviour when the service is already loaded:
  // ensureLoaded short-circuits without calling the loader.

  test('(c) ensureLoaded when already loaded → no loader call', () async {
    SharedPreferences.setMockInitialValues({'user_json': _userJsonNoCts});
    when(() => mockConn.isConnected).thenReturn(false);

    service = GasoductosService(conn: mockConn, loader: mockLoader);
    service.onInit();

    // First call loads (offline path: cache, empty).
    await service.reload();
    expect(service.isLoaded, isTrue);

    // Now reset loader mock expectations.
    clearInteractions(mockLoader);

    // ensureLoaded should be a no-op (already loaded).
    await service.ensureLoaded();

    verifyNever(
      () => mockLoader.loadFiles(any(), token: any(named: 'token')),
    );
  });

  // ─── (d) Online + network path → MasterDataSource.network ────────────────

  test('(d) online + network fetch → MasterDataSource.network', () async {
    SharedPreferences.setMockInitialValues({'user_json': _userJsonOneCt});
    when(() => mockConn.isConnected).thenReturn(true);

    // Loader succeeds but fires no GeoJSON events → buffer stays empty → count=0.
    when(() => mockLoader.loadFiles(any(), token: any(named: 'token')))
        .thenAnswer((_) async {
      // Fire geoJsonLoadCompleted so the service doesn't hang on _runCompleter.
      // We cannot easily dispatch the TypedAction here without full GetX init,
      // so we rely on the 1s timeout in _runOnce to unblock the completer.
      // The service sets resultSource=network and fetchedCount from the
      // (empty) buffer before the finally block.
    });

    service = GasoductosService(conn: mockConn, loader: mockLoader);
    service.onInit();

    final result = await service.reload();

    expect(result.source, equals(MasterDataSource.network));
    // No entities were dispatched via events → itemCount == 0.
    expect(result.itemCount, equals(0));
  });
}
