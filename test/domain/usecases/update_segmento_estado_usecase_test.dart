import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:get/get.dart';

import 'package:helireport_desherbaje/core/result/data_result.dart';
import 'package:helireport_desherbaje/domain/entities/segmento_entity.dart';
import 'package:helireport_desherbaje/domain/repository/segmento_repository.dart';
import 'package:helireport_desherbaje/domain/usecases/update_segmento_estado_usecase.dart';

class MockSegmentoRepository extends Mock implements SegmentoRepository {}

void main() {
  late UpdateSegmentoEstadoUseCase useCase;
  late MockSegmentoRepository mockRepo;

  setUpAll(() {
    registerFallbackValue(EstadoActividad.propuesta);
  });

  setUp(() {
    Get.reset();
    mockRepo = MockSegmentoRepository();
    useCase = UpdateSegmentoEstadoUseCase(mockRepo);
  });

  tearDown(Get.reset);

  group('UpdateSegmentoEstadoUseCase', () {
    test('delegates to repository and returns success', () async {
      when(() => mockRepo.updateEstado(1, EstadoActividad.ejecucion))
          .thenAnswer((_) async => DataResult.success(true));

      final result = await useCase.execute(1, EstadoActividad.ejecucion);

      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull, isTrue);
      verify(() => mockRepo.updateEstado(1, EstadoActividad.ejecucion)).called(1);
    });

    test('propagates repository failure', () async {
      when(() => mockRepo.updateEstado(any(), any()))
          .thenAnswer((_) async => DataResult.failure(message: 'DB error'));

      final result = await useCase.execute(99, EstadoActividad.finalizada);

      expect(result.isSuccess, isFalse);
      expect((result as DataFailure).message, equals('DB error'));
    });

    test('calls repository with correct id and estado', () async {
      when(() => mockRepo.updateEstado(42, EstadoActividad.cerrada))
          .thenAnswer((_) async => DataResult.success(true));

      await useCase.execute(42, EstadoActividad.cerrada);

      verify(() => mockRepo.updateEstado(42, EstadoActividad.cerrada)).called(1);
      verifyNever(() => mockRepo.updateEstado(any(), EstadoActividad.propuesta));
    });
  });
}
