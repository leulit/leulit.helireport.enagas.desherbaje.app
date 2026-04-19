sealed class DataResult<T> {
  const DataResult();

  factory DataResult.success(T data) = DataSuccess<T>;
  factory DataResult.failure({
    required String message,
    int statusCode = 500,
    Object? cause,
  }) => DataFailure<T>(message: message, statusCode: statusCode, cause: cause);

  bool get isSuccess => this is DataSuccess<T>;
  bool get isFailure => this is DataFailure<T>;

  T? get dataOrNull => switch (this) {
        DataSuccess<T>(data: final d) => d,
        DataFailure<T>() => null,
      };

  T getOrElse(T fallback) => switch (this) {
        DataSuccess<T>(data: final d) => d,
        DataFailure<T>() => fallback,
      };

  DataResult<R> map<R>(R Function(T) transform) => switch (this) {
        DataSuccess<T>(data: final d) => DataResult.success(transform(d)),
        DataFailure<T>(
          message: final m,
          statusCode: final s,
          cause: final c
        ) =>
          DataFailure<R>(message: m, statusCode: s, cause: c),
      };
}

final class DataSuccess<T> extends DataResult<T> {
  final T data;
  const DataSuccess(this.data);
}

final class DataFailure<T> extends DataResult<T> {
  final String message;
  final int statusCode;
  final Object? cause;
  const DataFailure({
    required this.message,
    this.statusCode = 500,
    this.cause,
  });
}
