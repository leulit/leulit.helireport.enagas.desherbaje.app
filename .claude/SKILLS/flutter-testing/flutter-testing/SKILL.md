---
name: flutter-testing
description: >
  Flutter testing skill — use this whenever the project involves unit tests,
  widget tests, integration tests, test coverage, mocking repositories,
  testing GetX controllers, or any quality assurance activity. Triggers on
  mentions of test, spec, mock, expect, verify, coverage, unit test, widget test,
  integration test, TDD, or any request to write tests for existing code.
  Always apply alongside flutter-core. Enforces GetX-compatible test patterns,
  clean mocking, and meaningful assertions.
---

# Flutter Testing Skill

> Always apply **flutter-core** in parallel. This skill extends it for testing.

## Test Pyramid

```
         ┌──────────────────┐
         │  Integration Tests│  ← Few, slow, test full flows
         │  (5-10% of tests) │
         ├──────────────────┤
         │   Widget Tests    │  ← Medium, test UI + controller interaction
         │  (20-30%)         │
         ├──────────────────┤
         │   Unit Tests      │  ← Many, fast, test logic in isolation
         │  (60-70%)         │
         └──────────────────┘
```

## Core Stack

| Package | Purpose |
|---|---|
| `flutter_test` | Built-in widget + async testing |
| `mocktail: ^1.0.4` | Mocking without code generation |
| `get_test` | GetX-compatible test utilities |
| `fake_async` | Control time in tests (debounce, timers) |

---

## Unit Testing: GetX Controllers

The key: register mocked dependencies with `Get.put()` before instantiating the controller.

```dart
// test/presentation/controllers/product_controller_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:get/get.dart';

// Mock repository — no code generation needed with mocktail
class MockProductRepository extends Mock implements IProductRepository {}

void main() {
  late ProductController controller;
  late MockProductRepository mockRepository;

  setUp(() {
    // Reset GetX state between tests
    Get.reset();
    mockRepository = MockProductRepository();
    controller = ProductController(mockRepository);
    Get.put(controller);
  });

  tearDown(() {
    Get.reset();
  });

  group('ProductController', () {
    final testProducts = [
      const Product(id: '1', name: 'Widget A', price: 9.99),
      const Product(id: '2', name: 'Widget B', price: 19.99),
    ];

    test('initial state is correct', () {
      expect(controller.products, isEmpty);
      expect(controller.isLoading.value, isFalse);
      expect(controller.errorMessage.value, isEmpty);
    });

    test('fetchProducts sets products on success', () async {
      // Arrange
      when(() => mockRepository.getAll())
          .thenAnswer((_) async => Right(testProducts));

      // Act
      await controller.fetchProducts();

      // Assert
      expect(controller.products, equals(testProducts));
      expect(controller.isLoading.value, isFalse);
      expect(controller.errorMessage.value, isEmpty);
      verify(() => mockRepository.getAll()).called(1);
    });

    test('fetchProducts sets error on failure', () async {
      // Arrange
      when(() => mockRepository.getAll())
          .thenAnswer((_) async => Left(const NetworkFailure()));

      // Act
      await controller.fetchProducts();

      // Assert
      expect(controller.products, isEmpty);
      expect(controller.errorMessage.value, isNotEmpty);
      expect(controller.isLoading.value, isFalse);
    });

    test('fetchProducts shows loading state during fetch', () async {
      // Track loading states during execution
      final loadingStates = <bool>[];
      controller.isLoading.listen(loadingStates.add);

      when(() => mockRepository.getAll())
          .thenAnswer((_) async {
            await Future.delayed(const Duration(milliseconds: 10));
            return Right(testProducts);
          });

      await controller.fetchProducts();

      expect(loadingStates, containsAllInOrder([true, false]));
    });
  });
}
```

---

## Unit Testing: Validators & Use Cases

```dart
// test/core/utils/validators_test.dart
void main() {
  group('Validators.email', () {
    test('returns null for valid email', () {
      expect(Validators.email('user@example.com'), isNull);
      expect(Validators.email('user.name+tag@domain.co.uk'), isNull);
    });

    test('returns error for empty input', () {
      expect(Validators.email(''), isNotNull);
      expect(Validators.email(null), isNotNull);
    });

    test('returns error for invalid format', () {
      expect(Validators.email('notanemail'), isNotNull);
      expect(Validators.email('@domain.com'), isNotNull);
      expect(Validators.email('user@'), isNotNull);
    });
  });

  group('Validators.compose', () {
    test('returns first error from composed validators', () {
      final result = Validators.compose('', [
        (v) => Validators.required(v),
        (v) => Validators.email(v),
      ]);
      expect(result, contains('required'));
    });

    test('returns null when all validators pass', () {
      final result = Validators.compose('user@example.com', [
        (v) => Validators.required(v),
        (v) => Validators.email(v),
      ]);
      expect(result, isNull);
    });
  });
}
```

---

