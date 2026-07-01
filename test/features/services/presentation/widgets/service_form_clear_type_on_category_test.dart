// Phase 16.5 — pure unit tests for the edit-flow hardening rules on
// [ServiceForm]:
//   • [ServiceForm.shouldClearServiceTypeOnCategoryChange]
//   • [ServiceForm.shouldResetNameOnTypeCleared]
//
// These are the highest-value, cheapest units in the phase: no widget tree, no
// Riverpod, no controllers — just the two branches that decide whether a
// category change orphans a selected service type (so the submit never carries
// a cross-category serviceTypeId — backend 16.3) and whether a type-derived name
// pre-fill is reset without clobbering a user-edited name.
//
// Rule 1 — shouldClearServiceTypeOnCategoryChange:
//   clear ⇔ newCategory null/empty
//          OR effectiveTypeCategory null/empty   (effective = selectedTypeCategory
//             when known, else previousCategory — the EDIT pre-seed case)
//          OR effectiveTypeCategory != newCategory
//
// Rule 2 — shouldResetNameOnTypeCleared:
//   reset ⇔ lastAutoFilledName != null && currentName == lastAutoFilledName
//   (a user-edited name — currentName != lastAutoFilledName — is preserved;
//    a name with no prior auto-fill — lastAutoFilledName == null — is preserved)

