// Phase 330 / 332 — pins the RESOLVED screen TYPE for the four
// `/staff/bookings*` routes, not merely that SOME `GoRoute` in the tree
// happens to carry a matching `path` string.
//
// ## Why this file exists
//
// `app_router.dart` registers, as top-level siblings:
//   • `/staff/bookings/archive`          (literal)
//   • `/staff/bookings/:bookingId`       (dynamic)
//   • `/staff/bookings/:bookingId/review`
//
// go_router resolves literal-before-dynamic siblings ONLY by DECLARATION
// ORDER. `/staff/bookings/:bookingId` matches `/staff/bookings/archive`
// perfectly happily, binding `bookingId == 'archive'`; the only thing that
// stops it is that `archive` is declared first. Nothing but a comment
// enforces that in the source.
//
// `app_router_page_type_test.dart`'s `_findRoute` walks the tree and returns
// the first `GoRoute` whose OWN `path` field equals the target string — a
// structural property of the node, NOT of go_router's matcher. Reordering
// the siblings changes no node's `path`, so that helper cannot see the
// regression. This is the same gap
// `master_bookings_route_shadowing_test.dart` closed one subtree up
// (`/master/bookings`), and this file is its `/staff/*` twin — same
// mechanism, same fixtures shape, SALON_MASTER session instead of
// INDEPENDENT_MASTER.
//
// Catching an order regression requires running go_router's own matcher —
// pumping the REAL `appRouterProvider`, driving `router.go(...)`, and
// asserting on the WIDGET TYPE that actually mounts.
//
// ## What the CONTROL arm is for
//
// The last group re-drives the same four paths for an INDEPENDENT_MASTER and
// asserts the role is bounced to `/master/profile` every time. Without it,
// a mistake that registered these routes OUTSIDE the `/staff/*` gate — or
// widened that gate — would pass every assertion above.
//
// Layer: Widget (real appRouterProvider + real authRedirect, fake repos).

import 'package:beautica_mobile/core/app_start_time.dart';
import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/appointment.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_partition.dart';
import 'package:beautica_mobile/features/booking/domain/booking_sort.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/domain/create_booking_request.dart';
import 'package:beautica_mobile/features/booking/domain/create_master_booking_request.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_detail_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/leave_client_feedback_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/master_archive_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/master_bookings_screen.dart';
import 'package:beautica_mobile/features/master/application/salon_master_own_profile_notifier.dart';
import 'package:beautica_mobile/features/master/data/master_repository.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_notifier.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_screen.dart';
import 'package:beautica_mobile/features/schedule/data/schedule_repository.dart';
import 'package:beautica_mobile/features/schedule/data/schedule_repository_provider.dart';
import 'package:beautica_mobile/features/schedule/domain/schedule_model.dart';
import 'package:beautica_mobile/features/schedule/domain/weekly_schedule.dart';
import 'package:beautica_mobile/features/services/data/master_service_catalog_provider.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/app_router.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/time/time_zones.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers/fakes/fake_auth_repository.dart';
import '../helpers/fakes/fake_master_repository.dart';
import '../helpers/fakes/fake_secure_storage.dart';
import '../helpers/fakes/fake_service_repository.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const String _kSalonId = 'salon-S';
const String _kMasterRowId = 'master-row-M';

/// A bookingId that is NOT `archive` and NOT `new` — so the `:bookingId`
/// assertions cannot pass for the wrong reason.
const String _kBookingId = '11111111-2222-4333-8444-555555555555';

const User _salonMasterUser = User(
  id: 'user-sm-1',
  email: 'salonmaster@beautica.ua',
  role: UserRole.salonMaster,
  firstName: 'Ірина',
  lastName: 'Салонна',
  salonId: _kSalonId,
);

const User _independentMasterUser = User(
  id: 'user-im-1',
  email: 'solo@beautica.ua',
  role: UserRole.independentMaster,
  firstName: 'Соло',
  lastName: 'Майстер',
);

class _FixedAuthNotifier extends AuthNotifier {
  _FixedAuthNotifier(this._user);

  final User _user;

  @override
  Future<AuthSession> build() async {
    final AuthSession session = AuthSession.authenticated(
      user: _user,
      accessToken: 'token',
    );
    state = AsyncData<AuthSession>(session);
    return session;
  }
}

