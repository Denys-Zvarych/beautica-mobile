// Phase 238 — BEAUTY PASSPORT page ([PassportScreen]) widget tests.
//
// WHAT THE PAGE IS NOW
// --------------------
// A scrolling `ListView` inside a `StaggeredReveal`, four blocks:
//   1. profile block          (own Consumer on `clientProfileProvider`)
//   2+3. identity strip + derived block (own Consumer on `passportProvider`)
//   4. BEAUTY WISH LIST       (`WishlistSection`, watches `wishlistProvider`)
//
// The full-page "document" card (`passport_table.dart` / `PassportCard`) and the
// `_EmptyPassport` invitation hero — with its `passport_find_master_button` —
// are DELETED, not unrouted. The wish list's own empty state now carries the
// «Знайти майстра» invitation, so the assertions that used to pin the hero are
// gone rather than re-pointed: there is no second CTA to assert.
//
// EVERY TEST HERE OVERRIDES `wishlistRepositoryProvider`
// -----------------------------------------------------
// `WishlistSection` watches `wishlistProvider`, which resolves through the real
// `HttpWishlistRepository` unless the repository is overridden. Without an
// override the section fails its fetch and renders `WishlistErrorState` — which
// draws a SECOND `Icons.cloud_off_rounded` on a page that already has one per
// failed block. That is not a cosmetic nuisance: it silently turns every
// icon-count assertion on this page into a different assertion. So the override
// is part of the base `_overrides()` and never optional.
//
// THE THREE CONTRACTS THIS FILE EXISTS TO PIN
// -------------------------------------------
//  A. THE ASYNC BRANCH ORDER IS EXPLICIT: `isLoading` → `hasError` → value.
//     `AsyncLoading(retrying: true)` STILL reports `hasError`, so a
//     `hasError`-first order (or a `.when()`) paints the failure straight back
//     under the client's finger the instant they tap retry. Pinned with a
//     Completer-held in-flight window, which is the only shape that goes red
//     when the branches are swapped.
//  B. AN ERROR NEVER DEGRADES INTO A NO-DATA RENDERING. A failed fetch and "no
//     history yet" must be different pixels — collapsing them is what let the
//     always-empty passport bug hide for a whole phase. With the empty hero
//     gone, the assertion is now that a failed passport renders its ERROR card
//     and NOT the identity strip / derived block.
//  C. THE PROFILE AND THE PASSPORT FAIL SEPARATELY, with distinct affordances
//     (`passport_profile_error_state` vs `passport_error_state`), because they
//     are separate Consumers on separate providers.
//
// CLOCK: `memberSinceYear` and `reviewsWritten` are WIRE values on
// `Passport`, so every fixture here is a literal int. Nothing reads
// `DateTime.now()`.

import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/features/home/application/home_hub_notifier.dart';
import 'package:beautica_mobile/features/home/domain/home_hub_models.dart';
import 'package:beautica_mobile/features/passport/application/passport_notifier.dart';
import 'package:beautica_mobile/features/passport/domain/passport.dart';
import 'package:beautica_mobile/features/passport/presentation/passport_screen.dart';
import 'package:beautica_mobile/features/passport/presentation/widgets/passport_derived_block.dart';
import 'package:beautica_mobile/features/passport/presentation/widgets/passport_identity_strip.dart';
import 'package:beautica_mobile/features/wishlist/application/wishlist_notifier.dart';
import 'package:beautica_mobile/features/wishlist/domain/wishlist_service.dart';
import 'package:beautica_mobile/features/wishlist/presentation/widgets/wishlist_compact_card.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fakes/fake_wishlist_repository.dart';
import '../../../helpers/pump_app.dart';

// ---------------------------------------------------------------------------
// Keys
// ---------------------------------------------------------------------------

const Key _kIdentityStrip = Key('passport_identity_strip');
const Key _kDerivedBlock = Key('passport_derived_block');
const Key _kPassportError = Key('passport_error_state');
const Key _kPassportRetry = Key('passport_retry_button');
const Key _kPassportSkeleton = Key('passport_skeleton');
const Key _kProfileError = Key('passport_profile_error_state');
const Key _kProfileRetry = Key('passport_profile_retry_button');
const Key _kProfileBlockMarker = Key('passport_change_photo_button');
const Key _kWishlistEmpty = Key('wishlist_empty_state');
const Key _kWishlistError = Key('wishlist_error_state');
const Key _kWishlistShowAll = Key('wishlist_show_all_button');

