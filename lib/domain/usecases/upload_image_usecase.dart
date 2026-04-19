import '../../data/repository/imagen_repository_impl.dart';

class UploadImageUseCase {
  final ImagenRepositoryImpl _repo;
  UploadImageUseCase(this._repo);

  Future<void> uploadPending(int actividadId) =>
      _repo.uploadPending(actividadId);
}
