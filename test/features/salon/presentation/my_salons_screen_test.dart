// Phase 21.1 — Widget tests for MySalonsScreen (the SALON_OWNER landing).
//
// Covers:
//   1. Card list rendering — one card per owned salon, data values bound
//      (name + locality/street), NOT just "some widget rendered".
//   2. «Основний» primary badge renders on the primary salon's card and on
//      NO other card.
//   3. Card tap navigates to RouteNames.salonManage(salon.id) — NOT
//      RouteNames.salonProfile(id), the client-facing public profile the
//      phase doc explicitly calls out as the mistake to avoid.
//   4. Loading branch — SkeletonShimmerScope renders while unresolved.
//   5. Error branch — ErrorState renders, and tapping retry actually
//      refetches (asserted by a real second build() call + the data
//      subsequently rendering, not just "the button exists").
//   6. Empty state — pinned even though it should not occur in practice.
//   7. STAGGER CRASH REGRESSION (mobile-perf HIGH follow-up) — the pre-fix
//      `_reveal(start: ...)` call for card index >= 8 of >= 9 salons handed
//      `Interval` an unclamped `start` above 1.0, red-screening on
//      `Interval`'s `begin <= 1.0` assert. Pumping ~12 salons here must not
//      throw, and every card (including the last) must still be reachable.
//      MUTATION-VERIFIED (mobile-qa, 2026-08-28) — reintroducing the pre-fix
//      unclamped `_cardRevealStart` formula AND reverting `_reveal`'s own
//      `start.clamp(0.0, 1.0)` reproduces the EXACT original crash (`Interval
//      .transformInternal`'s `'begin <= 1.0': is not true` assertion) against
//      this test, IF AND ONLY IF the viewport is tall enough for the
//      offending card to be built and animating from a FRACTIONAL `t` (see
//      that test's own in-body note on why `Curve.transform` short-circuits
//      `t == 0.0/1.0` and would silently pass a card built only after the
//      controller settles). Restoring the production file afterward reverts
//      to a clean `git diff` and the test back to GREEN.
//   8. ListView.builder LAZINESS (mobile-perf MEDIUM follow-up) — with 12
//      salons and the default (unscrolled) test viewport, a card far down
//      the list must NOT be built yet — proving the list is virtualized,
//      not a `Column` inside a `SingleChildScrollView` eagerly laying out
//      every card regardless of visibility.
//   9. SWIPE-TO-DELETE GATE (mobile-qa, mobile-security MEDIUM follow-up,
//      2026-09) — previously ZERO coverage (`grep` for `Dismissible`/
//      `canDelete` in this file returned nothing before this group):
//        a. an owner's card is wrapped in a `Dismissible`; a non-owner role
//           renders the same salon as a plain, un-swipeable card;
//        b. a swipe — INCLUDING a fast fling — still awaits
//           `DeleteSalonDialog` before any `deleteSalon()` call fires
//           (`Dismissible` awaits `confirmDismiss` regardless of gesture
//           velocity — pinned rather than trusted);
//        c. `confirmDismiss` always returning `false` means the swiped row
//           stays in the list until `mySalonsProvider`'s OWN invalidation
//           removes it — never Dismissible's own slide-out/resize;
//        d. `_DeleteInFlightOverlay` renders over the row while the delete
//           call is in flight, and the underlying `Dismissible` element
//           SURVIVES the whole round trip (never swapped out from under the
//           overlay).
//      MUTATION-VERIFIED (mobile-qa, 2026-09-03) — flipping
//      `confirmDismiss`'s hard-coded `return false` to `return true`
//      reproduces the `A dismissed Dismissible widget is still part of the
//      tree` `FlutterError` this design exists to avoid; see the phase doc's
//      `## Status` for the recorded mutation result. Restoring the
//      production file afterward reverts to a clean `git diff` and the test
//      back to GREEN.
//
// Strategy: `mySalonsProvider` (a `@Riverpod(keepAlive: true)` CLASS
// provider) is overridden directly with small `MySalons` subclasses —
// mirrors `salon_bookings_route_shadowing_test.dart`'s own `_SettledMySalons`
// shape. This sidesteps `authProvider` entirely (`my_salons_notifier_test
// .dart` owns that leg) and keeps this file scoped to the SCREEN's own
// loading/data/error/empty branches and navigation. Group 9 additionally
// overrides `isSalonOwnerProvider` directly (a plain, non-family provider —
// `.overrideWithValue` is valid) and `salonRepositoryProvider` with
// `FakeSalonRepository` (mirrors `delete_salon_flow_test.dart`'s own use of
// it) — `SalonManagementProfile.deleteSalon()` reads that repository
// directly, so no `SalonManagementProfile` notifier override is needed.
//
// LOADING-STATE PUMP TRAP: `_HubSkeleton` wraps `SkeletonShimmerScope`, whose
// `AnimationController` is `..repeat(reverse: true)` — it never settles, so
// `pumpAndSettle()` on the loading-state test would hang forever. A single
// bounded `tester.pump()` is used instead, mirroring
// `public_salon_profile_screen_test.dart`'s own precedent for the exact same
// widget.

