import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:leulit_pipeline_pattern/leulit_pipeline_pattern.dart';

import '../../core/app_typed_actions.dart';
import '../../core/services/connectivity_service.dart';
import '../model/file_data.dart';
import '../network/network_service.dart';

/// Resultado de descargar un único fichero JSON dentro del pipeline.
class FileLoadGeoJsonResult {
  /// Datos originales del fichero solicitado (group, filename, tag…).
  final FileData originalFileData;

  /// Payload JSON ya parseado a `Map<String, dynamic>`. Vacío si la descarga
  /// falló y el pipeline siguió en modo no bloqueante.
  final Map<String, dynamic> processedData;

  FileLoadGeoJsonResult({
    required this.originalFileData,
    required this.processedData,
  });

  factory FileLoadGeoJsonResult.empty() => FileLoadGeoJsonResult(
        originalFileData: const FileData(group: '', filename: ''),
        processedData: const {},
      );
}

/// Servicio genérico de descarga de ficheros JSON (típicamente GeoJSON).
///
/// Usa `TaskPipeline` para encadenar las descargas y emite eventos vía
/// `AppTypedActions`:
///
/// - `geoJsonLoadStarted`   → al iniciar (data = nº total de ficheros).
/// - `geoJsonLoaded`        → por cada fichero descargado correctamente
///   (data = `FileLoadGeoJsonResult`).
/// - `geoJsonLoadError`     → cuando un fichero falla (data = payload vacío).
/// - `geoJsonLoadCompleted` → al terminar (con éxito o error).
///
/// Cualquier consumidor (p. ej. `GasoductosService`) escucha el evento que
/// le interesa filtrando por `result.originalFileData.group`.
class JsonLoaderService extends GetxService {
  bool _isLoading = false;
  int _currentTotalFiles = 0;
  int _currentProcessedFiles = 0;

  /// Cola interna: si dos consumidores invocan `loadFiles` en paralelo, el
  /// segundo espera a que termine el primero. Evita que los eventos
  /// (broadcast globales) se mezclen entre dos pipelines simultáneos.
  Future<void>? _activeRun;

  bool get isLoading => _isLoading;
  int get totalFiles => _currentTotalFiles;
  int get processedFiles => _currentProcessedFiles;

  NetworkService get _network => Get.find<NetworkService>();
  ConnectivityService get _conn => Get.find<ConnectivityService>();

  /// Descarga la lista [files] secuencialmente. Si no hay conexión, dispara
  /// directamente `geoJsonLoadCompleted` y deja que el consumidor caiga al
  /// modo offline (caché local).
  Future<void> loadFiles(List<FileData> files) async {
    while (_activeRun != null) {
      await _activeRun;
    }
    final run = _runFiles(files);
    _activeRun = run;
    try {
      await run;
    } finally {
      _activeRun = null;
    }
  }

  Future<void> _runFiles(List<FileData> files) async {
    if (files.isEmpty) return;

    _isLoading = true;
    _currentTotalFiles = files.length;
    _currentProcessedFiles = 0;

    if (!_conn.isConnected) {
      _isLoading = false;
      AppTypedActions.geoJsonLoadCompleted.dispatch();
      return;
    }

    final pipeline = TaskPipeline<FileLoadGeoJsonResult>(broadcast: true);
    for (final file in files) {
      pipeline.addTask(_FileDownloadTask(file, _network));
    }

    pipeline.events.listen((event) {
      switch (event.type) {
        case PipelineEventType.pipelineStart:
          AppTypedActions.geoJsonLoadStarted.dispatch(data: files.length);
          break;
        case PipelineEventType.taskSuccess:
          if (event.data != null) {
            _currentProcessedFiles++;
            AppTypedActions.geoJsonLoaded.dispatch(data: event.data!);
          }
          break;
        case PipelineEventType.error:
          if (event.data != null) {
            AppTypedActions.geoJsonLoadError
                .dispatch(data: event.data!.processedData);
          }
          break;
        case PipelineEventType.pipelineEnd:
          AppTypedActions.geoJsonLoadCompleted.dispatch();
          break;
        case PipelineEventType.taskStart:
          break;
      }
    });

    final result =
        await pipeline.run(DataPipeline.of(FileLoadGeoJsonResult.empty()));

    result.fold(
      onSuccess: (_) => AppTypedActions.geoJsonLoadCompleted.dispatch(),
      onFailure: (_, __) => AppTypedActions.geoJsonLoadCompleted.dispatch(),
    );

    pipeline.dispose();
    _isLoading = false;
  }
}

/// Descarga un único [FileData] y emite su payload como
/// [FileLoadGeoJsonResult]. No bloquea el pipeline si falla — el siguiente
/// fichero se sigue intentando.
class _FileDownloadTask extends PipelineTask<FileLoadGeoJsonResult> {
  final FileData _fileData;
  final NetworkService _network;

  _FileDownloadTask(this._fileData, this._network);

  @override
  String get name => 'DownloadFile(${_fileData.group})';

  @override
  bool get isBlocking => false;

  @override
  Future<DataPipeline<FileLoadGeoJsonResult>> execute(
    DataPipeline<FileLoadGeoJsonResult> inputdata,
  ) async {
    try {
      final response = await _network.get(_fileData.filename);
      final raw = response.data;
      Map<String, dynamic> rawJson;
      if (raw is Map<String, dynamic>) {
        rawJson = raw;
      } else if (raw is Map) {
        rawJson = raw.cast<String, dynamic>();
      } else {
        throw FormatException(
          'Respuesta inesperada (${raw.runtimeType}) para ${_fileData.filename}',
        );
      }
      return DataPipeline.success(
        input: inputdata.input,
        output: FileLoadGeoJsonResult(
          originalFileData: _fileData,
          processedData: rawJson,
        ),
      );
    } catch (e, st) {
      debugPrint('❌ Error descargando ${_fileData.filename}: $e');
      return DataPipeline.error(
        input: inputdata.input,
        error: e,
        output: FileLoadGeoJsonResult(
          originalFileData: _fileData,
          processedData: const {},
        ),
        stackTrace: st,
      );
    }
  }
}
