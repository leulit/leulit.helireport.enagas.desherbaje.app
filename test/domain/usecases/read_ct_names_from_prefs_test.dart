import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:helireport_desherbaje/domain/usecases/get_segmentos_usecase.dart';

// Migrado desde `read_ct_ids_from_prefs_test.dart`: el filtro local de lectura
// de segmentos pasa de ctids (`user_cts`) a NOMBRES de CT (`user_json`), porque
// el segmento identifica su CT por nombre (contrato §3/§8).

String _userJson(List<Map<String, dynamic>> cts) => jsonEncode({
      'id': 7,
      'usuario': 'op',
      'cts': cts,
    });

void main() {
  group('readCtNamesFromPrefs', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('returns empty list when user_json is absent', () async {
      final prefs = await SharedPreferences.getInstance();
      expect(readCtNamesFromPrefs(prefs), isEmpty);
    });

    test('returns empty list for empty string', () async {
      SharedPreferences.setMockInitialValues({'user_json': ''});
      final prefs = await SharedPreferences.getInstance();
      expect(readCtNamesFromPrefs(prefs), isEmpty);
    });

    test('returns empty list for malformed JSON', () async {
      SharedPreferences.setMockInitialValues({'user_json': 'not_json'});
      final prefs = await SharedPreferences.getInstance();
      expect(readCtNamesFromPrefs(prefs), isEmpty);
    });

    test('reads CT names from the persisted user (§8)', () async {
      SharedPreferences.setMockInitialValues({
        'user_json': _userJson([
          {'ct_id': 12, 'ct': 'CT-BURGOS'},
          {'ct_id': 15, 'ct': 'CT-PLASENCIA'},
        ]),
      });
      final prefs = await SharedPreferences.getInstance();
      expect(
        readCtNamesFromPrefs(prefs),
        equals(['CT-BURGOS', 'CT-PLASENCIA']),
      );
    });

    test('drops empty CT names', () async {
      SharedPreferences.setMockInitialValues({
        'user_json': _userJson([
          {'ct_id': 12, 'ct': 'CT-BURGOS'},
          {'ct_id': 0, 'ct': ''},
        ]),
      });
      final prefs = await SharedPreferences.getInstance();
      expect(readCtNamesFromPrefs(prefs), equals(['CT-BURGOS']));
    });

    test('returns empty list when the user has no CTs', () async {
      SharedPreferences.setMockInitialValues({'user_json': _userJson([])});
      final prefs = await SharedPreferences.getInstance();
      expect(readCtNamesFromPrefs(prefs), isEmpty);
    });
  });
}
