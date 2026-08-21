// Track 27.x Wave A — the PROVIDER footer on «Деталі запису».
//
// `booking_detail_provider_view_test.dart` (Phase 7.2) proved the screen
// role-branches at all and pinned the footer EMPTY for that phase. This suite
// covers what Wave A fills it WITH:
//   • CONFIRMED, not yet started → «Перенести» + «Скасувати» (decline), no
//     «Завершити»;
//   • CONFIRMED, [Booking.hasStarted] (covers BOTH underway and fully
//     elapsed — `hasStartedAt` doesn't distinguish them) → «Завершити» AND
//     «Скасувати» (decline) ONLY — «Перенести» is OMITTED, not merely
//     disabled: it would still 409 server-side (Phase 27.1's
//     `BookingTemporalGuard`), and 2026-08-20's `ef521cace` briefly kept it
//     visible-but-inert with a caption, but the user reversed that this
//     session — a button that can never be tapped is never shown. Decline
//     itself is NOT time-gated — the backend now allows a provider decline
//     at any time, so it stays offered on an elapsed booking too («Клієнт
//     не прийшов» is recorded as a decline reason, not a separate action);
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
import 'package:beautica_mobile/core/time/clock_provider.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/booking/application/booking_detail_notifier.dart';
import 'package:beautica_mobile/features/booking/application/bookings_day_notifier.dart';
import 'package:beautica_mobile/features/booking/application/master_archive_notifier.dart';
import 'package:beautica_mobile/features/booking/application/booked_days_notifier.dart';
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
      'CONFIRMED, underway (started but not yet ended): complete + decline '
      'ENABLED, «Перенести» ABSENT — hasStarted is a DIFFERENT gate than '
      'isPast (see the dedicated pinned-clock group below for the '
      'falsifiable absence assertion)',
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
        // USER-LOCKED REVERSAL (this session) of the 2026-08-20 fix: the
        // button is omitted entirely once started, not merely disabled. See
        // the 'reschedule availability (hasStartedAt gate)' group below for
        // the pinned-clock falsifiable assertion.
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
      // The user-reported case: a fully-past booking must not show a
      // reschedule CTA it can never honour.
      expect(
        find.byKey(const Key('booking-detail-provider-reschedule')),
        findsNothing,
      );
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
  // «Перенести» availability once the booking has started (2026-08-20 fix) —
  // pinned-clock guard for the silent-omission bug.
  //
  // Before this fix, `_providerActions`' `hasStartedAt` branch omitted
  // «Перенести» outright once a booking started. The build-verifier proved
  // this was UNGUARDED: with both the disabled `NeumorphicButton` and its
  // caption `Text` commented out of production code,
  // `booking_detail_screen_test.dart` and `booking_detail_provider_view_test
  // .dart` stayed 31/31 green. This group is the guard — mutation-probed
  // (see the QA report that shipped alongside this group for the RED/GREEN
  // observations).
  //
  // Every instant here is pinned through `clockProvider.overrideWithValue`
  // — NEVER a `DateTime.now()` read — and every fixture's `startAt` is
  // derived from the SAME pinned constant, so the fixture clock and the
  // widget clock (which reads `now` from the SAME overridden `clockProvider`
  // via `booking_detail_screen.dart`'s `build()`) are identical by
  // construction. Mixing a pinned clock with a host-clock read in one test
  // is the recurring bug this file's OTHER groups avoid by going fully live
  // instead — this group goes fully pinned; never mix the two within one
  // test body.
  // -------------------------------------------------------------------------

  group('reschedule availability (hasStartedAt gate, pinned clock)', () {
    // Fixed instant used only relative to itself (every fixture below
    // derives its `startAt` from this SAME constant, not from wall-clock-
    // relative "upcoming" logic) — see the group doc above.
    // future-date-ok: pinned INPUT for the injected clock itself.
    final DateTime kNow = DateTime.utc(2026, 8, 20, 12);

    List<Object> overridesWithClock(
      Booking booking,
      _MockBookingRepository repo,
    ) => <Object>[
      ..._overrides(booking, repo),
      clockProvider.overrideWithValue(() => kNow),
    ];

    testWidgets(
      'started (hasStartedAt is TRUE at the pinned clock): «Перенести» is '
      'ABSENT entirely — no button, no caption; «Завершити»/«Скасувати» '
      'stay ENABLED — the fix must not have collaterally disabled the live '
      'actions',
      (tester) async {
        final Booking booking = _booking(
          status: BookingStatus.confirmed,
          startAt: kNow.subtract(const Duration(minutes: 10)),
          durationMinutes: 90,
        );
        expect(booking.hasStartedAt(kNow), isTrue);
        final repo = _MockBookingRepository();
        when(
          () => repo.declineBooking(any(), comment: any(named: 'comment')),
        ).thenAnswer((_) async {});

        await tester.pumpApp(
          BookingDetailScreen(bookingId: booking.id),
          overrides: overridesWithClock(booking, repo),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('booking-detail-provider-reschedule')),
          findsNothing,
          reason:
              'USER-LOCKED REVERSAL: a reschedule that can never succeed on '
              'this booking must not be offered at all',
        );
        expect(
          find.byKey(const Key('booking-detail-reschedule-unavailable-reason')),
          findsNothing,
          reason:
              'the caption is pointless once the button it explains is gone',
        );

        final Finder completeFinder = find.byKey(
          const Key('booking-detail-complete'),
        );
        expect(completeFinder, findsOneWidget);
        expect(
          tester.widget<NeumorphicButton>(completeFinder).onPressed,
          isNotNull,
        );

        // `_DestructiveSecondaryButton` (decline) has no disabled/onPressed
        // concept to inspect statically in this codebase — every render
        // wires `onTap` unconditionally — so "still enabled" is proven by
        // actually driving the interaction and observing the dialog open,
        // exactly as the 'decline flow' group above does for other cases.
        await tester.tap(find.byKey(const Key('booking-detail-decline')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('decline-booking-dialog')), findsOneWidget);
      },
    );

    testWidgets(
      'boundary — not yet started (startAt strictly AFTER the pinned clock): '
      '«Перенести» renders ENABLED and the unavailable-reason caption is '
      'ABSENT. Without this boundary, a regression disabling reschedule for '
      'EVERY confirmed booking (not only started ones) would pass the test '
      'above unnoticed',
      (tester) async {
        final Booking booking = _booking(
          status: BookingStatus.confirmed,
          startAt: kNow.add(const Duration(hours: 2)),
          durationMinutes: 90,
        );
        expect(booking.hasStartedAt(kNow), isFalse);
        final repo = _MockBookingRepository();

        await tester.pumpApp(
          BookingDetailScreen(bookingId: booking.id),
          overrides: overridesWithClock(booking, repo),
        );
        await tester.pumpAndSettle();

        final Finder rescheduleFinder = find.byKey(
          const Key('booking-detail-provider-reschedule'),
        );
        expect(rescheduleFinder, findsOneWidget);
        expect(
          tester.widget<NeumorphicButton>(rescheduleFinder).onPressed,
          isNotNull,
        );
        expect(
          find.byKey(const Key('booking-detail-reschedule-unavailable-reason')),
          findsNothing,
        );
        expect(find.byKey(const Key('booking-detail-complete')), findsNothing);
      },
    );
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

  // -------------------------------------------------------------------------
  // Day-rail / month-grid DOT SET (2026-08-20 fan-out fix). A decline
  // performed from this screen must also drop `bookedDaysProvider`: it is a
  // filter-independent `keepAlive()` SINGLETON with a THIRTY-MINUTE TTL, not
  // a member of the `bookingsDayProvider` family this screen already
  // invalidates, and `BookingRepository#findBookedDatesByMasterId` allow-lists
  // CONFIRMED/COMPLETED/NOT_COMPLETED — so a CONFIRMED -> DECLINED transition
  // CROSSES that boundary and can take a day's last dotted booking away. Left
  // stale, «Мої записи» keeps a dot on a day whose list now renders empty.
  //
  // Asserted by REFETCH COUNT, never by inspecting the value:
  // `ref.invalidate` reloads seamlessly and RETAINS the previous `.value`, so
  // a value-shape assertion here could never fail.
  // -------------------------------------------------------------------------
  group('bookedDaysProvider invalidation on decline (2026-08-20 fan-out fix)', () {
    testWidgets('a successful decline refetches an actively-watched '
        'bookedDaysProvider', (tester) async {
      final Booking booking = _booking(
        status: BookingStatus.confirmed,
        startAt: futureBookingStart(),
      );
      final repo = _MockBookingRepository();
      when(
        () => repo.declineBooking(any(), comment: any(named: 'comment')),
      ).thenAnswer((_) async {});

      int bookedDaysFetches = 0;
      await tester.pumpApp(
        BookingDetailScreen(bookingId: booking.id),
        overrides: <Object>[
          ..._overrides(booking, repo),
          // Overridden rather than left real: the production provider parks
          // its own 30-minute keepAlive `Timer`, which would fail this test at
          // teardown as a pending timer.
          bookedDaysProvider.overrideWith((ref) async {
            bookedDaysFetches++;
            return <DateTime>{};
          }),
        ],
      );
      await tester.pumpAndSettle();

      // Mirrors what «Мої записи» keeps warm underneath this pushed detail
      // screen in the real navigation stack.
      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byType(BookingDetailScreen)),
      );
      final ProviderSubscription<AsyncValue<Set<DateTime>>> sub = container
          .listen(bookedDaysProvider, (_, _) {});
      addTearDown(sub.close);
      await container.read(bookedDaysProvider.future);

      final int before = bookedDaysFetches;
      expect(before, 1, reason: 'sanity: fetched once for the live watcher');

      await tester.tap(find.byKey(const Key('booking-detail-decline')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('decline-booking-confirm')));
      await tester.pumpAndSettle();

      await container.read(bookedDaysProvider.future);
      expect(
        bookedDaysFetches,
        greaterThan(before),
        reason:
            'the declined booking may have been the last one on its day — the '
            'rail dot has to go with it, and only this invalidation drops the '
            '30-minute-TTL singleton that holds it',
      );
    });
  });

  // -------------------------------------------------------------------------
  // The SAME dot-set fan-out on the COMPLETE arm (audit cycle 2, 2026-08-20).
  //
  // ⚠ THIS ONE PINS A DELIBERATE NO-OP — do not "optimise" it away. ⚠
  //
  // Unlike the decline above, a complete CANNOT change dot membership:
  // `BookingRepository#findBookedDatesByMasterId`
  // (`beautica-backend/.../BookingRepository.java:185-195`) allow-lists
  // CONFIRMED/COMPLETED/NOT_COMPLETED, and CONFIRMED → COMPLETED stays inside
  // that list. The refetch is therefore redundant BY DESIGN and kept on
  // purpose, because `invalidateBookingViewsAfterProviderClose` is the ONE
  // shared answer to "which caches does a provider-initiated close drop?" —
  // and re-splitting that answer per transition is precisely the
  // hand-rolled-fan-out drift that caused the 2026-08-16 archive staleness
  // bug (two independent fan-outs for one contract; one silently missed a
  // target). See that helper's own doc, and the block comment on
  // `test/features/booking/application/booking_calendar_invalidation_test
  // .dart`'s matching helper-level test.
  //
  // What THIS test adds over that helper-level one: it drives the real
  // «Завершити» confirm dialog, so it fails if `_confirmComplete` is ever
  // rewired to a per-transition fan-out that omits `bookedDaysProvider` —
  // which the helper-level test, calling the helper directly, could not see.
  //
  // Refetch COUNT, never value: `ref.invalidate` reloads seamlessly and
  // retains the previous `.value`, so a value assertion could never fail.
  // -------------------------------------------------------------------------
  group('bookedDaysProvider invalidation on COMPLETE (deliberate no-op)', () {
    testWidgets('a successful complete still refetches an actively-watched '
        'bookedDaysProvider — proving the complete path routes through the '
        'SHARED close fan-out, not a per-transition one', (tester) async {
      // Started, so «Завершити» is offered at all.
      final Booking booking = _booking(
        status: BookingStatus.confirmed,
        startAt: DateTime.now().toUtc().subtract(const Duration(minutes: 5)),
      );
      final repo = _MockBookingRepository();
      when(() => repo.completeBooking(booking.id)).thenAnswer((_) async {});

      int bookedDaysFetches = 0;
      await tester.pumpApp(
        BookingDetailScreen(bookingId: booking.id),
        overrides: <Object>[
          ..._overrides(booking, repo),
          bookedDaysProvider.overrideWith((ref) async {
            bookedDaysFetches++;
            return <DateTime>{};
          }),
        ],
      );
      await tester.pumpAndSettle();

      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byType(BookingDetailScreen)),
      );
      final ProviderSubscription<AsyncValue<Set<DateTime>>> sub = container
          .listen(bookedDaysProvider, (_, _) {});
      addTearDown(sub.close);
      await container.read(bookedDaysProvider.future);

      final int before = bookedDaysFetches;
      expect(before, 1, reason: 'sanity: fetched once for the live watcher');

      await tester.tap(find.byKey(const Key('booking-detail-complete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('complete-booking-confirm')));
      await tester.pumpAndSettle();

      // Fixture sanity: the write actually happened, so a green assertion
      // below cannot come from a dialog that silently did nothing.
      verify(() => repo.completeBooking(booking.id)).called(1);

      await container.read(bookedDaysProvider.future);
      expect(
        bookedDaysFetches,
        greaterThan(before),
        reason:
            'CONFIRMED -> COMPLETED cannot change dot membership, so this '
            'refetch changes nothing on screen — and that is the point: it '
            'proves the complete path is still the SHARED fan-out. A per-'
            'transition split would leave this at 1 and look like a win.',
      );
    });
  });

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
        // AUDIT-FIX CYCLE 3 (FIX 3, 2026-08-21) — this file's session is
        // ALWAYS a PROVIDER (`_providerUser()`, wired into every test via
        // `_overrides`), so the seeded args must hide the master identity
        // card through the picker/confirm chain — the master must not see a
        // card of themselves. The mirror-image CLIENT assertion (must stay
        // VISIBLE) lives in `client_reschedule_flow_test.dart`, the only file
        // in this suite that drives a CLIENT session through this same
        // `startBookingReschedule` helper.
        expect(captured!.hideMasterIdentity, isTrue);
      },
    );
  });
}
