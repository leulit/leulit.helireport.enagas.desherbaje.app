import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:video_player/video_player.dart';

import '../../core/app_theme.dart';

/// Reproductor a pantalla completa de un vídeo. Se abre vía `Get.to` desde el
/// carrusel de fotos/vídeos. Reproduce un fichero del disco (capturas locales,
/// [VideoPlayerPage] con [path]) o una url remota (vídeos ya en la nube,
/// [VideoPlayerPage.network] con [url]).
class VideoPlayerPage extends StatefulWidget {
  final String? path;

  /// URL de reproducción **ya firmada** por
  /// `ApiSecurityService.buildSignedMediaUrl`: la media nunca se sirve sin
  /// credencial. Va firmada en la query, no en cabeceras, porque el
  /// reproductor la fija una vez y la reusa en cada seek.
  final String? url;
  const VideoPlayerPage({super.key, required this.path}) : url = null;
  const VideoPlayerPage.network(this.url, {super.key}) : path = null;

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  late final VideoPlayerController _controller;
  bool _initialized = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final url = widget.url;
    _controller = url != null
        ? VideoPlayerController.networkUrl(Uri.parse(url))
        : VideoPlayerController.file(File(widget.path!));
    _controller.initialize().then((_) {
      if (!mounted) return;
      setState(() => _initialized = true);
      _controller
        ..setLooping(false)
        ..play();
    }).catchError((Object e) {
      if (mounted) {
        setState(() => _error = 'No se pudo reproducir el vídeo: $e');
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _togglePlay() {
    setState(() {
      if (_controller.value.isPlaying) {
        _controller.pause();
      } else {
        _controller.play();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(icon: const Icon(Icons.close), onPressed: Get.back),
      ),
      body: Center(child: _buildBody()),
      floatingActionButton: _initialized
          ? FloatingActionButton(
              backgroundColor: AppColors.moduleGreen,
              onPressed: _togglePlay,
              child: Icon(
                _controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
              ),
            )
          : null,
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          _error!,
          style: const TextStyle(color: Colors.white),
          textAlign: TextAlign.center,
        ),
      );
    }
    if (!_initialized) {
      return const CircularProgressIndicator(color: AppColors.moduleGreen);
    }
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AspectRatio(
          aspectRatio: _controller.value.aspectRatio == 0
              ? 16 / 9
              : _controller.value.aspectRatio,
          child: GestureDetector(
            onTap: _togglePlay,
            child: VideoPlayer(_controller),
          ),
        ),
        VideoProgressIndicator(
          _controller,
          allowScrubbing: true,
          colors: const VideoProgressColors(playedColor: AppColors.moduleGreen),
        ),
      ],
    );
  }
}
