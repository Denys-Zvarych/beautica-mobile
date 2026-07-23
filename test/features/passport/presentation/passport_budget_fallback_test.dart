// Phase 13.8 — BEAUTY PASSPORT budget-chip fallback (widget tests).
//
// `_PopulatedPassport` (passport_screen.dart) routes `BudgetBand.max` through
// `renderableWholePrice` before formatting the budget chip, specifically so a
// malformed backend payload (`Infinity` / `NaN`, reachable on the wire via
// `jsonDecode('1e400')`) renders the "budget not known" placeholder instead
// of either throwing inside `build()` (a bare `.round()` on `Infinity` throws
// `UnsupportedError`) or printing a saturated `9223372036854775807 ₴`.
//
// These cases are dormant today (the repository still returns
// `PassportMapper.placeholder()` with a null budget) but arm the moment
// backend 19.5 ships a real budget band — this file is the regression guard
// for that day. See passport_screen.dart:276-286 and
// booking_price_labels.dart:279 (`renderableWholePrice`) for the full
// rationale.

import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/features/home/application/home_hub_notifier.dart';
import 'package:beautica_mobile/features/home/domain/home_hub_models.dart';
import 'package:beautica_mobile/features/passport/application/passport_notifier.dart';
import 'package:beautica_mobile/features/passport/domain/passport.dart';
import 'package:beautica_mobile/features/passport/presentation/passport_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/pump_app.dart';

// ---------------------------------------------------------------------------
// Sample data
// ---------------------------------------------------------------------------

const _sampleProfile = ClientProfileSummary(
  firstName: 'Олена',
  lastName: 'Тест',
  city: 'Львів',
  phone: '+380 97 000 00 00',
  clientRating: null,
  memberSinceYear: 2024,
);

Passport _passportWithBudget(BudgetBand? budget) => Passport(
  favoriteProcedures: const <String>['Манікюр', 'Брови', 'Педикюр'],
  favoriteDistricts: const <String>['Центр', 'Сихів', 'Франківський'],
  budget: budget,
  bookingsConsidered: 7,
  reviewsLeft: 5,
  memberSinceYear: 2024,
);

List<Object> _overrides(Passport passport) => [
  screenProtectionProvider.overrideWithValue(ScreenProtectionManager()),
  clientProfileProvider.overrideWith((ref) async => _sampleProfile),
  passportProvider.overrideWith((ref) async => passport),
];

Future<AppLocalizations> _uk() =>
    AppLocalizations.delegate.load(const Locale('uk'));

void main() {
  group('PassportScreen — budget chip fallback (unrenderable max)', () {
    testWidgets(
      'budget.max == double.infinity renders the "unknown" placeholder, '
      'not a throw',
      (tester) async {
        await tester.pumpApp(
          const PassportScreen(),
          overrides: _overrides(
            _passportWithBudget(
              const BudgetBand(avg: 600, min: 400, max: double.infinity),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          tester.takeException(),
          isNull,
          reason:
              'build() must not throw on an Infinity budget ceiling — that '
              'is exactly what renderableWholePrice guards against',
        );

        final AppLocalizations l10n = await _uk();
        expect(find.text(l10n.passportBudgetUnknown), findsOneWidget);
        // Never a saturated Int64.round() figure.
        expect(find.textContaining('9223372036854775807'), findsNothing);
      },
    );

    testWidgets(
      'budget.max == double.nan renders the "unknown" placeholder, not a '
      'throw',
      (tester) async {
        await tester.pumpApp(
          const PassportScreen(),
          overrides: _overrides(
            _passportWithBudget(
              const BudgetBand(avg: 600, min: 400, max: double.nan),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          tester.takeException(),
          isNull,
          reason: 'build() must not throw on a NaN budget ceiling',
        );

        final AppLocalizations l10n = await _uk();
        expect(find.text(l10n.passportBudgetUnknown), findsOneWidget);
      },
    );

    testWidgets('null budget (current placeholder shape) renders the "unknown" '
        'placeholder', (tester) async {
      await tester.pumpApp(
        const PassportScreen(),
        overrides: _overrides(_passportWithBudget(null)),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      final AppLocalizations l10n = await _uk();
      expect(find.text(l10n.passportBudgetUnknown), findsOneWidget);
    });

    testWidgets(
      'POSITIVE CONTROL: a finite max renders the ceiling label, proving '
      'the chip does not simply vanish for the unknown cases above',
      (tester) async {
        await tester.pumpApp(
          const PassportScreen(),
          overrides: _overrides(
            _passportWithBudget(
              const BudgetBand(avg: 900, min: 600, max: 1500),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);

        final AppLocalizations l10n = await _uk();
        expect(find.text(l10n.passportBudgetCeiling(1500)), findsOneWidget);
        expect(find.text(l10n.passportBudgetUnknown), findsNothing);
      },
    );
  });
}
