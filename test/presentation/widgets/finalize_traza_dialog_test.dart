import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:helireport_desherbaje/presentation/widgets/finalize_traza_dialog.dart';

void main() {
  tearDown(Get.reset);

  Future<void> pumpHost(WidgetTester tester) async {
    await tester.pumpWidget(
      GetMaterialApp(home: const Scaffold(body: SizedBox.shrink())),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('accepting the dialog does not use a disposed controller',
      (tester) async {
    await pumpHost(tester);

    final future = showFinalizeTrazaDialog(initialName: 'Traza X');
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Mi traza');
    await tester.tap(find.text('Aceptar'));
    // Exit transition: the TextField still rebuilds here. Disposing the
    // controller when the future resolves throws during these frames.
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(await future, 'Mi traza');
  });

  testWidgets('empty input keeps initialName', (tester) async {
    await pumpHost(tester);

    final future = showFinalizeTrazaDialog(initialName: 'Traza X');
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.text('Aceptar'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(await future, 'Traza X');
  });
}
