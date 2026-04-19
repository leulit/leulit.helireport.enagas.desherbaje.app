import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import '../../core/result/data_result.dart';
import '../entities/segmento_entity.dart';
import '../repository/segmento_repository.dart';

class GetSegmentosUseCase {
  final SegmentoRepository _repo;

  GetSegmentosUseCase(this._repo);

  Future<DataResult<List<SegmentoEntity>>> execute() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('user_id') ?? 0;
    final cts = readCtIdsFromPrefs(prefs);
    return _repo.getByOperador(userId, cts);
  }
}

/// Lee `user_cts` aceptando tanto el formato actual (JSON `"[12,15,23]"`)
/// como el legacy (`List<String>` de ids stringificados). El próximo login
/// lo reescribirá en formato JSON.
List<int> readCtIdsFromPrefs(SharedPreferences prefs) {
  final raw = prefs.get('user_cts');
  if (raw == null) return const <int>[];

  if (raw is String) {
    if (raw.isEmpty) return const <int>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.whereType<num>().map((n) => n.toInt()).toList();
      }
    } catch (_) {}
    return const <int>[];
  }

  if (raw is List) {
    final ids = <int>[];
    for (final item in raw) {
      if (item is int) {
        ids.add(item);
      } else if (item is num) {
        ids.add(item.toInt());
      } else if (item is String) {
        final parsed = int.tryParse(item);
        if (parsed != null) ids.add(parsed);
      }
    }
    return ids;
  }

  return const <int>[];
}
