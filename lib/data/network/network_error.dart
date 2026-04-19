enum NetworkErrorCategory {
  offline,
  timeout,
  retryable, // 5xx, 429, 408
  unauthorized, // 401, 403
  conflict, // 409, 412
  unrecoverable, // 400, 404, 422, other 4xx, unknown
}

class NetworkError implements Exception {
  final NetworkErrorCategory category;
  final int? statusCode;
  final String message;
  final Object? cause;
  final StackTrace? stackTrace;

  const NetworkError({
    required this.category,
    this.statusCode,
    required this.message,
    this.cause,
    this.stackTrace,
  });

  @override
  String toString() =>
      'NetworkError(category: $category, status: $statusCode, message: $message)';
}
