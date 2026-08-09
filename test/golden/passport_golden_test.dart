// Phase 238 — Visual regression goldens for the REBUILT BEAUTY PASSPORT page.
//
// WHY THIS FILE EXISTS
// --------------------
// Phase 238 deleted `passport_table.dart` (the full-page "document" card) and
// rebuilt the page around two new widgets — [PassportIdentityStrip] and
// [PassportDerivedBlock] — plus the wish-list section. The golden suite's 101
// passing tests proved the OTHER screens survived that deletion; not one pixel
// of the rebuilt page was covered by any baseline. This file closes that.
//
// TWO STATES, because they are structurally different pages:
//   • DATA        — profile + identity strip + derived block (both locality
//                   lines and the average pill) + a two-card wish-list line
//                   with «Показати всі (5)».
//   • NO HISTORY  — the identity strip ALONE (the derived block is omitted
//                   entirely when nothing is derivable, not rendered empty)
//                   above the wish list's empty invitation card. This is the
//                   branch a new account lands on, and it is the one that used
//                   to be indistinguishable from a failed fetch.
//
// Matrix: {320, 360, 414} dp × {textScale 1.0, 1.3} × 2 states = 12 PNGs.
//
// FIXTURES ARE THE WORST CASE the design was measured against — «Ламінування та
// фарбування брів», «Анастасія Мельниченко», «Шевченківський» — so a baseline
// captures the wrap behaviour that short convenient strings would hide. Every
// cell runs with overflow detection active (see `helpers/golden_pump.dart`), so
// a name that stopped wrapping and started overflowing fails here.
//
// CLOCK: `memberSinceYear` and `reviewsWritten` are WIRE values on [Passport]
// and literals in these fixtures. Nothing on this page reads `DateTime.now()`,
// so no clock override is needed and none is installed — there is no second
// clock here to disagree with a first one.
//
// ── THESE BASELINES ARE A DRIFT GUARD, NOT ACCEPTANCE ───────────────────────
//
// A golden generated from the code under test is self-referential: it locks in
// whatever the page renders today, right or wrong. Their job from here is
// UNINTENDED pixel drift, nothing more. What they specifically do NOT establish
// is the correctness of the LAYOUT at these cells — that is established
// independently of any PNG, by `passport_screen_overflow_test.dart` and the
// no-truncation regression tests, which assert off the laid-out render tree
// rather than off a picture.
//
// Alchemist CI mode obscures TEXT but renders gradients, so a wash change is
// exactly the class of drift these baselines can see.
//
// ── THE THREE DIVERGENCES THE FIRST BASELINES ENCODED ARE FIXED ─────────────
//
// The first cut of these PNGs was captured from a render that disagreed with
// the approved preview in three places. All three are now closed in `lib/`, and
// THESE baselines were re-captured from the corrected render — they no longer
// encode a known-wrong page:
//
//  1. [PassportIdentityStrip]'s blush wash — was a DIAGONAL three-stop ramp
//     highlighted with `BrandColors.white` (#F5EDE0). Now the preview's
//     `VelvetGradients.identityBlush` verbatim (`docs/signup-designs/
//     BeautyPassport/lib/theme/velvet_tokens.dart:679`): a VERTICAL two-stop
//     ramp, `lerp(base, shadowLightStrong, 0.45)` → `lerp(base, accent, 0.10)`.
//     Verified off this render: the strip is now flat across its width and
//     lifts to #F1EAE0 at the top, where it used to sit at bare `base`.
//  2. [PassportDerivedBlock]'s in-card rule — was alpha 0.35. Now 0.28, the
//     preview's `VelvetAlpha.hairlineSoft` (`velvet_tokens.dart:98`). The
//     identity strip's counter-rule stays at the full 0.5 (`VelvetAlpha
//     .hairline`); the two are a deliberate pair, not one value drifting.
//  3. `HubAvatar`'s initials — the 32 dp wish-list disc rendered them at 20 pt,
//     a size in no [VelvetText] token, because that was the `fontSize`
//     parameter's default. The scale is now DERIVED from `size` exactly as the
//     preview derives it: `statValue` (17) below 64 dp, `displayName` (19) at
//     or above. Only the two 96 dp profile portraits still pass an explicit
//     override.
//
// Re-blessing after a deliberate design change is fine; re-blessing to make a
// red run green is not. If one of these twelve moves without `lib/` moving,
// that is drift and the answer is to read the diff, not to regenerate.

import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/features/home/application/home_hub_notifier.dart';
import 'package:beautica_mobile/features/home/domain/home_hub_models.dart';
import 'package:beautica_mobile/features/passport/application/passport_notifier.dart';
import 'package:beautica_mobile/features/passport/domain/passport.dart';
import 'package:beautica_mobile/features/passport/presentation/passport_screen.dart';
import 'package:beautica_mobile/features/wishlist/application/wishlist_notifier.dart';
import 'package:beautica_mobile/features/wishlist/domain/wishlist_service.dart';

import '../helpers/fakes/fake_wishlist_repository.dart';
import 'helpers/golden_pump.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const _sampleProfile = ClientProfileSummary(
  firstName: 'Олена',
  lastName: 'Тест',
  city: 'Львів',
  phone: '+380 97 000 00 00',
  clientRating: null,
  memberSinceYear: 2024,
);

