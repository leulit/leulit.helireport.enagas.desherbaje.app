# Advanced GetX Patterns

## GetxService — Long-lived Singletons

Use `GetxService` for services that must persist for the app's lifetime (auth, storage, analytics).
They are never destroyed unless explicitly called with `Get.reset()`.

```dart
class AuthService extends GetxService {
  final currentUser = Rxn<User>();
  final isAuthenticated = false.obs;

  Future<AuthService> init() async {
    // Load persisted session, validate token, etc.
    final stored = await _loadStoredSession();
    if (stored != null) {
      currentUser.value = stored;
      isAuthenticated.value = true;
    }
    return this;
  }

  Future<void> logout() async {
    await _clearSession();
    currentUser.value = null;
    isAuthenticated.value = false;
    Get.offAllNamed(AppRoutes.login);
  }
}

// Register before runApp
void main() async {
  await Get.putAsync(() => AuthService().init());
  runApp(const MyApp());
}
```

## Workers — Reactive Side Effects

Workers react to observable changes without rebuilding widgets.

```dart
class SearchController extends GetxController {
  final query = ''.obs;
  final results = <Product>[].obs;

  @override
  void onInit() {
    super.onInit();
    // Debounce: fires 500ms after the user stops typing
    debounce(query, (_) => _search(), time: const Duration(milliseconds: 500));

    // Ever: fires on every change
    ever(results, (_) => _logAnalytics());

    // Once: fires only on the first change
    once(query, (_) => _trackFirstSearch());
  }

  void _search() async { /* ... */ }
}
```

## GetConnect — HTTP Client

Prefer `GetConnect` over `http` or `dio` for API calls — it integrates with GetX DI.

```dart
class ApiProvider extends GetConnect {
  @override
  void onInit() {
    httpClient.baseUrl = const String.fromEnvironment('API_BASE_URL');
    httpClient.timeout = const Duration(seconds: 30);

    // Request interceptor — attach auth token
    httpClient.addRequestModifier<dynamic>((request) async {
      final token = Get.find<AuthService>().token;
      if (token != null) {
        request.headers['Authorization'] = 'Bearer $token';
      }
      return request;
    });

    // Response interceptor — handle 401 globally
    httpClient.addResponseModifier((request, response) async {
      if (response.statusCode == 401) {
        await Get.find<AuthService>().logout();
      }
      return response;
    });
  }

  Future<Response<List<dynamic>>> getProducts() =>
      get('/products');

  Future<Response<dynamic>> createProduct(Map<String, dynamic> body) =>
      post('/products', body);
}
```

## Middleware — Route Guards

```dart
class AuthMiddleware extends GetMiddleware {
  @override
  int? get priority => 1;

  @override
  RouteSettings? redirect(String? route) {
    final isAuth = Get.find<AuthService>().isAuthenticated.value;
    return isAuth ? null : const RouteSettings(name: AppRoutes.login);
  }
}
```

## GetView vs GetWidget

```dart
// GetView: new controller instance per navigation (most common)
class ProductPage extends GetView<ProductController> { ... }

// GetWidget: caches the controller — use for widgets that must
// keep the same controller instance across rebuilds (e.g. tabs)
class TabWidget extends GetWidget<TabController> { ... }
```

## Dependency Lifecycle

```dart
// lazyPut: created on first access, destroyed when no longer used
Get.lazyPut<ProductController>(() => ProductController(Get.find()));

// put: created immediately, stays in memory
Get.put(AuthService());

// create: new instance every time Get.find() is called
Get.create<FormController>(() => FormController());

// Permanent: never auto-destroyed
Get.lazyPut<CacheService>(() => CacheService(), fenix: true);
```

## Observable Collections

```dart
final items = <String>[].obs;

// ✅ Triggers reactivity
items.add('new item');
items.assignAll(newList);
items.removeWhere((e) => e.isEmpty);

// ❌ Does NOT trigger reactivity
items.value.add('new item'); // mutates underlying list without notifying
```

## Rx Types Cheatsheet

```dart
final count = 0.obs;           // RxInt
final name = ''.obs;           // RxString
final flag = false.obs;        // RxBool
final price = 0.0.obs;         // RxDouble
final user = Rxn<User>();      // RxNullable<User> — starts null
final items = <Item>[].obs;    // RxList<Item>
final map = <String, int>{}.obs; // RxMap<String, int>
```