class _SettledMasterProfileNotifier extends MasterProfile {
  @override
  Future<Master> build() async => const Master(
    id: _kMasterRowId,
    firstName: 'Ірина',
    lastName: 'Салонна',
    avgRating: 0,
    reviewCount: 0,
    type: MasterType.salonMaster,
    salonId: _kSalonId,
  );
}

/// An «Архів» row that is CLOSEABLE: `awaitingClosure` is the server flag the
/// «Виконано» slot is gated on, and the start instant is a FIXED PAST literal
/// so `MasterBookingCard`'s belt-and-braces `hasStartedAt(now)` term is
/// satisfied against the real `clockProvider` for all time (a past literal can
/// never drift into "upcoming" — the reason `booking_fixture_dates.dart` only
/// requires the relative helper for FUTURE fixtures; no second clock is
/// introduced here, so the file stays clock-coherent).
final Booking _closeableArchiveRow = Booking(
  id: _kBookingId,
  masterId: _kMasterRowId,
  masterFirstName: 'Ірина',
  masterLastName: 'Салонна',
  masterType: 'SALON_MASTER',
  clientFirstName: 'Олена',
  clientLastName: 'Ковальчук',
  serviceId: 'svc-1',
  serviceName: 'Манікюр з покриттям',
  durationMinutes: 60,
  price: 500,
  startAt: DateTime.utc(2000, 1, 1, 10),
  endAt: DateTime.utc(2000, 1, 1, 11),
  status: BookingStatus.confirmed,
  canReview: false,
  awaitingClosure: true,
);

/// Every method throws except the two list reads the mounted screens make, so
/// an unexpected call fails loudly rather than silently hitting real Dio.
class _FakeBookingRepository implements BookingRepository {
  /// ADDITIVE, defaulting to the empty page every pre-existing test in this
  /// file was written against — so none of them changed behaviour when the
  /// phase-332 gate group below started needing a real row.
  const _FakeBookingRepository({this.rows = const <Booking>[]});

  final List<Booking> rows;

  @override
  Future<PageResponse<Booking>> getMyBookings({
    required Iterable<BookingStatus> statuses,
    required int page,
    int size = kBookingsPageSize,
    BookingSort? sort,
    Iterable<String>? serviceIds,
    DateTime? from,
    DateTime? to,
    BookingPartition? partition,
    CancelToken? cancelToken,
  }) async => PageResponse<Booking>(
    items: rows,
    page: 0,
    totalPages: 1,
    totalElements: rows.length,
  );

  @override
  Future<List<DateTime>> getMyBookedDays({
    required DateTime from,
    required DateTime to,
    CancelToken? cancelToken,
  }) async => const <DateTime>[];

  @override
  Future<Appointment> createMasterBooking(
    String masterId,
    CreateMasterBookingRequest request,
  ) => throw UnimplementedError();

  @override
  Future<Booking> createBooking(CreateBookingRequest req) =>
      throw UnimplementedError();

  @override
  Future<Booking> getBookingById(String id) => throw UnimplementedError();

  @override
  Future<void> cancelBooking(String id, {String? reason}) =>
      throw UnimplementedError();

  @override
  Future<void> declineBooking(String id, {String? comment}) =>
      throw UnimplementedError();

  @override
  Future<void> completeBooking(String id) => throw UnimplementedError();

  @override
  Future<Booking> rescheduleBooking(
    String id,
    DateTime newStartAt, {
    bool allowClientOverlap = false,
  }) => throw UnimplementedError();

  @override
  Future<void> createReview({
    required String bookingId,
    required int rating,
    String? comment,
  }) => throw UnimplementedError();
}

/// `MasterBookingsScreen` mounts with `useScheduleWindow: true`, which watches
/// `effectiveScheduleProvider`. Left un-overridden that fires a REAL Dio
/// request whose connection-timeout `Timer` outlives the tree — same flake
/// class as the role-landing fetch above.
class _EmptyScheduleRepository implements ScheduleRepository {
  @override
  Future<List<EffectiveDay>> effectiveSchedule(DateTime from, DateTime to) =>
      Future<List<EffectiveDay>>.value(const <EffectiveDay>[]);

  @override
  Future<List<WeeklySchedule>> listWeeklySchedules() =>
      Future<List<WeeklySchedule>>.value(const <WeeklySchedule>[]);

  @override
  Future<List<ScheduleOverride>> listOverrides(DateTime from, DateTime to) =>
      Future<List<ScheduleOverride>>.value(const <ScheduleOverride>[]);

  @override
  Future<WeeklySchedule> upsertWeeklySchedule(
    WeeklySchedule schedule, {
    String? scheduleId,
  }) => throw UnimplementedError();

