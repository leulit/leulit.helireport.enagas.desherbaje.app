---
name: flutter-backend-integration
user-invocable: true
description: >
  Flutter backend integration skill — use this whenever the project involves
  API calls, authentication, HTTP clients, database connections, Odoo integration,
  JWT tokens, refresh tokens, session management, REST APIs, GraphQL, WebSockets,
  or any network/backend communication. Triggers on mentions of API, endpoint,
  HTTP, GetConnect, authentication, login, token, Odoo, Node.js, MySQL,
  PostgreSQL, backend, or network layer. Always apply alongside flutter-core.
  Covers multi-auth strategies, Odoo JSON-RPC, offline-ready data layer, and
  robust error handling patterns.
---

# Flutter Backend Integration Skill

> Always apply **flutter-core** in parallel. This skill extends it for backend communication.

## Architecture: Data Layer

```
data/
├── providers/
│   ├── api_provider.dart         # GetConnect base — all HTTP calls
│   ├── odoo_provider.dart        # Odoo JSON-RPC specific provider
│   └── websocket_provider.dart   # Real-time connections
├── repositories/
│   ├── auth_repository_impl.dart
│   └── [feature]_repository_impl.dart
└── models/
    ├── api_response.dart         # Generic wrapper
    └── [feature]_model.dart
```

---

## Base API Provider (GetConnect)

```dart
// data/providers/api_provider.dart
class ApiProvider extends GetConnect {
  static const _baseUrlKey = 'API_BASE_URL'; // from --dart-define

  @override
  void onInit() {
    httpClient.baseUrl = const String.fromEnvironment(_baseUrlKey,
        defaultValue: 'https://api.dev.example.com');
    httpClient.timeout = const Duration(seconds: 30);
    httpClient.maxAuthRetries = 1;

    // Attach token on every request
    httpClient.addRequestModifier<dynamic>((request) async {
      final token = Get.find<AuthService>().accessToken;
      if (token != null) {
        request.headers['Authorization'] = 'Bearer $token';
      }
      request.headers['Accept'] = 'application/json';
      request.headers['Content-Type'] = 'application/json';
      return request;
    });

    // Handle 401 globally — attempt refresh, then logout
    httpClient.addAuthenticator<dynamic>((request) async {
      final refreshed = await Get.find<AuthService>().refreshToken();
      if (refreshed) {
        final newToken = Get.find<AuthService>().accessToken;
        request.headers['Authorization'] = 'Bearer $newToken';
        return request;
      }
      await Get.find<AuthService>().logout();
      return request;
    });

    httpClient.addResponseModifier((request, response) async {
      if (response.statusCode == 500) {
        // Log server errors centrally
        _logServerError(request, response);
      }
      return response;
    });
  }

  void _logServerError(Request request, Response response) {
    // Send to crash reporting (Sentry, Firebase Crashlytics, etc.)
    debugPrint('[API ERROR] ${request.method} ${request.url} → ${response.statusCode}');
  }
}
```

---

## Authentication Strategies

Since auth varies per project, the service is designed to be strategy-swappable.

### JWT with Refresh Token (most common)

```dart
class AuthService extends GetxService {
  static const _accessKey = 'auth_access_token';
  static const _refreshKey = 'auth_refresh_token';

  String? get accessToken => GetStorage().read(_accessKey);
  String? get _refreshTokenValue => GetStorage().read(_refreshKey);

  final currentUser = Rxn<UserEntity>();
  final isAuthenticated = false.obs;

  Future<AuthService> init() async {
    final token = accessToken;
    if (token != null && !_isExpired(token)) {
      isAuthenticated.value = true;
      await _loadCurrentUser();
    } else if (_refreshTokenValue != null) {
      await refreshToken();
    }
    return this;
  }

  Future<Either<Failure, UserEntity>> login(String email, String password) async {
    try {
      final response = await Get.find<ApiProvider>().post(
        '/auth/login',
        {'email': email, 'password': password},
      );
      if (response.statusCode == 200) {
        final data = response.body as Map<String, dynamic>;
        await _persistTokens(data['access_token'], data['refresh_token']);
        final user = UserEntity.fromJson(data['user']);
        currentUser.value = user;
        isAuthenticated.value = true;
        return Right(user);
      }
      return Left(AuthFailure(_parseError(response)));
    } on SocketException {
      return Left(const NetworkFailure());
    } catch (e) {
      return Left(AuthFailure(e.toString()));
    }
  }

  /// Returns true if refresh succeeded.
  Future<bool> refreshToken() async {
    final refresh = _refreshTokenValue;
    if (refresh == null) return false;
    try {
      final response = await Get.find<ApiProvider>().post(
        '/auth/refresh',
        {'refresh_token': refresh},
      );
      if (response.statusCode == 200) {
        final data = response.body as Map<String, dynamic>;
        await _persistTokens(data['access_token'], data['refresh_token']);
        isAuthenticated.value = true;
        return true;
      }
    } catch (_) {}
    await logout();
    return false;
  }

  Future<void> logout() async {
    await GetStorage().remove(_accessKey);
    await GetStorage().remove(_refreshKey);
    currentUser.value = null;
    isAuthenticated.value = false;
    Get.offAllNamed(AppRoutes.login);
  }

  Future<void> _persistTokens(String access, String refresh) async {
    await GetStorage().write(_accessKey, access);
    await GetStorage().write(_refreshKey, refresh);
  }

  bool _isExpired(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return true;
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      ) as Map<String, dynamic>;
      final exp = payload['exp'] as int;
      return DateTime.fromMillisecondsSinceEpoch(exp * 1000)
          .isBefore(DateTime.now());
    } catch (_) {
      return true;
    }
  }

  Future<void> _loadCurrentUser() async { /* ... */ }
  String _parseError(Response r) => (r.body?['message'] as String?) ?? 'Unknown error';
}
```

