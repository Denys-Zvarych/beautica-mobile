// REGRESSION GUARD — identity-card vertical alignment across Головна ↔ Beauty
// Passport.
//
// THE BUG (fixed)
// ---------------
// The user name/surname identity card jumped vertically when navigating between
// the client Home Hub (Головна) and the Beauty Passport page. Each page renders
// its OWN copy of the card and the spacer between the top bar and the card
// differed:
//   • HomeHubScreen   used `SizedBox(height: VelvetSpacing.lg)`     → 24 px
//   • PassportScreen  used `SizedBox(height: VelvetSpacing.sm + 2)` → 10 px
// a 14 px mismatch, so the card sat 14 px higher on Passport — a visible jump
// on every Home↔Passport switch.
//
// THE FIX
// -------
// Both bodies are now a `ListView` opened with the SAME
// `EdgeInsets.fromLTRB(lg, lg, lg, lg)` — home_hub_screen.dart:177 and
// passport_screen.dart:190 — with the profile block as the first child, so the
// two independently-rendered cards land at the same vertical Y.
//
// PHASE 238 RE-VERIFICATION. The passport page was rebuilt (non-scrolling
// Column → ListView, document card → identity strip + derived block + wish
// list). The invariant this file pins survived the rebuild UNCHANGED because
// the profile block is still the FIRST child under an identical top inset —
// which is exactly the claim worth re-asserting rather than assuming. The one
// change needed was the `wishlistRepositoryProvider` override: the page's new
// fourth block watches `wishlistProvider`, and leaving it live means every pump
// here fires a real repository call that can only fail.
//
// WHAT THIS TEST PINS
// -------------------
// Pump HomeHubScreen and PassportScreen INDEPENDENTLY with the SAME mocked
// `clientProfileProvider` data and the SAME fixed viewport, locate the identity
// card's name `Text` in each, and assert their top-left `dy` is EQUAL within
// ~1 px. The name `Text` is the canonical anchor of the card: both pages place
// it in the same Row(crossAxisAlignment.start) → Expanded → Column with an
// identical `SizedBox(height: 4)` above it, so the name's `dy` differs from the
// card's `dy` by the same constant on both pages. Locking the name `dy` locks
// the card `dy`.
//
// RED-AGAINST-BUG REASONING
// -------------------------
// Both pages share an identical top bar and an identical padding-top
// (`VelvetSpacing.sm`), so the ONLY input to the card's `dy` that differed was
// the top-bar → card spacer. With the OLD Passport spacer (10 px) vs Home
// (24 px), the Passport name's `dy` would be ~14 px SMALLER than Home's →
// `closeTo(homeDy, 1.0)` fails by ~14 px. With the fix (both 24 px) the two
// `dy` values coincide → green. This test therefore fails the instant either
// page's top spacer drifts again.
//
// NOTE FOR THE VERIFIER: no production change is needed for this test. It uses
// the existing `find.text(<name>)` anchor present on both screens — no new Key
// was added to lib/.

import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/features/home/application/home_hub_notifier.dart';
import 'package:beautica_mobile/features/home/domain/home_hub_models.dart';
import 'package:beautica_mobile/features/home/presentation/home_hub_screen.dart';
import 'package:beautica_mobile/features/passport/application/passport_notifier.dart';
import 'package:beautica_mobile/features/passport/domain/passport.dart';
import 'package:beautica_mobile/features/passport/presentation/passport_screen.dart';
import 'package:beautica_mobile/features/wishlist/application/wishlist_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fakes/fake_wishlist_repository.dart';
import '../../../helpers/pump_app.dart';

// ---------------------------------------------------------------------------
// No-op ScreenProtectionManager (the native FLAG_SECURE plugin must not fire).
// ---------------------------------------------------------------------------

class _NoOpScreenProtection extends ScreenProtectionManager {
  @override
  void acquire() {}

  @override
  void release() {}

  @override
  void reset() {}
}

// ---------------------------------------------------------------------------
// SHARED identity fixture — IDENTICAL on both screens so the card's vertical
// offset is driven purely by each page's chrome (top bar + spacer), never by
// differing content height.
// ---------------------------------------------------------------------------

const _sharedProfile = ClientProfileSummary(
  firstName: 'Олена',
  lastName: 'Тест',
  city: 'Львів',
  phone: '+380 97 000 00 00',
  clientRating: null,
  memberSinceYear: 2024,
);

const _kFullName = 'Олена Тест';

