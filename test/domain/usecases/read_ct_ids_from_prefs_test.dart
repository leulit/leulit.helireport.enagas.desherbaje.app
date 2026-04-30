import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:helireport_desherbaje/domain/usecases/get_segmentos_usecase.dart';

void main() {
  group('readCtIdsFromPrefs', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('returns empty list when key is absent', () async {
      final prefs = await SharedPreferences.getInstance();
      expect(readCtIdsFromPrefs(prefs), isEmpty);
    });

    test('returns empty list when key is absent (no prefs set)', () async {
      // key is simply not present → prefs.get returns null
      final prefs = await SharedPreferences.getInstance();
      expect(readCtIdsFromPrefs(prefs), isEmpty);
    });

    test('parses current JSON string format', () async {
      SharedPreferences.setMockInitialValues({'user_cts': '[12, 15, 23]'});
      final prefs = await SharedPreferences.getInstance();
      expect(readCtIdsFromPrefs(prefs), equals([12, 15, 23]));
    });

    test('returns empty list for empty JSON string', () async {
      SharedPreferences.setMockInitialValues({'user_cts': ''});
      final prefs = await SharedPreferences.getInstance();
      expect(readCtIdsFromPrefs(prefs), isEmpty);
    });

    test('returns empty list for malformed JSON string', () async {
      SharedPreferences.setMockInitialValues({'user_cts': 'not_json'});
      final prefs = await SharedPreferences.getInstance();
      expect(readCtIdsFromPrefs(prefs), isEmpty);
    });

    test('returns empty list when JSON string is not a List', () async {
      SharedPreferences.setMockInitialValues({'user_cts': '{"key": 1}'});
      final prefs = await SharedPreferences.getInstance();
      expect(readCtIdsFromPrefs(prefs), isEmpty);
    });

    test('parses legacy List<int> format', () async {
      SharedPreferences.setMockInitialValues({'user_cts': [12, 15, 23]});
      final prefs = await SharedPreferences.getInstance();
      expect(readCtIdsFromPrefs(prefs), equals([12, 15, 23]));
    });

    test('parses legacy List<String> format', () async {
      SharedPreferences.setMockInitialValues({'user_cts': ['12', '15', '23']});
      final prefs = await SharedPreferences.getInstance();
      expect(readCtIdsFromPrefs(prefs), equals([12, 15, 23]));
    });

    test('skips non-parseable strings in legacy List', () async {
      SharedPreferences.setMockInitialValues({'user_cts': ['12', 'abc', '23']});
      final prefs = await SharedPreferences.getInstance();
      expect(readCtIdsFromPrefs(prefs), equals([12, 23]));
    });

    test('handles double values in JSON string', () async {
      SharedPreferences.setMockInitialValues({'user_cts': '[12.0, 15.5, 23.9]'});
      final prefs = await SharedPreferences.getInstance();
      expect(readCtIdsFromPrefs(prefs), equals([12, 15, 23]));
    });

    test('handles empty JSON array', () async {
      SharedPreferences.setMockInitialValues({'user_cts': '[]'});
      final prefs = await SharedPreferences.getInstance();
      expect(readCtIdsFromPrefs(prefs), isEmpty);
    });
  });
}
