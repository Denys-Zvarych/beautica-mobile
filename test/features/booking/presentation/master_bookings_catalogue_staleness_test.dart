// Phase 7.7 audit remediation — the «Послуга» filter universe's two failure
// modes, both of which are about the CATALOGUE PROVIDER'S STATE rather than
// about the sheet that renders it.
//
//   • S1 (security) — an `AsyncError` that still RETAINS the previous account's
//     list must contribute nothing. `AsyncValue.value` returns retained data in
//     `AsyncLoading` and `AsyncError` alike, so reading `.value` leaks account
//     A's service names into account B's filter sheet on a shared device.
//   • S2 (functional) — the provider is `keepAlive`, so without an explicit
//     invalidation edge a service created mid-session never joins the filter
//     universe until the app is restarted.
//
// ## Why these are asserted through the SHEET and not on the provider
//
// Both bugs are only bugs because they reach the UI. A provider-level assertion
// («the AsyncValue is an error») would pass just as happily against the broken
// `.value` read — the whole point of S1 is that the provider IS in an error
// state and the screen used it anyway. So each test drives the real
// `_applyFilters` path and asserts on what the master can actually see.
//
// ## Host-zone independence
//
// Nothing here asserts on a date. The screen reads the clock for its rail
// origin, but no expectation below depends on it. Identical under TZ=UTC and
// TZ=Europe/Kyiv.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/features/booking/application/booked_days_notifier.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/master_bookings_screen.dart';
import 'package:beautica_mobile/features/services/data/master_service_catalog_provider.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';

import '../../../helpers/pump_app.dart';

class _MockBookingRepository extends Mock implements BookingRepository {}

class _NoOpScreenProtection extends ScreenProtectionManager {
  @override
  void acquire() {}
  @override
  void release() {}
}

/// A service repository whose catalogue the test can mutate between fetches,
/// and which can be told to start failing (the logout → 401 path).
class _FakeServiceRepository extends Fake implements ServiceRepository {
  List<MasterService> catalogue = <MasterService>[];
  Object? failWith;
  int fetches = 0;

  @override
  Future<List<MasterService>> listMyServices() async {
    fetches++;
    final Object? failure = failWith;
    if (failure != null) throw failure;
    return catalogue;
  }
}

MasterService _service(String id, String name) => MasterService(
  id: id,
  serviceDefId: 'def-$id',
  name: name,
  durationMinutes: 60,
);

Booking _booking(String id) {
  final DateTime start = DateTime.utc(2026, 7, 20, 12);
  return Booking(
    id: id,
    masterId: 'm1',
    masterFirstName: 'Марія',
    masterLastName: 'Іванюк',
    masterType: 'INDEPENDENT_MASTER',
    clientId: 'c-$id',
    clientFirstName: 'Олена',
    clientLastName: 'Ковальчук',
    serviceId: 'svc-a',
    serviceName: 'Манікюр з покриттям',
    durationMinutes: 90,
    price: 650,
    startAt: start,
    endAt: start.add(const Duration(minutes: 90)),
    status: BookingStatus.confirmed,
    canReview: false,
  );
}

