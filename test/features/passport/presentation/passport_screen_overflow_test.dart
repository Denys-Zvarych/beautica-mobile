// Phase 238 — BEAUTY PASSPORT page OVERFLOW regression guard.
//
// THE PAGE CHANGED SHAPE — SO DID THIS FILE'S PREMISE
// ---------------------------------------------------
// Until Phase 238 the passport was an INTENTIONALLY non-scrolling `Column` with
// an `Expanded` hero, so its dominant failure mode was VERTICAL: fixed chrome
// squeezing the hero to a negative height under a large text scale. That page
// is gone. `passport_screen.dart` is now a scrolling `ListView` of four blocks,
// and vertical growth is absorbed by the scroll — a Column can no longer
// overflow downward.
//
// What is left is HORIZONTAL, and there is more of it than before. Every block
// on the new page is a `Row` that cannot yield:
//   • the profile block   — 100 dp avatar slot + `Expanded` name/city/phone;
//   • the identity strip  — seal + 56/44 flex columns either side of a
//                           full-height hairline, inside an `IntrinsicHeight`;
//   • the derived block   — an `Expanded` eyebrow beside «≈» + a `PriceTag`,
//                           over a `Wrap` of locality names;
//   • the wish-list line  — two `Expanded` compact cards in an
//                           `IntrinsicHeight` row, each carrying an unbounded,
//                           un-ellipsised service name.
// All four grow with text scale, and none of them may ever paint an overflow
// stripe.
//
// SO THE WHOLE LIST MUST BE LAID OUT, NOT JUST THE FIRST SCREENFUL
// ----------------------------------------------------------------
// A `ListView` builds only what is visible (plus `cacheExtent`), so at 320x568
// the wish-list line — the widest-risk block on the page — is BELOW THE FOLD
// and is never laid out by a plain pump. A matrix that only pumped would
// therefore be measuring the profile block and calling it "the page". Each cell
// here scrolls to the bottom and asserts the tail block actually rendered, so
// the overflow guard sees every Row on the page.
//
// HOW OVERFLOW IS CAUGHT
// ----------------------
// The suite-wide guard (test/helpers/overflow_guard.dart) records the first
// RenderFlex overflow and fails the test in tearDown. Each cell ALSO asserts
// `tester.takeException()` is null as a second, explicit net.
//
// SURFACE SIZING — WHY NOT pumpApp(width:)
// ----------------------------------------
// `pumpApp(width:)` forces the surface HEIGHT to 2400, which would put the
// whole page above the fold and silently delete the scroll case this file now
// exists to exercise. Every cell therefore sets `view.physicalSize` to a REAL
// device size and installs the guard by hand.
//
// FIXTURES: the worst case on purpose — the longest real Ukrainian district
// («Шевченківський», the string the redesign exists to stop clipping), the
// longest real master name («Анастасія Мельниченко»), the longest service names
// and one RANGE price. Nothing here reads a clock: `memberSinceYear` is a wire
// value, so it is a literal.

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
// Fixtures — MAX content.
// ---------------------------------------------------------------------------

const _sampleProfile = ClientProfileSummary(
  firstName: 'Олександра',
  lastName: 'Коваленко-Тестівська',
  city: 'Печерський, Київ',
  phone: '+380 97 000 00 00',
  clientRating: 4.7,
  memberSinceYear: 2024,
);

const _populatedPassport = Passport(
  favoriteProcedures: <String>[
    'Манікюр гель-лак',
    'Брови ламінування',
    'Косметологія обличчя',
  ],
  favoriteDistricts: <String>['Шевченківський', 'Голосіївський', 'Печерський'],
  favoriteCities: <String>['Київ', 'Бровари'],
  budget: BudgetBand(avg: 1250, min: 400, max: 2400),
  bookingsConsidered: 12,
  reviewsWritten: 128,
  memberSinceYear: 2019,
);

/// A client with history but nothing derivable — the derived block is dropped
/// entirely, so the page is three blocks instead of four.
final Passport _noDerivedPassport = Passport.empty(memberSinceYear: 2026);

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

final List<WishlistService> _kFavourites = <WishlistService>[
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
    serviceName: 'Педикюр апаратний з покриттям',
    masterName: 'Вікторія Ткаченко',
    durationMinutes: 120,
    priceDisplay: '700–1100 ₴',
    isRange: true,
    priceMin: 700,
    priceMax: 1100,
  ),
];

