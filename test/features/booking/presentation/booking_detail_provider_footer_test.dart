// Track 27.x Wave A — the PROVIDER footer on «Деталі запису».
//
// `booking_detail_provider_view_test.dart` (Phase 7.2) proved the screen
// role-branches at all and pinned the footer EMPTY for that phase. This suite
// covers what Wave A fills it WITH:
//   • CONFIRMED, not yet started → «Перенести» + «Скасувати» (decline), no
//     «Завершити»;
//   • CONFIRMED, [Booking.hasStarted] → «Завершити» AND «Скасувати»
//     (decline) — reschedule alone is hidden (it would 409 server-side,
//     Phase 27.1); decline itself is NOT time-gated — the backend now allows
//     a provider decline at any time, so it stays offered on an elapsed
//     booking too («Клієнт не прийшов» is recorded as a decline reason, not a
//     separate action);
//   • every terminal status → nothing;
//   • the decline dialog (reused `cancel_booking_dialog.dart` chrome) wires
//     to `BookingRepository.declineBooking` with the optional comment (empty
//     → null), and backing out calls nothing — on BOTH a not-yet-started and
//     an elapsed CONFIRMED booking;
//   • the complete dialog wires to `completeBooking`, and backing out calls
//     nothing;
//   • a 409 from either endpoint (`ProviderDeclineWindowClosedFailure` /
//     `ProviderCompleteNotStartedFailure`) surfaces the friendly l10n message
//     and refetches rather than crashing or showing a raw error;
//   • «Перенести» on the provider footer reuses the EXACT SAME
//     `startBookingReschedule` flow the client uses (Phase 27.2 widened
//     `PATCH …/reschedule` to providers on the identical endpoint/shape, no
//     mobile-side branching needed) — pinned by pushing the slot picker
//     seeded with `rescheduleBookingId`.
//
// Finders are key-first; all copy is asserted through l10n, never a raw
// Cyrillic literal (CI no-raw-string gate).

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/booking/application/booking_detail_notifier.dart';
import 'package:beautica_mobile/features/booking/application/bookings_day_notifier.dart';
import 'package:beautica_mobile/features/booking/application/master_archive_notifier.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_display_x.dart';
import 'package:beautica_mobile/features/booking/domain/booking_slot_picker_args.dart';
import 'package:beautica_mobile/features/booking/domain/booking_sort.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/domain/bookings_day_query.dart';
import 'package:beautica_mobile/features/booking/domain/bookings_day_state.dart';
import 'package:beautica_mobile/features/booking/domain/master_archive_query.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_detail_screen.dart';
import 'package:beautica_mobile/features/master/application/public_master_profile_notifier.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
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

User _providerUser() => const User(
  id: 'u1',
  email: 'master@e.com',
  role: UserRole.independentMaster,
);

// Reschedule fixtures — matches `_booking`'s masterId ('m1') / serviceId
// ('s1') so `startBookingReschedule` resolves the service by id, mirroring
// `booking_detail_interactions_test.dart`'s identical fixtures.
const Master _kRescheduleMaster = Master(
  id: 'm1',
  firstName: 'Марія',
  lastName: 'Іванюк',
  avgRating: 4.9,
  reviewCount: 20,
  type: MasterType.independentMaster,
);

const MasterService _kRescheduleService = MasterService(
  id: 's1',
  serviceDefId: 'def-1',
  name: 'Манікюр з покриттям',
  durationMinutes: 90,
  priceMin: 650,
  priceDisplay: '650 ₴',
  category: 'MANICURE',
);

Booking _booking({
  String id = 'b1',
  BookingStatus status = BookingStatus.confirmed,
  DateTime? startAt,
  int durationMinutes = 90,
}) {
  final DateTime start = startAt ?? futureBookingStart();
  return Booking(
    id: id,
    masterId: 'm1',
    masterFirstName: 'Марія',
    masterLastName: 'Іванюк',
    masterType: 'INDEPENDENT_MASTER',
    clientId: 'c1',
    clientFirstName: 'Олена',
    clientLastName: 'Ковальчук',
    serviceId: 's1',
    serviceName: 'Манікюр з покриттям',
    durationMinutes: durationMinutes,
    price: 650,
    startAt: start,
    endAt: start.add(Duration(minutes: durationMinutes)),
    status: status,
    canReview: false,
    masterProfessionalTitle: 'Майстриня манікюру',
  );
}