// ---------------------------------------------------------------------------
// Fixtures. Hoisted to constants so no finder carries a Cyrillic literal at the
// call site (`scripts/forbid_cyrillic_finder.sh`) and so fixture and assertion
// cannot drift.
// ---------------------------------------------------------------------------

const String _kProfileName = 'Олена Тест';
const String _kProfileCity = 'Львів';
const String _kProfilePhone = '+380 97 000 00 00';

const _sampleProfile = ClientProfileSummary(
  firstName: 'Олена',
  lastName: 'Тест',
  city: _kProfileCity,
  phone: _kProfilePhone,
  clientRating: null,
  memberSinceYear: 2024,
);

/// Worst-case derived values, from the approved preview's `PassportSampleData`.
const List<String> _kDistricts = <String>[
  'Шевченківський',
  'Голосіївський',
  'Печерський',
];
const List<String> _kCities = <String>['Київ', 'Бровари'];

const int _kBudgetAvg = 750;
const int _kReviewsWritten = 12;

/// Deliberately not the current year: a screen that re-derived the join year
/// from the clock could not produce it.
const int _kMemberSinceYear = 2021;

const _populatedPassport = Passport(
  favoriteDistricts: _kDistricts,
  favoriteCities: _kCities,
  // `max` differs from `avg`, so a screen still reading the CEILING renders 900
  // and fails rather than passing on a coincidence.
  budget: BudgetBand(avg: 750, min: 400, max: 900),
  bookingsConsidered: 7,
  reviewsWritten: _kReviewsWritten,
  memberSinceYear: _kMemberSinceYear,
);

/// A passport with history but NOTHING derivable — no locality, no spend band.
/// Reachable in production: the derivation ran (bookings were considered) and
/// produced nothing statable.
const _noDerivedDataPassport = Passport(
  favoriteDistricts: <String>[],
  favoriteCities: <String>[],
  budget: null,
  bookingsConsidered: 4,
  reviewsWritten: 3,
  memberSinceYear: _kMemberSinceYear,
);

/// The preview's worst-case wish list: the longest realistic service and master
/// names, one FIXED price and one RANGE.
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

