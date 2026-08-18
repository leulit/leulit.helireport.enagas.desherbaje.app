import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:helireport_desherbaje/core/screen_controller.dart';

class _ListaController extends GetxController {
  bool closed = false;

  @override
  void onClose() {
    closed = true;
    super.onClose();
  }
}

/// Reproduce el flujo real: lista → detalle → `Get.offAllNamed` de vuelta a la
/// lista. La ruta vieja de la lista se destruye DESPUÉS de que el binding de la
/// nueva haya creado el controller, y el borrado por tipo de GetX se lleva por
/// delante el controller vivo si no se arma `lateRemove`.
Future<_ListaController> _navegarListaDetalleLista(
  WidgetTester tester, {
  required bool armado,
}) async {
  await tester.pumpWidget(GetMaterialApp(
    initialRoute: '/lista',
    getPages: [
      GetPage(
        name: '/lista',
        binding: BindingsBuilder(() {
          if (armado) {
            putScreenController<_ListaController>(() => _ListaController());
          } else {
            Get.lazyPut<_ListaController>(() => _ListaController());
          }
        }),
        page: () => GetBuilder<_ListaController>(
          init: Get.find<_ListaController>(),
          builder: (_) => TextButton(
            onPressed: () => Get.toNamed('/detalle'),
            child: const Text('ir a detalle'),
          ),
        ),
      ),
      GetPage(
        name: '/detalle',
        page: () => TextButton(
          onPressed: () => Get.offAllNamed('/lista'),
          child: const Text('volver a lista'),
        ),
      ),
    ],
  ));
  await tester.pumpAndSettle();

  await tester.tap(find.text('ir a detalle'));
  await tester.pumpAndSettle();

  await tester.tap(find.text('volver a lista'));
  await tester.pumpAndSettle();

  return Get.find<_ListaController>();
}

class _DetalleController extends GetxController {
  late final Object? arg = Get.arguments;
}

void main() {
  tearDown(Get.reset);

  testWidgets('putScreenController conserva vivo el controller de la pantalla '
      'que queda en pantalla tras Get.offAllNamed', (tester) async {
    final vivo = await _navegarListaDetalleLista(tester, armado: true);
    expect(vivo.closed, isFalse);
  });

  testWidgets('Get.lazyPut a secas cierra el controller de la pantalla visible '
      '(bug de get 4.7.3 que motiva el helper)', (tester) async {
    final zombi = await _navegarListaDetalleLista(tester, armado: false);
    expect(zombi.closed, isTrue);
  });

  testWidgets('cada entrada a una pantalla crea un controller nuevo, que lee '
      'sus propios Get.arguments', (tester) async {
    await tester.pumpWidget(GetMaterialApp(
      initialRoute: '/lista',
      getPages: [
        GetPage(
          name: '/lista',
          page: () => TextButton(
            onPressed: () => Get.toNamed('/detalle', arguments: 'B'),
            child: const Text('ir a detalle'),
          ),
        ),
        GetPage(
          name: '/detalle',
          binding: BindingsBuilder(() {
            putScreenController<_DetalleController>(() => _DetalleController());
          }),
          page: () => TextButton(
            onPressed: () => Get.offAllNamed('/lista'),
            child: Text(Get.find<_DetalleController>().arg.toString()),
          ),
        ),
      ],
    ));
    await tester.pumpAndSettle();

    Get.toNamed('/detalle', arguments: 'A');
    await tester.pumpAndSettle();
    expect(find.text('A'), findsOneWidget);

    await tester.tap(find.text('A'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ir a detalle'));
    await tester.pumpAndSettle();

    expect(find.text('B'), findsOneWidget);
    expect(Get.find<_DetalleController>().arg, 'B');
  });
}
