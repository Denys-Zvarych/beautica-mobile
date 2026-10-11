// Phase 383 (24.1f) — the owner master-mode «Записи» scope on the SHARED
// `MasterBookingsScreen` / `BookingsDiscoveryView`.
//
// Carry-over from phase 382 QA (MEDIUM): `BookingsDiscoveryView` rebuilt its
// live query through `BookingsDayQuery.dayList(...)` WITHOUT the seed's
// `asOwnerMaster`, and mapped every `MasterOwnDayQuery` to `bookedDaysProvider`.
// So the owner's own-row list reverted to the salon-wide `/bookings/me` on the
// first day/filter change, and the dots were always salon-wide.
//
// Asserted on the arguments the REPOSITORY receives — the only observation
// point that proves the whole chain (seed → `_rebuildQuery` → provider family
// → repo) carried the flag to the wire.
//
// Also pins: exactly ONE booked-days provider is mounted per mount (382 perf
// note), the «‹ Салон» pill renders only when a back label + action are
// passed, and a card tap pushes the host's detail route.
//
// Host-zone note: dates are Kyiv-day tokens from `kyivToday(DateTime.now)` /
// `railDayAt`, compared as-is. Identical under TZ=UTC and TZ=Europe/Kyiv.
//
// Layer: Widget (real BookingsDiscoveryView + real booked-days providers,
// mocked BookingRepository).

import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/features/booking/application/booked_days_notifier.dart';
import 'package:beautica_mobile/features/booking/application/bookings_capability.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_sort.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/master_archive_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/master_bookings_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/bookings_day_rail.dart';
import 'package:beautica_mobile/features/services/data/master_service_catalog_provider.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/pump_app.dart';

class _MockBookingRepository extends Mock implements BookingRepository {}

class _NoOpScreenProtection extends ScreenProtectionManager {
  @override
  void acquire() {}
  @override
  void release() {}
}

DateTime get _kyivToday => kyivToday(DateTime.now);

/// A day on the SAME visible rail week as today (so its chip is tappable),
/// never today itself.
DateTime get _otherDayThisWeek {
  final DateTime monday = mondayOf(_kyivToday);
  return <DateTime>[
    for (int i = 0; i < 7; i++) railDayAt(monday, i),
  ].firstWhere((DateTime d) => d != _kyivToday);
}

const Key _detailMarker = Key('stub-owner-booking-detail');

Booking _booking(String id) {
  final DateTime day = _kyivToday;
  final DateTime start = DateTime.utc(day.year, day.month, day.day, 9);
  return Booking(
    id: id,
    masterId: 'owner-row',
    masterFirstName: 'Олена',
    masterLastName: 'Ковальчук',
    masterType: 'SALON_OWNER',
    clientId: 'c-$id',
    clientFirstName: 'Ірина',
    clientLastName: 'Бондар',
    serviceId: 'svc-a',
    serviceName: 'Манікюр',
    durationMinutes: 60,
    price: 500,
    startAt: start,
    endAt: start.add(const Duration(minutes: 60)),
    status: BookingStatus.confirmed,
    canReview: false,
  );
}

List<Object> _overrides(BookingRepository repo) => <Object>[
  screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
  bookingRepositoryProvider.overrideWithValue(repo),
  masterServiceCatalogProvider.overrideWith(
    (ref) async => const <MasterService>[],
  ),
];