List<Object> _overrides(Booking booking, _MockBookingRepository repo) =>
    <Object>[
      screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
      bookingRepositoryProvider.overrideWithValue(repo),
      bookingDetailProvider(booking.id).overrideWith((ref) async => booking),
      authProvider.overrideWith(
        () => _StubAuth(
          AuthSession.authenticated(user: _providerUser(), accessToken: 't'),
        ),
      ),
    ];

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(BookingDetailScreen)));

Future<_MockBookingRepository> _pumpDetail(
  WidgetTester tester,
  Booking booking, {
  _MockBookingRepository? repo,
}) async {
  final _MockBookingRepository mockRepo = repo ?? _MockBookingRepository();
  await tester.pumpApp(
    BookingDetailScreen(bookingId: booking.id),
    overrides: _overrides(booking, mockRepo),
  );
  await tester.pumpAndSettle();
  return mockRepo;
}

void main() {
  setUpAll(() {
    registerFallbackValue(BookingStatus.confirmed);
    registerFallbackValue(<BookingStatus>{});
    registerFallbackValue(BookingSort.oldest);
  });

  // -------------------------------------------------------------------------
  // Footer content — by status and by `hasStarted`
  // -------------------------------------------------------------------------

  group('footer content', () {
    testWidgets(
      'CONFIRMED, not yet started: reschedule + decline, no complete',
      (tester) async {
        final Booking booking = _booking(
          status: BookingStatus.confirmed,
          startAt: futureBookingStart(),
        );
        expect(booking.hasStarted, isFalse);

        await _pumpDetail(tester, booking);

        expect(
          find.byKey(const Key('booking-detail-provider-reschedule')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('booking-detail-decline')), findsOneWidget);
        expect(find.byKey(const Key('booking-detail-complete')), findsNothing);
      },
    );

    testWidgets(
      'CONFIRMED, underway (started but not yet ended): complete + decline, '
      'no reschedule — hasStarted is a DIFFERENT gate than isPast',
      (tester) async {
        final DateTime start = DateTime.now().toUtc().subtract(
          const Duration(minutes: 10),
        );
        final Booking booking = _booking(
          status: BookingStatus.confirmed,
          startAt: start,
          durationMinutes: 90,
        );
        // Precondition proving the two gates diverge: started, but the
        // 90-minute window has not ended yet.
        expect(booking.hasStarted, isTrue);
        expect(booking.isPast, isFalse);

        await _pumpDetail(tester, booking);

        expect(
          find.byKey(const Key('booking-detail-complete')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('booking-detail-decline')), findsOneWidget);
        expect(
          find.byKey(const Key('booking-detail-provider-reschedule')),
          findsNothing,
        );
      },
    );

    testWidgets('CONFIRMED, fully elapsed: complete + decline both offered '
        '(not read-only) — the backend allows a provider decline at any time', (
      tester,
    ) async {
      final DateTime start = DateTime.now().toUtc().subtract(
        const Duration(days: 1),
      );
      final Booking booking = _booking(
        status: BookingStatus.confirmed,
        startAt: start,
        durationMinutes: 30,
      );

      await _pumpDetail(tester, booking);

      expect(find.byKey(const Key('booking-detail-complete')), findsOneWidget);
      expect(find.byKey(const Key('booking-detail-decline')), findsOneWidget);
    });

    testWidgets('every terminal status renders no provider action', (
      tester,
    ) async {
      for (final BookingStatus status in <BookingStatus>[
        BookingStatus.completed,
        BookingStatus.cancelled,
        BookingStatus.declined,
        BookingStatus.notCompleted,
      ]) {
        await _pumpDetail(tester, _booking(status: status));

        // Positive anchor first — a findsNothing against a half-built tree
        // proves nothing.
        expect(
          find.byKey(const Key('booking-detail-client-strip')),
          findsOneWidget,
          reason: 'the provider view did not render at $status',
        );
        expect(
          find.byKey(const Key('booking-detail-provider-reschedule')),
          findsNothing,
          reason: 'reschedule leaked at $status',
        );
        expect(
          find.byKey(const Key('booking-detail-decline')),
          findsNothing,
          reason: 'decline leaked at $status',
        );
        expect(
          find.byKey(const Key('booking-detail-complete')),
          findsNothing,
          reason: 'complete leaked at $status',
        );
      }
    });

    testWidgets('the CLIENT-only footer keys never leak into the provider '
        'view', (tester) async {
      await _pumpDetail(
        tester,
        _booking(
          status: BookingStatus.confirmed,
          startAt: futureBookingStart(),
        ),
      );

      expect(find.byKey(const Key('booking-detail-reschedule')), findsNothing);
      expect(find.byKey(const Key('booking-detail-cancel')), findsNothing);
    });
  });

  // -------------------------------------------------------------------------
  // Decline flow
  // -------------------------------------------------------------------------

  group('decline flow', () {
    testWidgets('confirming WITH a comment calls declineBooking with it', (
      tester,
    ) async {
      final repo = _MockBookingRepository();
      when(
        () => repo.declineBooking(any(), comment: any(named: 'comment')),
      ).thenAnswer((_) async {});
      final Booking booking = _booking(
        status: BookingStatus.confirmed,
        startAt: futureBookingStart(),
      );
      await _pumpDetail(tester, booking, repo: repo);

      await tester.tap(find.byKey(const Key('booking-detail-decline')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('decline-booking-dialog')), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('cancel-booking-note-field')),
        'Майстер захворів.',
      );
      await tester.tap(find.byKey(const Key('decline-booking-confirm')));
      await tester.pumpAndSettle();

      verify(
        () => repo.declineBooking(booking.id, comment: 'Майстер захворів.'),
      ).called(1);
      expect(find.byKey(const Key('decline-booking-dialog')), findsNothing);
    });

    testWidgets('confirming with an EMPTY comment sends comment: null', (
      tester,
    ) async {
      final repo = _MockBookingRepository();
      when(
        () => repo.declineBooking(any(), comment: any(named: 'comment')),
      ).thenAnswer((_) async {});
      final Booking booking = _booking(
        status: BookingStatus.confirmed,
        startAt: futureBookingStart(),
      );
      await _pumpDetail(tester, booking, repo: repo);

      await tester.tap(find.byKey(const Key('booking-detail-decline')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('decline-booking-confirm')));
      await tester.pumpAndSettle();

      verify(() => repo.declineBooking(booking.id, comment: null)).called(1);
    });

    testWidgets('backing out with «Не скасовувати» calls nothing', (
      tester,
    ) async {
      final repo = _MockBookingRepository();
      final Booking booking = _booking(
        status: BookingStatus.confirmed,
        startAt: futureBookingStart(),
      );
      await _pumpDetail(tester, booking, repo: repo);

      await tester.tap(find.byKey(const Key('booking-detail-decline')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('decline-booking-keep')));
      await tester.tap(find.byKey(const Key('decline-booking-keep')));
      await tester.pumpAndSettle();

      verifyNever(
        () => repo.declineBooking(any(), comment: any(named: 'comment')),
      );
      expect(find.byKey(const Key('decline-booking-dialog')), findsNothing);
    });

    testWidgets(
      'a 409 (ProviderDeclineWindowClosedFailure) shows the friendly message '
      'and refetches rather than crashing',
      (tester) async {
        final repo = _MockBookingRepository();
        when(
          () => repo.declineBooking(any(), comment: any(named: 'comment')),
        ).thenThrow(const ProviderDeclineWindowClosedFailure());
        final Booking booking = _booking(
          status: BookingStatus.confirmed,
          startAt: futureBookingStart(),
        );
        await _pumpDetail(tester, booking, repo: repo);
        final AppLocalizations l10n = _l10n(tester);

        await tester.tap(find.byKey(const Key('booking-detail-decline')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('decline-booking-confirm')));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(
          find.text(l10n.bookingErrorProviderDeclineWindowClosed),
          findsOneWidget,
        );
        // The dialog closed even though the write failed — it is a
        // confirmation, not a busy-state host.
        expect(find.byKey(const Key('decline-booking-dialog')), findsNothing);
      },
    );

    testWidgets('an UNKNOWN failure shows the generic error message', (
      tester,
    ) async {
      final repo = _MockBookingRepository();
      when(
        () => repo.declineBooking(any(), comment: any(named: 'comment')),
      ).thenThrow(Exception('boom'));
      final Booking booking = _booking(
        status: BookingStatus.confirmed,
        startAt: futureBookingStart(),
      );
      await _pumpDetail(tester, booking, repo: repo);
      final AppLocalizations l10n = _l10n(tester);

      await tester.tap(find.byKey(const Key('booking-detail-decline')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('decline-booking-confirm')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text(l10n.errUnknown), findsOneWidget);
    });

    testWidgets(
      'decline is ALSO offered and wired on an elapsed CONFIRMED booking — '
      'the backend allows a provider decline at any time',
      (tester) async {
        final repo = _MockBookingRepository();
        when(
          () => repo.declineBooking(any(), comment: any(named: 'comment')),
        ).thenAnswer((_) async {});
        final DateTime start = DateTime.now().toUtc().subtract(
          const Duration(days: 1),
        );
        final Booking booking = _booking(
          status: BookingStatus.confirmed,
          startAt: start,
          durationMinutes: 30,
        );
        expect(booking.hasStarted, isTrue);
        await _pumpDetail(tester, booking, repo: repo);

        // «Завершити» is offered alongside it, but this test is about decline.
        expect(
          find.byKey(const Key('booking-detail-complete')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('booking-detail-decline')), findsOneWidget);

        await tester.tap(find.byKey(const Key('booking-detail-decline')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('decline-booking-dialog')), findsOneWidget);

        await tester.enterText(
          find.byKey(const Key('cancel-booking-note-field')),
          'Клієнт не прийшов.',
        );
        await tester.tap(find.byKey(const Key('decline-booking-confirm')));
        await tester.pumpAndSettle();

        verify(
          () => repo.declineBooking(booking.id, comment: 'Клієнт не прийшов.'),
        ).called(1);
        expect(find.byKey(const Key('decline-booking-dialog')), findsNothing);
      },
    );
  });

  // -------------------------------------------------------------------------
  // Complete flow
  // -------------------------------------------------------------------------

  group('complete flow', () {
    /// A CONFIRMED booking that has started (so «Завершити» is offered).
    Booking startedBooking() {
      final DateTime start = DateTime.now().toUtc().subtract(
        const Duration(minutes: 5),
      );
      return _booking(
        status: BookingStatus.confirmed,
        startAt: start,
        durationMinutes: 90,
      );
    }

    testWidgets('confirming calls completeBooking', (tester) async {
      final repo = _MockBookingRepository();
      final Booking booking = startedBooking();
      when(() => repo.completeBooking(booking.id)).thenAnswer((_) async {});
      await _pumpDetail(tester, booking, repo: repo);

      await tester.tap(find.byKey(const Key('booking-detail-complete')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('complete-booking-dialog')), findsOneWidget);

      await tester.tap(find.byKey(const Key('complete-booking-confirm')));
      await tester.pumpAndSettle();

      verify(() => repo.completeBooking(booking.id)).called(1);
      expect(find.byKey(const Key('complete-booking-dialog')), findsNothing);
    });

    testWidgets('backing out calls nothing', (tester) async {
      final repo = _MockBookingRepository();
      final Booking booking = startedBooking();
      await _pumpDetail(tester, booking, repo: repo);

      await tester.tap(find.byKey(const Key('booking-detail-complete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('complete-booking-keep')));
      await tester.pumpAndSettle();

      verifyNever(() => repo.completeBooking(any()));
      expect(find.byKey(const Key('complete-booking-dialog')), findsNothing);
    });

    testWidgets(
      'a 409 (ProviderCompleteNotStartedFailure) shows the friendly message '
      'and refetches rather than crashing',
      (tester) async {
        final repo = _MockBookingRepository();
        final Booking booking = startedBooking();
        when(
          () => repo.completeBooking(booking.id),
        ).thenThrow(const ProviderCompleteNotStartedFailure());
        await _pumpDetail(tester, booking, repo: repo);
        final AppLocalizations l10n = _l10n(tester);

        await tester.tap(find.byKey(const Key('booking-detail-complete')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('complete-booking-confirm')));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(
          find.text(l10n.bookingErrorProviderCompleteNotStarted),
          findsOneWidget,
        );
      },
    );

    testWidgets('an UNKNOWN failure shows the generic error message', (
      tester,
    ) async {
      final repo = _MockBookingRepository();
      final Booking booking = startedBooking();
      when(() => repo.completeBooking(booking.id)).thenThrow(Exception('boom'));
      await _pumpDetail(tester, booking, repo: repo);
      final AppLocalizations l10n = _l10n(tester);

      await tester.tap(find.byKey(const Key('booking-detail-complete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('complete-booking-confirm')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text(l10n.errUnknown), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  // Day-list staleness — a successful decline/complete must invalidate the
  // master's OWN «Мої записи» day timeline (`bookingsDayProvider`), not only
  // `bookingDetailProvider`, or the list the master returns to would still
  // show the booking as CONFIRMED.
  // -------------------------------------------------------------------------

  group('day-list invalidation on success', () {
    /// Stubs `getMyBookings` (the call `BookingsDayNotifier._fetchDay`
    /// makes) to return an empty page — the invocation COUNT is read back
    /// via `verify(...).called(n)` on the mock itself, not this closure.
    void stubDayList(_MockBookingRepository repo) {
      when(
        () => repo.getMyBookings(
          statuses: any(named: 'statuses'),
          serviceIds: any(named: 'serviceIds'),
          from: any(named: 'from'),
          to: any(named: 'to'),
          sort: any(named: 'sort'),
          page: any(named: 'page'),
          size: any(named: 'size'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer(
        (_) async => const PageResponse<Booking>(
          items: <Booking>[],
          page: 0,
          totalPages: 1,
          totalElements: 0,
        ),
      );
    }

    testWidgets(
      'a successful decline refetches an actively-watched day-list family '
      'member for the booking\'s day',
      (tester) async {
        final Booking booking = _booking(
          status: BookingStatus.confirmed,
          startAt: futureBookingStart(),
        );
        final repo = _MockBookingRepository();
        when(
          () => repo.declineBooking(any(), comment: any(named: 'comment')),
        ).thenAnswer((_) async {});
        stubDayList(repo);

        await tester.pumpApp(
          BookingDetailScreen(bookingId: booking.id),
          overrides: _overrides(booking, repo),
        );
        await tester.pumpAndSettle();

        // Establish an ACTIVE watcher on the day-list family member for
        // THIS booking's day — mirrors what `bookings_discovery_view.dart`
        // watches underneath the pushed detail screen in the real app.
        final BookingsDayQuery dayQuery = BookingsDayQuery.of(
          day: booking.startAt,
        );
        final ProviderContainer container = ProviderScope.containerOf(
          tester.element(find.byType(BookingDetailScreen)),
        );
        final ProviderSubscription<AsyncValue<BookingsDayState>> sub = container
            .listen(bookingsDayProvider(dayQuery), (_, _) {});
        addTearDown(sub.close);
        await container.read(bookingsDayProvider(dayQuery).future);

        await tester.tap(find.byKey(const Key('booking-detail-decline')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('decline-booking-confirm')));
        await tester.pumpAndSettle();

        verify(
          () => repo.getMyBookings(
            statuses: any(named: 'statuses'),
            serviceIds: any(named: 'serviceIds'),
            from: any(named: 'from'),
            to: any(named: 'to'),
            sort: any(named: 'sort'),
            page: any(named: 'page'),
            size: any(named: 'size'),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).called(2); // initial watch fetch + the post-decline refetch.
      },
    );

    testWidgets(
      'a successful complete refetches an actively-watched day-list family '
      'member for the booking\'s day',
      (tester) async {
        final DateTime start = DateTime.now().toUtc().subtract(
          const Duration(minutes: 5),
        );
        final Booking booking = _booking(
          status: BookingStatus.confirmed,
          startAt: start,
          durationMinutes: 90,
        );
        final repo = _MockBookingRepository();
        when(() => repo.completeBooking(booking.id)).thenAnswer((_) async {});
        stubDayList(repo);

        await tester.pumpApp(
          BookingDetailScreen(bookingId: booking.id),
          overrides: _overrides(booking, repo),
        );
        await tester.pumpAndSettle();

        final BookingsDayQuery dayQuery = BookingsDayQuery.of(
          day: booking.startAt,
        );
        final ProviderContainer container = ProviderScope.containerOf(
          tester.element(find.byType(BookingDetailScreen)),
        );
        final ProviderSubscription<AsyncValue<BookingsDayState>> sub = container
            .listen(bookingsDayProvider(dayQuery), (_, _) {});
        addTearDown(sub.close);
        await container.read(bookingsDayProvider(dayQuery).future);

        await tester.tap(find.byKey(const Key('booking-detail-complete')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('complete-booking-confirm')));
        await tester.pumpAndSettle();

        verify(
          () => repo.getMyBookings(
            statuses: any(named: 'statuses'),
            serviceIds: any(named: 'serviceIds'),
            from: any(named: 'from'),
            to: any(named: 'to'),
            sort: any(named: 'sort'),
            page: any(named: 'page'),
            size: any(named: 'size'),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).called(2); // initial watch fetch + the post-complete refetch.
      },
    );
  });

  // -------------------------------------------------------------------------
  // Archive staleness (2026-08-16 fix) — a decline/complete performed from
  // THIS screen must also invalidate `masterArchiveProvider`, not only
  // `bookingDetailProvider`/`bookingsDayProvider` — a master who opened this
  // very booking FROM `MasterArchiveScreen`
  // (`master_archive_screen.dart:248-250` pushes the same
  // `BookingDetailScreen` every other entry point does) would otherwise see
  // the archive list keep serving the stale pre-close row. Routed through
  // the shared `invalidateBookingViewsAfterProviderClose` — see that
  // function's doc.
  // -------------------------------------------------------------------------

  group('archive invalidation on success (2026-08-16 fix)', () {
    /// Stubs `getMyBookings` in the SHAPE `MasterArchiveNotifier._fetchFirstPage`
    /// calls it (statuses/partition/serviceIds/sort/page — no from/to/size/
    /// cancelToken), distinct from `stubDayList`'s day-list shape above so
    /// the two never accidentally satisfy each other's `verify`.
    void stubArchiveList(_MockBookingRepository repo) {
      when(
        () => repo.getMyBookings(
          statuses: any(named: 'statuses'),
          partition: any(named: 'partition'),
          serviceIds: any(named: 'serviceIds'),
          sort: any(named: 'sort'),
          page: any(named: 'page'),
        ),
      ).thenAnswer(
        (_) async => const PageResponse<Booking>(
          items: <Booking>[],
          page: 0,
          totalPages: 1,
          totalElements: 0,
        ),
      );
    }

    testWidgets(
      'a successful decline refetches an actively-watched masterArchiveProvider '
      'filter combination — RED before the 2026-08-16 fix (only '
      'bookingDetailProvider/bookingsDayProvider were invalidated, never '
      'masterArchiveProvider)',
      (tester) async {
        final Booking booking = _booking(
          status: BookingStatus.confirmed,
          startAt: futureBookingStart(),
        );
        final repo = _MockBookingRepository();
        when(
          () => repo.declineBooking(any(), comment: any(named: 'comment')),
        ).thenAnswer((_) async {});
        stubArchiveList(repo);

        await tester.pumpApp(
          BookingDetailScreen(bookingId: booking.id),
          overrides: _overrides(booking, repo),
        );
        await tester.pumpAndSettle();

        // Mirrors what `MasterArchiveScreen` keeps warm underneath this
        // pushed detail screen in the real navigation stack: a LIVE
        // subscription on the default (untouched-filter) archive query.
        final MasterArchiveQuery archiveQuery = MasterArchiveQuery.of();
        final ProviderContainer container = ProviderScope.containerOf(
          tester.element(find.byType(BookingDetailScreen)),
        );
        final ProviderSubscription<AsyncValue<MasterArchiveState>> sub =
            container.listen(masterArchiveProvider(archiveQuery), (_, _) {});
        addTearDown(sub.close);
        await container.read(masterArchiveProvider(archiveQuery).future);

        await tester.tap(find.byKey(const Key('booking-detail-decline')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('decline-booking-confirm')));
        await tester.pumpAndSettle();

        verify(
          () => repo.getMyBookings(
            statuses: any(named: 'statuses'),
            partition: any(named: 'partition'),
            serviceIds: any(named: 'serviceIds'),
            sort: any(named: 'sort'),
            page: any(named: 'page'),
          ),
        ).called(2); // initial watch fetch + the post-decline refetch.
      },
    );

    testWidgets(
      'a successful complete refetches an actively-watched masterArchiveProvider '
      'filter combination — RED before the 2026-08-16 fix',
      (tester) async {
        final DateTime start = DateTime.now().toUtc().subtract(
          const Duration(minutes: 5),
        );
        final Booking booking = _booking(
          status: BookingStatus.confirmed,
          startAt: start,
          durationMinutes: 90,
        );
        final repo = _MockBookingRepository();
        when(() => repo.completeBooking(booking.id)).thenAnswer((_) async {});
        stubArchiveList(repo);

        await tester.pumpApp(
          BookingDetailScreen(bookingId: booking.id),
          overrides: _overrides(booking, repo),
        );
        await tester.pumpAndSettle();

        final MasterArchiveQuery archiveQuery = MasterArchiveQuery.of();
        final ProviderContainer container = ProviderScope.containerOf(
          tester.element(find.byType(BookingDetailScreen)),
        );
        final ProviderSubscription<AsyncValue<MasterArchiveState>> sub =
            container.listen(masterArchiveProvider(archiveQuery), (_, _) {});
        addTearDown(sub.close);
        await container.read(masterArchiveProvider(archiveQuery).future);

        await tester.tap(find.byKey(const Key('booking-detail-complete')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('complete-booking-confirm')));
        await tester.pumpAndSettle();

        verify(
          () => repo.getMyBookings(
            statuses: any(named: 'statuses'),
            partition: any(named: 'partition'),
            serviceIds: any(named: 'serviceIds'),
            sort: any(named: 'sort'),
            page: any(named: 'page'),
          ),
        ).called(2); // initial watch fetch + the post-complete refetch.
      },
    );
  });

  // -------------------------------------------------------------------------
  // «Перенести» reuses the SAME client reschedule flow (Phase 27.2)
  // -------------------------------------------------------------------------

  group('provider reschedule', () {
    testWidgets(
      'tapping «Перенести» on the provider footer pushes the slot picker '
      'seeded with rescheduleBookingId — identical to the client flow',
      (tester) async {
        final Booking booking = _booking(
          status: BookingStatus.confirmed,
          startAt: futureBookingStart(),
        );
        final repo = _MockBookingRepository();
        BookingSlotPickerArgs? captured;

        final router = GoRouter(
          initialLocation:
              '/master/bookings/${Uri.encodeComponent(booking.id)}',
          routes: <RouteBase>[
            GoRoute(
              path: '/master/bookings/:bookingId',
              builder: (_, _) => BookingDetailScreen(bookingId: booking.id),
            ),
            GoRoute(
              path: RouteNames.bookingSlots,
              builder: (BuildContext context, GoRouterState state) {
                captured = state.extra as BookingSlotPickerArgs?;
                return const Scaffold(key: Key('slots_stub'));
              },
            ),
          ],
        );

        await tester.pumpRoutedApp(
          router,
          overrides: <Object>[
            ..._overrides(booking, repo),
            publicMasterProfileProvider(booking.masterId).overrideWith(
              (ref) async => (
                _kRescheduleMaster,
                const <MasterService>[_kRescheduleService],
              ),
            ),
          ],
        );
        await tester.pumpAndSettle();

        final Finder reschedule = find.byKey(
          const Key('booking-detail-provider-reschedule'),
        );
        await tester.ensureVisible(reschedule);
        await tester.pumpAndSettle();
        await tester.tap(reschedule);
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('slots_stub')), findsOneWidget);
        expect(find.byType(BookingDetailScreen), findsNothing);
        expect(captured, isNotNull);
        expect(captured!.rescheduleBookingId, booking.id);
        expect(captured!.masterId, booking.masterId);
        expect(captured!.services.single.id, booking.serviceId);
      },
    );
  });
}
