// Regression guard (mobile-qa, DEBUG Step 2.7 Rule 3) — pins the resting visual
// state of the category dropdown on [ServiceForm].
//
// THE FOOTGUN THIS GUARDS
// -----------------------
// `approvedCategoriesProvider` (service_repository.dart, @Riverpod keepAlive)
// sources from `categoryRequestApiProvider → the real authenticated Dio`. It
// does NOT flow through `serviceRepositoryProvider`. So any fixture that
// overrides only the repo fake leaves this provider hitting the real Dio under
// `flutter test`. With no backend that resolves to an ERROR AsyncValue, and
// `_CategoryDropdown.build` maps `error → SelectFieldState.error`, so the
// category field paints the [BrandColors.error] (0xFFB0452F) ring AT REST —
// a silently-wrong fixture artifact (it leaked into a golden + a leaked
// 15s connect-timeout Timer elsewhere).
//
// The three bitten fixtures were fixed by adding
// `approvedCategoriesProvider.overrideWith((ref) async => <…>[])`. This test is
// the behaviour-level guard those fixtures lacked: it PINS that
//
//   • when the provider resolves SUCCESSFULLY (empty OR non-empty list), the
//     category field is NEUTRAL at rest — `NeumorphicInset.hasError == false`
//     and its painted ring is NOT the `BrandColors.error` fill — in BOTH
//     CREATE (blank) and EDIT (pre-filled valid value) modes; and
//   • when the provider is in ERROR, the field DOES surface the error ring —
//     locking the documented intended behaviour so a future "fix" can't
//     over-correct the neutral case into never-erroring.
//
// Isolation: fresh ProviderScope per pump; serviceRepositoryProvider +
// serviceTypesProvider + approvedCategoriesProvider all overridden so no real
// HTTP fires. The field is found by Key (M2), never by localised label. No
// `pump(const Duration())` fixed waits.

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/features/services/domain/service_type_option.dart';
import 'package:beautica_mobile/features/services/presentation/service_types_provider.dart';
import 'package:beautica_mobile/features/services/presentation/widgets/service_form.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/fakes/fake_service_repository.dart';

// ---------------------------------------------------------------------------
// Seed data
// ---------------------------------------------------------------------------

const _categories = <ServiceCategoryOption>[
  ServiceCategoryOption(name: 'MANICURE', displayName: 'Манікюр'),
];

// EDIT-mode seed: a valid persisted service whose category slug ('MANICURE')
// matches an approved option — the pre-filled, untouched, non-error case.
const _editSeed = MasterService(
  id: 's1',
  serviceDefId: 'def1',
  category: 'MANICURE',
  name: 'Манікюр класичний',
  durationMinutes: 60,
  priceType: ServicePriceType.fixed,
  priceMin: 350,
  priceDisplay: '350 грн',
);

// ---------------------------------------------------------------------------
// Finders (by Key — M2).
//
// The category field's wrapper carries Key('select-category-field-wrapper');
// inside it sits exactly one NeumorphicInset (the closed-field well whose ring
// turns red on error). We scope to that descendant.
// ---------------------------------------------------------------------------

final _categoryInset = find.descendant(
  of: find.byKey(const Key('select-category-field-wrapper')),
  matching: find.byType(NeumorphicInset),
);

// ---------------------------------------------------------------------------
// Pump helpers
// ---------------------------------------------------------------------------

/// Pumps [ServiceForm] with [categories] driving `approvedCategoriesProvider`.
/// A null [categories] means the provider FAILS (error AsyncValue). [initial]
/// non-null → EDIT mode.
Future<void> _pumpForm(
  WidgetTester tester, {
  required List<ServiceCategoryOption>? categories,
  MasterService? initial,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        serviceRepositoryProvider.overrideWithValue(FakeServiceRepository()),
        approvedCategoriesProvider.overrideWith((ref) async {
          if (categories == null) {
            throw Exception('approved categories load failed');
          }
          return categories;
        }),
        serviceTypesProvider.overrideWith(
          (ref, String categoryName) async => const <ServiceTypeOption>[],
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('uk'),
        home: Scaffold(
          body: SingleChildScrollView(
            child: ServiceForm(initial: initial, onSubmit: (_) async {}),
          ),
        ),
      ),
    ),
  );
  // Settle the AsyncValue (data/error) — no fixed-duration pump.
  await tester.pumpAndSettle();
}