import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_selectors.dart';
import 'package:beautica_mobile/features/location/data/location_repository.dart';
import 'package:beautica_mobile/features/location/domain/city.dart';
import 'package:beautica_mobile/features/location/domain/city_district.dart';
import 'package:beautica_mobile/features/location/domain/oblast.dart';
import 'package:beautica_mobile/features/salon/application/my_salons_notifier.dart';
import 'package:beautica_mobile/features/salon/data/salon_repository.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/salon/presentation/my_salons_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:beautica_mobile/shared/widgets/skeleton_shimmer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/fakes/fake_salon_repository.dart';
import '../../../helpers/pump_app.dart';

// ---------------------------------------------------------------------------
// mobile-qa gap-closure (2026-08-29) — `resolvedLocalityProvider` fixtures.
//
// The resolved-taxonomy-city branch of `_SalonHubCardState.build` (Phase
// 21.14 follow-up) had ZERO coverage: every existing fixture above sets
// `city:` with NO `cityId`/`oblastId`, so `hasTaxonomyCity` was always false
// and only the legacy fallback ever ran. These fixtures deliberately give
// the resolved city a DIFFERENT name than any legacy `city` string used
// alongside it, so a test asserting the resolved name is present PROVES the
// legacy value was not what rendered (see the "resolved city" group below).
// ---------------------------------------------------------------------------

const _resolvedOblast = Oblast(
  id: 'ob-1',
  name: 'Львівська область',
  katotthCode: 'A',
);
const _resolvedCity = City(
  id: 'ct-1',
  oblastId: 'ob-1',
  name: 'Львів', // deliberately NOT the same as any fixture's legacy `city`
  katotthCode: 'B',
  hasDistricts: false,
);

class _FakeLocationRepository implements LocationRepository {
  _FakeLocationRepository({this.oblastsCompleter});

  /// When set, `fetchOblasts` awaits this instead of resolving immediately —
  /// lets the async-fallback test hold the whole cascade in AsyncLoading
  /// indefinitely (never completed in that test), proving the card renders
  /// street/building synchronously without waiting on it.
  final Completer<List<Oblast>>? oblastsCompleter;

  @override
  Future<List<Oblast>> fetchOblasts() =>
      oblastsCompleter?.future ??
      Future<List<Oblast>>.value(const <Oblast>[_resolvedOblast]);

  @override
  Future<List<City>> fetchCities(String oblastId) async => const <City>[
    _resolvedCity,
  ];

  @override
  Future<List<CityDistrict>> fetchDistricts(String cityId) async =>
      const <CityDistrict>[];
}

/// A repository whose `fetchOblasts` always throws — proves a resolution
/// FAILURE (caught internally by `resolvedLocalityProvider`, never
/// rethrown — see that provider's own doc) still renders street/building
/// with no error box, exactly like the still-loading case.
class _ThrowingLocationRepository implements LocationRepository {
  @override
  Future<List<Oblast>> fetchOblasts() async => throw const NetworkFailure();

  @override
  Future<List<City>> fetchCities(String oblastId) async => const <City>[];

