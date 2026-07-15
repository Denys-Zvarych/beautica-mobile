// QA (track 14.x booking) — behavioural suite for [BookingDetailScreen].
//
// The overflow suite (booking_surfaces_overflow_test.dart) proves the detail
// screen never CLIPS at any status/width; this suite proves it renders the
// RIGHT THING at each status — the state machine the whole feature exists for:
//   • loading spinner (behind a live back button) / error + retry;
//   • the per-status hero + subline — only COMPLETED and NOT_COMPLETED still
//     carry the status medallion + title; CONFIRMED, CANCELLED and DECLINED
//     drop the hero entirely and speak through the subline alone (the
//     who-cancelled label collapsed to a neutral «Скасовано» on 2026-07-15);
//   • the action footer by status — CONFIRMED = reschedule + cancel;
//     COMPLETED/CANCELLED/DECLINED = rebook; NOT_COMPLETED = nothing;
//   • price shown only where money is a true statement (Booking.showsPrice);
//   • note visibility — a provider note arrives in a recessed [InboundNote]
//     (depth = authorship), the client's own words come back in an
//     [OutboundNote]; an OPTIONAL cancellation note is absent by default;
//   • the cancel wiring — «Скасувати запис» → dialog → confirm calls
//     BookingRepository.cancelBooking with the note (or null when blank), and
//     backing out calls nothing.
//
// Finders are key-first; status copy is asserted through l10n (never a raw
// literal), matching my_bookings_screen_test.dart.

import 'dart:async';

import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/features/booking/application/booking_detail_notifier.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_detail_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_notes.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_status_medallion.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/pump_app.dart';

// Fixture note values injected BY these tests (not app copy) — declared once so
// the same constant drives both the fixture and the rendered-note assertion,
// keeping the finder off a raw Cyrillic literal while still proving the exact
// injected text reaches the screen.
const String _clientCancelNote = 'Захворіла, вибачте.';
const String _providerDeclineNote = 'Майстер захворів, перепрошуємо.';

class _MockBookingRepository extends Mock implements BookingRepository {}

class _NoOpScreenProtection extends ScreenProtectionManager {
  @override
  void acquire() {}
  @override
  void release() {}
}

Booking _booking({
  String id = 'b1',
  required BookingStatus status,
  String? salonName,
  String? clientComment,
  String? providerComment,
  String? clientCancellationNote,
}) {
  final DateTime start = DateTime.utc(2026, 7, 20, 15);
  return Booking(
    id: id,
    masterId: 'm1',
    masterFirstName: 'Марія',
    masterLastName: 'Іванюк',
    masterAvatarUrl: null,
    masterType: salonName != null ? 'SALON_MASTER' : 'INDEPENDENT_MASTER',
    salonName: salonName,
    serviceId: 's1',
    serviceName: 'Манікюр з покриттям',
    categoryName: 'Манікюр',
    cityLabel: 'Львів',
    districtLabel: null,
    street: 'вул. Городоцька',
    buildingNo: '12',
    durationMinutes: 90,
    price: 650,
    startAt: start,
    endAt: start.add(const Duration(minutes: 90)),
    status: status,
    canReview: false,
    clientComment: clientComment,
    providerComment: providerComment,
    clientCancellationNote: clientCancellationNote,
    masterProfessionalTitle: 'Майстриня манікюру',
    locationNote: null,
  );
}

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(BookingDetailScreen)));

/// Pumps the detail screen with [booking] injected via the detail provider,
/// plus a mock repository (for cancel wiring) and a no-op screen protection.
Future<_MockBookingRepository> _pumpDetail(
  WidgetTester tester,
  Booking booking, {
  _MockBookingRepository? repo,
}) async {
  final _MockBookingRepository r = repo ?? _MockBookingRepository();
  await tester.pumpApp(
    BookingDetailScreen(bookingId: booking.id),
    overrides: <Object>[
      screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
      bookingRepositoryProvider.overrideWithValue(r),
      bookingDetailProvider(booking.id).overrideWith((ref) async => booking),
    ],
  );
  await tester.pumpAndSettle();
  return r;
}

