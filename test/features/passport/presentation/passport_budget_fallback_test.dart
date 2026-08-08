// Phases 13.8 / 235 / 238 — BEAUTY PASSPORT average-spend hardening.
//
// WHAT THE PAGE DOES NOW
// ----------------------
// `_PassportSection._content` (passport_screen.dart) computes
// `renderableWholePrice(passport.budget?.avg)` and hands the result — as a
// PRE-FORMATTED money string, or null — to [PassportDerivedBlock]. The block
// renders a [PriceTag] beside the «≈» marker when the figure is statable, and a
// BARE «—» keyed `passport_average_unknown` with NO pill when it is not.
//
// Phase 235 re-pointed the figure from `BudgetBand.max` (the ceiling, «до
// 800 ₴») to `BudgetBand.avg` (the average, «750 ₴»); Phase 238 replaced the
// document card's budget chip with the derived block's spend row. The hardening
// had to travel with BOTH moves, and this file is what proves it did: every
// case below feeds a malformed double through `avg` and asserts the bare-dash
// rendering, so the gate is pinned to the field the page actually reads rather
// than to a field it abandoned two phases ago.
//
// THE THREE FAILURE MODES THE GATE CLOSES
// ---------------------------------------
//   1. Infinity — reachable straight off the wire: `jsonDecode('1e400')` yields
//      `double.infinity` WITHOUT throwing, and a bare `.round()` on it throws
//      `UnsupportedError` from inside `build()`.
//   2. NaN — same `.round()` throw.
//   3. SATURATION above 2^63 — `double.round()` does not overflow and does not
//      throw; it saturates, so `(1e20).round()` is `9223372036854775807` and
//      the page would state a flatly fabricated «9223372036854775807 ₴».
//      `isRenderablePrice` alone does NOT close this one: its ceiling is 1e21
//      (where `toStringAsFixed(0)` stops emitting plain digits) while `round()`
//      saturates ~100x earlier at ≈9.22e18. `renderableWholePrice` carries the
//      extra `>= 2^63` check, and 1e20 is the value that separates the two.
//
// AN UNSTATABLE AVERAGE MUST RENDER THE BARE «—» AND NO PILL. Never a
// fabricated figure, and never a recessed well wrapped around nothing — the
// well is chrome that announces "here is a figure".
//
// Every test overrides `wishlistRepositoryProvider`: without it the wish-list
// section fails its real fetch and paints its own error card onto the page
// under measurement.

import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/core/widgets/price_tag.dart';
import 'package:beautica_mobile/features/home/application/home_hub_notifier.dart';
import 'package:beautica_mobile/features/home/domain/home_hub_models.dart';
import 'package:beautica_mobile/features/passport/application/passport_notifier.dart';
import 'package:beautica_mobile/features/passport/domain/passport.dart';
import 'package:beautica_mobile/features/passport/presentation/passport_screen.dart';
import 'package:beautica_mobile/features/passport/presentation/widgets/passport_derived_block.dart';
import 'package:beautica_mobile/features/wishlist/application/wishlist_notifier.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fakes/fake_wishlist_repository.dart';
import '../../../helpers/pump_app.dart';

const Key _kDerivedBlock = Key('passport_derived_block');
const Key _kAverageUnknown = Key('passport_average_unknown');

/// The saturating magnitude: finite, below `isRenderablePrice`'s 1e21 ceiling,
/// but at or above 2^63 — so ONLY the `renderableWholePrice` half of the gate
/// rejects it. A page that dropped that half would print
/// «9223372036854775807 ₴» here and pass every other case in this file.
const double _kSaturatingAvg = 1e20;

class _NoOpScreenProtection extends ScreenProtectionManager {
  @override
  void acquire() {}

  @override
  void release() {}

  @override
  void reset() {}
}

const _sampleProfile = ClientProfileSummary(
  firstName: 'Олена',
  lastName: 'Тест',
  city: 'Львів',
  phone: '+380 97 000 00 00',
  clientRating: null,
  memberSinceYear: 2024,
);

/// Localities are always populated so the derived BLOCK is always rendered —
/// otherwise `hasContent` would drop the whole block and «the figure is absent»
/// would be indistinguishable from «the block is absent», which is a different
/// contract (pinned in passport_screen_test.dart).
Passport _passportWithBudget(BudgetBand? budget) => Passport(
  favoriteProcedures: const <String>['Манікюр', 'Брови', 'Педикюр'],
  favoriteDistricts: const <String>['Шевченківський', 'Голосіївський'],
  favoriteCities: const <String>['Київ'],
  budget: budget,
  bookingsConsidered: 7,
  reviewsWritten: 5,
  // A WIRE value, never re-derived from a clock.
  memberSinceYear: 2021,
);

List<Object> _overrides(Passport passport) => <Object>[
  screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
  clientProfileProvider.overrideWith((ref) async => _sampleProfile),
  passportProvider.overrideWith((ref) async => passport),
  // Always overridden — see the file header.
  wishlistRepositoryProvider.overrideWithValue(FakeWishlistRepository()),
];

Future<AppLocalizations> _uk() =>
    AppLocalizations.delegate.load(const Locale('uk'));

