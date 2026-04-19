class NetworkResponse<T> {
  final int statusCode;
  final T? data;
  final Map<String, List<String>> headers;

  const NetworkResponse({
    required this.statusCode,
    this.data,
    this.headers = const {},
  });

  bool get isSuccess => statusCode >= 200 && statusCode < 300;
}
