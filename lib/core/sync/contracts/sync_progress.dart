/// Progreso de una subida larga DENTRO de un único job del outbox.
///
/// La mayoría de los jobs son una petición y no tienen nada que reportar: el
/// contador de "elemento N de M" del llamante ya los describe. Esto existe para
/// el caso contrario —el vídeo por chunks, minutos bajo un solo job— donde sin
/// bytes no hay forma de distinguir "subiendo" de "colgado".
class SyncProgress {
  /// Bytes confirmados por el servidor.
  final int sent;

  /// Bytes totales del elemento en curso.
  final int total;

  const SyncProgress({required this.sent, required this.total});

  /// 0.0–1.0, o `null` si el total no es utilizable (progreso indeterminado).
  double? get fraction {
    if (total <= 0) return null;
    return (sent / total).clamp(0.0, 1.0);
  }
}

/// Callback de progreso que el motor entrega al adaptador. Se invoca desde el
/// bucle del adaptador, así que debe ser barato: solo publicar estado.
typedef SyncProgressCallback = void Function(SyncProgress progress);