// ---------------------------------------------------------------------------
// The page states under measurement.
// ---------------------------------------------------------------------------

/// One composition of the four blocks, plus the key that proves its TAIL block
/// actually got laid out after scrolling.
class _PageState {
  const _PageState(this.label, this.overrides, this.tailKey);

  final String label;
  final List<Object> Function() overrides;

  /// A key in the page's LAST block. Asserted after the scroll so a cell can
  /// never pass by measuring only the part of the list that fitted.
  final Key tailKey;
}

List<Object> _base({
  required Object passport,
  required Object profile,
  required Object wishlist,
}) => <Object>[
  screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
  profile,
  passport,
  wishlist,
];

final List<_PageState> _states = <_PageState>[
  _PageState(
    'populated (max content) + 3 favourites',
    () => _base(
      profile: clientProfileProvider.overrideWith(
        (ref) async => _sampleProfile,
      ),
      passport: passportProvider.overrideWith(
        (ref) async => _populatedPassport,
      ),
      wishlist: wishlistRepositoryProvider.overrideWithValue(
        FakeWishlistRepository(services: _kFavourites),
      ),
    ),
    const Key('wishlist_show_all_button'),
  ),
  _PageState(
    'no derived data + empty wish list',
    () => _base(
      profile: clientProfileProvider.overrideWith(
        (ref) async => _sampleProfile,
      ),
      passport: passportProvider.overrideWith(
        (ref) async => _noDerivedPassport,
      ),
      wishlist: wishlistRepositoryProvider.overrideWithValue(
        FakeWishlistRepository(),
      ),
    ),
    const Key('wishlist_empty_state'),
  ),
  _PageState(
    'passport error + wish-list error (two failure cards)',
    () => _base(
      profile: clientProfileProvider.overrideWith(
        (ref) async => _sampleProfile,
      ),
      passport: passportProvider.overrideWith(
        // Async throw, never `thenThrow` — a sync throw during provider build
        // bypasses Riverpod's async machinery entirely.
        (ref) async => throw const ServerFailure(statusCode: 500),
      ),
      wishlist: wishlistRepositoryProvider.overrideWithValue(
        FakeWishlistRepository(failure: const ServerFailure(statusCode: 500)),
      ),
    ),
    const Key('wishlist_error_state'),
  ),
  _PageState(
    'profile error + populated passport + favourites',
    () => _base(
      profile: clientProfileProvider.overrideWith(
        (ref) async => throw const ServerFailure(statusCode: 500),
      ),
      passport: passportProvider.overrideWith(
        (ref) async => _populatedPassport,
      ),
      wishlist: wishlistRepositoryProvider.overrideWithValue(
        FakeWishlistRepository(services: _kFavourites),
      ),
    ),
    const Key('wishlist_show_all_button'),
  ),
];

// ---------------------------------------------------------------------------
// Viewport matrix (logical px).
// ---------------------------------------------------------------------------

class _Viewport {
  const _Viewport(this.label, this.width, this.height, this.scale);
  final String label;
  final double width;
  final double height;
  final double scale;
}

const List<_Viewport> _matrix = <_Viewport>[
  // THE REQUIRED CELL — iPhone-SE-class small phone.
  _Viewport('small-phone 320x568', 320, 568, 1.0),
  // THE REQUIRED a11y CELLS at that same width.
  _Viewport('small-phone 320x568 @1.3x', 320, 568, 1.3),
  _Viewport('small-phone 320x568 @1.5x', 320, 568, 1.5),
  // Compact low-end Android and the baseline modern phone.
  _Viewport('compact 360x640', 360, 640, 1.0),
  _Viewport('compact 360x640 @1.5x', 360, 640, 1.5),
  _Viewport('baseline 390x844', 390, 844, 1.0),
  _Viewport('baseline 390x844 @1.3x', 390, 844, 1.3),
  _Viewport('baseline 390x844 @1.5x', 390, 844, 1.5),
];

/// EXTREME-but-SAFE cells. Permanent guards: the page must stay overflow-free
/// far past any real device, so a future change that reintroduces a squeeze at
/// a reachable size trips these first.
const List<_Viewport> _extremeSafeMatrix = <_Viewport>[
  _Viewport('360x640 @2.0x (Android largest font)', 360, 640, 2.0),
  _Viewport('ultra-narrow 280x653 @1.0x', 280, 653, 1.0),
  _Viewport('ultra-narrow 280x653 @1.3x', 280, 653, 1.3),
  _Viewport('sub-floor 270x844 @1.0x', 270, 844, 1.0),
  // Short / landscape-ish surfaces: the ListView absorbs the vertical squeeze,
  // so these exercise the horizontal Rows at an extreme aspect ratio.
  _Viewport('landscape-ish 640x360 @1.0x', 640, 360, 1.0),
  _Viewport('landscape-ish 720x360 @1.5x', 720, 360, 1.5),
];

