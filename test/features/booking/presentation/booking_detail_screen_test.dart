// QA (track 14.x booking) — behavioural suite for [BookingDetailScreen].
//
// The overflow suite (booking_surfaces_overflow_test.dart) proves the detail
// screen never CLIPS at any status/width; this suite proves it renders the
// RIGHT THING at each status — the state machine the whole feature exists for:
//   • loading spinner (behind a live back button) / error + retry;
//   • the per-status hero + subline — the top status MEDALLION now survives on
//     NOT_COMPLETED alone (COMPLETED dropped its hero icon on 2026-07-16 while
//     keeping its title/subline); COMPLETED and NOT_COMPLETED still carry the
//     status TITLE; CONFIRMED, CANCELLED and DECLINED drop both hero and title
//     and speak through the subline alone (the who-cancelled label collapsed to
//     a neutral «Скасовано» on 2026-07-15);
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

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/booking/application/booking_detail_notifier.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/booking_detail_screen.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_notes.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_status_medallion.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_strip.dart';
import 'package:beautica_mobile/features/home/application/home_hub_notifier.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/feedback/velvet_snack.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/booking_fixture_dates.dart';
import '../../../helpers/pump_app.dart';
import '../../../helpers/velvet_snack_matchers.dart';

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
  String masterId = 'm1',
  required BookingStatus status,
  String? salonName,
  String? clientComment,
  String? providerComment,
  String? clientCancellationNote,
  DateTime? start,
  bool canReview = false,
}) {
  final DateTime startInstant = start ?? futureBookingStart();
  return Booking(
    id: id,
    masterId: masterId,
    masterFirstName: 'Марія',
    masterLastName: 'Іванюк',
    masterAvatarUrl: null,
    masterType: salonName != null ? 'SALON_MASTER' : 'INDEPENDENT_MASTER',
    salonName: salonName,
    serviceId: 's1',
    serviceName: 'Манікюр з покриттям',
    categoryName: 'NAIL_SERVICE',
    cityLabel: 'Львів',
    districtLabel: null,
    street: 'вул. Городоцька',
    buildingNo: '12',
    durationMinutes: 90,
    price: 650,
    startAt: startInstant,
    endAt: startInstant.add(const Duration(minutes: 90)),
    status: status,
    canReview: canReview,
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
  List<Object> extraOverrides = const <Object>[],
}) async {
  final _MockBookingRepository r = repo ?? _MockBookingRepository();
  await tester.pumpApp(
    BookingDetailScreen(bookingId: booking.id),
    overrides: <Object>[
      screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
      bookingRepositoryProvider.overrideWithValue(r),
      bookingDetailProvider(booking.id).overrideWith((ref) async => booking),
      ...extraOverrides,
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

  // -------------------------------------------------------------------------
  // Elapsed CONFIRMED — the read-only gate (BookingDisplayX.isPast).
  //
  // A CONFIRMED booking whose `endAt` is already past the device clock flips
  // read-only: Reschedule + Cancel + the header calendar icon drop away and the
  // terminal-state «Записатись знову» affordance (shared `_rebookActions`) takes
  // their place. The client gate is COSMETIC — the server still owns the real
  // rule (409 BOOKING_ALREADY_ELAPSED) — but the UI must not offer actions that
  // can only fail. `isPast` reads real `DateTime.now()`, so the fixture uses a
  // firmly past/future fixed instant (not now-relative) for determinism.
  // -------------------------------------------------------------------------

  group('CONFIRMED but ELAPSED — read-only', () {
    testWidgets('hides reschedule + cancel + header calendar icon and offers '
        '«Записатись знову»', (tester) async {
      await _pumpDetail(
        tester,
        _booking(
          status: BookingStatus.confirmed,
          // A fixed PAST instant is safe forever — it can never become
          // "upcoming" again, so it needs no now-relative offset.
          start: DateTime.utc(2000, 1, 1),
        ),
      );
      final l10n = _l10n(tester);

      // The three CONFIRMED affordances are gone…
      expect(find.byKey(const Key('booking-detail-reschedule')), findsNothing);
      expect(find.byKey(const Key('booking-detail-cancel')), findsNothing);
      expect(
        find.byKey(const Key('booking-detail-add-calendar')),
        findsNothing,
      );
      // …replaced by the single rebook CTA.
      expect(find.text(l10n.bookingDetailRebookCta), findsOneWidget);
      // The forward-looking reminder subline is now SUPPRESSED once the booking
      // has elapsed — part of the read-only treatment: `_subline(...)` returns
      // null for CONFIRMED && isPast, so «Нагадаємо про запис напередодні.»
      // (which can no longer be true) never renders on an elapsed detail.
      expect(find.text(l10n.bookingDetailSublineConfirmed), findsNothing);
    });
  });

  group('CONFIRMED and NOT elapsed — unchanged', () {
    testWidgets(
      'keeps reschedule + cancel + header calendar icon and shows NO rebook',
      (tester) async {
        await _pumpDetail(
          tester,
          _booking(
            status: BookingStatus.confirmed,
            // Deliberately a fixed FAR-future instant rather than a
            // now-relative one: this is the "NOT elapsed" twin of the fixed
            // firmly-past instant above, so both sides of `isPast`'s boundary
            // stay deterministic relative to EACH OTHER.
            // future-date-ok: fixed twin of the firmly-past instant above
            start: DateTime.utc(2999, 1, 1),
          ),
        );
        final l10n = _l10n(tester);

        // All three CONFIRMED affordances present — the gate is elapsed-only.
        expect(
          find.byKey(const Key('booking-detail-reschedule')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('booking-detail-cancel')), findsOneWidget);
        expect(
          find.byKey(const Key('booking-detail-add-calendar')),
          findsOneWidget,
        );
        // The rebook CTA is the terminal/elapsed affordance — absent here.
        expect(find.text(l10n.bookingDetailRebookCta), findsNothing);
      },
    );
  });

  // -------------------------------------------------------------------------
  // canReview gates the review CTA — hoisted ABOVE the status switch.
  //
  // Regression guard for the fix: a CONFIRMED booking that aged into
  // «Минулі» purely by elapsed time (never marked COMPLETED by the provider —
  // there is no auto-complete job) must still offer «Залишити відгук» the
  // moment the server says `canReview: true`. Before the fix, the review CTA
  // was reachable only from inside `case BookingStatus.completed`, so this
  // exact scenario silently dropped the button. `canReview` alone decides —
  // never `status` — per `Booking.canReview`'s doc.
  // -------------------------------------------------------------------------

  group('canReview gates the review CTA independently of status', () {
    testWidgets(
      'an ELAPSED CONFIRMED booking with canReview:true shows review + rebook '
      '(the bug this fix closes — an unclosed provider-side booking must '
      'still be reviewable)',
      (tester) async {
        await _pumpDetail(
          tester,
          _booking(
            status: BookingStatus.confirmed,
            start: DateTime.utc(2000, 1, 1),
            canReview: true,
          ),
        );
        final l10n = _l10n(tester);

        expect(
          find.byKey(const Key('booking-detail-leave-review')),
          findsOneWidget,
        );
        expect(find.text(l10n.bookingDetailReviewCta), findsOneWidget);
        expect(find.text(l10n.bookingDetailRebookCta), findsOneWidget);
      },
    );

    testWidgets(
      'an ELAPSED CONFIRMED booking with canReview:false shows rebook ONLY '
      '(unchanged behaviour — e.g. already reviewed)',
      (tester) async {
        await _pumpDetail(
          tester,
          _booking(
            status: BookingStatus.confirmed,
            start: DateTime.utc(2000, 1, 1),
            canReview: false,
          ),
        );
        final l10n = _l10n(tester);

        expect(
          find.byKey(const Key('booking-detail-leave-review')),
          findsNothing,
        );
        expect(find.text(l10n.bookingDetailRebookCta), findsOneWidget);
      },
    );

    testWidgets('COMPLETED with canReview:true shows review + rebook '
        '(unchanged behaviour)', (tester) async {
      await _pumpDetail(
        tester,
        _booking(status: BookingStatus.completed, canReview: true),
      );
      final l10n = _l10n(tester);

      expect(
        find.byKey(const Key('booking-detail-leave-review')),
        findsOneWidget,
      );
      expect(find.text(l10n.bookingDetailReviewCta), findsOneWidget);
      expect(find.text(l10n.bookingDetailRebookCta), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  // Terminal states rebook via the SHARED `_rebookActions` helper — a
  // regression guard for the refactor that extracted the elapsed-CONFIRMED and
  // terminal footers onto one code path. All three terminal rebook states must
  // still render exactly the «Записатись знову» button and no CONFIRMED action.
  // -------------------------------------------------------------------------

  group(
    'terminal states rebook via shared _rebookActions (refactor guard)',
    () {
      for (final BookingStatus status in <BookingStatus>[
        BookingStatus.completed,
        BookingStatus.cancelled,
        BookingStatus.declined,
      ]) {
        testWidgets('$status still shows «Записатись знову» and no CONFIRMED '
            'actions', (tester) async {
          await _pumpDetail(tester, _booking(status: status));
          final l10n = _l10n(tester);

          expect(find.text(l10n.bookingDetailRebookCta), findsOneWidget);
          expect(
            find.byKey(const Key('booking-detail-reschedule')),
            findsNothing,
          );
          expect(find.byKey(const Key('booking-detail-cancel')), findsNothing);
        });
      }

      // Re-audit LOW — the third unguarded empty-`masterId` push site.
      //
      // `booking_mapper.dart:119` maps `masterId: dto.masterId ?? ''`, so a
      // partial payload yields ''. `_onRebook` pushes `/masters/<id>`; with an
      // empty id that is `/masters/`, which matches no route, and
      // `app_router.dart` declares no `errorBuilder` — the tap would dump the
      // client on go_router's "page not found". The CTA must be DISABLED, not
      // merely a no-op, so the affordance is honest.
      testWidgets('an empty masterId disables «Записатись знову» rather than '
          'pushing a route that cannot match', (tester) async {
        await _pumpDetail(
          tester,
          _booking(status: BookingStatus.completed, masterId: ''),
        );
        final l10n = _l10n(tester);

        final Finder cta = find.widgetWithText(
          NeumorphicButton,
          l10n.bookingDetailRebookCta,
        );
        expect(cta, findsOneWidget);
        expect(tester.widget<NeumorphicButton>(cta).onPressed, isNull);
      });

      // The same fixture with a real id keeps the CTA live — so the assertion
      // above is pinned to the guard, not to the button being dead in general.
      testWidgets('a populated masterId leaves «Записатись знову» enabled', (
        tester,
      ) async {
        await _pumpDetail(tester, _booking(status: BookingStatus.completed));
        final l10n = _l10n(tester);

        final Finder cta = find.widgetWithText(
          NeumorphicButton,
          l10n.bookingDetailRebookCta,
        );
        expect(tester.widget<NeumorphicButton>(cta).onPressed, isNotNull);
      });

      // ── Phase 240 — the master strip, the FOURTH unguarded push site ─────
      //
      // The two tests above pin the empty-`masterId` guard on «Записатись
      // знову». Phase 240 made the master STRIP a navigation target too, on
      // every status at once (it renders outside the status switch), and that
      // push site shipped with no test. Same failure mode: `/masters//reviews`
      // matches no route and there is no `errorBuilder`, so the client lands
      // on go_router's "page not found".
      //
      // Paired negative/positive per M14 — the inert assertion must be pinned
      // to the guard, not to the strip being inert for some other reason.
      testWidgets('an empty masterId leaves the master strip INERT rather '
          'than pushing /masters//reviews', (tester) async {
        await _pumpDetail(
          tester,
          _booking(status: BookingStatus.confirmed, masterId: ''),
        );

        final Finder strip = find.byKey(
          const Key('booking-detail-master-strip'),
        );
        expect(strip, findsOneWidget);
        expect(
          tester.widget<MasterStrip>(strip).onTap,
          isNull,
          reason:
              'a blank id means "we do not know which master" — an inert '
              'strip is the honest affordance.',
        );
      });

      testWidgets('a populated masterId makes the master strip tappable — the '
          'client\'s route into the reviews they could not find', (
        tester,
      ) async {
        await _pumpDetail(tester, _booking(status: BookingStatus.confirmed));

        expect(
          tester
              .widget<MasterStrip>(
                find.byKey(const Key('booking-detail-master-strip')),
              )
              .onTap,
          isNotNull,
        );
      });

      // The strip renders OUTSIDE «Деталі запису»'s status switch, so every
      // status must get the route — including NOT_COMPLETED, whose action
      // footer is deliberately empty and which therefore had NO route to the
      // master at all before this change. That is the status most at risk of
      // being missed by a future refactor that moves the strip inside the
      // switch, so it is asserted per-status rather than once.
      for (final BookingStatus status in <BookingStatus>[
        BookingStatus.completed,
        BookingStatus.cancelled,
        BookingStatus.declined,
        BookingStatus.notCompleted,
      ]) {
        testWidgets('$status still offers the tappable master strip', (
          tester,
        ) async {
          await _pumpDetail(tester, _booking(status: status));

          final Finder strip = find.byKey(
            const Key('booking-detail-master-strip'),
          );
          expect(
            strip,
            findsOneWidget,
            reason: 'the strip renders outside the status switch',
          );
          expect(
            tester.widget<MasterStrip>(strip).onTap,
            isNotNull,
            reason:
                'a dead or no-show booking is exactly when the client most '
                'wants to read the master\'s reviews, and NOT_COMPLETED has '
                'no other route to them.',
          );
        });
      }
    },
  );

  // -------------------------------------------------------------------------
  // Cancel elapsed-race handling — stale screen / device-clock rollback.
  //
  // A NON-elapsed CONFIRMED booking shows «Скасувати запис», but the SERVER
  // clock is authoritative: it can 409 BOOKING_ALREADY_ELAPSED between the
  // screen opening and the confirm tap. The screen must catch it, surface the
  // localized `bookingErrorAlreadyElapsed` VelvetSnack (never a raw 409), and
  // refetch the booking (invalidate `bookingDetailProvider`) so it re-renders
  // read-only.
  // -------------------------------------------------------------------------

  group('cancel elapsed-race handling', () {
    testWidgets(
      'a BookingAlreadyElapsedFailure on confirm shows the localized message '
      'and refetches the booking',
      (tester) async {
        final repo = _MockBookingRepository();
        when(
          () => repo.cancelBooking(any(), reason: any(named: 'reason')),
        ).thenThrow(const BookingAlreadyElapsedFailure());

        // Non-elapsed so the cancel button is visible; the server 409s anyway.
        // Deliberate fixed far-future instant — see the "Elapsed CONFIRMED"
        // group header above for why this suite anchors on fixed instants
        // rather than a now-relative offset.
        final Booking booking = _booking(
          status: BookingStatus.confirmed,
          // future-date-ok: fixed far-future instant, deliberate (see above)
          start: DateTime.utc(2999, 1, 1),
        );
        int fetches = 0;
        await tester.pumpApp(
          BookingDetailScreen(bookingId: booking.id),
          overrides: <Object>[
            screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
            bookingRepositoryProvider.overrideWithValue(repo),
            bookingDetailProvider(booking.id).overrideWith((ref) async {
              fetches++;
              return booking;
            }),
          ],
        );
        await tester.pumpAndSettle();
        expect(fetches, 1, reason: 'the initial detail load');

        // Open the cancel dialog and confirm with an empty note.
        await tester.tap(find.byKey(const Key('booking-detail-cancel')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('cancel-booking-confirm')));
        await tester.pumpAndSettle();

        final l10n = _l10n(tester);
        // The clean localized message surfaced (not a raw 409 / errUnknown).
        expectVelvetSnack(
          l10n.bookingErrorAlreadyElapsed,
          variant: VelvetSnackVariant.error,
        );
        expect(find.text(l10n.errUnknown), findsNothing);
        // The write was attempted exactly once…
        verify(() => repo.cancelBooking('b1', reason: null)).called(1);
        // …and the catch refetched the booking so it can re-render read-only.
        expect(
          fetches,
          2,
          reason: 'ref.invalidate(bookingDetailProvider) forced a refetch',
        );

        // Drain the dwell Timer so none is pending at teardown.
        await pumpPastVelvetSnack(tester);
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

    testWidgets(
      'drops the top status medallion but KEEPS its status title (2026-07-16)',
      (tester) async {
        await _pumpDetail(tester, _booking(status: BookingStatus.completed));
        final l10n = _l10n(tester);

        // The ceremonial hero icon is gone on a finished booking…
        expect(find.byType(BookingStatusMedallion), findsNothing);
        // …but the header LABEL survives — the title/subline path is preserved,
        // only the top icon was narrowed away.
        expect(find.text(l10n.bookingStatusCompleted), findsWidgets);
        expect(find.text(l10n.bookingDetailSublineCompleted), findsOneWidget);
      },
    );
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
        expect(find.text(l10n.bookingDetailSublineDeclined), findsOneWidget);
        expect(find.textContaining('₴'), findsNothing);
        // The provider's words arrive — recessed InboundNote (depth = authorship).
        expect(find.text(_providerDeclineNote), findsOneWidget);
        expect(find.byType(InboundNote), findsOneWidget);
      },
    );

    testWidgets('an INDEPENDENT-master decline uses the neutral subline', (
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
      expect(find.text(l10n.bookingDetailSublineDeclined), findsOneWidget);
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
        // NOT_COMPLETED is the SOLE status that still carries the top status
        // medallion — guards that the COMPLETED-drop narrowing to
        // `notCompleted`-only did not over-hide the no-show hero too.
        expect(find.byType(BookingStatusMedallion), findsOneWidget);
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

    // mobile-qa (BookingCard cutover audit) — `startBookingCancel`
    // (booking_cancel_navigation.dart:179) invalidates `nextAppointmentProvider`
    // on a successful cancel so the Home Hub's «Найближчий запис» card
    // refreshes when the user backs out to /home. That fan-out target used to
    // be proven from a SECOND call site — the Home Hub card's own «Скасувати»
    // button (`home_hub_cancel_wiring_test.dart`, retired when the Home Hub's
    // populated card switched to the shared read-only `BookingCard`, which
    // carries no cancel trigger of its own any more). `BookingDetailScreen` is
    // now the ONLY surviving caller of `startBookingCancel`, and nothing here
    // asserted the invalidation reached `nextAppointmentProvider` from THIS
    // call site — this test closes that gap. Same seamless-invalidate trap
    // `booking_calendar_invalidation_test.dart` documents: `ref.invalidate` on
    // an already-loaded provider retains the previous `.value` while
    // refetching, so a refetch COUNT (not a null-then-value comparison) is the
    // only reliable signal.
    testWidgets(
      'a successful cancel invalidates nextAppointmentProvider — the Home '
      'Hub «Найближчий запис» card must refresh after the user cancels here',
      (tester) async {
        final repo = _MockBookingRepository();
        when(
          () => repo.cancelBooking(any(), reason: any(named: 'reason')),
        ).thenAnswer((_) async {});

        int nextApptFetches = 0;
        await _pumpDetail(
          tester,
          _booking(status: BookingStatus.confirmed),
          repo: repo,
          extraOverrides: <Object>[
            nextAppointmentProvider.overrideWith((ref) async {
              nextApptFetches++;
              return null;
            }),
          ],
        );

        // Hold a LIVE subscription so the invalidate triggers a genuine
        // refetch instead of Riverpod dropping an unwatched autoDispose member.
        final ProviderContainer container = ProviderScope.containerOf(
          tester.element(find.byType(BookingDetailScreen)),
          listen: false,
        );
        final ProviderSubscription<AsyncValue<Booking?>> sub = container.listen(
          nextAppointmentProvider,
          (_, _) {},
          fireImmediately: true,
        );
        addTearDown(sub.close);
        await container.read(nextAppointmentProvider.future);
        expect(
          nextApptFetches,
          1,
          reason:
              'sanity: the provider must have fetched once before any cancel',
        );

        await tester.tap(find.byKey(const Key('booking-detail-cancel')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('cancel-booking-confirm')));
        await tester.pumpAndSettle();

        await container.read(nextAppointmentProvider.future);
        expect(
          nextApptFetches,
          2,
          reason:
              'startBookingCancel must still invalidate nextAppointmentProvider '
              'on success — this is the ONLY surviving cancel call site since '
              'the Home Hub card lost its own «Скасувати» trigger in the '
              'BookingCard cutover, so this is now the ONLY test proving that '
              'invalidation line still fires',
        );
      },
    );
  });
}
