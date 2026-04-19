import 'dart:async';

import 'package:get/get.dart';
import 'package:leulit_flutter_actionmanager/leulit_flutter_actionmanager.dart';

/// Base de los `GetxController` del proyecto. Centraliza el ciclo de vida de:
///
/// - **Worker** (`ever`, `debounce`, `interval`, `once`): registrados con
///   [addWorker], dispuestos en [onClose].
/// - **TypedAction handlers**: registrados con [onTypedAction] u
///   [onTypedActionWithResult]; desconectados en [onClose].
///
/// Las clases hijas implementan [myOnInit] en lugar de sobrescribir [onInit] —
/// así nunca se olvida llamar a `super.onInit()`.
abstract class MyGetxController extends GetxController {
  final List<_TypedActionHandler> _actionHandlers = [];
  final List<Worker> _workers = [];

  /// Punto de entrada para inicialización del controller. Sustituye al
  /// [onInit] tradicional para evitar el típico "olvidé llamar a
  /// `super.onInit()`".
  void myOnInit();

  @override
  void onInit() {
    super.onInit();
    myOnInit();
  }

  @override
  void onClose() {
    for (final worker in _workers) {
      worker.dispose();
    }
    _workers.clear();

    for (final handler in _actionHandlers) {
      ActionManager.off(handler.action, handler.handlerId);
    }
    _actionHandlers.clear();

    super.onClose();
  }

  // ──────────────────────────── Workers ────────────────────────────

  /// Registra un [Worker] (`ever`, `debounce`, `interval`, `once`) para que se
  /// libere automáticamente cuando el controller se destruya.
  void addWorker(Worker worker) {
    _workers.add(worker);
  }

  // ──────────────────────────── TypedAction ────────────────────────────

  /// Registra un handler tipado para una [TypedAction]. Cualquier mismatch
  /// entre el `dispatch` y el `handler` se detecta en compilación.
  String onTypedAction<T>(
    TypedAction<T> typedAction,
    ActionHandler<T> handler, {
    String? debugLabel,
  }) {
    final handlerId = typedAction.on(handler, debugLabel: debugLabel);
    _actionHandlers
        .add(_TypedActionHandler(action: typedAction, handlerId: handlerId));
    return handlerId;
  }

  /// Variante de [onTypedAction] cuyo handler devuelve un valor capturado en
  /// `ActionDispatchResult.results` al usar `dispatchAsync` o
  /// `dispatchPipeline`.
  String onTypedActionWithResult<T>(
    TypedAction<T> typedAction,
    FutureOr<Object?> Function(ActionEvent<T> event) handler, {
    String? debugLabel,
  }) {
    final handlerId = ActionManager.on<T>(
      typedAction,
      handler,
      debugLabel: debugLabel,
    );
    _actionHandlers
        .add(_TypedActionHandler(action: typedAction, handlerId: handlerId));
    return handlerId;
  }
}

/// Tracking interno de handlers de [TypedAction] para poder desconectarlos en
/// [MyGetxController.onClose].
class _TypedActionHandler {
  final Object action;
  final String handlerId;

  _TypedActionHandler({required this.action, required this.handlerId});
}
