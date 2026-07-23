import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:helireport_desherbaje/presentation/auth/reset_password_page.dart';

// Testea SOLO la validación de formulario, que corre en cliente antes de tocar
// la red. Un submit válido llamaría a AuthRepositoryImpl → NetworkService (no
// registrado en test), así que esos tests quedarían acoplados a la red; se
// cubren con los tests del provider/backend.
void main() {
  tearDown(Get.reset);

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      const GetMaterialApp(home: ResetPasswordPage(email: 'a@b.com')),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('muestra el email en la descripción', (tester) async {
    await pumpPage(tester);
    expect(find.textContaining('a@b.com'), findsOneWidget);
  });

  testWidgets('submit vacío marca código y contraseña inválidos',
      (tester) async {
    await pumpPage(tester);

    await tester.tap(find.text('Cambiar contraseña'));
    await tester.pumpAndSettle();

    expect(find.text('El código tiene 6 dígitos'), findsOneWidget);
    expect(find.text('Mínimo 6 caracteres'), findsOneWidget);
  });

  testWidgets('contraseñas distintas → "no coinciden"', (tester) async {
    await pumpPage(tester);

    await tester.enterText(find.byType(TextFormField).at(0), '123456');
    await tester.enterText(find.byType(TextFormField).at(1), 'abcdef');
    await tester.enterText(find.byType(TextFormField).at(2), 'ZZZZZZ');
    await tester.tap(find.text('Cambiar contraseña'));
    await tester.pumpAndSettle();

    expect(find.text('Las contraseñas no coinciden'), findsOneWidget);
  });

  testWidgets('el campo código solo acepta dígitos', (tester) async {
    await pumpPage(tester);

    await tester.enterText(find.byType(TextFormField).at(0), 'ab12cd34');
    await tester.pump();

    final field = tester.widget<TextField>(
      find.descendant(
        of: find.byType(TextFormField).at(0),
        matching: find.byType(TextField),
      ),
    );
    expect(field.controller?.text, '1234');
  });
}
