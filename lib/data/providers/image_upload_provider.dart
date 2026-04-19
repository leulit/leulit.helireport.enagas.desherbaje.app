import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api_endpoints.dart';
import '../../data/network/network_file.dart';
import '../../data/network/network_service.dart';
import '../../domain/entities/imagen_segmento_entity.dart';

class ImageUploadProvider {
  final NetworkService _network = Get.find<NetworkService>();
  final _storage = const FlutterSecureStorage();

  Future<String?> uploadImage(ImagenSegmentoEntity imagen) async {
    final path = ApiEndpoints.imagenAdd;
    final token = await _storage.read(key: 'auth_token');
    final prefs = await SharedPreferences.getInstance();
    final usuario = prefs.getString('user_usuario') ?? '';
    final userId = prefs.getInt('user_id')?.toString() ?? '0';

    final file = File(imagen.ruta);
    final fileName = file.path.split('/').last;

    final bytes = await file.openRead().first;
    final mimeType = _detectMime(bytes);

    final fields = <String, dynamic>{
      'fileNameOriginal': fileName,
      'description': imagen.tipoFoto == TipoFoto.antes
          ? 'Antes del trabajo'
          : 'Después del trabajo',
      'tipo': 'imagen',
      'tipovigilancia': 'VH',
      'usuariologged': usuario,
      'idusuariologged': userId,
      'clientId': imagen.clientId,
      'actividadId': imagen.actividadId.toString(),
      'segmentoId': imagen.segmentoId.toString(),
      'tipoFoto': imagen.tipoFoto.name,
    };

    final files = <NetworkFile>[
      NetworkFile(
        fieldName: 'file',
        filePath: imagen.ruta,
        filename: fileName,
        contentType: mimeType,
      ),
    ];

    final headers = <String, String>{
      if (token != null) 'Authorization': 'Bearer $token',
    };

    final response = await _network.postMultipart(
      path,
      fields: fields,
      files: files,
      headers: headers,
    );
    final data = response.data as Map<String, dynamic>;
    return data['url'] as String? ?? data['remote_url'] as String?;
  }

  String _detectMime(List<int> bytes) {
    if (bytes.length >= 4) {
      if (bytes[0] == 0xFF && bytes[1] == 0xD8) return 'image/jpeg';
      if (bytes[0] == 0x89 && bytes[1] == 0x50) return 'image/png';
    }
    return 'image/jpeg';
  }
}
