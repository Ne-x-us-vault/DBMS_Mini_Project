import 'package:flutter_test/flutter_test.dart';

import 'package:split_chat/services/auth_repository.dart';

void main() {
  group('normalizeUsername', () {
    test('trims surrounding whitespace', () {
      expect(normalizeUsername('  Jaswa  '), 'jaswa');
    });

    test('lower-cases so names are unique case-insensitively', () {
      expect(normalizeUsername('Jaswa'), normalizeUsername('jaswa'));
      expect(normalizeUsername('JASWA'), normalizeUsername('jaswa'));
    });

    test('collapses internal runs of whitespace', () {
      expect(normalizeUsername('J  aswa'), 'j aswa');
      expect(normalizeUsername('Anna  Maria'), 'anna maria');
    });

    test('empty and whitespace-only names normalize to empty', () {
      expect(normalizeUsername(''), '');
      expect(normalizeUsername('   '), '');
    });
  });

  group('UsernameTakenException', () {
    test('carries the offending name', () {
      const e = UsernameTakenException(name: 'Jaswa');
      expect(e.name, 'Jaswa');
      expect(e.toString(), contains('Jaswa'));
    });
  });
}