  @override
  Future<List<CityDistrict>> fetchDistricts(String cityId) async =>
      const <CityDistrict>[];
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const List<Salon> _salons = <Salon>[
  Salon(
    id: 'salon-1',
    name: 'Салон Оксани',
    city: 'Київ',
    street: 'Хрещатик',
    buildingNo: '10',
    isPrimary: true,
  ),
  Salon(
    id: 'salon-2',
    name: 'Студія Ірини',
    city: 'Львів',
    street: 'Личаківська',
    buildingNo: '5',
    isPrimary: false,
  ),
  Salon(id: 'salon-3', name: 'Барбершоп «Стиль»', isPrimary: false),
];

/// [n] minimal salons — id-indexed so the crash-regression / laziness tests
/// can address a specific card by key without a full fixture per entry.
List<Salon> _manySalons(int n) => List<Salon>.generate(
  n,
  (int i) => Salon(id: 'salon-many-$i', name: 'Салон №$i', isPrimary: i == 0),
);

// mobile-qa gap-closure (swipe-to-delete audit 2026-09) — TWO salons: the
// one an owner swipes away, and the one that survives it. A single-salon
// fixture couldn't prove "the row is not removed by the gesture" (a list
// dropping to empty looks identical whether the row was removed by
// Dismissible's own animation or by the provider re-fetching a shorter
// list) or "the invalidated refetch renders the REMAINING salons".
const Salon _swipeSalonA = Salon(
  id: 'salon-swipe-a',
  name: 'Салон, що видаляють',
  isPrimary: false,
);
const Salon _swipeSalonB = Salon(
  id: 'salon-swipe-b',
  name: 'Салон, що лишається',
  isPrimary: true,
);

/// `runDeleteSalonFlow`'s own post-delete landing target depends on
/// `ref.read(authProvider).value` — without an override it resolves the
/// REAL (unauthenticated-by-default in a bare test container) session and
/// navigates to `RouteNames.login`, which would strand every assertion
/// below on the wrong screen. An authenticated SALON_OWNER session mirrors
/// who can actually reach this swipe gesture (the route itself is
/// SALON_OWNER-gated) and keeps the flow on `RouteNames.mySalons` — the
/// `matchedLocation == target` skip in `delete_salon_flow.dart` then means
/// no navigation happens at all, exactly like the real swipe-in-place
/// gesture.
class _AuthenticatedAsOwner extends AuthNotifier {
  @override
  Future<AuthSession> build() async => const AuthSession.authenticated(
    user: User(
      id: 'owner-swipe-1',
      email: 'owner-swipe@beautica.ua',
      role: UserRole.salonOwner,
      firstName: 'Оксана',
      lastName: 'Власниця',
    ),
    accessToken: 'tok-swipe',
  );
}

Finder get _dismissibleA =>
    find.byKey(const ValueKey<String>('my_salons_dismissible_salon-swipe-a'));
Finder get _cardA =>
    find.byKey(const ValueKey<String>('my_salons_card_salon-swipe-a'));
Finder get _cardB =>
    find.byKey(const ValueKey<String>('my_salons_card_salon-swipe-b'));
Finder get _deleteDialog => find.byKey(const Key('delete-salon-dialog'));
Finder get _confirmDeleteButton =>
    find.byKey(const Key('btn-confirm-delete-salon'));
Finder get _inFlightOverlaySpinner =>
    find.byKey(const Key('my_salons_delete_in_flight_spinner'));

/// Swipes [dismissibleA] `endToStart` — the only direction the production
/// `Dismissible` accepts. [velocity] lets a test drive a fast fling vs. a
/// slower one; both must still route through `confirmDismiss` per
/// `Dismissible`'s own contract (there is no "skip confirmDismiss on a fast
/// gesture" fast path in the framework — this is pinned, not merely
/// trusted, by the tests that call this with a high velocity).
Future<void> _swipeSalonADismissible(
  WidgetTester tester, {
  double velocity = 1000,
}) => tester.fling(_dismissibleA, const Offset(-500, 0), velocity);

// mobile-qa gap-closure (2026-08-29) — a salon that HAS the taxonomy
// `cityId`/`oblastId`. Its legacy `city` field is deliberately set to a
// DIFFERENT, stale value ('Одеса') so a test asserting the RESOLVED name
// ('Львів', see `_resolvedCity` above) renders — and the stale legacy value
// does NOT — actually proves the fix, not just that some city text exists.
const _salonWithTaxonomyCity = Salon(
  id: 'salon-taxonomy',
  name: 'Салон з таксономією',
  city: 'Одеса', // stale legacy value — must NOT be what renders
  oblastId: 'ob-1',
  cityId: 'ct-1',
  street: 'вул. Франка',
  buildingNo: '7',
);

// A genuinely pre-Phase-10.6 salon: no taxonomy ids at all, only the legacy
// free-text `city`. Must still render its legacy value — the
// `hasTaxonomyCity` gate exists precisely to distinguish this case from the
// one above.
const _salonPreTaxonomy = Salon(
  id: 'salon-legacy',
  name: 'Старий салон',
  city: 'Одеса',
  street: 'вул. Дерибасівська',
  buildingNo: '1',
);

// ---------------------------------------------------------------------------
// MySalons stubs — override the keepAlive CLASS provider directly (mirrors
// `salon_bookings_route_shadowing_test.dart`'s `_SettledMySalons`).
// ---------------------------------------------------------------------------

class _StubMySalons extends MySalons {
  _StubMySalons(this._builder);

  final Future<List<Salon>> Function() _builder;

  @override
  Future<List<Salon>> build() => _builder();
}

/// Serves [responses] in order — index `i` for the `i`-th `build()` call,
/// clamped to the last entry once exhausted. Lets the retry test prove a
/// SECOND real fetch happened (not just that the retry button exists).
class _SequencedMySalons extends MySalons {
  _SequencedMySalons(this._responses);

  final List<Future<List<Salon>> Function()> _responses;
  int buildCalls = 0;

