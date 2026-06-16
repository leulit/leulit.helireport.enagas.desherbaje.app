import 'package:flutter_test/flutter_test.dart';

import 'package:helireport_desherbaje/core/sync/contracts/conflict_resolver.dart';
import 'package:helireport_desherbaje/core/sync/contracts/syncable.dart';

class _FakeEntity implements Syncable {
  @override
  final String clientId;
  @override
  final String? remoteId = null;
  @override
  final DateTime updatedAt;

  const _FakeEntity({
    required this.clientId,
    required this.updatedAt,
  });

  @override
  Map<String, dynamic> toJson() => {'clientId': clientId};
}

void main() {
  final older = DateTime(2024, 1, 1);
  final newer = DateTime(2024, 6, 1);

  final local = _FakeEntity(clientId: 'local-id', updatedAt: newer);
  final remote = _FakeEntity(clientId: 'remote-id', updatedAt: older);

  group('ServerWinsResolver', () {
    const resolver = ServerWinsResolver<_FakeEntity>();

    test('always returns remote', () {
      expect(resolver.resolve(local: local, remote: remote), same(remote));
    });

    test('returns remote even when local is newer', () {
      final newerLocal = _FakeEntity(clientId: 'l', updatedAt: newer);
      final olderRemote = _FakeEntity(clientId: 'r', updatedAt: older);
      expect(
        resolver.resolve(local: newerLocal, remote: olderRemote),
        same(olderRemote),
      );
    });
  });

  group('LocalWinsResolver', () {
    const resolver = LocalWinsResolver<_FakeEntity>();

    test('always returns local', () {
      expect(resolver.resolve(local: local, remote: remote), same(local));
    });

    test('returns local even when remote is newer', () {
      final olderLocal = _FakeEntity(clientId: 'l', updatedAt: older);
      final newerRemote = _FakeEntity(clientId: 'r', updatedAt: newer);
      expect(
        resolver.resolve(local: olderLocal, remote: newerRemote),
        same(olderLocal),
      );
    });
  });

  group('LastWriteWinsResolver', () {
    const resolver = LastWriteWinsResolver<_FakeEntity>();

    test('returns local when local.updatedAt is after remote', () {
      final newerLocal = _FakeEntity(clientId: 'l', updatedAt: newer);
      final olderRemote = _FakeEntity(clientId: 'r', updatedAt: older);
      expect(
        resolver.resolve(local: newerLocal, remote: olderRemote),
        same(newerLocal),
      );
    });

    test('returns remote when remote.updatedAt is after local', () {
      final olderLocal = _FakeEntity(clientId: 'l', updatedAt: older);
      final newerRemote = _FakeEntity(clientId: 'r', updatedAt: newer);
      expect(
        resolver.resolve(local: olderLocal, remote: newerRemote),
        same(newerRemote),
      );
    });

    test('returns remote when timestamps are equal (isAfter is false)', () {
      final sameTime = DateTime(2024, 3, 15);
      final a = _FakeEntity(clientId: 'a', updatedAt: sameTime);
      final b = _FakeEntity(clientId: 'b', updatedAt: sameTime);
      // local.updatedAt.isAfter(remote.updatedAt) == false → returns remote
      expect(resolver.resolve(local: a, remote: b), same(b));
    });
  });

  group('InteractiveConflictResolver', () {
    const resolver = InteractiveConflictResolver<_FakeEntity>();

    test('always returns null to defer to the user', () {
      expect(resolver.resolve(local: local, remote: remote), isNull);
    });
  });
}
