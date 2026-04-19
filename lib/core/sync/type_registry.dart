import 'contracts/conflict_resolver.dart';
import 'contracts/local_store.dart';
import 'contracts/remote_adapter.dart';
import 'contracts/syncable.dart';

class TypeRegistration<T extends Syncable> {
  final String entityType;
  final RemoteAdapter<T> adapter;
  final ConflictResolver<T> conflictResolver;
  final T Function(Map<String, dynamic> json) fromJson;
  final LocalStore<T>? localStore;

  const TypeRegistration({
    required this.entityType,
    required this.adapter,
    required this.conflictResolver,
    required this.fromJson,
    this.localStore,
  });
}

class TypeRegistry {
  final Map<String, TypeRegistration<Syncable>> _registrations = {};

  void register<T extends Syncable>(TypeRegistration<T> registration) {
    if (_registrations.containsKey(registration.entityType)) {
      throw StateError(
        'Type "${registration.entityType}" is already registered.',
      );
    }
    _registrations[registration.entityType] =
        registration as TypeRegistration<Syncable>;
  }

  TypeRegistration<Syncable>? lookup(String entityType) =>
      _registrations[entityType];

  bool isRegistered(String entityType) =>
      _registrations.containsKey(entityType);

  Iterable<String> get registeredTypes => _registrations.keys;

  bool get isEmpty => _registrations.isEmpty;

  void clear() => _registrations.clear();
}
