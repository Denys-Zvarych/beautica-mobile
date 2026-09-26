// Phase 352 D4 — matchSearchSuggestions: the LOCAL (national instant-row)
// matcher. Mirrors the backend SearchSuggestionServiceTest cases so the two
// layers can never disagree about what a term matches.

import 'package:beautica_mobile/features/discovery/domain/search_suggestion.dart';
import 'package:beautica_mobile/features/discovery/domain/search_suggestions.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:flutter_test/flutter_test.dart';

ServiceCategoryOption _c(String key, String label) =>
    ServiceCategoryOption(name: key, displayName: label);

// «Нарощення вій» word-starts on «нар»/«вій»; «Манікюр» does not.
final _lashes = _c('EYELASH', 'Нарощення вій');
final _manicure = _c('MANICURE', 'Манікюр');
final _pedicure = _c('PEDICURE', 'Педикюр');
// Contains «мані» mid-word but does not START on it or any of its words —
// tells a substring-only match apart from a word-start one.
final _thermani = _c('THERM', 'Термані');
final _apostrophe = _c('BROW', 'Брів’яр');

void main() {
  group('folding', () {
    test('«нар» matches «Нарощення вій» (word-start)', () {
      final result = matchSearchSuggestions('нар', <ServiceCategoryOption>[
        _lashes,
        _manicure,
      ]);
      expect(result.map((s) => s.categoryKey), contains('EYELASH'));
    });

    test('case-insensitive: «НАР» matches the same as «нар»', () {
      final lower = matchSearchSuggestions('нар', <ServiceCategoryOption>[
        _lashes,
      ]);
      final upper = matchSearchSuggestions('НАР', <ServiceCategoryOption>[
        _lashes,
      ]);
      expect(upper.map((s) => s.categoryKey), lower.map((s) => s.categoryKey));
      expect(upper, isNotEmpty);
    });

    test("apostrophe variants ' / ’ / ʼ all fold to the same match", () {
      for (final variant in <String>["брів'яр", 'брів’яр', 'брівʼяр']) {
        final result = matchSearchSuggestions(variant, <ServiceCategoryOption>[
          _apostrophe,
        ]);
        expect(
          result,
          isNotEmpty,
          reason: 'apostrophe variant "$variant" should match',
        );
      }
    });
  });

  group('tiering', () {
    test('1 char requires word-start — a mid-word letter matches nothing', () {
      // «а» is mid-word in «Манікюр» (м-А-нікюр starts with м, not а) — no
      // word in the label starts with «а».
      final result = matchSearchSuggestions('а', <ServiceCategoryOption>[
        _manicure,
      ]);
      expect(result, isEmpty);
    });

    test('2 chars still requires word-start, not substring', () {
      // «ані» is a substring of «Термані» but no word starts with it.
      final result = matchSearchSuggestions('ан', <ServiceCategoryOption>[
        _thermani,
      ]);
      expect(result, isEmpty);
    });

    test('3+ chars falls back to substring when no word starts with it', () {
      final result = matchSearchSuggestions('ані', <ServiceCategoryOption>[
        _thermani,
      ]);
      expect(result.map((s) => s.categoryKey), contains('THERM'));
    });
  });

  group('ranking', () {
    test('a label-start match ranks first; unrelated labels are excluded', () {
      final result = matchSearchSuggestions('ман', <ServiceCategoryOption>[
        _lashes, // no "ман" anywhere — excluded
        _pedicure, // no "ман" anywhere — excluded
        _manicure, // label-start
      ]);
      expect(result.single.categoryKey, 'MANICURE');
    });

    test(
      'a word-start match on a later word ranks above a substring-only one',
      () {
        // "Салон манікюру" word-starts on "ман" (second word); "Термані"
        // only contains "ман" mid-word (т-е-р-М-А-Н-і) — substring only.
        final wordStartLater = _c('SALON_M', 'Салон манікюру');
        final result = matchSearchSuggestions('ман', <ServiceCategoryOption>[
          _thermani,
          wordStartLater,
        ]);
        expect(result.map((s) => s.categoryKey).toList(), <String>[
          'SALON_M',
          'THERM',
        ]);
      },
    );
  });

  group('cap', () {
    test('caps at max, applied AFTER ranking (fixture with >6 matches)', () {
      final categories = <ServiceCategoryOption>[
        for (int i = 0; i < 9; i++) _c('CAT_$i', 'Манікюр $i'),
      ];
      final result = matchSearchSuggestions(
        'ман',
        categories,
        max: kSearchSuggestionMax,
      );
      expect(result.length, kSearchSuggestionMax);
    });
  });

  group('blank input', () {
    test('a blank term returns no rows', () {
      expect(
        matchSearchSuggestions('', <ServiceCategoryOption>[_manicure]),
        isEmpty,
      );
      expect(
        matchSearchSuggestions('   ', <ServiceCategoryOption>[_manicure]),
        isEmpty,
      );
    });
  });

  group('foldedLabels (mobile-perf LOW cycle-1 — shared-fold reuse)', () {
    // A genuine "the fold runs once per BUILD, not once per KEYSTROKE" claim
    // needs a call-counter seam inside `foldSearchLabel`/this function — not
    // allowed in lib code (no test-only instrumentation in production
    // sources). What IS testable without one: that the `foldedLabels`
    // parameter is actually CONSULTED rather than silently ignored — proven
    // by handing in folds that deliberately disagree with what
    // `foldSearchLabel(category.displayName)` would produce and observing
    // the match follow the PASSED-IN fold, not the label. The provider side
    // (`search_suggestions_provider.dart`'s `_foldedLabelsFor`) is covered by
    // the existing widget-level suggestion tests continuing to pass
    // unchanged — proving the refactor moved no behaviour — plus code
    // reading: `identical(categories, _memoCategories)` short-circuits every
    // rebuild after the categories list first resolves, and
    // `approvedCategoriesProvider` (a `keepAlive` FutureProvider) hands back
    // the SAME list instance on every subsequent watch.
    test('a deliberately WRONG folded label wins the match instead of the '
        'real fold of displayName — proves foldedLabels[i] is read, not '
        'recomputed', () {
      final result = matchSearchSuggestions(
        'мак',
        <ServiceCategoryOption>[_lashes, _manicure],
        foldedLabels: const <String>[
          'нарощення вій', // _lashes' real fold — no "мак"
          'макіяж', // _manicure's REAL displayName folds to "манікюр", not
          // this — only reachable if the passed-in fold is what's used
        ],
      );
      expect(result.map((s) => s.categoryKey).toList(), <String>['MANICURE']);
    });

    test(
      'omitting foldedLabels (the default) folds displayName itself, exactly '
      'as before this fix',
      () {
        final result = matchSearchSuggestions('нар', <ServiceCategoryOption>[
          _lashes,
          _manicure,
        ]);
        expect(result.map((s) => s.categoryKey), <String>['EYELASH']);
      },
    );

    test(
      'a mismatched-length foldedLabels trips the parallel-arrays assertion',
      () {
        expect(
          () => matchSearchSuggestions(
            'нар',
            <ServiceCategoryOption>[_lashes, _manicure],
            foldedLabels: const <String>['нарощення вій'],
          ),
          throwsA(isA<AssertionError>()),
        );
      },
    );
  });

  group('output shape', () {
    test('every row is CATEGORY with no serviceTypeSlug', () {
      final result = matchSearchSuggestions('ман', <ServiceCategoryOption>[
        _manicure,
      ]);
      expect(result.single.type, SearchSuggestionType.category);
      expect(result.single.serviceTypeSlug, isNull);
      expect(result.single.label, 'Манікюр');
    });
  });
}
