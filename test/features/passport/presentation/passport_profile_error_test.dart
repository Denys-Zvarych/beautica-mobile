// Phase 13.8 — BEAUTY PASSPORT profile-block ERROR state regression guard.
//
// WHY THIS FILE EXISTS
// --------------------
// `_ProfileBlock` used to render whatever `clientProfileProvider` handed it,
// and a FAILED profile fetch fell through to a synthesised all-empty
// `ClientProfileSummary`: an initial-less avatar plus the
// «Місто не вказано» / «Телефон не вказано» placeholder lines. A 401/500 was
// therefore pixel-identical to "this client has not filled in their details
// yet" — the SAME defect class as the always-empty passport bug that hid a
// broken data layer for a whole phase. `_ProfileError` closes that: a distinct
// glyph well + message + retry CTA laid out on `_ProfileBlock`'s own geometry.
//
// THE ASSERTION THAT MATTERS (group 4)
// ------------------------------------
// A `.when()`-shaped test would pass against a BROKEN branch order too, so it
// would be worthless here. `AsyncLoading(retrying: true)` SATISFIES `hasError`
// (Riverpod carries the previous error forward through the whole in-flight
// retry). If `hasError` were matched before `isLoading`, the error affordance
// would flash straight back the instant the client taps «Спробувати знову».
// The mid-retry group holds the second fetch open on a `Completer` so the
// in-flight window is deterministic rather than a race with a microtask, and
// asserts the error affordance is ABSENT inside it — which is exactly the
// assertion that goes RED when the two branches are swapped.
//
// RETRY POLICY IS PINNED PER TEST, NOT COPIED
// -------------------------------------------
// `beauticaProviderRetry` (the pumpApp default AND production's policy)
// classifies a 5xx `ServerFailure` as transient, so with it in force the
// element parks in `AsyncLoading(retrying: true)` through `pumpAndSettle` and
// NEVER reaches `AsyncError` — the surfaced error state would simply never
// render. Every test here is about the SURFACED error and the USER-driven
// retry behind the button, so the automatic policy is disabled with
// `retry: (_, _) => null`. Note this is a deliberate per-test choice: group 4
// still needs a retry IN FLIGHT, and it gets one from the `ref.invalidate`
// the button fires, not from the provider-level policy.
//
// The fixture throws from an `async` body (never a bare `thenThrow`): a sync
// throw during provider build bypasses Riverpod's retry machinery entirely,
// so it would model a failure shape a Dio-backed repository can never produce.
//
// PHASE 238 — THE PAGE GREW A FOURTH BLOCK
// ----------------------------------------
// `WishlistSection` now sits under the passport section and watches
// `wishlistProvider`. Its repository MUST be overridden here (see [_overrides]):
// left live it fails its fetch and renders a second `cloud_off` failure card,
// which silently changes what every glyph assertion in this file measures.

import 'dart:async';

import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/features/home/application/home_hub_notifier.dart';
import 'package:beautica_mobile/features/home/domain/home_hub_models.dart';
import 'package:beautica_mobile/features/passport/application/passport_notifier.dart';
import 'package:beautica_mobile/features/passport/domain/passport.dart';
import 'package:beautica_mobile/features/passport/presentation/passport_screen.dart';
import 'package:beautica_mobile/features/wishlist/application/wishlist_notifier.dart';
import 'package:beautica_mobile/features/wishlist/domain/wishlist_service.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fakes/fake_wishlist_repository.dart';
import '../../../helpers/overflow_guard.dart';
import '../../../helpers/pump_app.dart';

// ---------------------------------------------------------------------------
// Keys under test.
// ---------------------------------------------------------------------------

const Key _kProfileErrorState = Key('passport_profile_error_state');
const Key _kProfileRetryButton = Key('passport_profile_retry_button');

/// Rendered ONLY by `_ProfileBlock` (the camera badge on the avatar), so its
/// presence/absence is a precise proxy for "the populated profile block is on
/// screen" without reaching into a private widget type.
const Key _kProfileBlockMarker = Key('passport_change_photo_button');