final List<WishlistService> _kFiveFavourites = <WishlistService>[
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
    priceDisplay: '700–1100 ₴',
    isRange: true,
    priceMin: 700,
    priceMax: 1100,
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

// ---------------------------------------------------------------------------
// Overrides
// ---------------------------------------------------------------------------

/// The base override set. NOTE the wish-list repository is ALWAYS overridden —
/// see the file header for why an un-overridden one silently changes what every
/// other assertion on this page means.
List<Object> _overrides({
  required Passport passport,
  ClientProfileSummary profile = _sampleProfile,
  ScreenProtectionManager? protection,
  List<WishlistService> wishlist = const <WishlistService>[],
  Failure? wishlistFailure,
}) => <Object>[
  screenProtectionProvider.overrideWithValue(
    protection ?? _NoOpScreenProtection(),
  ),
  clientProfileProvider.overrideWith((ref) async => profile),
  passportProvider.overrideWith((ref) async => passport),
  wishlistRepositoryProvider.overrideWithValue(
    FakeWishlistRepository(services: wishlist, failure: wishlistFailure),
  ),
];

Future<AppLocalizations> _uk() =>
    AppLocalizations.delegate.load(const Locale('uk'));

void main() {
  // -------------------------------------------------------------------------
  // 1. Chrome + profile.
  // -------------------------------------------------------------------------
  group('PassportScreen — chrome + profile block', () {
    testWidgets('body renders WITHOUT the top bar (bar is shell-owned)', (
      tester,
    ) async {
      // The top bar (wordmark · bell · burger) is mounted by ClientShell above
      // the branch body, NOT by PassportScreen. Its per-branch config is pinned
      // in test/features/shell/client_shell_top_bar_test.dart.
      await tester.pumpApp(
        const PassportScreen(),
        overrides: _overrides(passport: _populatedPassport),
      );
      await tester.pumpAndSettle();

      expect(find.text('beautica'), findsNothing);
      expect(find.byKey(const Key('passport_bell_button')), findsNothing);
      expect(find.byKey(const Key('btn-menu-passport')), findsNothing);
      // i18n-finder-ok: the profile name is fixture DATA, not AppLocalizations.
      expect(find.text(_kProfileName), findsOneWidget);
    });

    testWidgets('renders the profile name, city and phone', (tester) async {
      await tester.pumpApp(
        const PassportScreen(),
        overrides: _overrides(passport: _populatedPassport),
      );
      await tester.pumpAndSettle();

      // i18n-finder-ok: all three are fixture DATA off the profile provider.
      expect(find.text(_kProfileName), findsOneWidget);
      expect(find.text(_kProfileCity), findsOneWidget);
      expect(find.text(_kProfilePhone), findsOneWidget);
    });

    testWidgets('profile location line has NO chevron (design dropped it)', (
      tester,
    ) async {
      await tester.pumpApp(
        const PassportScreen(),
        overrides: _overrides(passport: _populatedPassport),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.expand_more), findsNothing);
      expect(find.byIcon(Icons.expand_more_rounded), findsNothing);
      expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
    });
  });

  // -------------------------------------------------------------------------
  // 2. Identity strip + derived block (the PassportCard's replacements).
  // -------------------------------------------------------------------------
  group('PassportScreen — identity strip + derived block', () {
    testWidgets(
      'renders the untranslated "BEAUTY PASSPORT" title and Ukrainian subtitle',
      (tester) async {
        await tester.pumpApp(
          const PassportScreen(),
          overrides: _overrides(passport: _populatedPassport),
        );
        await tester.pumpAndSettle();

        // Asserted against the exported constants so the test proves these are
        // NOT routed through l10n.
        expect(kBeautyPassportTitle, 'BEAUTY PASSPORT');
        expect(find.byKey(_kIdentityStrip), findsOneWidget);
        expect(find.text(kBeautyPassportTitle), findsOneWidget);
        expect(find.text(kBeautyPassportSubtitle), findsOneWidget);
      },
    );

    testWidgets('renders the derived standing from the WIRE, not the clock', (
      tester,
    ) async {
      await tester.pumpApp(
        const PassportScreen(),
        overrides: _overrides(passport: _populatedPassport),
      );
      await tester.pumpAndSettle();

      final AppLocalizations l10n = await _uk();
      expect(
        find.text(l10n.passportReviewsLeft(_kReviewsWritten)),
        findsOneWidget,
      );
      expect(
        find.text(l10n.passportMemberSince('$_kMemberSinceYear')),
        findsOneWidget,
      );
    });

    testWidgets('renders every derived district and city name', (tester) async {
      await tester.pumpApp(
        const PassportScreen(),
        overrides: _overrides(passport: _populatedPassport),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(_kDerivedBlock), findsOneWidget);
      // i18n-finder-ok: locality names are backend-derived DATA off the passport
      // fixture, identical in every locale.
      for (final String name in <String>[..._kDistricts, ..._kCities]) {
        expect(
          find.text(name),
          findsOneWidget,
          reason: 'derived locality «$name» must render',
        );
      }
    });

    testWidgets('renders the budget AVERAGE, never the ceiling', (
      tester,
    ) async {
      await tester.pumpApp(
        const PassportScreen(),
        overrides: _overrides(passport: _populatedPassport),
      );
      await tester.pumpAndSettle();

      final AppLocalizations l10n = await _uk();
      expect(
        find.text(l10n.passportBudgetAverage(_kBudgetAvg)),
        findsOneWidget,
      );
      // The fixture's max (900) differs from its avg, so a screen still wired
      // to `.max` fails here instead of passing on a coincidence.
      expect(find.text(l10n.passportBudgetAverage(900)), findsNothing);
      expect(find.text(l10n.passportBudgetUnknown), findsNothing);
    });

    testWidgets('should_omitDerivedBlock_when_neitherLocalityNorAverageKnown', (
      tester,
    ) async {
      // `PassportDerivedBlock.hasContent` is false ⇒ the CALLER drops the whole
      // block rather than rendering an empty card with two dead eyebrows.
      await tester.pumpApp(
        const PassportScreen(),
        overrides: _overrides(passport: _noDerivedDataPassport),
      );
      await tester.pumpAndSettle();

      final AppLocalizations l10n = await _uk();

      expect(
        find.byKey(_kDerivedBlock),
        findsNothing,
        reason:
            'with no locality history AND no spend band there is nothing to '
            'report — the block is omitted, not rendered empty',
      );
      expect(find.byType(PassportDerivedBlock), findsNothing);
      expect(
        find.text(l10n.passportLocalitiesLabel.toUpperCase()),
        findsNothing,
      );
      expect(
        find.text(l10n.passportAverageSpendLabel.toUpperCase()),
        findsNothing,
      );

      // The identity strip STAYS: it is meaningful for a client with no derived
      // history, which is exactly why this page needs no empty hero.
      expect(
        find.byKey(_kIdentityStrip),
        findsOneWidget,
        reason:
            'the strip carries the client standing regardless of derived data '
            '— dropping it too would recreate the deleted empty hero',
      );
      expect(find.text(l10n.passportReviewsLeft(3)), findsOneWidget);
      expect(find.byKey(_kPassportError), findsNothing);
    });

    testWidgets(
      'POSITIVE CONTROL: a locality-only passport still renders the block',
      (tester) async {
        // Guards the omission test above from passing because the block never
        // renders at all.
        await tester.pumpApp(
          const PassportScreen(),
          overrides: _overrides(
            passport: _noDerivedDataPassport.copyWith(
              favoriteDistricts: _kDistricts,
            ),
          ),
        );
        await tester.pumpAndSettle();

        final AppLocalizations l10n = await _uk();
        expect(find.byKey(_kDerivedBlock), findsOneWidget);
        // i18n-finder-ok: backend-derived locality DATA, not UI copy.
        expect(find.text(_kDistricts.first), findsOneWidget);
        // No spend band ⇒ the bare «—», never a fabricated figure.
        expect(
          find.byKey(const Key('passport_average_unknown')),
          findsOneWidget,
        );
        expect(find.text(l10n.passportBudgetUnknown), findsOneWidget);
      },
    );

    testWidgets('the deleted document card leaves NO trace on the page', (
      tester,
    ) async {
      // `passport_table.dart` (`PassportCard`) and the `_EmptyPassport` hero are
      // GONE, not unrouted. Nothing on this page may still offer the hero's CTA
      // or the retired «+ Додати ще» affordance.
      await tester.pumpApp(
        const PassportScreen(),
        overrides: _overrides(passport: _populatedPassport),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('passport_find_master_button')),
        findsNothing,
        reason:
            'the empty hero and its CTA key were deleted in Phase 238 — the '
            'wish list\'s own empty state carries the invitation now',
      );
      expect(find.textContaining('Додати'), findsNothing);
    });
  });

  // -------------------------------------------------------------------------
  // 3. PASSPORT ERROR — a distinct state, never a degrade, and never flashed
  //    back mid-retry.
  // -------------------------------------------------------------------------
  group('PassportScreen — passport error state', () {
    testWidgets(
      'a failed fetch renders the ERROR card, NOT a no-data rendering',
      (tester) async {
        await tester.pumpApp(
          const PassportScreen(),
          overrides: <Object>[
            screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
            clientProfileProvider.overrideWith((ref) async => _sampleProfile),
            passportProvider.overrideWith(
              // Thrown from an ASYNC body, never `thenThrow`: a synchronous
              // throw during provider build bypasses Riverpod's retry machinery
              // entirely and models a shape a Dio-backed repository cannot
              // produce.
              (ref) async => throw const ServerFailure(statusCode: 500),
            ),
            wishlistRepositoryProvider.overrideWithValue(
              FakeWishlistRepository(services: _kFiveFavourites),
            ),
          ],
          // Retry OFF. `beauticaProviderRetry` (the pumpApp default AND
          // production's policy) classifies a 5xx as transient, so the element
          // would park in AsyncLoading(retrying: true) — which STILL reports
          // hasError — through pumpAndSettle and never reach AsyncError. This
          // test is about the SURFACED error, so the automatic retry is off and
          // the USER-driven one is exercised below.
          retry: (_, _) => null,
        );
        await tester.pumpAndSettle();

        final AppLocalizations l10n = await _uk();
        expect(find.byKey(_kPassportError), findsOneWidget);
        expect(find.text(l10n.passportErrorTitle), findsOneWidget);
        expect(find.text(l10n.passportErrorBody), findsOneWidget);
        expect(find.byKey(_kPassportRetry), findsOneWidget);

        // THE REGRESSION. A failure must NOT degrade into "nothing derived
        // yet": with the empty hero deleted, that degrade would look like a
        // strip-less, block-less page — indistinguishable from a brand-new
        // account.
        expect(
          find.byKey(_kIdentityStrip),
          findsNothing,
          reason:
              'an errored passport must not render the identity strip — a '
              'strip full of zeroes reads as "new client", which is exactly '
              'the collapse that hid the broken data layer for a whole phase',
        );
        expect(find.byKey(_kDerivedBlock), findsNothing);
        expect(find.byKey(_kPassportSkeleton), findsNothing);

        // The other two blocks are unaffected — separate Consumers.
        expect(find.byKey(_kProfileBlockMarker), findsOneWidget);
        expect(find.byKey(_kProfileError), findsNothing);
        expect(find.byType(WishlistCompactCard), findsNWidgets(2));
      },
    );

    testWidgets('tapping retry re-runs the fetch and shows the passport', (
      tester,
    ) async {
      int attempt = 0;
      await tester.pumpApp(
        const PassportScreen(),
        overrides: <Object>[
          screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
          clientProfileProvider.overrideWith((ref) async => _sampleProfile),
          passportProvider.overrideWith((ref) async {
            attempt++;
            if (attempt == 1) throw const ServerFailure(statusCode: 500);
            return _populatedPassport;
          }),
          wishlistRepositoryProvider.overrideWithValue(
            FakeWishlistRepository(services: _kFiveFavourites),
          ),
        ],
        retry: (_, _) => null,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(_kPassportError), findsOneWidget);

      await tester.tap(find.byKey(_kPassportRetry));
      await tester.pumpAndSettle();

      expect(attempt, 2, reason: 'retry must re-run the provider');
      expect(find.byKey(_kPassportError), findsNothing);
      expect(find.byKey(_kIdentityStrip), findsOneWidget);
      expect(find.byKey(_kDerivedBlock), findsOneWidget);
    });

    testWidgets(
      'THE BRANCH ORDER: the error card is ABSENT while a retry is in flight',
      (tester) async {
        // `ref.invalidate` puts the provider back into AsyncLoading while it
        // STILL CARRIES the previous error, so `hasError` stays TRUE for the
        // whole in-flight retry. Only matching `isLoading` FIRST keeps the error
        // card off screen; a `hasError`-first order (or a `.when()`) flashes it
        // straight back under the client's finger.
        //
        // The second fetch is held open on a Completer so the in-flight window
        // is deterministic rather than a race with a microtask.
        final Completer<Passport> gate = Completer<Passport>();
        int attempt = 0;

        await tester.pumpApp(
          const PassportScreen(),
          overrides: <Object>[
            screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
            clientProfileProvider.overrideWith((ref) async => _sampleProfile),
            passportProvider.overrideWith((ref) async {
              attempt++;
              if (attempt == 1) throw const ServerFailure(statusCode: 500);
              return gate.future;
            }),
            wishlistRepositoryProvider.overrideWithValue(
              FakeWishlistRepository(services: _kFiveFavourites),
            ),
          ],
          retry: (_, _) => null,
        );
        await tester.pumpAndSettle();
        expect(find.byKey(_kPassportError), findsOneWidget);

        await tester.tap(find.byKey(_kPassportRetry));
        await tester.pump();

        // ── IN FLIGHT ──────────────────────────────────────────────────────
        expect(attempt, 2, reason: 'the retry must actually be in flight');
        expect(gate.isCompleted, isFalse);
        expect(
          find.byKey(_kPassportError),
          findsNothing,
          reason:
              'AsyncLoading(retrying) still reports hasError — matching '
              'hasError before isLoading would flash the error card back the '
              'instant the client taps retry',
        );
        expect(find.byKey(_kPassportRetry), findsNothing);
        expect(
          find.byKey(_kPassportSkeleton),
          findsOneWidget,
          reason:
              'a FIRST load has no retained value, so the skeleton — not the '
              'error card and not a blank gap — holds the slot',
        );

        // Still absent after further frames inside the same window: proves the
        // assertion is not a one-frame coincidence. There is nothing to pump
        // UNTIL (the assertion is that NOTHING appears) and pumpAndSettle would
        // deadlock on the pending future.
        // fixed-wait-ok: absence assertion inside a Completer-held window.
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byKey(_kPassportError), findsNothing);
        expect(gate.isCompleted, isFalse);

        // ── RELEASED ───────────────────────────────────────────────────────
        gate.complete(_populatedPassport);
        await tester.pumpAndSettle();
        expect(find.byKey(_kPassportError), findsNothing);
        expect(find.byKey(_kIdentityStrip), findsOneWidget);
      },
    );

    testWidgets(
      'a retry that fails AGAIN returns to the error card (not stuck loading)',
      (tester) async {
        // The mirror of the branch-order test: hiding the affordance mid-retry
        // is only half the contract — it must COME BACK when the retry genuinely
        // fails, or a permanently-broken passport sits on an endless skeleton.
        int attempt = 0;
        await tester.pumpApp(
          const PassportScreen(),
          overrides: <Object>[
            screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
            clientProfileProvider.overrideWith((ref) async => _sampleProfile),
            passportProvider.overrideWith((ref) async {
              attempt++;
              throw const ServerFailure(statusCode: 500);
            }),
            wishlistRepositoryProvider.overrideWithValue(
              FakeWishlistRepository(services: _kFiveFavourites),
            ),
          ],
          retry: (_, _) => null,
        );
        await tester.pumpAndSettle();
        expect(find.byKey(_kPassportError), findsOneWidget);

        await tester.tap(find.byKey(_kPassportRetry));
        await tester.pumpAndSettle();

        expect(attempt, 2);
        expect(find.byKey(_kPassportError), findsOneWidget);
        expect(find.byKey(_kPassportRetry), findsOneWidget);
        expect(find.byKey(_kIdentityStrip), findsNothing);
      },
    );
  });

  // -------------------------------------------------------------------------
  // 4. THE THREE BLOCKS FAIL SEPARATELY, WITH DISTINCT AFFORDANCES.
  // -------------------------------------------------------------------------
  group('PassportScreen — profile vs passport failures are distinct', () {
    testWidgets(
      'a passport failure leaves the profile block intact and vice versa',
      (tester) async {
        // PASSPORT fails, profile fine.
        await tester.pumpApp(
          const PassportScreen(),
          overrides: <Object>[
            screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
            clientProfileProvider.overrideWith((ref) async => _sampleProfile),
            passportProvider.overrideWith(
              (ref) async => throw const ServerFailure(statusCode: 500),
            ),
            wishlistRepositoryProvider.overrideWithValue(
              FakeWishlistRepository(services: _kFiveFavourites),
            ),
          ],
          retry: (_, _) => null,
        );
        await tester.pumpAndSettle();

        expect(find.byKey(_kPassportError), findsOneWidget);
        expect(find.byKey(_kPassportRetry), findsOneWidget);
        expect(find.byKey(_kProfileError), findsNothing);
        expect(find.byKey(_kProfileRetry), findsNothing);
        expect(find.byKey(_kProfileBlockMarker), findsOneWidget);

        // THE ICON DISAMBIGUATION. Every failure state on this page draws
        // `Icons.cloud_off_rounded`, so a bare `findsOneWidget` on the glyph is
        // not a statement about WHICH block failed. Scope it to the state.
        expect(
          find.descendant(
            of: find.byKey(_kPassportError),
            matching: find.byIcon(Icons.cloud_off_rounded),
          ),
          findsOneWidget,
        );
        expect(
          find.byIcon(Icons.cloud_off_rounded),
          findsOneWidget,
          reason:
              'exactly ONE block failed, so exactly one cloud_off may be on '
              'the page — a second one means an un-overridden provider is '
              'failing silently (the wish-list repository is the usual cause)',
        );
      },
    );

    testWidgets(
      'a profile failure surfaces its OWN affordance, passport untouched',
      (tester) async {
        await tester.pumpApp(
          const PassportScreen(),
          overrides: <Object>[
            screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
            clientProfileProvider.overrideWith(
              (ref) async => throw const ServerFailure(statusCode: 500),
            ),
            passportProvider.overrideWith((ref) async => _populatedPassport),
            wishlistRepositoryProvider.overrideWithValue(
              FakeWishlistRepository(services: _kFiveFavourites),
            ),
          ],
          retry: (_, _) => null,
        );
        await tester.pumpAndSettle();

        final AppLocalizations l10n = await _uk();

        expect(find.byKey(_kProfileError), findsOneWidget);
        expect(find.byKey(_kProfileRetry), findsOneWidget);
        expect(find.text(l10n.homeHubProfileLoadError), findsOneWidget);

        // NOT a blank-field profile block — the degrade this state replaces.
        expect(find.byKey(_kProfileBlockMarker), findsNothing);
        expect(find.text(l10n.homeHubLocationPlaceholder), findsNothing);
        expect(find.text(l10n.homeHubPhonePlaceholder), findsNothing);

        // The passport section is unaffected.
        expect(find.byKey(_kPassportError), findsNothing);
        expect(find.byKey(_kIdentityStrip), findsOneWidget);
        expect(find.byKey(_kDerivedBlock), findsOneWidget);

        expect(
          find.descendant(
            of: find.byKey(_kProfileError),
            matching: find.byIcon(Icons.cloud_off_rounded),
          ),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);
      },
    );
  });

  // -------------------------------------------------------------------------
  // 5. BEAUTY WISH LIST — the page's fourth block.
  // -------------------------------------------------------------------------
  group('PassportScreen — BEAUTY WISH LIST section', () {
    testWidgets('should_renderExactlyTwoCompactCards_when_wishlistHasFive', (
      tester,
    ) async {
      await tester.pumpApp(
        const PassportScreen(),
        overrides: _overrides(
          passport: _populatedPassport,
          wishlist: _kFiveFavourites,
        ),
        width: 390,
      );
      await tester.pumpAndSettle();

      final AppLocalizations l10n = await _uk();

      expect(
        find.byType(WishlistCompactCard),
        findsNWidgets(2),
        reason:
            'the line shows exactly WishlistSection.previewCount cards — it is '
            'a LINE, not a rail: no ListView, no carousel, no peeking third',
      );
      // The first two entries, in wire order — the backend ranks this list.
      // i18n-finder-ok: service names are fixture DATA off the fake repository.
      expect(find.text(_kFiveFavourites[0].serviceName), findsOneWidget);
      expect(find.text(_kFiveFavourites[1].serviceName), findsOneWidget);
      expect(find.text(_kFiveFavourites[2].serviceName), findsNothing);

      // Everything that did not fit lives behind the overflow control, which
      // must state the FULL count, not the visible two.
      expect(find.byKey(_kWishlistShowAll), findsOneWidget);
      expect(find.text(l10n.wishlistShowAll(5)), findsOneWidget);
      expect(find.text(l10n.wishlistShowAll(2)), findsNothing);

      expect(find.byKey(_kWishlistEmpty), findsNothing);
      expect(find.byKey(_kWishlistError), findsNothing);
    });

    testWidgets('should_keepLoneCardAtHalfWidth_when_oneFavouriteRemains', (
      tester,
    ) async {
      // A card that doubled in width on the removal of its neighbour would read
      // as a layout bug, not as a list shrinking. The section pads the row with
      // an empty `Expanded`, so the lone card keeps HALF the row.
      await tester.pumpApp(
        const PassportScreen(),
        overrides: _overrides(
          passport: _populatedPassport,
          wishlist: <WishlistService>[_kFiveFavourites.first],
        ),
        width: 390,
      );
      await tester.pumpAndSettle();

      expect(find.byType(WishlistCompactCard), findsOneWidget);

      // The row's own width: the ListView's content box, i.e. the surface minus
      // `EdgeInsets.all(VelvetSpacing.lg)` on both sides.
      final double rowWidth = tester
          .getSize(find.byKey(_kWishlistShowAll))
          .width;
      final double cardWidth = tester
          .getSize(find.byType(WishlistCompactCard))
          .width;

      expect(
        cardWidth,
        lessThan(rowWidth * 0.6),
        reason:
            'a lone favourite must keep HALF the row (plus the gap split), not '
            'stretch across it — measured card=$cardWidth row=$rowWidth',
      );
      expect(
        cardWidth,
        greaterThan(rowWidth * 0.4),
        reason: 'nor may it collapse below half — measured card=$cardWidth',
      );

      final AppLocalizations l10n = await _uk();
      expect(find.text(l10n.wishlistShowAll(1)), findsOneWidget);
    });

    testWidgets('should_renderEmptyState_when_wishlistIsEmpty', (tester) async {
      await tester.pumpApp(
        const PassportScreen(),
        overrides: _overrides(
          passport: _populatedPassport,
          wishlist: const <WishlistService>[],
        ),
      );
      await tester.pumpAndSettle();

      final AppLocalizations l10n = await _uk();

      expect(find.byKey(_kWishlistEmpty), findsOneWidget);
      expect(find.text(l10n.wishlistEmptyMessage), findsOneWidget);
      expect(
        find.text(l10n.wishlistEmptyCta),
        findsOneWidget,
        reason:
            'the wish list\'s empty state carries the «Знайти майстра» '
            'invitation now that the passport\'s own empty hero is deleted',
      );

      expect(find.byType(WishlistCompactCard), findsNothing);
      expect(find.byKey(_kWishlistShowAll), findsNothing);
      expect(find.byKey(_kWishlistError), findsNothing);

      // An EMPTY wish list is not a failed one — no failure glyph anywhere.
      expect(find.byIcon(Icons.cloud_off_rounded), findsNothing);

      // The rest of the page is untouched: a client with no favourites still
      // has a passport.
      expect(find.byKey(_kIdentityStrip), findsOneWidget);
      expect(find.byKey(_kDerivedBlock), findsOneWidget);
    });

    testWidgets('should_renderErrorState_when_wishlistFails', (tester) async {
      await tester.pumpApp(
        const PassportScreen(),
        overrides: _overrides(
          passport: _populatedPassport,
          // FakeWishlistRepository raises AFTER an await, never synchronously —
          // a sync throw would bypass Riverpod's async machinery entirely.
          wishlistFailure: const ServerFailure(statusCode: 500),
        ),
        retry: (_, _) => null,
      );
      await tester.pumpAndSettle();

      final AppLocalizations l10n = await _uk();

      expect(find.byKey(_kWishlistError), findsOneWidget);
      expect(find.text(l10n.wishlistErrorTitle), findsOneWidget);
      expect(find.byKey(const Key('wishlist_retry_button')), findsOneWidget);

      // A FAILED wish list is NOT an empty one — that collapse is the defect
      // class this page keeps being audited for.
      expect(
        find.byKey(_kWishlistEmpty),
        findsNothing,
        reason:
            'a failed fetch must be visually distinct from "nothing saved yet"',
      );
      expect(find.text(l10n.wishlistEmptyCta), findsNothing);
      expect(find.byType(WishlistCompactCard), findsNothing);
      expect(find.byKey(_kWishlistShowAll), findsNothing);

      // ONLY the wish list failed — the two passport blocks are intact, and the
      // single cloud_off on the page belongs to the wish-list card.
      expect(find.byKey(_kIdentityStrip), findsOneWidget);
      expect(find.byKey(_kPassportError), findsNothing);
      expect(find.byKey(_kProfileError), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(_kWishlistError),
          matching: find.byIcon(Icons.cloud_off_rounded),
        ),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  // 6. FLAG_SECURE lifecycle — the PII contract.
  // -------------------------------------------------------------------------
  group('PassportScreen — FLAG_SECURE lifecycle', () {
    testWidgets('acquires screen protection on mount, releases on dispose', (
      tester,
    ) async {
      // A REAL manager: its native enable/disable is kDebugMode-guarded (skipped
      // under flutter test), so only the reference-count bookkeeping runs — and
      // the refcount is the contract.
      final ScreenProtectionManager protection = ScreenProtectionManager();
      expect(protection.acquirerCount, 0);

      await tester.pumpApp(
        const PassportScreen(),
        overrides: _overrides(
          passport: _populatedPassport,
          protection: protection,
          wishlist: _kFiveFavourites,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        protection.acquirerCount,
        1,
        reason:
            'PassportScreen renders real client name / phone / city — it must '
            'acquire() screen protection in initState',
      );

      // Replace the screen so PassportScreen is disposed.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      expect(
        protection.acquirerCount,
        0,
        reason: 'PassportScreen must release() screen protection in dispose',
      );
    });
  });
}