### Session / Cookie Auth
```dart
// For cookie-based auth, persist session ID in GetStorage
// and attach as header (since Flutter's HTTP client doesn't auto-handle cookies)
httpClient.addRequestModifier<dynamic>((request) async {
  final sessionId = GetStorage().read<String>('session_id');
  if (sessionId != null) {
    request.headers['Cookie'] = 'session=$sessionId';
  }
  return request;
});
```

---

## Odoo JSON-RPC Integration

```dart
// data/providers/odoo_provider.dart
class OdooProvider extends GetConnect {
  final String baseUrl;
  String? _sessionId;

  OdooProvider(this.baseUrl);

  @override
  void onInit() {
    httpClient.baseUrl = baseUrl;
    httpClient.timeout = const Duration(seconds: 60); // Odoo can be slow
    httpClient.addRequestModifier<dynamic>((request) async {
      if (_sessionId != null) {
        request.headers['Cookie'] = 'session_id=$_sessionId';
      }
      return request;
    });
  }

  /// Authenticate with Odoo and get session_id.
  Future<Either<Failure, int>> authenticate({
    required String db,
    required String login,
    required String password,
  }) async {
    final response = await _jsonRpcCall('/web/session/authenticate', {
      'db': db, 'login': login, 'password': password,
    });
    return response.fold(
      Left.new,
      (data) {
        _sessionId = data['session_id'] as String?;
        return Right(data['uid'] as int);
      },
    );
  }

  /// Call any Odoo model method via JSON-RPC.
  Future<Either<Failure, dynamic>> callKw({
    required String model,
    required String method,
    List args = const [],
    Map<String, dynamic> kwargs = const {},
  }) {
    return _jsonRpcCall('/web/dataset/call_kw', {
      'model': model,
      'method': method,
      'args': args,
      'kwargs': {'context': {}, ...kwargs},
    });
  }

  /// Search records with domain filter.
  Future<Either<Failure, List<Map<String, dynamic>>>> searchRead({
    required String model,
    List domain = const [],
    required List<String> fields,
    int? limit,
    int offset = 0,
  }) async {
    final result = await callKw(
      model: model,
      method: 'search_read',
      args: [domain],
      kwargs: {'fields': fields, 'limit': limit, 'offset': offset},
    );
    return result.map((data) =>
        (data as List).cast<Map<String, dynamic>>());
  }

  Future<Either<Failure, dynamic>> _jsonRpcCall(
    String endpoint,
    Map<String, dynamic> params,
  ) async {
    try {
      final response = await post(endpoint, {
        'jsonrpc': '2.0',
        'method': 'call',
        'id': DateTime.now().millisecondsSinceEpoch,
        'params': params,
      });
      if (response.statusCode == 200) {
        final body = response.body as Map<String, dynamic>;
        if (body.containsKey('error')) {
          return Left(ServerFailure(body['error']['data']['message'] ?? 'Odoo error'));
        }
        return Right(body['result']);
      }
      return Left(ServerFailure('HTTP ${response.statusCode}'));
    } on SocketException {
      return Left(const NetworkFailure());
    }
  }
}
```

---

## Generic API Response Wrapper

```dart
// Always wrap API responses — never expose raw HTTP to domain layer
class ApiResponse<T> {
  final T? data;
  final String? error;
  final int? statusCode;
  final bool get isSuccess => error == null && data != null;

  const ApiResponse.success(this.data) : error = null, statusCode = 200;
  const ApiResponse.failure(this.error, {this.statusCode}) : data = null;
}

// Paginated response
class PaginatedResponse<T> {
  final List<T> items;
  final int total;
  final int page;
  final int pageSize;
  bool get hasMore => (page * pageSize) < total;

  const PaginatedResponse({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
  });
}
```

---

## WebSocket (Real-time)

```dart
class WebSocketProvider extends GetxService {
  WebSocket? _socket;
  final _messageController = StreamController<dynamic>.broadcast();
  Stream<dynamic> get messages => _messageController.stream;
  final isConnected = false.obs;

  Future<void> connect(String url) async {
    _socket = await WebSocket.connect(url);
    isConnected.value = true;
    _socket!.listen(
      _messageController.add,
      onError: (_) => _reconnect(url),
      onDone: () => _reconnect(url),
    );
  }

  void send(Map<String, dynamic> payload) {
    _socket?.add(jsonEncode(payload));
  }

  Future<void> _reconnect(String url) async {
    isConnected.value = false;
    await Future.delayed(const Duration(seconds: 3));
    await connect(url);
  }

  @override
  void onClose() {
    _socket?.close();
    _messageController.close();
    super.onClose();
  }
}
```

---

> **Config & DI**: See `flutter-core` for AppConfig, environment variables, and GetX service registration.

## Reference Files

- `references/error-handling.md` — Failure taxonomy, user-facing messages
- `references/multipart-uploads.md` — File uploads with progress