/// Resolves the category field's [NeumorphicInset] and returns whether it is in
/// the error treatment. `hasError` is `error || isErrorState` inside the field,
/// so a true value here means the red ring is painted.
bool _categoryHasError(WidgetTester tester) {
  final inset = tester.widget<NeumorphicInset>(_categoryInset);
  return inset.hasError;
}

/// Reads the painted ring colour from the inset's [AnimatedContainer] border.
/// At rest (no error) the border is transparent (width 0); on error it is
/// [BrandColors.error] (width 2).
Color _categoryRingColor(WidgetTester tester) {
  final container = tester.widget<AnimatedContainer>(
    find.descendant(
      of: _categoryInset,
      matching: find.byType(AnimatedContainer),
    ),
  );
  final decoration = container.decoration! as BoxDecoration;
  return decoration.border!.top.color;
}

void main() {
  group('category dropdown resting state — SUCCESS data → neutral (no error '
      'ring at rest)', () {
    // Both an empty and a non-empty approved list must render NEUTRAL. The
    // footgun manifested even with empty data (the bug was ERROR vs DATA, not
    // populated vs empty), so we pin both shapes.
    for (final entry in <String, List<ServiceCategoryOption>>{
      'empty list': const <ServiceCategoryOption>[],
      'non-empty list': _categories,
    }.entries) {
      final shape = entry.key;
      final data = entry.value;

      testWidgets('CREATE mode, $shape → field is idle, ring is not the error '
          'fill', (tester) async {
        await _pumpForm(tester, categories: data);

        expect(_categoryInset, findsOneWidget);
        expect(
          _categoryHasError(tester),
          isFalse,
          reason:
              'category field must be NEUTRAL when approvedCategoriesProvider '
              'resolves with data ($shape) and the form is untouched (CREATE)',
        );
        expect(
          _categoryRingColor(tester),
          isNot(BrandColors.error),
          reason: 'no $shape resting state may paint the 0xFFB0452F error ring',
        );
      });

      testWidgets('EDIT mode (pre-filled valid value), $shape → field is idle, '
          'ring is not the error fill', (tester) async {
        await _pumpForm(tester, categories: data, initial: _editSeed);

        expect(_categoryInset, findsOneWidget);
        expect(
          _categoryHasError(tester),
          isFalse,
          reason:
              'pre-filled valid category must stay NEUTRAL at rest (EDIT); a '
              'red ring here is the success-data fixture footgun',
        );
        expect(
          _categoryRingColor(tester),
          isNot(BrandColors.error),
          reason: 'EDIT resting state ($shape) must not paint the error ring',
        );
      });
    }
  });

  group('category dropdown resting state — ERROR async → error ring shown '
      '(documented intended behaviour)', () {
    testWidgets('CREATE mode, provider ERROR → field shows the error '
        'treatment', (tester) async {
      await _pumpForm(tester, categories: null);

      expect(_categoryInset, findsOneWidget);
      expect(
        _categoryHasError(tester),
        isTrue,
        reason:
            'a genuine approvedCategoriesProvider load failure MUST surface the '
            'error treatment — the neutral-state fix must not erase this',
      );
      expect(
        _categoryRingColor(tester),
        BrandColors.error,
        reason: 'error state paints the 0xFFB0452F ring (the intended signal)',
      );
    });

    testWidgets('EDIT mode, provider ERROR → field still shows the error '
        'treatment', (tester) async {
      await _pumpForm(tester, categories: null, initial: _editSeed);

      expect(_categoryInset, findsOneWidget);
      expect(
        _categoryHasError(tester),
        isTrue,
        reason:
            'EDIT mode must surface the error ring on a genuine load '
            'failure too',
      );
      expect(_categoryRingColor(tester), BrandColors.error);
    });
  });
}