/// Asserts the spend row is showing the BARE «—»: the unknown key, no pill, no
/// «≈» marker, and no fabricated digits anywhere on the page.
Future<void> _expectBareDashAndNoPill(WidgetTester tester) async {
  final AppLocalizations l10n = await _uk();

  expect(
    find.byKey(_kDerivedBlock),
    findsOneWidget,
    reason: 'the block itself must still render — only the FIGURE is unknown',
  );
  expect(find.byKey(_kAverageUnknown), findsOneWidget);
  expect(find.text(l10n.passportBudgetUnknown), findsOneWidget);

  expect(
    find.byType(PriceTag),
    findsNothing,
    reason:
        'the unknown case DROPS the pill — a recessed well around an em dash '
        'reads as a value that exists',
  );
  expect(
    find.text(kApproximatelyMarker),
    findsNothing,
    reason: 'with no figure there is nothing for «≈» to qualify',
  );

  // Never the saturated Int64 figure, and never a stray exponent rendering.
  expect(find.textContaining('9223372036854775807'), findsNothing);
  expect(find.textContaining('Infinity'), findsNothing);
  expect(find.textContaining('NaN'), findsNothing);
  expect(find.textContaining('e+'), findsNothing);
}

void main() {
  group('PassportScreen — unstatable average renders the bare «—»', () {
    testWidgets(
      'budget.avg == double.infinity — no throw, bare dash, no pill',
      (tester) async {
        await tester.pumpApp(
          const PassportScreen(),
          overrides: _overrides(
            _passportWithBudget(
              const BudgetBand(avg: double.infinity, min: 400, max: 800),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          tester.takeException(),
          isNull,
          reason:
              'build() must not throw on an Infinity average — a bare .round() '
              'throws UnsupportedError, which is what renderableWholePrice '
              'guards against',
        );
        await _expectBareDashAndNoPill(tester);
      },
    );

    testWidgets('budget.avg == double.nan — no throw, bare dash, no pill', (
      tester,
    ) async {
      await tester.pumpApp(
        const PassportScreen(),
        overrides: _overrides(
          _passportWithBudget(
            const BudgetBand(avg: double.nan, min: 400, max: 800),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      await _expectBareDashAndNoPill(tester);
    });

    testWidgets('budget.avg == 1e20 — the 2^63 SATURATION case, not merely the '
        'finite/negative one', (tester) async {
      // THE CASE `isRenderablePrice` ALONE WOULD PASS. 1e20 is finite,
      // non-negative and below the 1e21 exponent ceiling, so only the
      // `>= 2^63` half of `renderableWholePrice` rejects it. Dropping that
      // half prints «9223372036854775807 ₴» and every other test in this
      // file stays green.
      await tester.pumpApp(
        const PassportScreen(),
        overrides: _overrides(
          _passportWithBudget(
            const BudgetBand(avg: _kSaturatingAvg, min: 400, max: 800),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      await _expectBareDashAndNoPill(tester);
    });

    testWidgets('a negative average renders the bare dash, never «-500 ₴»', (
      tester,
    ) async {
      await tester.pumpApp(
        const PassportScreen(),
        overrides: _overrides(
          _passportWithBudget(const BudgetBand(avg: -500, min: 400, max: 800)),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      await _expectBareDashAndNoPill(tester);
      expect(find.textContaining('-500'), findsNothing);
    });

    testWidgets('a null budget band renders the bare dash', (tester) async {
      await tester.pumpApp(
        const PassportScreen(),
        overrides: _overrides(_passportWithBudget(null)),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      await _expectBareDashAndNoPill(tester);
    });
  });

  group('PassportScreen — POSITIVE CONTROLS', () {
    testWidgets(
      'a finite avg renders the AVERAGE in a pill, proving the figure does '
      'not simply vanish for the unknown cases above',
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
        // 900 is the AVERAGE. Asserting it — and NOT 1500, the ceiling — is
        // what proves the page reads `avg`: a screen still wired to `max` would
        // render 1500 and fail here rather than passing silently.
        expect(find.text(l10n.passportBudgetAverage(900)), findsOneWidget);
        expect(find.text(l10n.passportBudgetAverage(1500)), findsNothing);
        expect(find.text(l10n.passportBudgetUnknown), findsNothing);
        expect(find.byKey(_kAverageUnknown), findsNothing);

        // The figure lives in the SHARED pill, beside — and outside — the «≈».
        expect(find.byType(PriceTag), findsOneWidget);
        expect(find.text(kApproximatelyMarker), findsOneWidget);
        expect(
          tester.widget<PriceTag>(find.byType(PriceTag)).price,
          l10n.passportBudgetAverage(900),
          reason:
              'the pill must carry a PURE money string — «≈» is drawn beside '
              'it so every price pill in the app holds exactly one figure',
        );
      },
    );

    testWidgets(
      'the boundary just BELOW 2^63 still renders, so the saturation guard is '
      'not simply rejecting everything large',
      (tester) async {
        // 9.2e18 < 2^63 (≈9.223e18) and < 1e21, so it IS statable. Without this
        // control, a `renderableWholePrice` that returned null for any value
        // above (say) 1000 would satisfy every unknown-case test above.
        await tester.pumpApp(
          const PassportScreen(),
          overrides: _overrides(
            _passportWithBudget(
              const BudgetBand(avg: 9.2e18, min: 400, max: 800),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(
          find.byKey(_kAverageUnknown),
          findsNothing,
          reason:
              'a finite value below 2^63 is statable — rejecting it would mean '
              'the guard is a blanket cap rather than the round() boundary',
        );
        expect(find.byType(PriceTag), findsOneWidget);
        expect(find.text(kApproximatelyMarker), findsOneWidget);
      },
    );
  });
}
