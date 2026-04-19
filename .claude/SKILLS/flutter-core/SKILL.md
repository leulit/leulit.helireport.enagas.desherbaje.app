---
name: flutter-core
description: >
  Foundational skill for all Flutter/Dart development in VS Code. Use this skill
  for EVERY Flutter task — creating widgets, controllers, routes, services,
  architecture decisions, dependency injection, state management, navigation, or
  any Dart code. Triggers on any mention of Flutter, Dart, widget, GetX, screen,
  controller, route, or app development. Always apply this skill even when the
  request seems simple — it enforces the project's non-negotiable standards for
  architecture, performance, and code quality across iOS, Android, and Web targets.
---

# Flutter Core Skill

## Non-Negotiable Principles

Every line of code must satisfy these properties — no exceptions:

| Property | Requirement |
|---|---|
| **Performance** | Minimize rebuilds. Prefer `StatelessWidget`. Use `const` everywhere possible. |
| **Stability** | Handle every failure path explicitly. No silent failures. |
| **Scalability** | Decouple layers. No business logic in widgets. |
| **Usability** | UI decisions must serve the user first. Smooth, responsive, accessible. |
| **Maintainability** | SOLID principles. Clean Architecture. Self-documenting code. |

---

## Architecture

### Layer Structure (Clean Architecture)

```
lib/
├── app/
│   ├── bindings/       # GetX dependency injection bindings
│   ├── routes/         # Route definitions and middleware
│   └── theme/          # ThemeData, colors, typography
├── core/
│   ├── error/          # Failure types, error handling
│   ├── network/        # HTTP client, interceptors (GetConnect)
│   ├── storage/        # Local persistence abstraction
│   └── utils/          # Pure utility functions (no Flutter deps)
├── data/
│   ├── models/         # Data transfer objects, JSON serialization
│   ├── providers/      # Remote data sources (API calls)
│   └── repositories/   # Repository implementations
├── domain/
│   ├── entities/       # Business entities (pure Dart)
│   ├── repositories/   # Repository interfaces (abstract)
│   └── usecases/       # Single-responsibility use cases
└── presentation/
    ├── controllers/    # GetxControllers — logic only, no UI
    ├── pages/          # Full screens (GetView<Controller>)
    ├── widgets/        # Reusable StatelessWidgets
    └── bindings/       # Page-level bindings
```

### SOLID Applied to Flutter/GetX

- **S** — One controller per screen/feature. One use case per operation.
- **O** — Extend via new controllers/use cases, never modify existing ones.
- **L** — Repository implementations are interchangeable with their interfaces.
- **I** — Split large controllers into focused sub-controllers.
- **D** — Controllers depend on repository interfaces, never on implementations.

---

## State Management: GetX

**Version**: `get: ^4.7.3`

### Controller Pattern

```dart
// ✅ Correct: logic isolated in controller
class ProductController extends GetxController {
  final IProductRepository _repository;

  ProductController(this._repository);

  // Observable state — use .obs
  final products = <Product>[].obs;
  final isLoading = false.obs;
  final errorMessage = ''.obs;

  @override
  void onInit() {
    super.onInit();
    fetchProducts();
  }

  Future<void> fetchProducts() async {
    isLoading.value = true;
    errorMessage.value = '';
    try {
      final result = await _repository.getAll();
      result.fold(
        (failure) => errorMessage.value = failure.message,
        (data) => products.assignAll(data),
      );
    } finally {
      isLoading.value = false;
    }
  }
}
```

### Widget Pattern: Always StatelessWidget + GetView

```dart
// ✅ Preferred: StatelessWidget + GetView — zero unnecessary rebuilds
class ProductPage extends GetView<ProductController> {
  const ProductPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Products')),
      body: Obx(() {
        if (controller.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }
        if (controller.errorMessage.isNotEmpty) {
          return ErrorView(message: controller.errorMessage.value);
        }
        return ProductList(products: controller.products);
      }),
    );
  }
}

// ✅ Reusable widgets: always StatelessWidget + const constructors
class ProductList extends StatelessWidget {
  final List<Product> products;

  const ProductList({super.key, required this.products});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: products.length,
      itemBuilder: (_, i) => ProductCard(product: products[i]),
    );
  }
}
```

```dart
// ❌ Never: StatefulWidget when StatelessWidget + GetX suffices
// ❌ Never: business logic inside build()
// ❌ Never: GetBuilder when Obx is sufficient
// ❌ Never: context-dependent navigation (use Get.toNamed())
```

### When StatefulWidget IS Acceptable

Only when managing widget-local ephemeral state that has no business value:
- `AnimationController` lifecycle
- `TextEditingController` / `FocusNode` (prefer GetX alternatives when practical)
- Platform-specific lifecycle hooks (`WidgetsBindingObserver`)

### Reactive Bindings

```dart
// Binding: lazy dependency injection
class ProductBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<IProductRepository>(() => ProductRepositoryImpl(Get.find()));
    Get.lazyPut<ProductController>(() => ProductController(Get.find()));
  }
}
```