void main() {
  setUpAll(() {
    registerFallbackValue(BookingStatus.confirmed);
    registerFallbackValue(BookingSort.oldest);
    registerFallbackValue(<BookingStatus>[]);
    registerFallbackValue(DateTime(2026));
  });

  late _MockBookingRepository repo;
  late List<bool> listAsMaster;
  late List<DateTime?> listFroms;
  late List<bool> bookedDaysAsMaster;

  setUp(() {
    repo = _MockBookingRepository();
    listAsMaster = <bool>[];
    listFroms = <DateTime?>[];
    bookedDaysAsMaster = <bool>[];
    when(
      () => repo.getMyBookings(
        statuses: any(named: 'statuses'),
        page: any(named: 'page'),
        size: any(named: 'size'),
        cancelToken: any(named: 'cancelToken'),
        sort: any(named: 'sort'),
        serviceIds: any(named: 'serviceIds'),
        from: any(named: 'from'),
        to: any(named: 'to'),
        partition: any(named: 'partition'),
        asMaster: any(named: 'asMaster'),
      ),
    ).thenAnswer((Invocation i) async {
      listAsMaster.add(i.namedArguments[#asMaster] as bool? ?? false);
      listFroms.add(i.namedArguments[#from] as DateTime?);
      return PageResponse<Booking>(
        items: <Booking>[_booking('b1')],
        page: 0,
        totalPages: 1,
        totalElements: 1,
      );
    });
    when(
      () => repo.getMyBookedDays(
        from: any(named: 'from'),
        to: any(named: 'to'),
        cancelToken: any(named: 'cancelToken'),
        asMaster: any(named: 'asMaster'),
      ),
    ).thenAnswer((Invocation i) async {
      bookedDaysAsMaster.add(i.namedArguments[#asMaster] as bool? ?? false);
      return <DateTime>[_kyivToday];
    });
  });

  Future<GoRouter> pump(
    WidgetTester tester, {
    required bool asOwnerMaster,
    String? backLabel,
    VoidCallback? onBack,
  }) async {
    final GoRouter router = GoRouter(
      initialLocation: '/',
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (BuildContext context, GoRouterState state) =>
              MasterBookingsScreen(
                asOwnerMaster: asOwnerMaster,
                detailRouteBuilder: RouteNames.salonStaffBookingDetail,
                backLabel: backLabel,
                onBack: onBack,
              ),
        ),
        GoRoute(
          path: '${RouteNames.salonStaffBookings}/:bookingId',
          builder: (BuildContext context, GoRouterState state) =>
              const Scaffold(body: SizedBox.shrink(key: _detailMarker)),
        ),
      ],
    );
    await tester.pumpRoutedApp(
      router,
      overrides: <Object>[
        screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
        bookingRepositoryProvider.overrideWithValue(repo),
        masterServiceCatalogProvider.overrideWith(
          (ref) async => const <MasterService>[
            MasterService(
              id: 'svc-a',
              serviceDefId: 'def-a',
              name: 'Манікюр',
              durationMinutes: 60,
            ),
          ],
        ),
      ],
    );
    await tester.pumpAndSettle();
    return router;
  }

  Future<void> changeDayAndFilter(WidgetTester tester) async {
    final DateTime otherDay = _otherDayThisWeek;
    await tester.tap(find.byKey(dayChipKey(otherDay)));
    // fixed-wait-ok: advancing past the 220 ms day-select debounce.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(
      listFroms.last,
      otherDay,
      reason: 'fixture guard: the rail tap did not re-scope the query',
    );

    await tester.tap(find.byKey(const Key('master-bookings-filter-button')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('master-bookings-filter-status-cancelled')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('master-bookings-filter-apply')));
    await tester.pumpAndSettle();
  }

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(
        tester.element(find.byType(MasterBookingsScreen)),
      );

  // MUTATION: dropped `asOwnerMaster: asOwnerMaster` from `_masterOwnQuery` →
  // the post-day-change calls carried `false`, this test failed. Restored.
  // MUTATION: mapped every `MasterOwnDayQuery` to `bookedDaysProvider` again →
  // `bookedDaysAsMaster` was `[false]`, this test failed. Restored.
  testWidgets('asOwnerMaster: every getMyBookings (landing, day change, '
      'filter change) and every getMyBookedDays carries asMaster: true; only '
      'the owner booked-days provider is mounted', (tester) async {
    await pump(tester, asOwnerMaster: true);
    await changeDayAndFilter(tester);

    expect(
      listAsMaster.length,
      greaterThanOrEqualTo(3),
      reason: 'landing + day change + filter apply each fetch',
    );
    expect(listAsMaster, everyElement(isTrue));
    expect(bookedDaysAsMaster, isNotEmpty);
    expect(bookedDaysAsMaster, everyElement(isTrue));

    final ProviderContainer container = containerOf(tester);
    expect(container.exists(ownerMasterBookedDaysProvider), isTrue);
    expect(
      container.exists(bookedDaysProvider),
      isFalse,
      reason: 'one rail-dots provider per mount — never both',
    );
  });

  testWidgets('default (asOwnerMaster: false): no call EVER carries '
      'asMaster: true; only the plain booked-days provider is mounted', (
    tester,
  ) async {
    await pump(tester, asOwnerMaster: false);
    await changeDayAndFilter(tester);

    expect(listAsMaster.length, greaterThanOrEqualTo(3));
    expect(listAsMaster, everyElement(isFalse));
    expect(bookedDaysAsMaster, isNotEmpty);
    expect(bookedDaysAsMaster, everyElement(isFalse));

    final ProviderContainer container = containerOf(tester);
    expect(container.exists(bookedDaysProvider), isTrue);
    expect(container.exists(ownerMasterBookedDaysProvider), isFalse);
  });

  testWidgets('backLabel + onBack render the labelled pill and tapping it '
      'calls onBack', (tester) async {
    int backs = 0;
    await pump(
      tester,
      asOwnerMaster: true,
      backLabel: 'Salon-pill',
      onBack: () => backs++,
    );

    final Finder back = find.byKey(const Key('bookings-discovery-back'));
    expect(back, findsOneWidget);
    expect(
      find.descendant(of: back, matching: find.text('Salon-pill')),
      findsOneWidget,
    );
    await tester.tap(back);
    await tester.pump();
    expect(backs, 1);
  });

  // Phase 383 (LOW layout) — at 320 dp the labelled pill would leave the
  // «Записи» title ~1 glyph next to archive + filter + (+), so the header
  // collapses it to the icon-only chevron: same key, same semantics, still
  // tappable. MUTATION: `labelledBackFits` forced `true` → this test failed.
  testWidgets('320 dp: the labelled pill collapses to the icon-only chevron, '
      'semantics and tap intact', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    int backs = 0;
    await pump(
      tester,
      asOwnerMaster: true,
      backLabel: 'Salon-pill',
      onBack: () => backs++,
    );

    final Finder back = find.byKey(const Key('bookings-discovery-back'));
    expect(back, findsOneWidget);
    expect(
      find.descendant(of: back, matching: find.text('Salon-pill')),
      findsNothing,
    );
    expect(tester.getSize(back), const Size(48, 48));
    final SemanticsHandle handle = tester.ensureSemantics();
    final BuildContext ctx = tester.element(back);
    expect(
      tester.getSemantics(back),
      isSemantics(
        label: AppLocalizations.of(ctx).bookingsDiscoveryBackSemantics,
        isButton: true,
      ),
    );
    handle.dispose();
    await tester.tap(back);
    await tester.pump();
    expect(backs, 1);
  });

  testWidgets('no onBack (the tab-root default) renders no back button even '
      'with a backLabel', (tester) async {
    await pump(tester, asOwnerMaster: true, backLabel: 'Salon-pill');
    expect(find.byKey(const Key('bookings-discovery-back')), findsNothing);
  });

  testWidgets('a card tap pushes the host detail route '
      '(/salon/bookings/<id>)', (tester) async {
    final GoRouter router = await pump(tester, asOwnerMaster: true);
    await tester.tap(find.byKey(const Key('master-booking-card-b1')));
    await tester.pumpAndSettle();
    expect(find.byKey(_detailMarker), findsOneWidget);
    // `push` yields an ImperativeRouteMatch, which `currentConfiguration.uri`
    // excludes — read the LEAF match instead.
    expect(
      router.routerDelegate.currentConfiguration.last.matchedLocation,
      RouteNames.salonStaffBookingDetail('b1'),
    );
  });

  // Phase 383 QA — the detail push forwards `detailExtra` verbatim (the
  // owner mount's salon id → `BookingDetailScreen.salonId` → salon board dots
  // drop on a write), and (+) runs the host's `onCreateBooking` instead of
  // the INDEPENDENT_MASTER default `/master/bookings/new`.
  // MUTATION: dropped `extra: detailExtra` from `onBookingTap` → `extra` was
  // null, the first test failed. Restored.
  // MUTATION: dropped `onCreateBooking: onCreateBooking` from the view
  // wiring → (+) pushed the `/master/bookings/new` stub, the second test
  // failed. Restored.
  testWidgets('a card tap pushes detail with the host detailExtra on extra', (
    tester,
  ) async {
    Object? seenExtra = const Object();
    await tester.pumpRoutedApp(
      GoRouter(
        initialLocation: '/',
        routes: <RouteBase>[
          GoRoute(
            path: '/',
            builder: (BuildContext context, GoRouterState state) =>
                const MasterBookingsScreen(
                  asOwnerMaster: true,
                  detailRouteBuilder: RouteNames.salonStaffBookingDetail,
                  detailExtra: 'salon-owner-1',
                ),
          ),
          GoRoute(
            path: '${RouteNames.salonStaffBookings}/:bookingId',
            builder: (BuildContext context, GoRouterState state) {
              seenExtra = state.extra;
              return const Scaffold(body: SizedBox.shrink(key: _detailMarker));
            },
          ),
        ],
      ),
      overrides: _overrides(repo),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('master-booking-card-b1')));
    await tester.pumpAndSettle();

    expect(find.byKey(_detailMarker), findsOneWidget);
    expect(seenExtra, 'salon-owner-1');
  });

  testWidgets('(+) runs the host onCreateBooking, never the default '
      '/master/bookings/new push', (tester) async {
    int creates = 0;
    const Key defaultWizard = Key('stub-default-master-wizard');
    await tester.pumpRoutedApp(
      GoRouter(
        initialLocation: '/',
        routes: <RouteBase>[
          GoRoute(
            path: '/',
            builder: (BuildContext context, GoRouterState state) =>
                MasterBookingsScreen(
                  asOwnerMaster: true,
                  detailRouteBuilder: RouteNames.salonStaffBookingDetail,
                  onCreateBooking: () => creates++,
                ),
          ),
          GoRoute(
            path: RouteNames.masterBookingNew,
            builder: (BuildContext context, GoRouterState state) =>
                const Scaffold(body: SizedBox.shrink(key: defaultWizard)),
          ),
        ],
      ),
      overrides: <Object>[
        ..._overrides(repo),
        // The owner mount's role (SALON_OWNER) may create — the gate itself
        // is pinned elsewhere; here only WHERE (+) goes matters.
        bookingCreationEnabledProvider.overrideWithValue(true),
      ],
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('master-bookings-add')));
    await tester.pumpAndSettle();

    expect(creates, 1);
    expect(find.byKey(defaultWizard), findsNothing);
  });

  // MUTATION: dropped `asOwnerMaster: widget.asOwnerMaster` from
  // `MasterArchiveScreen._query` → the archive fetched with `false`, this
  // test failed. Restored.
  for (final bool owner in <bool>[true, false]) {
    testWidgets('MasterArchiveScreen(asOwnerMaster: $owner) fetches '
        '/bookings/me with asMaster: $owner', (tester) async {
      await tester.pumpRoutedApp(
        GoRouter(
          initialLocation: '/',
          routes: <RouteBase>[
            GoRoute(
              path: '/',
              builder: (BuildContext context, GoRouterState state) =>
                  MasterArchiveScreen(
                    asOwnerMaster: owner,
                    detailRouteBuilder: RouteNames.salonStaffBookingDetail,
                    reviewRouteBuilder: RouteNames.salonStaffClientReview,
                  ),
            ),
          ],
        ),
        overrides: <Object>[
          screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
          bookingRepositoryProvider.overrideWithValue(repo),
          masterServiceCatalogProvider.overrideWith(
            (ref) async => const <MasterService>[],
          ),
        ],
      );
      await tester.pumpAndSettle();

      expect(listAsMaster, isNotEmpty);
      expect(listAsMaster, everyElement(owner));
    });
  }
}
