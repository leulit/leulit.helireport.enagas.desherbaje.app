import '../../core/sync/contracts/conflict_resolver.dart';
import '../../domain/entities/segmento_entity.dart';

/// Resolves segmento pull conflicts by field ownership, not by "one side
/// wins wholesale": the operator's offline edits (estado, descripción,
/// geometría, fechas…) always win, but the cloud snapshot of `imagenes`/
/// `mensajes` always wins — those are append-mostly collections where the
/// backend has visibility the device may not (media/messages from other
/// devices), and overwriting them with the stale local snapshot would hide
/// content instead of merging it.
///
/// [SegmentoEntity.copyWith] only overrides the two named parameters passed
/// here (`x ?? this.x` per field) and never touches `_updatedAt` — the local
/// edit's timestamp is preserved, which is correct: the edit still hasn't
/// been pushed, so its "last changed" moment has not changed.
class SegmentoConflictResolver implements ConflictResolver<SegmentoEntity> {
  const SegmentoConflictResolver();

  @override
  SegmentoEntity resolve({
    required SegmentoEntity local,
    required SegmentoEntity remote,
  }) =>
      local.copyWith(imagenes: remote.imagenes, mensajes: remote.mensajes);
}