---

## Navigation

Always use GetX named routes — never Navigator.push, never BuildContext for routing.

```dart
// routes/app_routes.dart
abstract class AppRoutes {
  static const home = '/home';
  static const product = '/product';
  static const productDetail = '/product/detail';
}

// routes/app_pages.dart
class AppPages {
  static final pages = [
    GetPage(
      name: AppRoutes.product,
      page: () => const ProductPage(),
      binding: ProductBinding(),
      middlewares: [AuthMiddleware()],
    ),
  ];
}

// Navigation calls — no context needed
Get.toNamed(AppRoutes.productDetail, arguments: product);
Get.back();
Get.offAllNamed(AppRoutes.home);
```

---

## Error Handling

Use a typed `Either<Failure, T>` pattern throughout the data and domain layers.

```dart
// core/error/failures.dart
abstract class Failure {
  final String message;
  const Failure(this.message);
}

class NetworkFailure extends Failure {
  const NetworkFailure([super.message = 'Network error']);
}

class ServerFailure extends Failure {
  final int? statusCode;
  const ServerFailure(super.message, {this.statusCode});
}

class CacheFailure extends Failure {
  const CacheFailure([super.message = 'Cache error']);
}
```

```dart
// Repository implementation: always catch, never throw to UI
Future<Either<Failure, List<Product>>> getAll() async {
  try {
    final response = await _provider.fetchProducts();
    if (response.statusCode == 200) {
      return Right(response.body.map(Product.fromJson).toList());
    }
    return Left(ServerFailure('Server error', statusCode: response.statusCode));
  } on SocketException {
    return Left(const NetworkFailure());
  } catch (e) {
    return Left(ServerFailure(e.toString()));
  }
}
```

---

## Performance Rules

1. **`const` everywhere** — every widget constructor, every decoration, every text style that doesn't change.
2. **Narrow `Obx` scope** — wrap only the widget that reacts to state, not the whole screen.
3. **`ListView.builder` / `SliverList`** — never `Column` with a mapped list for scrollable content.
4. **No logic in `build()`** — computed values belong in the controller as getters or derived observables.
5. **Avoid deep widget trees** — extract into `StatelessWidget` subclasses, not helper methods.
6. **Image optimization** — use `cached_network_image`, specify `width`/`height`, use appropriate `fit`.
7. **Lazy loading** — `Get.lazyPut` for all dependencies; `Get.create` when multiple instances needed.

```dart
// ✅ Narrow Obx — only Text rebuilds
Row(
  children: [
    const Icon(Icons.person),
    Obx(() => Text(controller.userName.value)),  // only this rebuilds
  ],
)

// ❌ Wide Obx — entire Row rebuilds unnecessarily
Obx(() => Row(
  children: [
    const Icon(Icons.person),
    Text(controller.userName.value),
  ],
))
```

---

## Multi-Platform Considerations

```dart
// Platform-adaptive layout
class ResponsiveLayout extends StatelessWidget {
  final Widget mobile;
  final Widget? tablet;
  final Widget? web;

  const ResponsiveLayout({
    super.key,
    required this.mobile,
    this.tablet,
    this.web,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 1200 && web != null) return web!;
        if (constraints.maxWidth >= 600 && tablet != null) return tablet!;
        return mobile;
      },
    );
  }
}
```

- **Web**: use `SelectableText` for copyable content, `MouseRegion` for hover states, `kIsWeb` guards for web-only APIs.
- **iOS/Android**: use `Platform.isIOS` / `Platform.isAndroid` only at the service layer, never in widgets.
- **Shared logic**: business logic must be platform-agnostic — no `dart:io` in domain/data layers if targeting web.

---

## Usability Standards

- **Touch targets**: minimum 48×48dp for all interactive elements.
- **Loading states**: every async operation shows a loading indicator — no silent waits.
- **Empty states**: every list/grid has a meaningful empty state widget.
- **Error states**: actionable error messages with retry options, never raw exception strings.
- **Accessibility**: `Semantics` labels on custom interactive widgets, sufficient color contrast (WCAG AA minimum).
- **Feedback**: every user action gets immediate visual feedback (tap highlight, progress, confirmation).
- **Internationalization**: use `GetX` i18n from day one — no hardcoded user-visible strings.

---

## Code Style

- Follow [Effective Dart](https://dart.dev/guides/language/effective-dart) conventions.
- `dart format` compatible — no manual line-break tricks that break the formatter.
- Explicit types on public APIs — no `var` on class members or function signatures.
- Private members prefixed with `_`.
- No `print()` — use a proper logger (e.g., `logger` package) with log levels.
- Maximum function length: ~30 lines. Extract if longer.

---

## Reference Files

For deeper guidance, read:
- `references/getx-patterns.md` — Advanced GetX patterns: services, middleware, workers, GetConnect
- `references/testing.md` — Unit testing controllers and repositories with GetX
- `references/platform-specifics.md` — iOS/Android/Web platform channel and conditional code patterns
