// Regression test — `_StaggeredReveal` must MEMOIZE its per-section reveal
// animations and DISPOSE them on unmount.
//
// THE BUG
// -------
// `_StaggeredRevealState._reveal` is invoked once per section on EVERY build of
// the hub's ListView, and `_HomeHubBody` watches four providers — so the screen
// rebuilds often. Each call allocated a fresh `CurvedAnimation`, and
// `CurvedAnimation`'s constructor registers a status listener on its parent:
//
//   CurvedAnimation({required this.parent, ...}) {
//     ...
//     parent.addStatusListener(_updateCurveDirection);   // ← only dispose()
//   }                                                    //   ever removes it
//
// Nothing disposed them, so `_controller`'s status-listener list grew by six on
// every rebuild and was never drained for the screen's whole lifetime.
//
// THE FIX UNDER TEST
// ------------------
//   • `_reveal` is a `putIfAbsent` over `Map<(double, double), _RevealAnimations>`
//     keyed on the interval record — six distinct intervals, so it converges.
//   • `dispose()` disposes every cached `CurvedAnimation`, clears the map, THEN
//     disposes `_controller` (that order matters: `CurvedAnimation.dispose()`
//     calls `parent.removeStatusListener(...)` and needs the parent alive).
//
// WHY THESE ASSERTIONS AND NOT "the screen still renders"
// ------------------------------------------------------
// The refactor is behaviour-preserving, so any render/golden assertion passes
// identically on the old code. The two halves are only observable as OBJECT
// IDENTITY and OBJECT LIFECYCLE:
//
//   1. Memoization → the `FadeTransition.opacity` / `SlideTransition.position`
//      instances for a section must be the SAME objects after a rebuild, and the
//      set of DISTINCT instances must not grow across repeated rebuilds. On the
//      old code every rebuild minted six new ones.
//   2. Disposal → `CurvedAnimation` exposes a public `isDisposed` flag which
//      `dispose()` sets (see the framework source quoted above). Reading it off
//      the instances captured from the live tree, after the screen is unmounted,
//      is a direct observation of the teardown — not a proxy for it. On the old
//      code it stays `false` forever.
//
// Both halves are verified to go RED on the reverted implementation.
//
// `_StaggeredReveal` and `_RevealAnimations` are private, so everything here
// goes through the public widget tree (`FadeTransition` / `SlideTransition`).

import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/features/booking/application/booking_reschedule_in_flight_notifier.dart';
import 'package:beautica_mobile/features/home/application/home_hub_notifier.dart';
import 'package:beautica_mobile/features/home/domain/home_hub_models.dart';
import 'package:beautica_mobile/features/home/presentation/home_hub_screen.dart';
import 'package:beautica_mobile/features/rating/application/my_rating_notifier.dart';
import 'package:beautica_mobile/features/rating/domain/client_rating.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/pump_app.dart';

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

/// `HomeHubScreen` acquires a [ScreenProtectionManager] in `initState`; the
/// native plugin must not be called from a widget test.
class _NoOpScreenProtection extends ScreenProtectionManager {
  @override
  void acquire() {}

  @override
  void release() {}

  @override
  void reset() {}
}

const ClientProfileSummary _profile = ClientProfileSummary(
  firstName: 'Test',
  lastName: 'Client',
  city: 'Lviv',
  phone: '+380 97 000 00 00',
  clientRating: null,
  memberSinceYear: 2026,
);

/// Successful-value overrides only.
///
/// Riverpod 3.x auto-retries a failed build, so an `AsyncError` driven by
/// `overrideWith((ref) => Future.error(...))` never settles into an error state
/// in a widget test (it re-enters `AsyncLoading(retrying: true)`). Rebuilds here
/// are therefore driven by a real state emission on
/// `bookingRescheduleInFlightProvider`, which `_HomeHubBody` watches.
List<Object> _overrides() => <Object>[
  screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
  myRatingProvider.overrideWith((ref) async => const ClientRating()),
  clientProfileProvider.overrideWith((ref) async => _profile),
  nextAppointmentProvider.overrideWith((ref) async => null),
  favoriteMastersProvider.overrideWith(
    (ref) async => const <FavoriteMasterItem>[],
  ),
  beautyTimelineProvider.overrideWith((ref) async => const <TimelineEntry>[]),
  unlikeFavoriteMasterProvider.overrideWith(() => UnlikeFavoriteMaster()),
];

/// Number of `reveal(...)` call sites in `_HomeHubBody`'s ListView. The fix's
/// contract is that the cache converges at exactly this many entries no matter
/// how many times the body rebuilds. Pumped on a tall surface (see
/// [_pumpHub]) so the ListView materialises every section rather than lazily
/// skipping the ones below the fold.
const int _revealSectionCount = 6;

/// Pumps the real screen on a surface tall enough to build every section.
///
/// `pumpApp`'s `width` knob sets a 2400dp-tall view; without it the default
/// 800x600 surface leaves the last section below the fold and `ListView`'s
/// lazy sliver never builds it, so only five reveals exist.
Future<ProviderContainer> _pumpHub(WidgetTester tester) async {
  await tester.pumpApp(
    const HomeHubScreen(),
    overrides: _overrides(),
    width: 390,
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(HomeHubScreen)));
}

