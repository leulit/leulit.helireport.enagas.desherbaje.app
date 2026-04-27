import 'contracts/conflict_resolver.dart';
import 'contracts/local_store.dart';
import 'contracts/remote_adapter.dart';
import 'contracts/remote_fetcher.dart';
import 'contracts/syncable.dart';

class TypeRegistration<T extends Syncable> {
  final String entityType;
  final LocalStore<T> store;
  final ConflictResolver<T> conflictResolver;
  final T Function(Map<String, dynamic> json) fromJson;
  final RemoteAdapter<T>? adapter;
  final RemoteFetcher<T>? fetcher;

  /// Maps an entity to a human-readable `{label: value}` map used by the
  /// conflict diff view. Required when [conflictResolver] is
  /// [InteractiveConflictResolver]; ignored otherwise.
  final Map<String, String> Function(T entity)? formatForDisplay;

  const TypeRegistration({
    required this.entityType,
    required this.store,
    required this.conflictResolver,
    required this.fromJson,
    this.adapter,
    this.fetcher,
    this.formatForDisplay,
  });

  bool get hasAdapter => adapter != null;
  bool get hasFetcher => fetcher != null;
}

class TypeRegistry {
  final Map<String, TypeRegistration<Syncable>> _registrations = {};

  void register<T extends Syncable>(TypeRegistration<T> registration) {
    if (_registrations.containsKey(registration.entityType)) {
      throw StateError(
        'Type "${registration.entityType}" is already registered.',
      );
    }
    if (!registration.hasAdapter && !registration.hasFetcher) {
      throw ArgumentError(
        'Type "${registration.entityType}" must declare at least one of '
        'adapter (push) or fetcher (pull).',
      );
    }
    _registrations[registration.entityType] =
        registration as TypeRegistration<Syncable>;
  }

  TypeRegistration<Syncable>? lookup(String entityType) =>
      _registrations[entityType];

  Iterable<TypeRegistration<Syncable>> get registrations =>
      _registrations.values;

  Iterable<String> get registeredTypes => _registrations.keys;

  bool isRegistered(String entityType) =>
      _registrations.containsKey(entityType);

  bool get isEmpty => _registrations.isEmpty;

  void clear() => _registrations.clear();
}
