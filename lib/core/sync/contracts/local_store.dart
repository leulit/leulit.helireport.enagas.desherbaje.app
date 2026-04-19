import 'package:sqflite/sqflite.dart';

import 'syncable.dart';

abstract class LocalStore<T extends Syncable> {
  Future<void> upsert(T entity, {DatabaseExecutor? txn});

  Future<void> delete(String clientId, {DatabaseExecutor? txn});

  Future<T?> findByClientId(String clientId);

  Future<List<T>> findAll();

  Future<void> markSynced({
    required String clientId,
    String? remoteId,
    DatabaseExecutor? txn,
  });
}