import 'package:beautica_mobile/features/services/presentation/widgets/service_form.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ServiceForm.shouldClearServiceTypeOnCategoryChange', () {
    test('C-1. incompatible new category (type-category known) → clear', () {
      // Type belongs to MANICURE; the master switched the category to HAIRCUT.
      // The selection is now cross-category and must be dropped.
      expect(
        ServiceForm.shouldClearServiceTypeOnCategoryChange(
          previousCategory: 'MANICURE',
          newCategory: 'HAIRCUT',
          selectedTypeCategory: 'MANICURE',
        ),
        isTrue,
      );
    });

    test(
      'C-2. compatible / same new category (type-category known) → retain',
      () {
        // Re-selecting the SAME category must keep a still-valid selection rather
        // than silently discarding the master's choice.
        expect(
          ServiceForm.shouldClearServiceTypeOnCategoryChange(
            previousCategory: 'MANICURE',
            newCategory: 'MANICURE',
            selectedTypeCategory: 'MANICURE',
          ),
          isFalse,
        );
      },
    );

    test('C-3. null new category (category cleared entirely) → clear', () {
      // An orphan type with no category is invalid → drop it.
      expect(
        ServiceForm.shouldClearServiceTypeOnCategoryChange(
          previousCategory: 'MANICURE',
          newCategory: null,
          selectedTypeCategory: 'MANICURE',
        ),
        isTrue,
      );
    });

    test('C-4. empty new category → clear', () {
      expect(
        ServiceForm.shouldClearServiceTypeOnCategoryChange(
          previousCategory: 'MANICURE',
          newCategory: '',
          selectedTypeCategory: 'MANICURE',
        ),
        isTrue,
      );
    });

    test(
      'C-5. EDIT pre-seed: null captured type-category, INCOMPATIBLE change → '
      'falls back to previousCategory → clear',
      () {
        // On edit the loaded service carries no explicit type-category
        // (selectedTypeCategory == null), so the rule falls back to
        // previousCategory (the type was chosen under it by construction).
        // previousCategory MANICURE != newCategory HAIRCUT → clear.
        expect(
          ServiceForm.shouldClearServiceTypeOnCategoryChange(
            previousCategory: 'MANICURE',
            newCategory: 'HAIRCUT',
            selectedTypeCategory: null,
          ),
          isTrue,
        );
      },
    );

    test('C-6. EDIT pre-seed: null captured type-category, SAME change → '
        'falls back to previousCategory → retain', () {
      // previousCategory MANICURE == newCategory MANICURE → keep the selection
      // (the edit pre-seed must not be discarded by a no-op re-select).
      expect(
        ServiceForm.shouldClearServiceTypeOnCategoryChange(
          previousCategory: 'MANICURE',
          newCategory: 'MANICURE',
          selectedTypeCategory: null,
        ),
        isFalse,
      );
    });

    test('C-7. EDIT pre-seed: empty captured type-category → falls back to '
        'previousCategory (not treated as known)', () {
      // An empty string captured-category must be treated as "unknown" and
      // fall back to previousCategory, NOT compared as an empty category.
      expect(
        ServiceForm.shouldClearServiceTypeOnCategoryChange(
          previousCategory: 'MANICURE',
          newCategory: 'MANICURE',
          selectedTypeCategory: '',
        ),
        isFalse,
      );
    });

    test(
      'C-8. both captured AND previous category null → clear (no anchor)',
      () {
        // Nothing to anchor the type to → it is orphaned → clear.
        expect(
          ServiceForm.shouldClearServiceTypeOnCategoryChange(
            previousCategory: null,
            newCategory: 'HAIRCUT',
            selectedTypeCategory: null,
          ),
          isTrue,
        );
      },
    );

    test(
      'C-9. captured type-category WINS over previousCategory when they differ',
      () {
        // The captured type-category (HAIRCUT) is authoritative even when the
        // form\'s previousCategory (MANICURE) disagrees: a new HAIRCUT category
        // is compatible with the captured HAIRCUT type → retain.
        expect(
          ServiceForm.shouldClearServiceTypeOnCategoryChange(
            previousCategory: 'MANICURE',
            newCategory: 'HAIRCUT',
            selectedTypeCategory: 'HAIRCUT',
          ),
          isFalse,
        );
      },
    );

    // -----------------------------------------------------------------------
    // Gap-2 regression — slug-safe comparison (categorySlugMatches), NOT raw
    // `!=`. These FAIL against the pre-fix code (which used `typeCategory !=
    // newCategory`): trailing-whitespace / case drift between the loaded
    // service's category slug and the approved-list slug would be seen as a
    // genuine change, wrongly CLEARING a still-valid type. The fix compares
    // via categorySlugMatches (trim + upper-case), so drift retains the type.
    // -----------------------------------------------------------------------
    group('Gap-2 slug-safe drift (immune to case/whitespace)', () {
      test('C-10. trailing-whitespace drift on the TYPE category → retain', () {
        // Loaded type category 'BROWS ' (trailing space) vs new approved-list
        // slug 'BROWS'. Same category → must KEEP the selection. Raw `!=` would
        // see 'BROWS ' != 'BROWS' → clear (the bug).
        expect(
          ServiceForm.shouldClearServiceTypeOnCategoryChange(
            previousCategory: 'BROWS ',
            newCategory: 'BROWS',
            selectedTypeCategory: 'BROWS ',
          ),
          isFalse,
          reason:
              'trailing-whitespace drift must not clear a same-category type '
              '(slug-safe compare, not raw !=)',
        );
      });

      test('C-11. trailing-whitespace drift on the NEW category → retain', () {
        // The drift can also be on the incoming new-category slug.
        expect(
          ServiceForm.shouldClearServiceTypeOnCategoryChange(
            previousCategory: 'BROWS',
            newCategory: 'BROWS ',
            selectedTypeCategory: 'BROWS',
          ),
          isFalse,
        );
      });

      test('C-12. case drift → retain', () {
        // 'brows' vs 'BROWS' — same category, different case. Slug-safe compare
        // upper-cases both → equal → retain. Raw `!=` would clear (the bug).
        expect(
          ServiceForm.shouldClearServiceTypeOnCategoryChange(
            previousCategory: 'brows',
            newCategory: 'BROWS',
            selectedTypeCategory: 'brows',
          ),
          isFalse,
          reason: 'case drift must not clear a same-category type',
        );
      });

      test('C-13. combined case + whitespace drift → retain', () {
        expect(
          ServiceForm.shouldClearServiceTypeOnCategoryChange(
            previousCategory: '  Brows  ',
            newCategory: 'BROWS',
            selectedTypeCategory: '  Brows  ',
          ),
          isFalse,
        );
      });

      test(
        'C-14. drift must NOT mask a genuine cross-category change → clear',
        () {
          // Belt-and-suspenders: the slug-safe compare must still CLEAR when the
          // categories genuinely differ (so the fix did not over-correct into
          // "never clear"). 'NAILS' vs 'BROWS ' is a real change → clear.
          expect(
            ServiceForm.shouldClearServiceTypeOnCategoryChange(
              previousCategory: 'NAILS',
              newCategory: 'BROWS ',
              selectedTypeCategory: 'NAILS',
            ),
            isTrue,
            reason:
                'a genuine cross-category change must still clear, even with '
                'whitespace on the new slug',
          );
        },
      );
    });
  });

  group('ServiceForm.shouldResetNameOnTypeCleared', () {
    test('R-1. name still equals the type-derived auto-fill → reset', () {
      expect(
        ServiceForm.shouldResetNameOnTypeCleared(
          currentName: 'Класичний манікюр',
          lastAutoFilledName: 'Класичний манікюр',
        ),
        isTrue,
      );
    });

    test('R-2. user-edited name (differs from auto-fill) → preserved', () {
      // The load-bearing don\'t-clobber invariant: a hand-typed name survives
      // the type clear.
      expect(
        ServiceForm.shouldResetNameOnTypeCleared(
          currentName: 'Мій власний манікюр',
          lastAutoFilledName: 'Класичний манікюр',
        ),
        isFalse,
      );
    });

    test('R-3. no prior auto-fill (lastAutoFilledName null) → preserved', () {
      // The name was never type-derived, so clearing the type must not touch it.
      expect(
        ServiceForm.shouldResetNameOnTypeCleared(
          currentName: 'Щось своє',
          lastAutoFilledName: null,
        ),
        isFalse,
      );
    });

    test('R-4. empty name with no prior auto-fill → preserved (no-op)', () {
      expect(
        ServiceForm.shouldResetNameOnTypeCleared(
          currentName: '',
          lastAutoFilledName: null,
        ),
        isFalse,
      );
    });
  });
}
