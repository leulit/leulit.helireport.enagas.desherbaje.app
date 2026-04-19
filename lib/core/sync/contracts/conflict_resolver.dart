import 'syncable.dart';

enum ConflictDecision { keepLocal, keepServer, merged, manual }

class ResolutionResult<T extends Syncable> {
  final ConflictDecision decision;
  final T? resolved;

  const ResolutionResult(this.decision, {this.resolved});

  const ResolutionResult.keepLocal(T local)
      : decision = ConflictDecision.keepLocal,
        resolved = local;

  const ResolutionResult.keepServer(T server)
      : decision = ConflictDecision.keepServer,
        resolved = server;

  const ResolutionResult.merged(T merged)
      : decision = ConflictDecision.merged,
        resolved = merged;

  const ResolutionResult.manual()
      : decision = ConflictDecision.manual,
        resolved = null;
}

abstract class ConflictResolver<T extends Syncable> {
  ResolutionResult<T> resolve({required T local, required T server});
}

class LastWriteWinsResolver<T extends Syncable> implements ConflictResolver<T> {
  const LastWriteWinsResolver();

  @override
  ResolutionResult<T> resolve({required T local, required T server}) =>
      local.updatedAt.isAfter(server.updatedAt)
          ? ResolutionResult.keepLocal(local)
          : ResolutionResult.keepServer(server);
}

class ServerWinsResolver<T extends Syncable> implements ConflictResolver<T> {
  const ServerWinsResolver();

  @override
  ResolutionResult<T> resolve({required T local, required T server}) =>
      ResolutionResult.keepServer(server);
}

class ClientWinsResolver<T extends Syncable> implements ConflictResolver<T> {
  const ClientWinsResolver();

  @override
  ResolutionResult<T> resolve({required T local, required T server}) =>
      ResolutionResult.keepLocal(local);
}

class ManualResolver<T extends Syncable> implements ConflictResolver<T> {
  const ManualResolver();

  @override
  ResolutionResult<T> resolve({required T local, required T server}) =>
      const ResolutionResult.manual();
}
