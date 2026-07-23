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

  testWidgets('devuelve el email recortado', (tester) async {
    await pumpHost(tester);

    final future = showForgotPasswordDialog();
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), '  a@b.com ');
    await tester.tap(find.text('Enviar'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(await future, 'a@b.com');
  });

  testWidgets('email vacío no cierra el diálogo', (tester) async {
    await pumpHost(tester);

    showForgotPasswordDialog();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Enviar'));
    await tester.pumpAndSettle();

    expect(find.text('Introduce tu email'), findsOneWidget);
  });

  testWidgets('cancelar devuelve null', (tester) async {
    await pumpHost(tester);

    final future = showForgotPasswordDialog();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(await future, isNull);
  });
}