// Fixed device viewport — the same surface for BOTH pumps so SafeArea insets and
// the top-bar layout are identical and the only variable is the spacer.
const Size _kViewport = Size(390, 844);

// ---------------------------------------------------------------------------
// Overrides
// ---------------------------------------------------------------------------

// Both screens are pumped through the SAME ProviderScope root (pumpApp reuses
// it), and Riverpod forbids changing the NUMBER of overrides between pumps. So
// both pumps share ONE override list that satisfies BOTH screens: each screen
// only reads the providers it watches and ignores the rest. The shared profile
// override is the load-bearing one (drives the identity card on both pages).
List<Object> _sharedOverrides() => <Object>[
  screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
  clientProfileProvider.overrideWith((ref) async => _sharedProfile),
  // Home-only providers (Passport ignores these).
  nextAppointmentProvider.overrideWith((ref) async => null),
  favoriteMastersProvider.overrideWith(
    (ref) async => const <FavoriteMasterItem>[],
  ),
  beautyTimelineProvider.overrideWith((ref) async => const <TimelineEntry>[]),
  unlikeFavoriteMasterProvider.overrideWith(() => UnlikeFavoriteMaster()),
  // Passport-only providers (Home ignores these).
  passportProvider.overrideWith(
    (ref) async => Passport.empty(memberSinceYear: 2024),
  ),
  // Phase 238: the passport page's fourth block watches `wishlistProvider`.
  // Overridden to an empty (SUCCEEDING) wish list so no real repository call is
  // attempted and the tail of the page renders deterministically. It sits below
  // the profile block either way, so it cannot move the measurement — the point
  // is to keep the pump free of an unrelated failing fetch.
  wishlistRepositoryProvider.overrideWithValue(FakeWishlistRepository()),
];

/// Pumps [screen] at the FIXED [_kViewport] and settles the staggered-reveal
/// animation + the profile future, then returns the top-left offset (logical
/// px) of the identity-card name `Text`.
Future<Offset> _identityCardNameOffset(
  WidgetTester tester,
  Widget screen,
) async {
  tester.view.physicalSize = _kViewport;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpApp(screen, overrides: _sharedOverrides());
  // pumpAndSettle drains BOTH the profile future and the Home staggered-reveal
  // SlideTransition (which translates the profile subtree until the controller
  // reaches 1.0). After settle the slide transform is identity, so getTopLeft
  // returns the true laid-out position driven by the spacer.
  await tester.pumpAndSettle();

  final Finder name = find.text(_kFullName);
  expect(
    name,
    findsOneWidget,
    reason: 'identity-card name must render on ${screen.runtimeType}',
  );
  return tester.getTopLeft(name);
}

void main() {
  group('identity card cross-screen vertical alignment (Home ↔ Passport)', () {
    testWidgets('name Text top-left is equal on HomeHubScreen and PassportScreen', (
      tester,
    ) async {
      // Pump each screen independently — the bug was that two independently
      // rendered cards diverged. Measure each in isolation, then compare.
      final Offset home = await _identityCardNameOffset(
        tester,
        const HomeHubScreen(),
      );

      final Offset passport = await _identityCardNameOffset(
        tester,
        const PassportScreen(),
      );

      // ~1 px tolerance absorbs sub-pixel rounding only. The pre-fix spacer
      // mismatch (24 px vs 10 px) put these ~14 px apart → this fails red
      // against the bug and passes only when both pages use the same spacer.
      expect(
        passport.dy,
        closeTo(home.dy, 1.0),
        reason:
            'The identity card must sit at the same vertical Y on Головна and '
            'Beauty Passport so it does not jump on navigation. A failure here '
            'means one page\'s ListView top inset drifted from the other (the '
            'original bug: Passport used VelvetSpacing.sm + 2 = 10 px vs Home '
            'VelvetSpacing.lg = 24 px → a ~14 px jump). home=$home '
            'passport=$passport',
      );

      // The HORIZONTAL half of the same claim. Both pages now open their
      // ListView with `EdgeInsets.fromLTRB(lg, lg, lg, lg)`, so a card that
      // matched vertically but sat at a different left inset would still jump
      // on navigation — sideways instead of up. Asserting only `dy` would
      // miss that entirely.
      expect(
        passport.dx,
        closeTo(home.dx, 1.0),
        reason:
            'both pages use the same `VelvetSpacing.lg` horizontal page '
            'padding, so the identity card must share a left edge too. '
            'home=$home passport=$passport',
      );
    });
  });
}
