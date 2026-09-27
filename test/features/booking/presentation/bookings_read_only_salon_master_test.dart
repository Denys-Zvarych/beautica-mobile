// Phases 328 / 329 / 331 — the WIDGET-level proof that an invited,
// read-only `SALON_MASTER` sees NO write affordance on the shared «Записи»
// surfaces, and the positive control that an `INDEPENDENT_MASTER` still does.
//
// WHY A SEPARATE FILE (mobile-qa branch audit, 2026-09-15). The track shipped
// with provider-level wiring but only PERMISSIVE-arm widget coverage:
// `master_bookings_screen_test.dart` seeds an `INDEPENDENT_MASTER` in exactly
// one harness (`_pumpWithNavRoutes`) so its «+» tap test keeps working, and
// `booking_detail_provider_footer_test.dart` seeds the same role throughout.
// Nothing anywhere pumped either screen as a `SALON_MASTER`. The behaviour
// the whole track exists for was therefore verified at the provider layer
// only (see `../application/bookings_capability_test.dart`) — never through
// the widgets that consume it, which is where the wiring can silently come
// undone (a dropped `canCreateBooking:` argument, a `_providerActions` gate
// moved back above the early returns).
//
// Kept OUT of `master_bookings_screen_test.dart` deliberately: that file's
// `_pump` harness intentionally stays UNAUTHENTICATED to preserve exact
// fetch-call counts (`bookings_day_notifier.dart:493-500` refetches on a
// `null → id` user transition), and its one seeded harness
// (`_pumpWithNavRoutes`) hard-codes the independent master. A read-only role
// needs its own seeded harness either way, so it gets its own file rather
// than a fifth override site in a 1400-line one.
//
// EVERY negative assertion here is a FINDER assertion (`findsNothing`), never
// a widget-property read — `project_widget_field_assertion_is_vacuous`. And
// every negative case is paired with the identical-fixture positive control
// in the same group, so "absent" can never be mistaken for "the screen never
// rendered" (M14: a negative-path assertion must be able to go red).

import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/booking/application/booked_days_notifier.dart';
import 'package:beautica_mobile/features/booking/application/booking_detail_notifier.dart';
import 'package:beautica_mobile/features/booking/application/booking_viewer_role.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_sort.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_detail_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/master_bookings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/booking_fixture_dates.dart';
import '../../../helpers/pump_app.dart';

class _MockBookingRepository extends Mock implements BookingRepository {}

class _NoOpScreenProtection extends ScreenProtectionManager {
  @override
  void acquire() {}
  @override
  void release() {}
}

class _StubAuth extends AuthNotifier {
  _StubAuth(this._session);

  final AuthSession _session;

  @override
  Future<AuthSession> build() async => _session;
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

/// The INVITED, read-only role this whole track exists for.
const User _salonMaster = User(
  id: 'u-salon-master',
  email: 'invited@beautica.ua',
  role: UserRole.salonMaster,
  firstName: 'Ірина',
  lastName: 'Запрошена',
);

/// The positive control — the role that has always had full «Записи» write
/// access. Every negative case below is re-run with THIS user and the
/// otherwise-identical fixture.
const User _independentMaster = User(
  id: 'u-independent-master',
  email: 'master@beautica.ua',
  role: UserRole.independentMaster,
  firstName: 'Олена',
  lastName: 'Майстер',
);

List<Object> _authOverride(User user) => <Object>[
  authProvider.overrideWith(
    () => _StubAuth(AuthSession.authenticated(user: user, accessToken: 'tok')),
  ),
];

// ---------------------------------------------------------------------------
// «Записи» list — the header's (+) add-booking affordance (phase 329)
// ---------------------------------------------------------------------------

const Key _kAddButton = Key('master-bookings-add');

PageResponse<Booking> _emptyPage() => const PageResponse<Booking>(
  items: <Booking>[],
  page: 0,
  totalPages: 1,
  totalElements: 0,
);

/// Mirrors `master_bookings_screen_test.dart`'s `_pump` (a REAL `GoRouter` —
/// the discovery view's filter sheet closes with go_router's `context.pop`),
/// plus the seeded session this file is about.
Future<void> _pumpBookingsScreen(WidgetTester tester, User viewer) async {
  final repo = _MockBookingRepository();
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
    ),
  ).thenAnswer((_) async => _emptyPage());

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
    overrides: <Object>[
      ..._authOverride(viewer),
      screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
      bookingRepositoryProvider.overrideWithValue(repo),
      bookedDaysProvider.overrideWith((ref) async => const <DateTime>{}),
    ],
  );
  await tester.pumpAndSettle();
}

// ---------------------------------------------------------------------------
// «Деталі запису» — the provider action footer (phase 331)
// ---------------------------------------------------------------------------

/// Every STATUS-TRANSITION affordance `_providerActions` can offer. The gate
/// under test returns `const <Widget>[]` before any of them, so all three
/// must be absent together — asserting only one would leave the other two
/// free to reappear.
const List<Key> _kTransitionKeys = <Key>[
  Key('booking-detail-provider-reschedule'),
  Key('booking-detail-decline'),
  Key('booking-detail-complete'),
];

/// The SERVER-driven review CTA. Deliberately NOT a transition: it sits in
/// the `COMPLETED` arm ABOVE the read-only gate and must stay reachable for a
/// read-only viewer (leaving feedback about a client is not a booking
/// mutation). Pinned here so a future edit that "tidies" the gate up above
/// that arm is caught.
const Key _kReviewCta = Key('booking-detail-leave-client-feedback');