  @override
  Future<void> deleteWeeklySchedule(String scheduleId) =>
      throw UnimplementedError();

  @override
  Future<ScheduleOverride> putOverride(
    ScheduleOverride override, {
    bool cancelOverlapping = false,
  }) => throw UnimplementedError();

  @override
  Future<void> clearOverride(DateTime date) => throw UnimplementedError();

  @override
  Future<OverrideConflictCheck> previewConflicts(ScheduleOverride span) =>
      throw UnimplementedError();
}

class _RouterApp extends StatelessWidget {
  const _RouterApp({required this.router});

  final GoRouter router;

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    routerConfig: router,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('uk', 'UA'),
  );
}

void main() {
  // `MasterArchiveScreen` groups its rows by KYIV day (`groupArchiveByKyivDay`
  // → `kyivDayOf`), which reads the tz database. Idempotent; a no-op for the
  // pre-existing groups here, which mount an EMPTY archive and never group.
  setUpAll(initBeauticaTimeZones);

  setUp(
    () => AppStartTime.setStartForTest(
      DateTime.now().subtract(const Duration(seconds: 5)),
    ),
  );
  tearDown(AppStartTime.resetForTest);

  ProviderContainer makeContainer(User user, {List<Booking> rows = const []}) {
    final container = ProviderContainer(
      // Retry DISABLED (not `beauticaProviderRetry`): this file mounts the
      // real role landing on the way to each route under test, and a provider
      // it reads without an override (e.g. the salon-master own-profile fetch)
      // legitimately fails here — the production retry policy then schedules a
      // `Timer`, which trips flutter_test's "a Timer is still pending"
      // invariant at teardown. Retry BEHAVIOUR is not what this file pins;
      // route RESOLUTION is.
      retry: (int retryCount, Object error) => null,
      overrides: [
        authProvider.overrideWith(() => _FixedAuthNotifier(user)),
        authRepositoryProvider.overrideWith((_) => FakeAuthRepository()),
        secureStorageProvider.overrideWith((_) => FakeSecureStorage()),
        masterProfileProvider.overrideWith(_SettledMasterProfileNotifier.new),
        masterRepositoryProvider.overrideWith((_) => FakeMasterRepository()),
        serviceRepositoryProvider.overrideWith((_) => FakeServiceRepository()),
        approvedCategoriesProvider.overrideWith(
          (ref) async => const <ServiceCategoryOption>[],
        ),
        masterServiceCatalogProvider.overrideWith(
          (ref) async => const <MasterService>[],
        ),
        bookingRepositoryProvider.overrideWith(
          (_) => _FakeBookingRepository(rows: rows),
        ),
        // The SALON_MASTER role landing (`/staff/profile`) is mounted on the
        // way to every route under test. Left un-overridden it fires a REAL
        // Dio request whose connection-timeout `Timer` outlives the tree and
        // trips flutter_test's `!timersPending` invariant — the exact flake
        // `app_router_no_leaked_timer_test.dart` documents. Settled here so
        // the landing resolves synchronously and schedules nothing.
        scheduleRepositoryProvider.overrideWith(
          (ref, scope) => _EmptyScheduleRepository(),
        ),
        salonMasterOwnProfileProvider.overrideWith(
          (ref) async => (
            const Master(
              id: _kMasterRowId,
              firstName: 'Ірина',
              lastName: 'Салонна',
              avgRating: 0,
              reviewCount: 0,
              type: MasterType.salonMaster,
              salonId: _kSalonId,
            ),
            const <MasterService>[],
            null,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<GoRouter> pumpRouter(
    WidgetTester tester,
    User user, {
    List<Booking> rows = const [],
  }) async {
    final container = makeContainer(user, rows: rows);
    final GoRouter router = container.read(appRouterProvider);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _RouterApp(router: router),
      ),
    );
    await container.read(authProvider.future);
    await tester.pump();
    return router;
  }

  // -------------------------------------------------------------------------
  // The matcher-level pin. Asserting `pathParameters` is EMPTY is what makes
  // this non-vacuous: a shadowed `/staff/bookings/archive` still resolves to
  // "some route", it just carries `{bookingId: 'archive'}`.
  // -------------------------------------------------------------------------
  group('go_router matcher — the literal is not swallowed by :bookingId', () {
    testWidgets('/staff/bookings/archive resolves the ARCHIVE route with NO '
        'path parameters', (tester) async {
      final GoRouter router = await pumpRouter(tester, _salonMasterUser);

      final RouteMatchList match = router.configuration.findMatch(
        Uri.parse(RouteNames.salonMasterBookingsArchive),
      );

      expect(match.isError, isFalse);
      expect(
        match.pathParameters,
        isEmpty,
        reason:
            'a non-empty map here means :bookingId absorbed the literal as '
            'bookingId == "archive" — the exact shadowing this file exists '
            'to catch.',
      );
      expect(
        (match.matches.last.route as GoRoute).path,
        RouteNames.salonMasterBookingsArchive,
      );
    });

    testWidgets('/staff/bookings/<uuid> still binds bookingId', (tester) async {
      final GoRouter router = await pumpRouter(tester, _salonMasterUser);

      final RouteMatchList match = router.configuration.findMatch(
        Uri.parse(RouteNames.salonMasterBookingDetail(_kBookingId)),
      );

      expect(match.isError, isFalse);
      expect(match.pathParameters['bookingId'], _kBookingId);
    });
  });

  // -------------------------------------------------------------------------
  // The page-TYPE pin — the one that actually proves the right SCREEN renders.
  // -------------------------------------------------------------------------
  group('SALON_MASTER — the four /staff/bookings* routes resolve to the SAME '
      'screens the INDEPENDENT_MASTER uses', () {
    testWidgets('/staff/bookings renders MasterBookingsScreen', (tester) async {
      final GoRouter router = await pumpRouter(tester, _salonMasterUser);

      router.go(RouteNames.salonMasterBookings);
      await tester.pump();
      await tester.pump();

      expect(find.byType(MasterBookingsScreen), findsOneWidget);
      expect(
        find.byType(MasterProfileScreen),
        findsNothing,
        reason: 'a bounce would land back on the role landing, not here',
      );

      // This screen's two keepAlive caches arm real `Timer`s —
      // `booked_days_notifier.dart:126` (30 min) and
      // `effective_schedule_notifier.dart:288` (5 min) — which outlive the
      // widget tree and trip flutter_test's `!timersPending` teardown
      // invariant. Dispose the tree and drain the fake clock past the longer
      // of the two, the pattern `app_router_no_leaked_timer_test.dart`
      // documents. Not needed on the other three routes: none of them mounts
      // the day list.
      await tester.pumpWidget(const SizedBox.shrink());
      // fixed-wait-ok: a TTL CROSSING, not a guess — the two keepAlive links
      // named above close on 5-minute and 30-minute `Timer`s, so the wait has
      // to be longer than the longer of the two literals; there is no state
      // to pump UNTIL, the whole point is that nothing remains scheduled.
      await tester.pump(const Duration(minutes: 31));
    });

    testWidgets('/staff/bookings/archive renders MasterArchiveScreen, never '
        'BookingDetailScreen', (tester) async {
      final GoRouter router = await pumpRouter(tester, _salonMasterUser);

      router.go(RouteNames.salonMasterBookingsArchive);
      await tester.pump();
      await tester.pump();

      expect(
        find.byType(MasterArchiveScreen),
        findsOneWidget,
        reason:
            'if :bookingId ever moves ahead of archive in app_router.dart, '
            'go_router absorbs "archive" as a booking id and the archive '
            'becomes unreachable — this must catch that.',
      );
      expect(find.byType(BookingDetailScreen), findsNothing);
    });

    testWidgets('/staff/bookings/<uuid> renders BookingDetailScreen', (
      tester,
    ) async {
      final GoRouter router = await pumpRouter(tester, _salonMasterUser);

      router.go(RouteNames.salonMasterBookingDetail(_kBookingId));
      await tester.pump();
      await tester.pump();

      expect(find.byType(BookingDetailScreen), findsOneWidget);
      expect(find.byType(MasterArchiveScreen), findsNothing);
    });

    testWidgets(
      '/staff/bookings/<uuid>/review renders LeaveClientFeedbackScreen — the '
      'ONE write backend phase 316 grants this role must be reachable',
      (tester) async {
        final GoRouter router = await pumpRouter(tester, _salonMasterUser);

        router.go(RouteNames.salonMasterClientReview(_kBookingId));
        await tester.pump();
        await tester.pump();

        expect(find.byType(LeaveClientFeedbackScreen), findsOneWidget);
        expect(
          find.byType(BookingDetailScreen),
          findsNothing,
          reason:
              'registered STANDALONE, not nested under the detail route — a '
              'nested registration mounts a shadow detail page underneath '
              'and breaks pop-back from the archive entry path (see '
              'RouteNames.clientReview\'s own registration comment).',
        );
      },
    );
  });

  // -------------------------------------------------------------------------
  // Phase 332 — the transitions gate holds AT THE ROUTE, not only on a
  // directly-pumped screen.
  //
  // `master_archive_screen_test.dart`'s phase-332 group pins «Виконано» on a
  // `MasterArchiveScreen` pumped by hand, under a bespoke `GoRouter` and a
  // hand-built override list. That harness cannot see anything the REAL
  // `/staff/*` mount contributes: the shell, the role landing it passes
  // through, or any future `ProviderScope`/`overrides` added at or above the
  // shell. A shell-level override of `bookingTransitionsEnabledProvider`
  // would silently RE-ARM the close affordance at this route while that
  // direct-pump test stayed green — mobile-security, 2026-09-15.
  //
  // Pinned here by driving the production `appRouterProvider` to the real
  // path and asserting the FINDER (never a widget property — a field read
  // proves nothing about what rendered).
  //
  // ANTI-VACUITY (M14): an absence assertion passes for the wrong reason
  // whenever the row, the list, or the whole screen failed to build. So the
  // row's own card key is asserted PRESENT first, and the second test drives
  // the SAME fixture through the `/master/bookings/archive` mount under an
  // `INDEPENDENT_MASTER` session and requires the SAME key to be PRESENT.
  // Only the session differs between the two arms.
  // -------------------------------------------------------------------------
  group('Phase 332 — «Виконано» at the ROUTE', () {
    testWidgets(
      '/staff/bookings/archive renders the row but NOT «Виконано» for a '
      'SALON_MASTER',
      (tester) async {
        final GoRouter router = await pumpRouter(
          tester,
          _salonMasterUser,
          rows: <Booking>[_closeableArchiveRow],
        );

        router.go(RouteNames.salonMasterBookingsArchive);
        await tester.pumpAndSettle();

        expect(
          find.byType(MasterArchiveScreen),
          findsOneWidget,
          reason: 'the mount itself must resolve — see the shadowing group.',
        );
        expect(
          find.byKey(const Key('master-booking-card-$_kBookingId')),
          findsOneWidget,
          reason:
              'ANTI-VACUITY — the closeable row must actually be on screen, '
              'otherwise the absence below would pass on an empty archive.',
        );
        expect(
          find.byKey(const Key('master-booking-card-complete-$_kBookingId')),
          findsNothing,
          reason:
              'bookingTransitionsEnabledProvider resolves false for '
              'SALON_MASTER, so the close affordance must be ABSENT at the '
              'REAL route — not merely on a hand-pumped screen.',
        );
      },
    );

    testWidgets('CONTROL — the SAME row DOES render «Виконано» at '
        '/master/bookings/archive for an INDEPENDENT_MASTER', (tester) async {
      final GoRouter router = await pumpRouter(
        tester,
        _independentMasterUser,
        rows: <Booking>[_closeableArchiveRow],
      );

      router.go(RouteNames.masterBookingsArchive);
      await tester.pumpAndSettle();

      expect(find.byType(MasterArchiveScreen), findsOneWidget);
      expect(
        find.byKey(const Key('master-booking-card-complete-$_kBookingId')),
        findsOneWidget,
        reason:
            'the SAME screen, the SAME fixture, the SAME production router '
            '— only the session differs. Without this arm the absence above '
            'would also pass if the row simply stopped rendering its action '
            'slots, or if the gate were wired to something other than the '
            'role.',
      );

      // `/master/bookings/archive` is a NESTED child of `/master/bookings`,
      // so the parent `MasterBookingsScreen` builds underneath and arms the
      // two keepAlive `Timer`s `booked_days_notifier.dart:126` (30 min) and
      // `effective_schedule_notifier.dart:288` (5 min) — which outlive the
      // tree and trip `!timersPending`. Drained exactly as the
      // `/staff/bookings` test above does; the `/staff/bookings/archive`
      // arm needs no drain because that route is registered FLAT, with no
      // bookings parent.
      await tester.pumpWidget(const SizedBox.shrink());
      // fixed-wait-ok: a TTL CROSSING past the longer of the two literals
      // named above, not a guess — there is no state to pump UNTIL.
      await tester.pump(const Duration(minutes: 31));
    });
  });

  // -------------------------------------------------------------------------
  // Phase 330 — «Додати робочі години» at the ROUTE.
  //
  // mobile-qa branch audit, 2026-09-15: `canAddWorkingHours` — the phase-330
  // parameter `app_router.dart` passes `false` on THIS mount, and the
  // nullable `MasterBookingsNoWorkingHoursState.onAddHours` it drives — had
  // ZERO references anywhere in `test/` or `integration_test/`. That is the
  // empty state the router's own comment calls "a COMMON landing for an
  // invited master (the salon owns their schedule)", and the CTA it drops is
  // a SCHEDULE WRITE `scheduleEditableProvider` has denied this role since
  // phase 309 — so the route would have been the only thing standing between
  // a read-only master and a write, with nothing pinning it.
  //
  // `_EmptyScheduleRepository` returns no effective days, which is exactly
  // the "no working hours" condition, so both arms reach the state naturally.
  // Same two-arm shape as the «Виконано» group above: the state's own key is
  // asserted PRESENT first (M14 anti-vacuity), and the INDEPENDENT_MASTER
  // control requires the CTA to be PRESENT on the same fixture.
  // -------------------------------------------------------------------------
  group('Phase 330 — «Додати робочі години» at the ROUTE', () {
    Future<void> drain(WidgetTester tester) async {
      // `MasterBookingsScreen`'s two keepAlive caches arm real `Timer`s (30
      // min / 5 min) that outlive the tree — see the `/staff/bookings` test
      // above for the full note.
      await tester.pumpWidget(const SizedBox.shrink());
      // fixed-wait-ok: a TTL CROSSING past the longer literal, not a guess.
      await tester.pump(const Duration(minutes: 31));
    }

    testWidgets(
      '/staff/bookings renders the no-working-hours state but NOT its CTA '
      'for a SALON_MASTER',
      (tester) async {
        final GoRouter router = await pumpRouter(tester, _salonMasterUser);

        router.go(RouteNames.salonMasterBookings);
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('master-bookings-no-schedule')),
          findsOneWidget,
          reason:
              'ANTI-VACUITY — the empty state itself must render, otherwise '
              'the absence below would pass on a list that never reached it.',
        );
        expect(
          find.byKey(const Key('master-bookings-no-schedule-cta')),
          findsNothing,
          reason:
              'publishing working hours is a schedule WRITE this role has '
              'been denied since phase 309; the route passes '
              'canAddWorkingHours: false so the CTA must be ABSENT, not '
              'disabled.',
        );

        await drain(tester);
      },
    );

    testWidgets(
      'CONTROL — /master/bookings renders the SAME state WITH the CTA for an '
      'INDEPENDENT_MASTER',
      (tester) async {
        final GoRouter router = await pumpRouter(
          tester,
          _independentMasterUser,
        );

        router.go(RouteNames.masterBookings);
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('master-bookings-no-schedule')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('master-bookings-no-schedule-cta')),
          findsOneWidget,
          reason:
              'the SAME screen and the SAME empty schedule — only the mount '
              'and the session differ. Without this arm the absence above '
              'would also pass if `onAddHours` had been wired to null on '
              'EVERY mount, or if the CTA had simply been deleted.',
        );

        await drain(tester);
      },
    );
  });

  // -------------------------------------------------------------------------
  // CONTROL — the /staff/* gate is real. Without this group, routes
  // registered outside it would pass everything above.
  // -------------------------------------------------------------------------
  group('CONTROL — an INDEPENDENT_MASTER is bounced off every '
      '/staff/bookings* path', () {
    for (final (String label, String path) in <(String, String)>[
      ('/staff/bookings', RouteNames.salonMasterBookings),
      ('/staff/bookings/archive', RouteNames.salonMasterBookingsArchive),
      ('/staff/bookings/:id', '/staff/bookings/$_kBookingId'),
      ('/staff/bookings/:id/review', '/staff/bookings/$_kBookingId/review'),
    ]) {
      testWidgets('$label bounces to /master/profile', (tester) async {
        final GoRouter router = await pumpRouter(
          tester,
          _independentMasterUser,
        );

        router.go(path);
        await tester.pump();
        await tester.pump();

        expect(find.byType(MasterBookingsScreen), findsNothing);
        expect(find.byType(MasterArchiveScreen), findsNothing);
        expect(find.byType(LeaveClientFeedbackScreen), findsNothing);
        expect(find.byType(BookingDetailScreen), findsNothing);
      });
    }
  });
}
