import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:helireport_desherbaje/domain/entities/segmento_entity.dart';
import 'package:helireport_desherbaje/presentation/mapa/lines_cut/lines_cut_dialog.dart';

void main() {
  tearDown(Get.reset);

  Future<void> pumpHost(WidgetTester tester) async {
    await tester.pumpWidget(
      GetMaterialApp(home: const Scaffold(body: SizedBox.shrink())),
    );
    await tester.pumpAndSettle();
  }

  Future<CutDialogResult?> openDialog() => showLinesCutCaptureDialog(
        headerTitle: 'Corte aplicado',
        headerSubtitle: '3 segmentos',
        totalMeters: 1250,
        totalSquareMeters: 6250,
      );

  testWidgets('applying the dialog does not use a disposed controller',
      (tester) async {
    await pumpHost(tester);

    final future = openDialog();
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '  Desbroce zona A  ');
    await tester.tap(find.text('Aplicar'));
    // Exit transition: the TextField still rebuilds here. Disposing the
    // controller when the future resolves throws during these frames.
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final result = await future;
    expect(result, isNotNull);
    expect(result!.descripcion, 'Desbroce zona A');
    expect(result.tipoActividad, TipoActividad.posicionDesherbajeTraza);
    expect(result.estado, EstadoActividad.contratista);
  });

  testWidgets('cancelling resolves to null without exceptions', (tester) async {
    await pumpHost(tester);

    final future = openDialog();
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'texto descartado');
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(await future, isNull);
  });
}