## Widget Testing

```dart
// test/presentation/pages/login_page_test.dart
void main() {
  late MockAuthRepository mockRepository;

  setUp(() {
    Get.reset();
    mockRepository = MockAuthRepository();
    Get.put<IAuthRepository>(mockRepository);
    Get.put(LoginController(mockRepository));
  });

  tearDown(() => Get.reset());

  Widget buildTestApp() => GetMaterialApp(
    home: const LoginPage(),
  );

  group('LoginPage', () {
    testWidgets('renders email and password fields', (tester) async {
      await tester.pumpWidget(buildTestApp());

      expect(find.byType(TextFormField), findsNWidgets(2));
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
    });

    testWidgets('shows error when submitting empty form', (tester) async {
      await tester.pumpWidget(buildTestApp());

      // Tap submit without filling fields
      await tester.tap(find.text('Sign In'));
      await tester.pump();

      expect(find.text('Email is required'), findsOneWidget);
      expect(find.text('Password is required'), findsOneWidget);
    });

    testWidgets('shows loading indicator during submit', (tester) async {
      when(() => mockRepository.login(
        email: any(named: 'email'),
        password: any(named: 'password'),
      )).thenAnswer((_) async {
        await Future.delayed(const Duration(milliseconds: 100));
        return Right(const UserEntity(id: '1', email: 'user@test.com'));
      });

      await tester.pumpWidget(buildTestApp());

      await tester.enterText(
          find.byType(TextFormField).at(0), 'user@test.com');
      await tester.enterText(
          find.byType(TextFormField).at(1), 'password123');
      await tester.tap(find.text('Sign In'));
      await tester.pump(); // Start the async operation

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pumpAndSettle(); // Complete it
    });

    testWidgets('navigates to home on successful login', (tester) async {
      when(() => mockRepository.login(
        email: any(named: 'email'),
        password: any(named: 'password'),
      )).thenAnswer((_) async =>
          Right(const UserEntity(id: '1', email: 'user@test.com')));

      await tester.pumpWidget(GetMaterialApp(
        initialRoute: AppRoutes.login,
        getPages: AppPages.pages,
        home: const LoginPage(),
      ));

      await tester.enterText(
          find.byType(TextFormField).at(0), 'user@test.com');
      await tester.enterText(
          find.byType(TextFormField).at(1), 'password123');
      await tester.tap(find.text('Sign In'));
      await tester.pumpAndSettle();

      // Should no longer be on login page
      expect(find.byType(LoginPage), findsNothing);
    });
  });
}
```

---

## Testing with Fake Data (Fixtures)

```dart
// test/fixtures/product_fixtures.dart
abstract class ProductFixtures {
  static const validProduct = Product(
    id: 'test-id-1',
    name: 'Test Product',
    price: 9.99,
    description: 'A test product',
  );

  static final productList = List.generate(
    10, (i) => Product(id: 'id-$i', name: 'Product $i', price: i * 10.0),
  );

  static String get validProductJson => jsonEncode({
    'id': 'test-id-1',
    'name': 'Test Product',
    'price': 9.99,
  });
}
```

---

## Testing Debounce & Timers (fake_async)

```dart
import 'package:fake_async/fake_async.dart';

test('search debounces correctly', () {
  fakeAsync((async) {
    final controller = SearchController(mockRepository);
    when(() => mockRepository.search(any())).thenAnswer(
      (_) async => Right([]));

    controller.onQueryChanged('flutter');
    async.elapse(const Duration(milliseconds: 300)); // < debounce
    verifyNever(() => mockRepository.search(any()));

    async.elapse(const Duration(milliseconds: 300)); // = debounce
    verify(() => mockRepository.search('flutter')).called(1);
  });
});
```

---

## Repository Mocking with mocktail

```dart
// Always register fallback values for custom types
setUpAll(() {
  registerFallbackValue(const Product(id: '', name: '', price: 0));
  registerFallbackValue(const NetworkFailure());
});

// Stub with argument matchers
when(() => mockRepository.getById(any()))
    .thenAnswer((_) async => Right(ProductFixtures.validProduct));

when(() => mockRepository.getById('invalid-id'))
    .thenAnswer((_) async => Left(const ServerFailure('Not found', statusCode: 404)));

// Verify call count and arguments
verify(() => mockRepository.getById('test-id-1')).called(1);
verifyNever(() => mockRepository.delete(any()));
```

---

## Coverage & CI

```bash
# Run all tests with coverage
flutter test --coverage

# Generate HTML coverage report
genhtml coverage/lcov.info -o coverage/html
open coverage/html/index.html

# Run tests with verbose output
flutter test --reporter expanded

# Run specific test file
flutter test test/presentation/controllers/product_controller_test.dart
```

Target coverage thresholds:
- **Controllers**: ≥ 90%
- **Validators / use cases**: 100%
- **Repositories**: ≥ 80%
- **Widgets**: ≥ 60%
