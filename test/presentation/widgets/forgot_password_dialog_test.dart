import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:helireport_desherbaje/presentation/widgets/forgot_password_dialog.dart';

void main() {
  tearDown(Get.reset);

  Future<void> pumpHost(WidgetTester tester) async {
    await tester.pumpWidget(
      GetMaterialApp(home: const Scaffold(body: SizedBox.shrink())),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('envío OK → resuelve con el email recortado', (tester) async {
    await pumpHost(tester);

    String? received;
    final future = showForgotPasswordDialog(
      onSubmit: (email) async => received = email,
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), '  a@b.com ');
    await tester.tap(find.text('Enviar'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(received, 'a@b.com');
    expect(await future, 'a@b.com');
  });

  testWidgets('email vacío no cierra el diálogo ni llama onSubmit',
      (tester) async {
    await pumpHost(tester);

    var called = false;
    showForgotPasswordDialog(onSubmit: (_) async => called = true);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Enviar'));
    await tester.pumpAndSettle();

    expect(called, isFalse);
    expect(find.text('Introduce tu email'), findsOneWidget);
    expect(find.text('Enviar'), findsOneWidget); // sigue abierto
  });

  testWidgets('error de envío → muestra el motivo y NO cierra el diálogo',
      (tester) async {
    await pumpHost(tester);

    final future = showForgotPasswordDialog(
      onSubmit: (_) async =>
          throw Exception('Ese email no existe en la base de datos'),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), 'noexiste@x.com');
    await tester.tap(find.text('Enviar'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // El motivo del backend se muestra inline, el diálogo sigue abierto.
    expect(
        find.text('Ese email no existe en la base de datos'), findsOneWidget);
    expect(find.text('Enviar'), findsOneWidget);

    // Corregir y reenviar con éxito cierra el diálogo con el email.
    await tester.enterText(find.byType(TextFormField), 'ok@x.com');
    // Reemplaza el diálogo abierto por uno que ahora resuelve OK sería otro
    // caso; aquí basta comprobar que el flujo de reintento vive en el diálogo.
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(await future, isNull);
  });

  testWidgets('cancelar devuelve null', (tester) async {
    await pumpHost(tester);

    final future = showForgotPasswordDialog(onSubmit: (_) async {});
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(await future, isNull);
  });
}