/// Pumps [PassportScreen] at an EXACT device viewport, settles both futures,
/// then scrolls the ListView to the very bottom so EVERY block is laid out.
Future<void> _pumpAndScrollThrough(
  WidgetTester tester, {
  required _Viewport vp,
  required _PageState state,
}) async {
  installOverflowGuard();

  tester.view.physicalSize = Size(vp.width, vp.height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      // Retry OFF so the error cells actually reach AsyncError and their
      // failure cards are on screen to be measured. `beauticaProviderRetry`
      // classifies a 5xx as transient, which would park those cells in
      // AsyncLoading(retrying: true) — a skeleton, not the state under test.
      retry: (_, _) => null,
      overrides: state.overrides().cast(),
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('uk'),
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(vp.width, vp.height),
            textScaler: TextScaler.linear(vp.scale),
          ),
          child: const PassportScreen(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  // Drag the list all the way up so the tail block is built and laid out. A
  // `drag` rather than a `fling`: no ballistic simulation to settle, and the
  // offset is deliberately far larger than any page height so one drag always
  // reaches the end.
  final Finder list = find.byType(Scrollable).first;
  await tester.drag(list, const Offset(0, -4000));
  await tester.pumpAndSettle();
}

void main() {
  for (final _PageState state in _states) {
    group('PassportScreen overflow — ${state.label}', () {
      for (final _Viewport vp in <_Viewport>[
        ..._matrix,
        ..._extremeSafeMatrix,
      ]) {
        testWidgets('no overflow at ${vp.label}', (tester) async {
          await _pumpAndScrollThrough(tester, vp: vp, state: state);

          expect(
            find.byKey(const Key('client-branch-passport')),
            findsOneWidget,
            reason: 'PassportScreen must render (sanity) at ${vp.label}',
          );
          expect(
            find.byKey(state.tailKey),
            findsOneWidget,
            reason:
                'the page TAIL (${state.tailKey}) must be laid out after the '
                'scroll — without it this cell would be measuring only the '
                'blocks that happened to fit above the fold at ${vp.label}',
          );
          expect(
            tester.takeException(),
            isNull,
            reason:
                'PassportScreen (${state.label}) must not overflow at '
                '${vp.label} — profile Row / identity strip IntrinsicHeight / '
                'derived block spend Row / two-card wish-list line.',
          );
        });
      }
    });
  }

  // -------------------------------------------------------------------------
  // NON-VACUITY. The matrix above is only meaningful if the scroll genuinely
  // matters — i.e. if the page really is taller than the small-phone viewport
  // and the tail block really is NOT laid out before the drag. Without this,
  // a future refactor that fitted everything on one screen would quietly turn
  // every cell above into a first-screenful-only assertion again.
  // -------------------------------------------------------------------------
  group('PassportScreen overflow — the scroll is load-bearing', () {
    testWidgets('the wish-list line is BELOW THE FOLD at 320x568', (
      tester,
    ) async {
      installOverflowGuard();
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          overrides: _states.first.overrides().cast(),
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: Locale('uk'),
            home: MediaQuery(
              data: MediaQueryData(size: Size(320, 568)),
              child: PassportScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final Finder showAll = find.byKey(const Key('wishlist_show_all_button'));
      final bool builtBeforeScroll = showAll.evaluate().isNotEmpty;
      final double foldBefore = builtBeforeScroll
          ? tester.getTopLeft(showAll).dy
          : double.infinity;

      await tester.drag(find.byType(Scrollable).first, const Offset(0, -4000));
      await tester.pumpAndSettle();

      expect(
        showAll,
        findsOneWidget,
        reason: 'the tail must be reachable by scrolling',
      );
      expect(
        foldBefore,
        greaterThan(568),
        reason:
            'the wish-list overflow control must sit BELOW the 568 dp fold '
            'before the scroll — if the whole page fitted, the matrix above '
            'would be asserting nothing about the blocks past the first '
            'screenful (measured pre-scroll dy: $foldBefore)',
      );
    });
  });
}