/// Every reveal opacity animation currently in the tree, in section order.
List<Animation<double>> _opacities(WidgetTester tester) => tester
    .widgetList<FadeTransition>(
      find.descendant(
        of: find.byType(HomeHubScreen),
        matching: find.byType(FadeTransition),
      ),
    )
    .map((FadeTransition f) => f.opacity)
    .toList();

/// Every reveal slide animation currently in the tree, in section order.
List<Animation<Offset>> _positions(WidgetTester tester) => tester
    .widgetList<SlideTransition>(
      find.descendant(
        of: find.byType(HomeHubScreen),
        matching: find.byType(SlideTransition),
      ),
    )
    .map((SlideTransition s) => s.position)
    .toList();

/// Emits a new value on a provider `_HomeHubBody` watches, forcing a rebuild of
/// the body — and therefore six fresh `reveal(...)` calls.
Future<void> _rebuildViaProvider(
  WidgetTester tester,
  ProviderContainer container, {
  required bool inFlight,
}) async {
  final BookingRescheduleInFlight notifier = container.read(
    bookingRescheduleInFlightProvider.notifier,
  );
  inFlight ? notifier.begin() : notifier.end();
  await tester.pump();
}

void main() {
  group('_StaggeredReveal — animation memoization', () {
    testWidgets('a provider-driven rebuild reuses the SAME animation objects', (
      WidgetTester tester,
    ) async {
      final ProviderContainer container = await _pumpHub(tester);

      final List<Animation<double>> opacityBefore = _opacities(tester);
      final List<Animation<Offset>> positionBefore = _positions(tester);

      expect(
        opacityBefore,
        hasLength(_revealSectionCount),
        reason:
            'Harness sanity: every reveal section must be materialised, '
            'otherwise the identity assertions below cover only a subset.',
      );

      await _rebuildViaProvider(tester, container, inFlight: true);

      final List<Animation<double>> opacityAfter = _opacities(tester);
      final List<Animation<Offset>> positionAfter = _positions(tester);

      expect(opacityAfter, hasLength(opacityBefore.length));
      for (int i = 0; i < opacityBefore.length; i++) {
        expect(
          identical(opacityBefore[i], opacityAfter[i]),
          isTrue,
          reason:
              'Section $i re-allocated its CurvedAnimation on rebuild. Each new '
              'instance adds a status listener to the reveal controller that '
              'only its own dispose() can remove — that is the leak.',
        );
      }

      for (int i = 0; i < positionBefore.length; i++) {
        expect(
          identical(positionBefore[i], positionAfter[i]),
          isTrue,
          reason:
              'Section $i re-allocated its slide Animation on rebuild; the '
              'cached _RevealAnimations holder must carry the tween view too.',
        );
      }
    });

    testWidgets('repeated rebuilds do not grow the set of animation objects', (
      WidgetTester tester,
    ) async {
      // The defect was UNBOUNDED growth, so the load-bearing measurement is the
      // count of DISTINCT instances the screen has ever exposed — not just
      // equality across one rebuild. Six rebuilds on the old code surface
      // 6 sections x 7 builds = 42 distinct objects; memoized, it stays at 6.
      final ProviderContainer container = await _pumpHub(tester);

      final Set<Animation<double>> seen = Set<Animation<double>>.identity()
        ..addAll(_opacities(tester));

      for (int i = 0; i < 6; i++) {
        await _rebuildViaProvider(tester, container, inFlight: i.isEven);
        seen.addAll(_opacities(tester));
      }

      expect(
        seen,
        hasLength(_revealSectionCount),
        reason:
            'The reveal cache must converge at one CurvedAnimation per distinct '
            '(start, end) interval. Any growth here is a listener accumulating '
            'on the controller for the screen\'s lifetime.',
      );
    });
  });

  group('_StaggeredReveal — animation disposal', () {
    testWidgets('every reveal CurvedAnimation is disposed when the screen '
        'unmounts', (WidgetTester tester) async {
      await _pumpHub(tester);

      final List<CurvedAnimation> curved = _opacities(
        tester,
      ).whereType<CurvedAnimation>().toList();

      expect(
        curved,
        hasLength(_revealSectionCount),
        reason:
            'Every reveal opacity must be a CurvedAnimation — that is the type '
            'holding the controller status listener.',
      );
      expect(
        curved.map((CurvedAnimation a) => a.isDisposed),
        everyElement(isFalse),
        reason:
            'Guard against a vacuous test: while mounted, none may be disposed '
            'yet, so the post-unmount assertion below is a real state change.',
      );

      // Unmount by replacing the whole tree.
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pumpAndSettle();

      expect(
        curved.map((CurvedAnimation a) => a.isDisposed),
        everyElement(isTrue),
        reason:
            'CurvedAnimation.dispose() is the ONLY thing that calls '
            'parent.removeStatusListener(...). Memoizing without disposing '
            'would merely bound the leak, leaving the listener-removal defect '
            'intact — so this is the half that matters most.',
      );
    });

    testWidgets('disposal order leaves no pending framework error', (
      WidgetTester tester,
    ) async {
      // CurvedAnimation.dispose() reaches into its parent, so the cached
      // animations MUST be disposed before _controller. Disposing the
      // controller first would surface as a use-after-dispose FlutterError.
      await _pumpHub(tester);

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pumpAndSettle();

      expect(
        tester.takeException(),
        isNull,
        reason:
            'Tearing down the hub must not throw — dispose the cached '
            'CurvedAnimations first, then the controller.',
      );
    });
  });
}