  @override
  Future<List<Salon>> build() {
    final int i = buildCalls.clamp(0, _responses.length - 1);
    buildCalls++;
    return _responses[i]();
  }
}

// ---------------------------------------------------------------------------
// Router — registers the hub plus BOTH possible tap destinations, so the
// navigation test can prove it lands on the salon shell, never the public
// client-facing profile.
// ---------------------------------------------------------------------------

GoRouter _router() => GoRouter(
  initialLocation: RouteNames.mySalons,
  routes: <RouteBase>[
    GoRoute(
      path: RouteNames.mySalons,
      builder: (context, state) => const MySalonsScreen(),
    ),
    // Phase 21.3 — the «+ Додати салон» CTA's destination. A literal under
    // `/salons/`, registered BEFORE the dynamic `/salons/:salonId` route
    // below — same literal-before-dynamic ordering `RouteNames.registerSalon`
    // itself documents; declaring it AFTER would shadow it as
    // `salonId == 'register'` and silently resolve to the public-profile
    // route instead.
    GoRoute(
      path: RouteNames.registerSalon,
      builder: (context, state) =>
          const Scaffold(body: Text('register-salon-screen')),
    ),
    // Phase 21.8 — the hub is now a SWITCHER: picking a salon lands in its
    // shell, not its (separately routed) management profile.
    GoRoute(
      path: '/salons/:salonId/shell',
      builder: (context, state) => Scaffold(
        body: Text('shell-screen-${state.pathParameters['salonId']}'),
      ),
    ),
    GoRoute(
      path: '/salons/:salonId',
      builder: (context, state) => Scaffold(
        body: Text('public-profile-${state.pathParameters['salonId']}'),
      ),
    ),
  ],
);

Future<AppLocalizations> _loadL10n() =>
    AppLocalizations.delegate.load(const Locale('uk'));

void main() {
  group('card list rendering', () {
    testWidgets('renders one card per salon with name + address bound, and the '
        'primary badge ONLY on the primary salon', (tester) async {
      final l10n = await _loadL10n();
      await tester.pumpRoutedApp(
        _router(),
        overrides: <Object>[
          mySalonsProvider.overrideWith(
            () => _StubMySalons(() async => _salons),
          ),
        ],
      );
      await tester.pumpAndSettle();

      for (final Salon s in _salons) {
        final Finder card = find.byKey(
          ValueKey<String>('my_salons_card_${s.id}'),
        );
        expect(card, findsOneWidget, reason: 'missing card for ${s.id}');
        expect(
          find.descendant(of: card, matching: find.text(s.name)),
          findsOneWidget,
          reason: 'card for ${s.id} must render its own salon name',
        );
      }

      // Street/locality DATA VALUE bound, not just "some text rendered".
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('my_salons_card_salon-1')),
          matching: find.textContaining('Хрещатик'),
        ),
        findsOneWidget,
      );

      // Primary badge on salon-1 (isPrimary: true) only.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('my_salons_card_salon-1')),
          matching: find.text(l10n.mySalonsPrimaryBadgeLabel),
        ),
        findsOneWidget,
      );
      for (final String otherId in <String>['salon-2', 'salon-3']) {
        expect(
          find.descendant(
            of: find.byKey(ValueKey<String>('my_salons_card_$otherId')),
            matching: find.text(l10n.mySalonsPrimaryBadgeLabel),
          ),
          findsNothing,
          reason: '$otherId is not primary and must not show the badge',
        );
      }
    });
  });

  group('top bar title (2026-09-01 — moved off the "beautica" wordmark)', () {
    testWidgets(
      "the top bar shows the screen's own mySalonsTitle exactly once, and "
      'the "beautica" wordmark no longer renders anywhere on the hub',
      (tester) async {
        final l10n = await _loadL10n();
        await tester.pumpRoutedApp(
          _router(),
          overrides: <Object>[
            mySalonsProvider.overrideWith(
              () => _StubMySalons(() async => _salons),
            ),
          ],
        );
        await tester.pumpAndSettle();

        expect(
          find.text(l10n.mySalonsTitle),
          findsOneWidget,
          reason:
              '«Мої салони» must render exactly once — in the top bar, not '
              'duplicated as a separate heading below it',
        );
        expect(
          find.text('beautica'),
          findsNothing,
          reason: 'the brand wordmark was replaced by the screen\'s own title',
        );
      },
    );
  });

  group('navigation', () {
    testWidgets(
      'card tap opens RouteNames.salonShell(id) via go, never salonProfile(id)',
      (tester) async {
        final GoRouter router = _router();
        addTearDown(router.dispose);
        await tester.pumpRoutedApp(
          router,
          overrides: <Object>[
            mySalonsProvider.overrideWith(
              () => _StubMySalons(() async => _salons),
            ),
          ],
        );
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const ValueKey<String>('my_salons_card_salon-1')),
        );
        await tester.pumpAndSettle();

        expect(find.text('shell-screen-salon-1'), findsOneWidget);
        expect(
          find.text('public-profile-salon-1'),
          findsNothing,
          reason:
              'must NEVER land on the public/client salon profile — the '
              'exact mistake the phase doc calls out',
        );
        // Phase 21.8 — the hub is a SWITCHER: `go`, not `push`. The hub's
        // own route must not remain underneath on the stack.
        expect(
          // router-location-ok: only router.go(...) (never push) is used here, so the ImperativeRouteMatch exclusion does not apply.
          router.routerDelegate.currentConfiguration.uri.toString(),
          equals(RouteNames.salonShell('salon-1')),
        );
      },
    );

    testWidgets('the «+ Додати салон» CTA pushes RouteNames.registerSalon', (
      tester,
    ) async {
      final GoRouter router = _router();
      addTearDown(router.dispose);
      await tester.pumpRoutedApp(
        router,
        overrides: <Object>[
          mySalonsProvider.overrideWith(
            () => _StubMySalons(() async => _salons),
          ),
        ],
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('my_salons_add_cta')));
      await tester.pumpAndSettle();

      expect(find.text('register-salon-screen'), findsOneWidget);
      expect(
        find.text('public-profile-register'),
        findsNothing,
        reason:
            'if the dynamic /salons/:salonId sibling absorbed "register" as '
            'a salonId, this would render instead — the exact literal-vs-'
            'dynamic shadowing mistake RouteNames.registerSalon documents',
      );
    });
  });

  group('async states', () {
    testWidgets('loading branch renders the skeleton', (tester) async {
      await tester.pumpRoutedApp(
        _router(),
        overrides: <Object>[
          mySalonsProvider.overrideWith(
            () => _StubMySalons(() => Completer<List<Salon>>().future),
          ),
        ],
      );
      // pumpAndSettle would hang — SkeletonShimmerScope's controller repeats
      // forever. One bounded pump is enough to observe the loading branch.
      await tester.pump();

      expect(find.byType(SkeletonShimmerScope), findsWidgets);
      expect(
        find.byKey(const ValueKey<String>('my_salons_card_salon-1')),
        findsNothing,
      );
    });

    testWidgets('error branch renders ErrorState, and tapping retry actually '
        'refetches (a real second build(), not just a button)', (tester) async {
      final notifier = _SequencedMySalons(<Future<List<Salon>> Function()>[
        () async => throw const NetworkFailure(),
        () async => _salons,
      ]);
      await tester.pumpRoutedApp(
        _router(),
        overrides: <Object>[mySalonsProvider.overrideWith(() => notifier)],
        // Terminal error surface, not the production retry curve — see
        // pump_app.dart's own `retry` doc.
        retry: (_, _) => null,
      );
      await tester.pumpAndSettle();

      expect(find.byType(ErrorState), findsOneWidget);
      expect(notifier.buildCalls, 1);

      await tester.tap(
        find.byKey(const ValueKey<String>('error_state_retry_button')),
      );
      await tester.pumpAndSettle();

      expect(
        notifier.buildCalls,
        2,
        reason: 'retry must trigger a REAL second build(), not a no-op',
      );
      expect(find.byType(ErrorState), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('my_salons_card_salon-1')),
        findsOneWidget,
      );
    });

    testWidgets('empty state renders (not expected in practice, but pinned)', (
      tester,
    ) async {
      final l10n = await _loadL10n();
      await tester.pumpRoutedApp(
        _router(),
        overrides: <Object>[
          mySalonsProvider.overrideWith(
            () => _StubMySalons(() async => const <Salon>[]),
          ),
        ],
      );
      await tester.pumpAndSettle();

      expect(find.text(l10n.mySalonsEmptyTitle), findsOneWidget);
      expect(find.text(l10n.mySalonsEmptyBody), findsOneWidget);
    });
  });

  group('stagger + virtualization regressions (mobile-perf follow-ups)', () {
    testWidgets(
      'a large salon count (12) does not crash the staggered entrance, and '
      'every card remains reachable',
      (tester) async {
        // TALL VIEWPORT, DELIBERATELY: `Curve.transform` short-circuits to a
        // bare return WITHOUT calling `transformInternal` (and therefore
        // without running its `begin <= 1.0` assert) whenever `t == 0.0` or
        // `t == 1.0` (`curves.dart`'s own `Curve.transform`). A card that is
        // only built AFTER the entrance AnimationController has already
        // settled at `t == 1.0` — e.g. one scrolled into view post-
        // `pumpAndSettle`, as an off-screen/lazily-built card would be —
        // NEVER exercises the assert this test exists to pin, and would
        // pass even with the pre-fix formula. Sizing the viewport tall
        // enough that all 12 cards are built and animating from the FIRST
        // frame (fractional `t`, not 0/1) is what actually reproduces the
        // crash the mobile-perf HIGH follow-up fixed.
        tester.view.physicalSize = const Size(800, 4000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final List<Salon> many = _manySalons(12);
        await tester.pumpRoutedApp(
          _router(),
          overrides: <Object>[
            mySalonsProvider.overrideWith(
              () => _StubMySalons(() async => many),
            ),
          ],
        );
        // Pump through several MID-FLIGHT frames (fractional `t`) before
        // settling — pre-fix, one of these throws a FlutterError (Interval's
        // `begin <= 1.0` assert) for card index >= 8. A test that only
        // pumped straight to `pumpAndSettle`'s final (t == 1.0) frame would
        // not reproduce it, per this test's own header note.
        for (int i = 0; i < 8; i++) {
          // fixed-wait-ok: deliberately sampling MID-FLIGHT frames of the
          // 900ms entrance AnimationController (fractional `t`, never
          // exactly 0.0/1.0) — this is not "wait for a condition", it is the
          // regression mechanism itself (see this test's own header on why
          // `Curve.transform` short-circuits at t==0/1 and pumpUntilFound
          // would not exercise the assert).
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.pumpAndSettle();

        for (int i = 0; i < 12; i++) {
          expect(
            find.byKey(ValueKey<String>('my_salons_card_salon-many-$i')),
            findsOneWidget,
            reason: 'card $i of 12 must render without crashing the tree',
          );
        }
      },
    );

    testWidgets(
      'ListView.builder is lazy — a far-down card is not built before it is '
      'scrolled into view',
      (tester) async {
        final List<Salon> many = _manySalons(12);
        await tester.pumpRoutedApp(
          _router(),
          overrides: <Object>[
            mySalonsProvider.overrideWith(
              () => _StubMySalons(() async => many),
            ),
          ],
        );
        await tester.pumpAndSettle();

        // First card built (near the top of the unscrolled viewport)...
        expect(
          find.byKey(const ValueKey<String>('my_salons_card_salon-many-0')),
          findsOneWidget,
        );
        // ...but the LAST card must not be — proving the list virtualizes
        // instead of a `Column`/`SingleChildScrollView` eagerly laying out
        // every card regardless of visibility.
        expect(
          find.byKey(const ValueKey<String>('my_salons_card_salon-many-11')),
          findsNothing,
          reason:
              'card 11 of 12 must not be built while still off-screen — a '
              'ListView.builder regression back to eager Column layout '
              'would make this find a widget',
        );
      },
    );
  });

  // mobile-qa gap-closure (2026-08-29) — closes the coverage gap named in the
  // QA brief: EVERY existing fixture above sets `city:` with no `cityId`/
  // `oblastId`, so `hasTaxonomyCity` was always false and the resolved-name
  // branch of `_SalonHubCardState.build` had zero coverage. `mobile-dev`
  // reported "test assertions changed — none" for exactly this reason.
  group('resolved taxonomy city (mobile-qa gap-closure)', () {
    testWidgets(
      'a salon WITH cityId renders the RESOLVED city, never the stale '
      'legacy salon.city even when it is present and DIFFERENT',
      (tester) async {
        await tester.pumpRoutedApp(
          _router(),
          overrides: <Object>[
            mySalonsProvider.overrideWith(
              () => _StubMySalons(() async => <Salon>[_salonWithTaxonomyCity]),
            ),
            locationRepositoryProvider.overrideWith(
              (_) => _FakeLocationRepository(),
            ),
          ],
        );
        await tester.pumpAndSettle();

        final Finder card = find.byKey(
          const ValueKey<String>('my_salons_card_salon-taxonomy'),
        );
        expect(card, findsOneWidget);
        expect(
          find.descendant(of: card, matching: find.textContaining('Львів')),
          findsOneWidget,
          reason: 'the RESOLVED city name must render',
        );
        expect(
          find.descendant(of: card, matching: find.textContaining('Одеса')),
          findsNothing,
          reason:
              'the stale legacy salon.city ("Одеса") must NEVER render '
              'once a resolved taxonomy city is available — this is the '
              'actual bug the gate exists to prevent',
        );
      },
    );

    testWidgets(
      'a genuinely pre-taxonomy salon (cityId null, legacy city set) still '
      'shows the legacy value',
      (tester) async {
        await tester.pumpRoutedApp(
          _router(),
          overrides: <Object>[
            mySalonsProvider.overrideWith(
              () => _StubMySalons(() async => <Salon>[_salonPreTaxonomy]),
            ),
            locationRepositoryProvider.overrideWith(
              (_) => _FakeLocationRepository(),
            ),
          ],
        );
        await tester.pumpAndSettle();

        final Finder card = find.byKey(
          const ValueKey<String>('my_salons_card_salon-legacy'),
        );
        expect(
          find.descendant(of: card, matching: find.textContaining('Одеса')),
          findsOneWidget,
          reason:
              'no cityId at all -> hasTaxonomyCity is false -> the legacy '
              'value is the only thing there is to show',
        );
      },
    );

    testWidgets(
      'while resolution is still pending, the card renders street/building '
      'immediately and never a spinner or error box',
      (tester) async {
        final oblastsCompleter = Completer<List<Oblast>>();
        await tester.pumpRoutedApp(
          _router(),
          overrides: <Object>[
            mySalonsProvider.overrideWith(
              () => _StubMySalons(() async => <Salon>[_salonWithTaxonomyCity]),
            ),
            locationRepositoryProvider.overrideWith(
              (_) =>
                  _FakeLocationRepository(oblastsCompleter: oblastsCompleter),
            ),
          ],
        );
        // ONE bounded pump — mySalonsProvider's own Future resolves, but the
        // resolvedLocalityProvider cascade is deliberately held open
        // (oblastsCompleter never completes in this test).
        await tester.pump();
        await tester.pump();

        final Finder card = find.byKey(
          const ValueKey<String>('my_salons_card_salon-taxonomy'),
        );
        expect(card, findsOneWidget);
        expect(
          find.descendant(
            of: card,
            matching: find.textContaining('вул. Франка'),
          ),
          findsOneWidget,
          reason:
              'street/building are plain salon fields — they must render '
              'on the FIRST frame, never waiting on the async lookup',
        );
        expect(
          find.descendant(
            of: card,
            matching: find.byType(CircularProgressIndicator),
          ),
          findsNothing,
          reason:
              'AsyncValue.value collapses loading to null — never a '
              'spinner inside the card',
        );
        expect(
          find.descendant(of: card, matching: find.byType(ErrorState)),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'a resolution FAILURE (repository throws) is swallowed — the card '
      'still renders street/building, no error box',
      (tester) async {
        await tester.pumpRoutedApp(
          _router(),
          overrides: <Object>[
            mySalonsProvider.overrideWith(
              () => _StubMySalons(() async => <Salon>[_salonWithTaxonomyCity]),
            ),
            locationRepositoryProvider.overrideWith(
              (_) => _ThrowingLocationRepository(),
            ),
          ],
        );
        await tester.pumpAndSettle();

        final Finder card = find.byKey(
          const ValueKey<String>('my_salons_card_salon-taxonomy'),
        );
        expect(card, findsOneWidget);
        expect(
          find.descendant(
            of: card,
            matching: find.textContaining('вул. Франка'),
          ),
          findsOneWidget,
        );
        expect(find.byType(ErrorState), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  });

  // ===========================================================================
  // Group 9 — swipe-to-delete gate (mobile-qa / mobile-security MEDIUM
  // follow-up, 2026-09). See this file's header for the full case list and
  // the mutation-check result.
  // ===========================================================================
  group('swipe-to-delete gate', () {
    testWidgets(
      'an owner sees a Dismissible on the card; a non-owner role renders '
      'the SAME salon as a plain, un-swipeable card',
      (tester) async {
        for (final bool isOwner in <bool>[true, false]) {
          final GoRouter router = _router();
          addTearDown(router.dispose);
          await tester.pumpRoutedApp(
            router,
            overrides: <Object>[
              mySalonsProvider.overrideWith(
                () => _StubMySalons(
                  () async => <Salon>[_swipeSalonA, _swipeSalonB],
                ),
              ),
              isSalonOwnerProvider.overrideWithValue(isOwner),
            ],
          );
          await tester.pumpAndSettle();

          // The card itself always renders regardless of role.
          expect(_cardA, findsOneWidget, reason: 'isOwner=$isOwner');
          expect(
            _dismissibleA,
            isOwner ? findsOneWidget : findsNothing,
            reason:
                'isOwner=$isOwner — a non-owner must get a plain card, no '
                'swipe affordance at all',
          );
        }
      },
    );

    testWidgets(
      'a FAST fling still awaits DeleteSalonDialog before any deleteSalon() '
      'call fires, and the row is NEVER removed by the gesture itself '
      '(confirmDismiss always returns false)',
      (tester) async {
        final repo = FakeSalonRepository(salon: _swipeSalonA);
        final GoRouter router = _router();
        addTearDown(router.dispose);
        // Deliberately a STABLE `_StubMySalons` (always re-serves BOTH
        // salons, with no backing store to mutate) — the point of this
        // fixture choice is that NOTHING ever invalidates salon-swipe-a out
        // of the list, so if it disappears anyway, that can only be
        // Dismissible's own gesture/animation removing it — exactly the
        // MUTATION TARGET below.
        await tester.pumpRoutedApp(
          router,
          overrides: <Object>[
            mySalonsProvider.overrideWith(
              () => _StubMySalons(
                () async => <Salon>[_swipeSalonA, _swipeSalonB],
              ),
            ),
            isSalonOwnerProvider.overrideWithValue(true),
            salonRepositoryProvider.overrideWithValue(repo),
            authProvider.overrideWith(_AuthenticatedAsOwner.new),
          ],
        );
        await tester.pumpAndSettle();

        // A deliberately fast fling — well above the default drag velocity
        // used elsewhere in this file's tap-based tests.
        await _swipeSalonADismissible(tester, velocity: 4000);
        await tester.pumpAndSettle();

        expect(
          _deleteDialog,
          findsOneWidget,
          reason:
              'even a fast fling must land on the confirm dialog, never '
              'skip straight to deleting',
        );
        expect(
          repo.deleteCalls,
          0,
          reason: 'no delete call before the owner confirms',
        );

        await tester.tap(_confirmDeleteButton);
        // Deliberately bounded pumps, NOT pumpAndSettle: with this stable
        // stub, `_DeleteInFlightOverlay`'s indeterminate
        // `CircularProgressIndicator` never stops animating once
        // `_deletingSalonIds` is set (nothing ever invalidates the id back
        // out — see `MySalonsScreen._deletingSalonIds`'s own doc for why
        // that is inert in a REAL app but not in this fixture) — the SAME
        // never-settles trap this file's header documents for
        // `_HubSkeleton`.
        await tester.pump();

        expect(repo.deleteCalls, 1);
        expect(repo.lastDeleteSalonId, _swipeSalonA.id);

        // MUTATION TARGET (mobile-qa, 2026-09-03): flipping the production
        // `confirmDismiss`'s hard-coded `return false` to `return true`
        // makes `Dismissible` hide its `child` the instant its own
        // move/resize animation reaches `dismissed` — REGARDLESS of
        // whether anything actually removed the salon from the data the
        // parent is still supplying. Under that mutation `_cardA` goes
        // `findsNothing` on the very next pump; with the real `return
        // false` it stays visible for as long as nothing ELSE removes it
        // (proven here by the stub NEVER removing it).
        expect(
          _cardA,
          findsOneWidget,
          reason:
              'confirmDismiss always returns false — the swipe gesture '
              'itself must never make the row disappear',
        );
        expect(
          _dismissibleA,
          findsOneWidget,
          reason: 'the Dismissible element itself must also still be there',
        );
      },
    );

    testWidgets(
      'confirmDismiss returning false: the swiped row is removed ONLY by '
      'the invalidated mySalonsProvider refetch, never by a race with '
      "Dismissible's own dismiss animation, and the REMAINING salon "
      'renders afterward',
      (tester) async {
        // Deliberately UNGATED (no `deleteSalonGate`) — a genuine
        // (non-instant) round trip on this exact path IS covered, gated, by
        // the test right below this one, which passes. This ungated variant
        // stays alongside it because it proves something the gated test
        // does not need to: the row's removal is driven by the provider's
        // own invalidated refetch, not by Dismissible's confirmDismiss
        // return value racing it — a race that only needs the delete call
        // to resolve at all, gated or not.
        final repo = FakeSalonRepository(salon: _swipeSalonA);
        final notifier = _SequencedMySalons(<Future<List<Salon>> Function()>[
          () async => <Salon>[_swipeSalonA, _swipeSalonB],
          // Post-invalidate refetch: the deleted salon is gone, the
          // survivor remains — proves the hub renders the REMAINING
          // salons, not merely "the list shrank".
          () async => <Salon>[_swipeSalonB],
        ]);
        final GoRouter router = _router();
        addTearDown(router.dispose);
        await tester.pumpRoutedApp(
          router,
          overrides: <Object>[
            mySalonsProvider.overrideWith(() => notifier),
            isSalonOwnerProvider.overrideWithValue(true),
            salonRepositoryProvider.overrideWithValue(repo),
            authProvider.overrideWith(_AuthenticatedAsOwner.new),
          ],
        );
        await tester.pumpAndSettle();

        await _swipeSalonADismissible(tester);
        await tester.pumpAndSettle();
        await tester.tap(_confirmDeleteButton);
        await tester.pumpAndSettle();

        // MUTATION TARGET (mobile-qa, 2026-09-03): flipping the production
        // `confirmDismiss`'s hard-coded `return false` to `return true`
        // makes Dismissible race its own dismiss/resize animation against
        // this provider-driven removal, throwing `FlutterError("A
        // dismissed Dismissible widget is still part of the tree")` — that
        // exception surfaces via `tester.takeException()` (or a failed
        // `pumpAndSettle`), so this assertion goes RED under that mutation.
        expect(
          tester.takeException(),
          isNull,
          reason:
              'a Dismissible racing its own dismiss animation against the '
              'invalidated refetch throws — this is the exact trap '
              'confirmDismiss always returning false avoids',
        );
        expect(
          _cardA,
          findsNothing,
          reason:
              'once the invalidated refetch resolves without salon-swipe-a, '
              'its row simply stops being rendered',
        );
        expect(notifier.buildCalls, 2, reason: 'a genuine second fetch');
        expect(
          _cardB,
          findsOneWidget,
          reason: 'the surviving salon must still render',
        );
      },
    );

    // FIXED (mobile-qa CRITICAL finding, swipe-to-delete audit 2026-09-03):
    // a delete round trip that spans more than one frame (any real,
    // non-instant network call) used to throw `UnmountedRefException` from
    // `SalonManagementProfile.deleteSalon()`'s own
    // `ref.invalidate(mySalonsProvider)`
    // (salon_management_profile_notifier.dart) — `salonManagementProfile
    // Provider(salonId)` is an `@riverpod` (autoDispose) family that NOTHING
    // in `MySalonsScreen`'s tree watches, unlike every other caller of
    // `runDeleteSalonFlow`. `deleteSalon()` itself does NOT call
    // `ref.keepAlive()` — it was tried and does not reliably survive this
    // race either (see that method's own doc). The actual fix moved the
    // `mySalonsProvider` invalidation OUT of the notifier entirely: it now
    // lives in `runDeleteSalonFlow` (`delete_salon_flow.dart`), fired
    // through a `ProviderContainer` captured on the CALLING screen's own
    // `context` before the delete call, which has no lifecycle tie to the
    // per-salon `salonManagementProfileProvider` family element at all — so
    // it is correct whether or not that element survives the round trip.
    // Reproduced deterministically below with a
    // `FakeSalonRepository.deleteSalonGate` Completer.
    testWidgets(
      'confirmDismiss returning false leaves the row in the list until '
      'mySalonsProvider invalidation removes it, with the in-flight '
      'overlay shown and the Dismissible element surviving the whole '
      'round trip',
      (tester) async {
        final repo = FakeSalonRepository(salon: _swipeSalonA)
          ..deleteSalonGate = Completer<void>();
        final notifier = _SequencedMySalons(<Future<List<Salon>> Function()>[
          () async => <Salon>[_swipeSalonA, _swipeSalonB],
          // Post-invalidate refetch: the deleted salon is gone, the
          // survivor remains — proves the hub renders the REMAINING
          // salons, not merely "the list shrank".
          () async => <Salon>[_swipeSalonB],
        ]);
        final GoRouter router = _router();
        addTearDown(router.dispose);
        await tester.pumpRoutedApp(
          router,
          overrides: <Object>[
            mySalonsProvider.overrideWith(() => notifier),
            isSalonOwnerProvider.overrideWithValue(true),
            salonRepositoryProvider.overrideWithValue(repo),
            authProvider.overrideWith(_AuthenticatedAsOwner.new),
          ],
        );
        await tester.pumpAndSettle();

        await _swipeSalonADismissible(tester);
        await tester.pumpAndSettle();
        await tester.tap(_confirmDeleteButton);
        await tester.pump(); // run the tap handler up to the gated await

        // The delete call is genuinely in flight (repo counted it, gate not
        // yet completed).
        expect(repo.deleteCalls, 1);
        expect(notifier.buildCalls, 1, reason: 'not yet invalidated');

        // The row is STILL in the list — never removed by Dismissible's own
        // slide-out/resize, only by the provider re-fetching.
        expect(
          _cardA,
          findsOneWidget,
          reason:
              'confirmDismiss always returns false — the swipe gesture '
              'itself must never remove the row',
        );
        expect(
          _dismissibleA,
          findsOneWidget,
          reason:
              'the Dismissible ELEMENT must survive the in-flight window — '
              'it is the Stack\'s base child, never conditionally swapped',
        );
        expect(
          _inFlightOverlaySpinner,
          findsOneWidget,
          reason:
              'the in-flight overlay must render while the delete '
              'round trip is pending',
        );

        // Unblock the delete call — this lets `runDeleteSalonFlow` reach its
        // own `container.invalidate(mySalonsProvider)` (the caller-owned
        // container captured before this await started), triggering the
        // SECOND _SequencedMySalons response.
        repo.deleteSalonGate!.complete();
        await tester.pumpAndSettle();

        expect(
          notifier.buildCalls,
          2,
          reason: 'mySalonsProvider must have genuinely re-fetched',
        );
        expect(
          _cardA,
          findsNothing,
          reason:
              'once the invalidated refetch resolves without salon-swipe-a, '
              'its row (and overlay) simply stop being rendered',
        );
        expect(
          _inFlightOverlaySpinner,
          findsNothing,
          reason: 'the overlay must not linger once the row is gone',
        );
        expect(
          _cardB,
          findsOneWidget,
          reason: 'the surviving salon must still render',
        );
      },
    );
  });
}
