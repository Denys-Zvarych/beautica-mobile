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
//
// Strategy: `mySalonsProvider` (a `@Riverpod(keepAlive: true)` CLASS
// provider) is overridden directly with small `MySalons` subclasses —
// mirrors `salon_bookings_route_shadowing_test.dart`'s own `_SettledMySalons`
// shape. This sidesteps `authProvider` entirely (`my_salons_notifier_test
// .dart` owns that leg) and keeps this file scoped to the SCREEN's own
// loading/data/error/empty branches and navigation.
//
// LOADING-STATE PUMP TRAP: `_HubSkeleton` wraps `SkeletonShimmerScope`, whose
// `AnimationController` is `..repeat(reverse: true)` — it never settles, so
// `pumpAndSettle()` on the loading-state test would hang forever. A single
// bounded `tester.pump()` is used instead, mirroring
// `public_salon_profile_screen_test.dart`'s own precedent for the exact same
// widget.

import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/salon/application/my_salons_notifier.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/salon/presentation/my_salons_screen.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:beautica_mobile/shared/widgets/skeleton_shimmer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/pump_app.dart';

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
}
