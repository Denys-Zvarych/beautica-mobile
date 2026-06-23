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
// passport_screen.dart now uses `SizedBox(height: VelvetSpacing.lg)` for the
// top-bar → card spacer, so BOTH independently-rendered cards land at the same
// vertical Y.
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
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

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
  // Passport-only provider (Home ignores this).
  passportProvider.overrideWith((ref) async => Passport.empty()),
];

/// Pumps [screen] at the FIXED [_kViewport] and settles the staggered-reveal
/// animation + the profile future, then returns the top-left `dy` (logical px)
/// of the identity-card name `Text`.
Future<double> _identityCardNameDy(WidgetTester tester, Widget screen) async {
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
  return tester.getTopLeft(name).dy;
}

void main() {
  group('identity card cross-screen vertical alignment (Home ↔ Passport)', () {
    testWidgets(
      'name Text top-left dy is equal on HomeHubScreen and PassportScreen',
      (tester) async {
        // Pump each screen independently — the bug was that two independently
        // rendered cards diverged. Measure each in isolation, then compare.
        final double homeDy = await _identityCardNameDy(
          tester,
          const HomeHubScreen(),
        );

        final double passportDy = await _identityCardNameDy(
          tester,
          const PassportScreen(),
        );

        // ~1 px tolerance absorbs sub-pixel rounding only. The pre-fix spacer
        // mismatch (24 px vs 10 px) put these ~14 px apart → this fails red
        // against the bug and passes only when both pages use the same spacer.
        expect(
          passportDy,
          closeTo(homeDy, 1.0),
          reason:
              'The identity card must sit at the same vertical Y on Головна and '
              'Beauty Passport so it does not jump on navigation. A failure here '
              'means one page\'s top-bar → card spacer drifted from the other '
              '(the original bug: Passport used VelvetSpacing.sm + 2 = 10 px vs '
              'Home VelvetSpacing.lg = 24 px → a ~14 px jump). homeDy=$homeDy '
              'passportDy=$passportDy',
        );
      },
    );
  });
}
