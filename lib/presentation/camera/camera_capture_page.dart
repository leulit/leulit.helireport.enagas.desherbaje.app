import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/app_theme.dart';

/// Modo de captura de la pantalla de cámara.
enum _CaptureMode { photo, video }

/// Pantalla de captura con cámara nativa (paquete `camera`) y selector
/// Foto | Vídeo. Devuelve un registro `({String path, bool isVideo})` vía
/// `Get.back`; `null` si el usuario cancela.
class CameraCapturePage extends StatefulWidget {
  const CameraCapturePage({super.key});

  @override
  State<CameraCapturePage> createState() => _CameraCapturePageState();
}

class _CameraCapturePageState extends State<CameraCapturePage>
    with WidgetsBindingObserver {
  CameraController? _controller;
  String? _error;
  bool _isCapturing = false;
  bool _isRecording = false;
  _CaptureMode _mode = _CaptureMode.photo;

  /// Corte de grabación a 3 min, igual que la grabadora nativa previa.
  Timer? _maxDurationTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _maxDurationTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      c.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _error = 'No hay cámaras disponibles en el dispositivo.');
        return;
      }
      // Preferimos la trasera; si no, la primera disponible.
      final cam = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        cam,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Error inicializando cámara: $e');
    }
  }

  /// Cambia el modo foto/vídeo. El vídeo se graba sin audio (`enableAudio:
  /// false`), así que no hace falta recrear el controlador al cambiar de modo.
  void _setMode(_CaptureMode mode) {
    if (_mode == mode || _isRecording) return;
    setState(() => _mode = mode);
  }

  Future<void> _onShutter() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (_mode == _CaptureMode.photo) {
      await _takePhoto(c);
    } else if (_isRecording) {
      await _stopVideo(c);
    } else {
      await _startVideo(c);
    }
  }

  Future<void> _takePhoto(CameraController c) async {
    if (_isCapturing) return;
    setState(() => _isCapturing = true);
    try {
      final file = await c.takePicture();
      if (mounted) Get.back<Object?>(result: (path: file.path, isVideo: false));
    } catch (e) {
      if (mounted) {
        Get.snackbar('Error', 'No se pudo capturar la foto: $e');
        setState(() => _isCapturing = false);
      }
    }
  }

  Future<void> _startVideo(CameraController c) async {
    try {
      await c.startVideoRecording();
      if (!mounted) return;
      setState(() => _isRecording = true);
      _maxDurationTimer =
          Timer(const Duration(minutes: 3), () => _stopVideo(c));
    } catch (e) {
      if (mounted) Get.snackbar('Error', 'No se pudo iniciar la grabación: $e');
    }
  }

  Future<void> _stopVideo(CameraController c) async {
    if (!_isRecording) return;
    _isRecording = false; // guard inmediato: el timer y el tap no re-entran
    _maxDurationTimer?.cancel();
    _maxDurationTimer = null;
    try {
      final file = await c.stopVideoRecording();
      if (mounted) Get.back<Object?>(result: (path: file.path, isVideo: true));
    } catch (e) {
      if (mounted) {
        Get.snackbar('Error', 'No se pudo detener la grabación: $e');
        setState(() {});
      }
    }
  }

  Future<void> _onClose() async {
    if (_isRecording) {
      _maxDurationTimer?.cancel();
      _maxDurationTimer = null;
      _isRecording = false;
      try {
        await _controller?.stopVideoRecording();
      } catch (_) {}
    }
    Get.back<Object?>(result: null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(child: _buildPreview()),
          // Cerrar
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 8,
            child: _CircleIconButton(icon: Icons.close, onTap: _onClose),
          ),
          // Indicador de grabación
          if (_isRecording)
            Positioned(
              top: MediaQuery.of(context).padding.top + 12,
              left: 0,
              right: 0,
              child: const Center(child: _RecBadge()),
            ),
          // Disparador + selector de modo
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 16,
            left: 0,
            right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: _ShutterButton(
                    mode: _mode,
                    isRecording: _isRecording,
                    isLoading: _isCapturing,
                    onTap: _onShutter,
                  ),
                ),
                const SizedBox(height: 16),
                _ModeSelector(
                  mode: _mode,
                  enabled: !_isRecording,
                  onSelect: _setMode,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.moduleGreen),
      );
    }
    return CameraPreview(c);
  }
}

class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}

class _RecBadge extends StatelessWidget {
  const _RecBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.fiber_manual_record, color: Colors.red, size: 12),
          SizedBox(width: 6),
          Text(
            'REC',
            style: TextStyle(
                color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _ModeSelector extends StatelessWidget {
  final _CaptureMode mode;
  final bool enabled;
  final ValueChanged<_CaptureMode> onSelect;
  const _ModeSelector({
    required this.mode,
    required this.enabled,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _tab('FOTO', _CaptureMode.photo),
          const SizedBox(width: 8),
          _tab('VÍDEO', _CaptureMode.video),
        ],
      ),
    );
  }

  Widget _tab(String label, _CaptureMode m) {
    final active = mode == m;
    return GestureDetector(
      onTap: enabled ? () => onSelect(m) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: active ? AppColors.moduleGreen : Colors.black45,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: active ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

class _ShutterButton extends StatelessWidget {
  final _CaptureMode mode;
  final bool isRecording;
  final bool isLoading;
  final VoidCallback onTap;
  const _ShutterButton({
    required this.mode,
    required this.isRecording,
    required this.isLoading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: Container(
        width: 78,
        height: 78,
        decoration: BoxDecoration(
          color: Colors.white24,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 4),
        ),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: isLoading
              ? const CircularProgressIndicator(
                  strokeWidth: 3, color: Colors.white)
              : _inner(),
        ),
      ),
    );
  }

  Widget _inner() {
    if (mode == _CaptureMode.photo) {
      return const DecoratedBox(
        decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle),
      );
    }
    if (!isRecording) {
      return const DecoratedBox(
        decoration: BoxDecoration(color: Colors.red, shape: BoxShape.circle),
      );
    }
    return Center(
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(6),
        ),
      ),
    );
  }
}