void main() {
  late _MockBookingRepository bookings;
  late _FakeServiceRepository services;

  setUp(() {
    bookings = _MockBookingRepository();
    services = _FakeServiceRepository();
    when(
      () => bookings.getMyBookings(
        statuses: any(named: 'statuses'),
        page: any(named: 'page'),
        size: any(named: 'size'),
        sort: any(named: 'sort'),
        serviceIds: any(named: 'serviceIds'),
        from: any(named: 'from'),
        to: any(named: 'to'),
      ),
    ).thenAnswer(
      (_) async => PageResponse<Booking>(
        items: <Booking>[_booking('b1')],
        page: 0,
        totalPages: 1,
        totalElements: 1,
      ),
    );
  });

  /// Pumps the screen against the REAL `masterServiceCatalogProvider`, wired to
  /// [services].
  ///
  /// Deliberately NOT `masterServiceCatalogProvider.overrideWith(...)` (which
  /// is what the sibling wiring test uses): both bugs under test are about that
  /// provider's own caching and error behaviour, so overriding it away would
  /// replace the subject of the test with a stub. Overriding the REPOSITORY
  /// beneath it keeps the provider real while still keeping Dio out of the tree.
  ///
  /// `retry: (_, _) => null` disables Riverpod's failed-build backoff so an
  /// `AsyncError` stays put through `pumpAndSettle` instead of being retried
  /// into a fresh success (and leaving a pending Timer at test end).
  Future<ProviderContainer> pump(WidgetTester tester) async {
    await tester.pumpRoutedApp(
      GoRouter(
        initialLocation: '/',
        routes: <RouteBase>[
          GoRoute(
            path: '/',
            builder: (BuildContext context, GoRouterState state) =>
                const MasterBookingsScreen(),
          ),
        ],
      ),
      retry: (_, _) => null,
      overrides: <Object>[
        screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
        bookingRepositoryProvider.overrideWithValue(bookings),
        bookedDaysProvider.overrideWith((ref) async => <DateTime>{}),
        serviceRepositoryProvider.overrideWithValue(services),
      ],
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
      tester.element(find.byType(MasterBookingsScreen)),
    );
  }

  Future<void> openFilters(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('master-bookings-filter-button')));
    await tester.pumpAndSettle();
  }

  Future<void> closeFilters(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('master-bookings-filter-apply')));
    await tester.pumpAndSettle();
  }

  final Finder serviceSection = find.byKey(
    const Key('master-bookings-filter-section-service'),
  );

  group('S1 — a retained catalogue never renders', () {
    // MUTATION: reverted `_applyFilters` to
    // `ref.read(masterServiceCatalogProvider).value ?? const []` → this test
    // FAILED (the «Послуга» section rendered, and both of account A's service
    // rows were findable by key). Restored.
    testWidgets(
      'an AsyncError still holding the previous account\'s list contributes '
      'nothing to the filter universe',
      (WidgetTester tester) async {
        // Account A's session: the catalogue resolves normally.
        services.catalogue = <MasterService>[
          _service('svc-a', 'Манікюр з покриттям'),
          _service('svc-b', 'Педикюр'),
        ];
        final ProviderContainer container = await pump(tester);

        // Sanity: A really can see the section. Without this the test could
        // pass by the sheet never rendering a service section at all.
        await openFilters(tester);
        expect(serviceSection, findsOneWidget);
        expect(
          find.byKey(const Key('master-bookings-filter-service-svc-a')),
          findsOneWidget,
        );
        await closeFilters(tester);

        // Logout: `authProvider` flips, the repository is recreated, and the
        // keepAlive catalogue re-runs — into a 401. `logout()` deliberately
        // does NOT invalidate feature providers (cycle avoidance), which is
        // what makes this state reachable in production.
        services.failWith = const UnauthorizedFailure();
        container.invalidate(masterServiceCatalogProvider);
        await tester.pumpAndSettle();

        // THE ANTI-VACUITY ASSERTION.
        //
        // Everything below is only meaningful if the provider is in an error
        // state that STILL CARRIES account A's data — i.e. if `.value` would
        // genuinely have leaked it. Riverpod's seamless-reload retains the
        // previous value across an invalidate, and if a future version stopped
        // doing so this test would silently become a tautology. Pin it.
        final AsyncValue<List<MasterService>> state = container.read(
          masterServiceCatalogProvider,
        );
        expect(state.hasError, isTrue, reason: 'the refetch must have failed');
        expect(
          state.value,
          isNotNull,
          reason:
              'the retained value is the whole hazard — if Riverpod stops '
              'retaining it, this test no longer proves anything and the '
              'production guard needs re-deriving, not this expectation '
              'relaxing',
        );
        expect(state.value, hasLength(2));

        // Account B opens the filter sheet. A's catalogue must be invisible.
        await openFilters(tester);
        expect(
          serviceSection,
          findsNothing,
          reason:
              'an empty universe omits the whole «Послуга» section — the '
              'sheet degrades correctly rather than rendering an empty heading',
        );
        expect(
          find.byKey(const Key('master-bookings-filter-service-svc-a')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('master-bookings-filter-service-svc-b')),
          findsNothing,
        );
      },
    );
  });

  group('S2 — the catalogue is invalidated by a service mutation', () {
    // MUTATION HONESTY NOTE — this test pins the CONSUMER half of S2, not the
    // invalidation edge itself.
    //
    // It invalidates the provider directly, so mutating
    // `invalidateMasterServiceCatalogues` does NOT fail it. That was verified,
    // not assumed.
    //
    // What it pins instead is the SUBSCRIPTION, which is the half of S2 the
    // audit did not identify and which the invalidation edge is useless
    // without: an invalidated `keepAlive` provider with no listeners does not
    // rebuild, so the refetch is deferred to the next read and the sheet opens
    // on `AsyncLoading` — showing no services at all, which is worse than the
    // stale list. MUTATION: replaced `_ServiceCatalogueWarmer` in the screen's
    // column with a plain `SizedBox.shrink()` (i.e. back to the one-shot
    // `ref.read` warm-up) → this test FAILED on the re-fetch count. Restored.
    //
    // The edge itself is pinned in
    // `services_catalogue_invalidation_test.dart`, which drives the real
    // helper and DOES fail when the catalogue line is dropped from it.
    testWidgets(
      'a service created mid-session joins the filter universe after the '
      'shared invalidation',
      (WidgetTester tester) async {
        services.catalogue = <MasterService>[_service('svc-a', 'Манікюр')];
        final ProviderContainer container = await pump(tester);

        await openFilters(tester);
        expect(
          find.byKey(const Key('master-bookings-filter-service-svc-new')),
          findsNothing,
        );
        await closeFilters(tester);

        // Stands in for what `invalidateMasterServiceCatalogues` does to this
        // provider after a create — see the honesty note above for why the
        // helper itself is exercised in its own file rather than here.
        services.catalogue = <MasterService>[
          _service('svc-a', 'Манікюр'),
          _service('svc-new', 'Нарощення вій'),
        ];
        final int before = services.fetches;
        container.invalidate(masterServiceCatalogProvider);
        await tester.pumpAndSettle();

        expect(
          services.fetches,
          before + 1,
          reason: 'the invalidation must actually re-fetch, not re-read cache',
        );

        await openFilters(tester);
        expect(
          find.byKey(const Key('master-bookings-filter-service-svc-new')),
          findsOneWidget,
          reason:
              'a service added mid-session must be filterable without an app '
              'restart — the keepAlive catalogue shipped with no invalidation '
              'edge at all',
        );
      },
    );
  });
}