// ---------------------------------------------------------------------------
// Fixture. The name is hoisted into a constant rather than inlined into a
// finder: `scripts/forbid_cyrillic_finder.sh` (rightly) rejects a
// `find.text('<Cyrillic literal>')`, which couples a test to the UA locale
// shipping. Asserting through the constant keeps the finder locale-decoupled
// at the call site, and the phone below is locale-invariant ASCII data — it is
// the specific loaded value the retry test binds against, so the test proves
// real data reached the widget rather than merely that "something rendered".
// ---------------------------------------------------------------------------

const String _kProfileName = 'Олена Тест';
const String _kProfilePhone = '+380 97 000 00 00';

const _sampleProfile = ClientProfileSummary(
  firstName: 'Олена',
  lastName: 'Тест',
  city: 'Львів',
  phone: _kProfilePhone,
  clientRating: null,
  memberSinceYear: 2024,
);

const _populatedPassport = Passport(
  favoriteProcedures: <String>['Манікюр', 'Брови', 'Педикюр'],
  favoriteDistricts: <String>['Центр', 'Сихів', 'Франківський'],
  favoriteCities: <String>['Львів', 'Київ'],
  budget: BudgetBand(avg: 600, min: 400, max: 800),
  bookingsConsidered: 7,
  reviewsWritten: 5,
  // A WIRE value; nothing in this file reads a clock.
  memberSinceYear: 2024,
);

/// Two saved favourites, so the page's fourth block renders its HAPPY state and
/// contributes no failure glyph of its own — see [_overrides].
const List<WishlistService> _kFavourites = <WishlistService>[
  WishlistService(
    masterServiceId: 'w1',
    masterId: 'm-w1',
    serviceName: 'Ламінування та фарбування брів',
    masterName: 'Анастасія Мельниченко',
    durationMinutes: 150,
    priceDisplay: '1 200 ₴',
  ),
  WishlistService(
    masterServiceId: 'w2',
    masterId: 'm-w2',
    serviceName: 'Манікюр з покриттям гель-лак',
    masterName: 'Ірина Бондаренко',
    durationMinutes: 90,
    priceDisplay: '600–900 ₴',
  ),
];

/// A never-failing passport AND a never-failing wish list, so the ONLY failure
/// on screen is the profile.
///
/// THE WISH-LIST OVERRIDE IS NOT OPTIONAL (Phase 238). `WishlistSection` watches
/// `wishlistProvider`, which resolves through the real `HttpWishlistRepository`
/// unless the repository is overridden — so without this the section fails its
/// fetch and paints `WishlistErrorState`, which draws a SECOND
/// `Icons.cloud_off_rounded` onto the page. That is exactly how this file broke
/// when the page gained its fourth block: `find.byIcon(Icons.cloud_off_rounded)`
/// started reporting two widgets and the profile-error assertion became an
/// assertion about an unrelated block's failure.
List<Object> _overrides(
  Future<ClientProfileSummary> Function(Ref ref) profile,
) => <Object>[
  screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
  clientProfileProvider.overrideWith(profile),
  passportProvider.overrideWith((ref) async => _populatedPassport),
  wishlistRepositoryProvider.overrideWithValue(
    FakeWishlistRepository(services: _kFavourites),
  ),
];

/// The native FLAG_SECURE plugin must never fire under `flutter test`.
class _NoOpScreenProtection extends ScreenProtectionManager {
  @override
  void acquire() {}

  @override
  void release() {}

  @override
  void reset() {}
}

Future<AppLocalizations> _uk() =>
    AppLocalizations.delegate.load(const Locale('uk'));

