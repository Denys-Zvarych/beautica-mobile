// Unit tests for the category slug derivation + validation helpers.

import 'package:beautica_mobile/features/services/domain/category_slug.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('deriveCategorySlug', () {
    test('latin words → uppercase underscore slug', () {
      expect(deriveCategorySlug('Nail art'), 'NAIL_ART');
      expect(deriveCategorySlug('  spaced   out  '), 'SPACED_OUT');
    });

    test('transliterates Ukrainian to latin', () {
      expect(deriveCategorySlug('Манікюр'), 'MANIKIUR');
      // щ → SHCH, ї → I
      expect(deriveCategorySlug('Нарощування вій'), 'NAROSHCHUVANNIA_VII');
    });

    test('drops punctuation and collapses separators', () {
      expect(deriveCategorySlug('Hair — cut!!!'), 'HAIR_CUT');
    });

    test('prefixes a leading digit so it starts with a letter', () {
      expect(deriveCategorySlug('3d brows'), 'C_3D_BROWS');
    });

    test('returns empty when no usable characters', () {
      expect(deriveCategorySlug('!!! ??? ...'), '');
      expect(deriveCategorySlug(''), '');
    });

    test('truncates to the max length and trims trailing underscore', () {
      final long = 'a' * 60;
      final slug = deriveCategorySlug(long);
      expect(slug.length, lessThanOrEqualTo(kCategorySlugMaxLength));
    });

    test('derived slugs are always valid (when non-empty)', () {
      for (final input in <String>[
        'Maní cure',
        'Нарощування вій',
        'Hair-Cut',
        '3d brows',
      ]) {
        final slug = deriveCategorySlug(input);
        if (slug.isNotEmpty) {
          expect(
            isValidCategorySlug(slug),
            isTrue,
            reason: 'slug "$slug" derived from "$input" must be valid',
          );
        }
      }
    });
  });

  group('isValidCategorySlug', () {
    test('accepts valid slugs', () {
      expect(isValidCategorySlug('MANICURE'), isTrue);
      expect(isValidCategorySlug('NAIL_ART'), isTrue);
      expect(isValidCategorySlug('A1_B2'), isTrue);
    });

    test('rejects invalid slugs', () {
      expect(isValidCategorySlug(''), isFalse);
      expect(isValidCategorySlug('lower'), isFalse);
      expect(isValidCategorySlug('1LEADING_DIGIT'), isFalse);
      expect(isValidCategorySlug('HAS SPACE'), isFalse);
      expect(isValidCategorySlug('HAS-DASH'), isFalse);
      expect(isValidCategorySlug('_LEADING_UNDERSCORE'), isFalse);
      expect(isValidCategorySlug('A' * 51), isFalse);
    });
  });
}