/// The preview's worst-case derived history: the district that used to clip to
/// «Шев…», three of them, plus two cities on a second line.
const _populatedPassport = Passport(
  favoriteDistricts: <String>['Шевченківський', 'Голосіївський', 'Печерський'],
  favoriteCities: <String>['Київ', 'Бровари'],
  // `max` differs from `avg` so a page still rendering the CEILING draws a
  // visibly different pill rather than an identical one.
  budget: BudgetBand(avg: 750, min: 400, max: 2400),
  bookingsConsidered: 7,
  reviewsWritten: 12,
  memberSinceYear: 2021,
);

/// History exists, but nothing is derivable — no locality, no spend band. The
/// derived block is OMITTED here, not rendered empty, so this cell is what
/// pins that the page collapses rather than showing an empty card.
const _noHistoryPassport = Passport(
  favoriteDistricts: <String>[],
  favoriteCities: <String>[],
  budget: null,
  bookingsConsidered: 0,
  reviewsWritten: 0,
  memberSinceYear: 2021,
);

WishlistService _wish(
  String id, {
  required String serviceName,
  required String masterName,
  required int durationMinutes,
  required String priceDisplay,
  bool isRange = false,
  double? priceMin,
  double? priceMax,
}) => WishlistService(
  masterServiceId: id,
  masterId: 'm-$id',
  serviceName: serviceName,
  masterName: masterName,
  durationMinutes: durationMinutes,
  priceDisplay: priceDisplay,
  isRangePrice: isRange,
  priceMin: priceMin,
  priceMax: priceMax,
);

/// FIVE favourites, so the line shows two and the overflow button states «5».
/// The first pair is the measured worst case: a name that must wrap to two
/// lines beside a RANGE price that must render as the app's own en-dash band.
final List<WishlistService> _fiveFavourites = <WishlistService>[
  _wish(
    'w1',
    serviceName: 'Ламінування та фарбування брів',
    masterName: 'Анастасія Мельниченко',
    durationMinutes: 150,
    priceDisplay: '1 200 ₴',
  ),
  _wish(
    'w2',
    serviceName: 'Манікюр з покриттям гель-лак',
    masterName: 'Ірина Бондаренко',
    durationMinutes: 90,
    priceDisplay: 'від 600 до 900 ₴',
    isRange: true,
    priceMin: 600,
    priceMax: 900,
  ),
  _wish(
    'w3',
    serviceName: 'Нарощування вій — класика 2D',
    masterName: 'Олена Ковальчук',
    durationMinutes: 60,
    priceDisplay: '800 ₴',
  ),
  _wish(
    'w4',
    serviceName: 'Корекція брів та фарбування хною',
    masterName: 'Софія Романюк',
    durationMinutes: 45,
    priceDisplay: '450 ₴',
  ),
  _wish(
    'w5',
    serviceName: 'Педикюр апаратний з покриттям',
    masterName: 'Вікторія Ткаченко',
    durationMinutes: 120,
    priceDisplay: 'від 700 до 1100 ₴',
    isRange: true,
    priceMin: 700,
    priceMax: 1100,
  ),
];

/// The native FLAG_SECURE plugin must never fire under `flutter test` —
/// [PassportScreen.initState] acquires screen protection on mount.
class _NoOpScreenProtection extends ScreenProtectionManager {
  @override
  void acquire() {}

  @override
  void release() {}

  @override
  void reset() {}
}

/// NOTE the wish-list REPOSITORY is always overridden. `WishlistSection`
/// watches `wishlistProvider`, which resolves through the real
/// `HttpWishlistRepository` otherwise — the section would fail its fetch and
/// draw its error card, silently goldening a different page.
List<Object> _overrides({
  required Passport passport,
  required List<WishlistService> wishlist,
}) => <Object>[
  screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
  clientProfileProvider.overrideWith((ref) async => _sampleProfile),
  passportProvider.overrideWith((ref) async => passport),
  wishlistRepositoryProvider.overrideWithValue(
    FakeWishlistRepository(services: wishlist),
  ),
];

// ---------------------------------------------------------------------------
// Goldens
// ---------------------------------------------------------------------------

void main() {
  for (final width in kGoldenWidths) {
    for (final scale in kGoldenTextScales) {
      final suffix = widthScaleSuffix(width, scale);

      goldenTest(
        'passport DATA ${width.toInt()}dp text-${scale}x',
        fileName: 'passport_data_$suffix',
        constraints: BoxConstraints.tight(Size(width, kGoldenHeight)),
        textScaleFactor: scale,
        pumpWidget: goldenPumpWidget(
          overrides: _overrides(
            passport: _populatedPassport,
            wishlist: _fiveFavourites,
          ),
          width: width,
        ),
        builder: () => const PassportScreen(),
      );

      goldenTest(
        'passport NO HISTORY ${width.toInt()}dp text-${scale}x',
        fileName: 'passport_no_history_$suffix',
        constraints: BoxConstraints.tight(Size(width, kGoldenHeight)),
        textScaleFactor: scale,
        pumpWidget: goldenPumpWidget(
          overrides: _overrides(
            passport: _noHistoryPassport,
            wishlist: const <WishlistService>[],
          ),
          width: width,
        ),
        builder: () => const PassportScreen(),
      );
    }
  }
}