void main() {
  // -------------------------------------------------------------------------
  // 1. A failed profile fetch surfaces the error affordance and NEVER the
  //    blank-field profile block.
  // -------------------------------------------------------------------------
  group('PassportScreen profile — failed fetch surfaces the error state', () {
    testWidgets(
      'renders the profile error affordance, NOT a blank-field profile block',
      (tester) async {
        await tester.pumpApp(
          const PassportScreen(),
          overrides: _overrides(
            (ref) async => throw const ServerFailure(statusCode: 500),
          ),
          retry: (_, _) => null,
        );
        await tester.pumpAndSettle();

        final AppLocalizations l10n = await _uk();

        // The affordance itself: distinct state + a real retry CTA.
        expect(find.byKey(_kProfileErrorState), findsOneWidget);
        expect(find.byKey(_kProfileRetryButton), findsOneWidget);
        // DISAMBIGUATED (Phase 238). Every failure state on this page draws
        // `Icons.cloud_off_rounded` — the profile error, the passport error and
        // the wish-list error. A bare `findsOneWidget` on the glyph is
        // therefore not a statement about WHICH block failed, so the finder is
        // scoped to the state under test AND the page-wide count is asserted
        // separately (it is 1 only because the other two blocks are overridden
        // to succeed).
        expect(
          find.descendant(
            of: find.byKey(_kProfileErrorState),
            matching: find.byIcon(Icons.cloud_off_rounded),
          ),
          findsOneWidget,
        );
        expect(
          find.byIcon(Icons.cloud_off_rounded),
          findsOneWidget,
          reason:
              'only the PROFILE failed, so exactly one cloud_off may be on the '
              'page — a second one means another provider is failing silently '
              '(an un-overridden wishlistRepositoryProvider is the usual cause)',
        );
        expect(find.text(l10n.homeHubProfileLoadError), findsOneWidget);
        expect(find.text(l10n.retryLabel), findsOneWidget);

        // THE REGRESSION. A failure must not degrade to the profile block at
        // all — and specifically not to its placeholder lines, which read as
        // "no details yet" and are what made the old failure invisible.
        expect(
          find.byKey(_kProfileBlockMarker),
          findsNothing,
          reason:
              'a failed profile fetch must not render the profile block — a '
              'blank-field block is visually indistinguishable from "this '
              'client has no details yet", which is the bug this guards',
        );
        expect(
          find.text(l10n.homeHubLocationPlaceholder),
          findsNothing,
          reason:
              'the «city not set» placeholder is the exact blank-field '
              'degrade the error state replaces',
        );
        expect(
          find.text(l10n.homeHubPhonePlaceholder),
          findsNothing,
          reason:
              'the «phone not set» placeholder is the exact blank-field '
              'degrade the error state replaces',
        );
        expect(find.text(_kProfileName), findsNothing);
        expect(find.text(_kProfilePhone), findsNothing);

        // The passport hero is unaffected — only the profile sub-block failed.
        expect(find.byKey(const Key('passport_error_state')), findsNothing);
      },
    );
  });

  // -------------------------------------------------------------------------
  // 2. No overflow. `_ProfileError` occupies `_ProfileBlock`'s footprint (a
  //    100 dp slot + an Expanded column carrying a STRETCHED CTA), so it is
  //    exactly the kind of Row that overflows on a narrow surface at a large
  //    accessibility text scale. Surface height is set explicitly rather than
  //    via `pumpApp(width:)` — that knob forces a 2400 dp height, which gives
  //    the non-scrolling Column so much slack that no short-phone cell ever
  //    reproduces the squeeze (same reasoning as
  //    passport_screen_overflow_test.dart).
  // -------------------------------------------------------------------------
  group('PassportScreen profile error — overflow matrix', () {
    const List<(String, double, double, double)> matrix =
        <(String, double, double, double)>[
          ('small-phone 320x568', 320, 568, 1.0),
          ('compact 360x640', 360, 640, 1.0),
          ('baseline 390x844', 390, 844, 1.0),
          ('baseline 390x844 @1.3x', 390, 844, 1.3),
          ('baseline 390x844 @1.5x', 390, 844, 1.5),
          ('ultra-narrow 280x653', 280, 653, 1.0),
          ('360x640 @2.0x (a11y largest font)', 360, 640, 2.0),
        ];

    for (final (String label, double w, double h, double scale) in matrix) {
      testWidgets('no overflow at $label (profile error)', (tester) async {
        installOverflowGuard();

        tester.view.physicalSize = Size(w, h);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          ProviderScope(
            // Automatic retry OFF so the element actually reaches AsyncError
            // and the state under test is on screen to be measured.
            retry: (_, _) => null,
            overrides: _overrides(
              (ref) async => throw const ServerFailure(statusCode: 500),
            ).cast(),
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: const Locale('uk'),
              home: MediaQuery(
                data: MediaQueryData(
                  size: Size(w, h),
                  textScaler: TextScaler.linear(scale),
                ),
                child: const PassportScreen(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(_kProfileErrorState),
          findsOneWidget,
          reason: 'the state under measurement must actually be on screen',
        );
        expect(
          tester.takeException(),
          isNull,
          reason:
              '_ProfileError (100 dp glyph slot + stretched retry CTA) must '
              'not overflow at $label',
        );
      });
    }
  });

  // -------------------------------------------------------------------------
  // 3. Retry re-runs the provider and reaches the POPULATED block.
  // -------------------------------------------------------------------------
  group('PassportScreen profile error — retry recovers', () {
    testWidgets('tapping retry re-runs the fetch and renders the profile', (
      tester,
    ) async {
      int attempts = 0;
      await tester.pumpApp(
        const PassportScreen(),
        overrides: _overrides((ref) async {
          attempts++;
          if (attempts == 1) throw const ServerFailure(statusCode: 500);
          return _sampleProfile;
        }),
        retry: (_, _) => null,
      );
      await tester.pumpAndSettle();

      expect(attempts, 1);
      expect(find.byKey(_kProfileErrorState), findsOneWidget);

      await tester.tap(find.byKey(_kProfileRetryButton));
      await tester.pumpAndSettle();

      // The provider genuinely re-ran (call count moved) AND the populated
      // block is on screen carrying its real data — not merely "the error is
      // gone", which a silent collapse would also satisfy.
      expect(
        attempts,
        2,
        reason: 'retry must re-run clientProfileProvider, not just repaint',
      );
      expect(find.byKey(_kProfileErrorState), findsNothing);
      expect(find.byKey(_kProfileBlockMarker), findsOneWidget);
      expect(find.text(_kProfileName), findsOneWidget);
      expect(find.text(_kProfilePhone), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  // 4. THE ONE THAT MATTERS — the error affordance is ABSENT mid-retry.
  //
  // `ref.invalidate` puts the provider back into `AsyncLoading` while it STILL
  // CARRIES the previous error, so `hasError` stays TRUE for the whole
  // in-flight retry. Only matching `isLoading` FIRST keeps the error state off
  // screen; a `hasError`-first order (or a `.when()`) flashes it straight back
  // under the client's finger.
  //
  // MUTATION-PROVEN: swapping the `isLoading` / `hasError` branches in
  // passport_screen.dart makes THIS test — and only this shape of test — go
  // red. The second fetch is held open on a Completer so the in-flight window
  // is deterministic and not a race with a microtask that might already have
  // resolved by the first pump.
  // -------------------------------------------------------------------------
  group('PassportScreen profile error — mid-retry does NOT flash back', () {
    testWidgets('error affordance is absent while the retry is in flight', (
      tester,
    ) async {
      final Completer<ClientProfileSummary> gate =
          Completer<ClientProfileSummary>();
      int attempts = 0;

      await tester.pumpApp(
        const PassportScreen(),
        overrides: _overrides((ref) async {
          attempts++;
          if (attempts == 1) throw const ServerFailure(statusCode: 500);
          // Held open — the retry stays in flight until the test releases it.
          return gate.future;
        }),
        retry: (_, _) => null,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(_kProfileErrorState), findsOneWidget);

      await tester.tap(find.byKey(_kProfileRetryButton));
      await tester.pump();

      // ── IN FLIGHT ────────────────────────────────────────────────────────
      expect(attempts, 2, reason: 'the retry must actually be in flight');
      expect(gate.isCompleted, isFalse, reason: 'the fetch is still pending');
      expect(
        find.byKey(_kProfileErrorState),
        findsNothing,
        reason:
            'AsyncLoading(retrying) still reports hasError — matching '
            'hasError before isLoading would flash the error state back the '
            'instant the client taps retry',
      );
      expect(
        find.byKey(_kProfileRetryButton),
        findsNothing,
        reason: 'the retry CTA must not be re-offered mid-retry',
      );

      // Still absent after further frames inside the same in-flight window —
      // proves the assertion is not a one-frame coincidence.
      //
      // There is no condition to pump UNTIL — the assertion is that NOTHING
      // appears — and `pumpAndSettle` would deadlock on the pending future.
      // The Completer holds the fetch open for the whole window, so any
      // duration lands inside it and the wait cannot be flaky.
      // fixed-wait-ok: absence assertion inside a Completer-held window.
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(_kProfileErrorState), findsNothing);
      expect(gate.isCompleted, isFalse);

      // ── RELEASED ─────────────────────────────────────────────────────────
      gate.complete(_sampleProfile);
      await tester.pumpAndSettle();

      expect(find.byKey(_kProfileErrorState), findsNothing);
      expect(find.byKey(_kProfileBlockMarker), findsOneWidget);
      expect(find.text(_kProfileName), findsOneWidget);
    });

    testWidgets(
      'a retry that fails AGAIN returns to the error state (not stuck loading)',
      (tester) async {
        // The mirror of the test above: proving the affordance is hidden
        // mid-retry is only half the contract — it must COME BACK when the
        // retry genuinely fails, or a permanently-broken profile would sit on
        // an endless skeleton with no way out.
        int attempts = 0;
        await tester.pumpApp(
          const PassportScreen(),
          overrides: _overrides((ref) async {
            attempts++;
            throw const ServerFailure(statusCode: 500);
          }),
          retry: (_, _) => null,
        );
        await tester.pumpAndSettle();
        expect(find.byKey(_kProfileErrorState), findsOneWidget);

        await tester.tap(find.byKey(_kProfileRetryButton));
        await tester.pumpAndSettle();

        expect(attempts, 2);
        expect(find.byKey(_kProfileErrorState), findsOneWidget);
        expect(find.byKey(_kProfileRetryButton), findsOneWidget);
        expect(find.byKey(_kProfileBlockMarker), findsNothing);
      },
    );
  });

  // -------------------------------------------------------------------------
  // Sanity: the production retry policy is NOT what surfaces this state.
  // Documents WHY every test above pins `retry: (_, _) => null` — under the
  // real policy a 5xx is transient, so the element stays in
  // AsyncLoading(retrying: true) and the error affordance never appears.
  // Without this, a future reader "cleaning up" the retry override would
  // silently turn the whole file green-for-the-wrong-reason.
  // -------------------------------------------------------------------------
  group('PassportScreen profile error — production retry policy', () {
    testWidgets(
      'under beauticaProviderRetry a 5xx stays retrying, so no error affordance',
      (tester) async {
        await tester.pumpApp(
          const PassportScreen(),
          overrides: _overrides(
            (ref) async => throw const ServerFailure(statusCode: 500),
          ),
          // Explicitly the production predicate (also pumpApp's default).
          retry: beauticaProviderRetry,
        );
        await tester.pump();
        // Asserting an ABSENCE, so there is nothing to pump until; and
        // pumpAndSettle is unusable by construction — under the production
        // policy the provider keeps retrying, which is the behaviour under
        // test. Any duration inside the retry window proves the same thing,
        // so the exact value cannot make this flaky.
        // fixed-wait-ok: absence assertion inside the provider retry window.
        await tester.pump(const Duration(milliseconds: 100));

        expect(
          find.byKey(_kProfileErrorState),
          findsNothing,
          reason:
              'beauticaProviderRetry classifies a 5xx ServerFailure as '
              'transient, so the element parks in AsyncLoading(retrying) and '
              'never reaches AsyncError — which is exactly why the tests '
              'above disable it rather than inheriting the default',
        );
      },
    );
  });
}