Booking _booking({
  BookingStatus status = BookingStatus.confirmed,
  bool providerCanReviewClient = false,
}) {
  // Live host clock on BOTH sides — the fixture start and the screen's
  // un-overridden `clockProvider` — so the two agree
  // (`project_test_clock_coherence_invariant`: the bug is MIXING a pinned
  // clock with a host read, not reading the host clock).
  final DateTime start = futureBookingStart();
  return Booking(
    id: 'b-readonly-1',
    masterId: 'm1',
    masterFirstName: 'Марія',
    masterLastName: 'Іванюк',
    masterType: 'SALON_MASTER',
    clientId: 'c1',
    clientFirstName: 'Олена',
    clientLastName: 'Ковальчук',
    serviceId: 's1',
    serviceName: 'Манікюр з покриттям',
    durationMinutes: 90,
    price: 650,
    startAt: start,
    endAt: start.add(const Duration(minutes: 90)),
    status: status,
    canReview: false,
    providerCanReviewClient: providerCanReviewClient,
  );
}

Future<void> _pumpDetail(
  WidgetTester tester,
  User viewer,
  Booking booking,
) async {
  await tester.pumpApp(
    BookingDetailScreen(bookingId: booking.id),
    overrides: <Object>[
      ..._authOverride(viewer),
      screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
      bookingRepositoryProvider.overrideWithValue(_MockBookingRepository()),
      bookingDetailProvider(booking.id).overrideWith((ref) async => booking),
    ],
  );
  await tester.pumpAndSettle();
}

/// Reads the RESOLVED viewer role out of the pumped tree.
///
/// This is the anti-vacuity anchor for every «Деталі запису» negative below
/// (M14). `bookingViewerRoleProvider` maps `SALON_MASTER` onto
/// [BookingViewerRole.provider] (`booking_viewer_role.dart:71-76`), so the
/// PROVIDER footer is the one being built for them — meaning an empty footer
/// really is the transitions gate firing, and not the screen quietly falling
/// back to the CLIENT footer (which would produce the same `findsNothing` for
/// an entirely different reason).
BookingViewerRole _resolvedViewerRole(WidgetTester tester) =>
    ProviderScope.containerOf(
      tester.element(find.byType(BookingDetailScreen)),
    ).read(bookingViewerRoleProvider);

void main() {
  setUpAll(() {
    registerFallbackValue(BookingStatus.confirmed);
    registerFallbackValue(BookingSort.oldest);
    registerFallbackValue(<BookingStatus>[]);
  });

  group('«Записи» list — the (+) add-booking affordance (phase 329)', () {
    testWidgets('an invited SALON_MASTER sees NO add-booking button', (
      tester,
    ) async {
      await _pumpBookingsScreen(tester, _salonMaster);

      expect(
        find.byKey(_kAddButton),
        findsNothing,
        reason:
            'a read-only viewer must not be offered a write affordance at '
            'all — ABSENT, not disabled (BookingsDiscoveryView.'
            'canCreateBooking resolved from bookingCreationEnabledProvider)',
      );
    });

    testWidgets(
      'the INDEPENDENT_MASTER positive control still sees it (proving the '
      'negative above is the capability gate, not a screen that failed to '
      'render)',
      (tester) async {
        await _pumpBookingsScreen(tester, _independentMaster);

        expect(find.byKey(_kAddButton), findsOneWidget);
      },
    );
  });

  group('«Деталі запису» — the provider action footer (phase 331)', () {
    testWidgets(
      'an invited SALON_MASTER viewing a CONFIRMED booking gets NO status-'
      'transition buttons',
      (tester) async {
        await _pumpDetail(tester, _salonMaster, _booking());

        // Anti-vacuity: the PROVIDER footer is what is being built for this
        // role. Without this, an empty footer could just as well mean the
        // screen resolved the CLIENT footer instead.
        expect(
          _resolvedViewerRole(tester),
          BookingViewerRole.provider,
          reason:
              'SALON_MASTER maps onto BookingViewerRole.provider — so the '
              'footer below is genuinely _providerActions, and its emptiness '
              'is the transitions gate firing',
        );

        for (final Key key in _kTransitionKeys) {
          expect(
            find.byKey(key),
            findsNothing,
            reason:
                '$key is a status TRANSITION and must be absent for a '
                'read-only viewer',
          );
        }
      },
    );

    testWidgets('the INDEPENDENT_MASTER positive control gets «Перенести» and '
        '«Скасувати» on the same CONFIRMED booking', (tester) async {
      await _pumpDetail(tester, _independentMaster, _booking());

      expect(
        find.byKey(const Key('booking-detail-provider-reschedule')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('booking-detail-decline')), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // The ORDERING pin: the read-only gate sits BELOW the COMPLETED review
    // arm in `_providerActions`, on purpose. Moving it above (the obvious
    // "tidy the early returns together" refactor) would silently strip a
    // read-only viewer's feedback CTA too — a server-driven affordance that
    // is NOT a booking mutation. No other test in the repo pins that order.
    // -----------------------------------------------------------------------
    testWidgets(
      'an invited SALON_MASTER KEEPS the server-driven «Залишити відгук про '
      'клієнта» CTA on a COMPLETED, reviewable booking',
      (tester) async {
        await _pumpDetail(
          tester,
          _salonMaster,
          _booking(
            status: BookingStatus.completed,
            providerCanReviewClient: true,
          ),
        );

        expect(
          find.byKey(_kReviewCta),
          findsOneWidget,
          reason:
              'the review CTA is gated by the SERVER '
              '(Booking.providerCanReviewClient), never by the client-side '
              'transitions capability — leaving feedback about a client is '
              'not a booking mutation',
        );
        // ...and still no transitions alongside it.
        for (final Key key in _kTransitionKeys) {
          expect(find.byKey(key), findsNothing);
        }
      },
    );
  });
}