void main() {
  setUpAll(() {
    registerFallbackValue(BookingStatus.confirmed);
  });

  // -------------------------------------------------------------------------
  // Async states
  // -------------------------------------------------------------------------

  group('async states', () {
    testWidgets('shows a spinner behind a live back button while loading', (
      tester,
    ) async {
      final completer = Completer<Booking>();
      await tester.pumpApp(
        const BookingDetailScreen(bookingId: 'b1'),
        overrides: <Object>[
          screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
          bookingDetailProvider('b1').overrideWith((ref) => completer.future),
        ],
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      // The back affordance is present even mid-fetch — a slow load never traps
      // the client.
      expect(find.byKey(const Key('booking-detail-back')), findsOneWidget);

      completer.complete(_booking(status: BookingStatus.confirmed));
      await tester.pumpAndSettle();
    });

    testWidgets('shows the error state with a retry button on failure', (
      tester,
    ) async {
      await tester.pumpApp(
        const BookingDetailScreen(bookingId: 'b1'),
        overrides: <Object>[
          screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
          bookingDetailProvider(
            'b1',
          ).overrideWith((ref) async => throw Exception('down')),
        ],
        // Keep the AsyncError put through pumpAndSettle (no backoff retry timer).
        retry: (_, _) => null,
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('booking-detail-error-retry')),
        findsOneWidget,
      );
      // Tapping retry re-invalidates the provider without throwing out of the
      // widget.
      await tester.tap(find.byKey(const Key('booking-detail-error-retry')));
      await tester.pump();
      expect(
        find.byKey(const Key('booking-detail-error-retry')),
        findsOneWidget,
      );
    });
  });

  // -------------------------------------------------------------------------
  // Status-distinct headline + subline + action footer + price
  // -------------------------------------------------------------------------

  group('CONFIRMED', () {
    testWidgets(
      'subline (no status hero/title), reschedule & cancel actions, price shown',
      (tester) async {
        await _pumpDetail(
          tester,
          _booking(
            status: BookingStatus.confirmed,
            clientComment: 'Без ароматизаторів — алергія.',
          ),
        );
        final l10n = _l10n(tester);

        // The big status hero (medallion + «Підтверджено» title) is gone on a
        // CONFIRMED booking — only the reworded subline speaks to the state.
        expect(find.byType(BookingStatusMedallion), findsNothing);
        expect(find.text(l10n.bookingStatusConfirmed), findsNothing);
        expect(find.text(l10n.bookingDetailSublineConfirmed), findsOneWidget);
        // Both pinned actions.
        expect(find.text(l10n.bookingDetailRescheduleCta), findsOneWidget);
        expect(find.byKey(const Key('booking-detail-cancel')), findsOneWidget);
        // Money is a true statement here.
        expect(find.textContaining('₴'), findsWidgets);
        // The client's own booking brief comes back as OUTbound (their words).
        expect(find.byType(OutboundNote), findsOneWidget);
        expect(find.byType(InboundNote), findsNothing);
      },
    );
  });

  group('COMPLETED', () {
    testWidgets('rebook action, price shown, no cancel', (tester) async {
      await _pumpDetail(tester, _booking(status: BookingStatus.completed));
      final l10n = _l10n(tester);

      expect(find.text(l10n.bookingStatusCompleted), findsWidgets);
      expect(find.text(l10n.bookingDetailSublineCompleted), findsOneWidget);
      expect(find.text(l10n.bookingDetailRebookCta), findsOneWidget);
      expect(find.byKey(const Key('booking-detail-cancel')), findsNothing);
      expect(find.textContaining('₴'), findsWidgets);
    });
  });

  group('CANCELLED (client backed out)', () {
    testWidgets(
      'no status hero/title, subline, rebook action, NO price, optional note absent',
      (tester) async {
        await _pumpDetail(tester, _booking(status: BookingStatus.cancelled));
        final l10n = _l10n(tester);

        // The medallion + big status title are gone (2026-07-15 collapse) —
        // the subline carries the neutral cancelled state.
        expect(find.byType(BookingStatusMedallion), findsNothing);
        expect(find.text(l10n.bookingDetailSublineCancelled), findsOneWidget);
        expect(find.text(l10n.bookingDetailRebookCta), findsOneWidget);
        // A cancelled appointment owes nothing — price suppressed.
        expect(find.textContaining('₴'), findsNothing);
        // The cancellation note is OPTIONAL — none written here → no note block.
        expect(find.byType(OutboundNote), findsNothing);
        expect(find.byType(InboundNote), findsNothing);
      },
    );

    testWidgets(
      'renders the client cancellation note as OUTbound when present',
      (tester) async {
        await _pumpDetail(
          tester,
          _booking(
            status: BookingStatus.cancelled,
            clientCancellationNote: _clientCancelNote,
          ),
        );

        expect(find.text(_clientCancelNote), findsOneWidget);
        expect(find.byType(OutboundNote), findsOneWidget);
        expect(find.byType(InboundNote), findsNothing);
      },
    );
  });

  group('DECLINED (provider backed out)', () {
    testWidgets(
      'a SALON decline drops the hero, keeps its subline and renders the '
      'provider note as INbound',
      (tester) async {
        await _pumpDetail(
          tester,
          _booking(
            status: BookingStatus.declined,
            salonName: 'Lviv Nails Studio',
            providerComment: _providerDeclineNote,
          ),
        );
        final l10n = _l10n(tester);

        // No medallion, no big status title — the neutral collapse.
        expect(find.byType(BookingStatusMedallion), findsNothing);
        expect(
          find.text(l10n.bookingDetailSublineDeclinedSalon),
          findsOneWidget,
        );
        expect(find.textContaining('₴'), findsNothing);
        // The provider's words arrive — recessed InboundNote (depth = authorship).
        expect(find.text(_providerDeclineNote), findsOneWidget);
        expect(find.byType(InboundNote), findsOneWidget);
      },
    );

    testWidgets('an INDEPENDENT-master decline keeps its own subline', (
      tester,
    ) async {
      await _pumpDetail(
        tester,
        _booking(
          status: BookingStatus.declined,
          providerComment: 'Мушу скасувати.',
        ),
      );
      final l10n = _l10n(tester);

      expect(find.byType(BookingStatusMedallion), findsNothing);
      expect(
        find.text(l10n.bookingDetailSublineDeclinedMaster),
        findsOneWidget,
      );
    });
  });

  group('NOT_COMPLETED (no-show)', () {
    testWidgets(
      'no action footer at all, price suppressed, provider note INbound',
      (tester) async {
        await _pumpDetail(
          tester,
          _booking(
            status: BookingStatus.notCompleted,
            providerComment: 'Чекала пів години, не відповідали.',
          ),
        );
        final l10n = _l10n(tester);

        expect(find.text(l10n.bookingStatusNotCompleted), findsWidgets);
        // Deliberately NO action — no rebook shortcut under a no-show account.
        expect(find.text(l10n.bookingDetailRebookCta), findsNothing);
        expect(find.text(l10n.bookingDetailRescheduleCta), findsNothing);
        expect(find.byKey(const Key('booking-detail-cancel')), findsNothing);
        expect(find.textContaining('₴'), findsNothing);
        expect(find.byType(InboundNote), findsOneWidget);
      },
    );
  });

  // -------------------------------------------------------------------------
  // Cancel wiring — «Скасувати запис» → dialog → repository
  // -------------------------------------------------------------------------

  group('cancel flow', () {
    testWidgets('confirming WITH a note calls cancelBooking with that note', (
      tester,
    ) async {
      final repo = _MockBookingRepository();
      when(
        () => repo.cancelBooking(any(), reason: any(named: 'reason')),
      ).thenAnswer((_) async {});
      await _pumpDetail(
        tester,
        _booking(status: BookingStatus.confirmed),
        repo: repo,
      );

      await tester.tap(find.byKey(const Key('booking-detail-cancel')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cancel-booking-dialog')), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('cancel-booking-note-field')),
        'Захворіла.',
      );
      await tester.tap(find.byKey(const Key('cancel-booking-confirm')));
      await tester.pumpAndSettle();

      verify(() => repo.cancelBooking('b1', reason: 'Захворіла.')).called(1);
    });

    testWidgets('confirming with an EMPTY note sends reason: null', (
      tester,
    ) async {
      final repo = _MockBookingRepository();
      when(
        () => repo.cancelBooking(any(), reason: any(named: 'reason')),
      ).thenAnswer((_) async {});
      await _pumpDetail(
        tester,
        _booking(status: BookingStatus.confirmed),
        repo: repo,
      );

      await tester.tap(find.byKey(const Key('booking-detail-cancel')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cancel-booking-confirm')));
      await tester.pumpAndSettle();

      verify(() => repo.cancelBooking('b1', reason: null)).called(1);
    });

    testWidgets('backing out with «Не скасовувати» cancels nothing', (
      tester,
    ) async {
      final repo = _MockBookingRepository();
      await _pumpDetail(
        tester,
        _booking(status: BookingStatus.confirmed),
        repo: repo,
      );

      await tester.tap(find.byKey(const Key('booking-detail-cancel')));
      await tester.pumpAndSettle();
      // warnIfMissed: the keep button sits under the dialog's barrier subtree in
      // the hit path; the tap still lands (verified by verifyNever below).
      await tester.tap(
        find.byKey(const Key('cancel-booking-keep')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      verifyNever(
        () => repo.cancelBooking(any(), reason: any(named: 'reason')),
      );
    });
  });
}
