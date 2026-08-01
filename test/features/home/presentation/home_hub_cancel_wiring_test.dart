// QA (Phase 225 live-data wiring, Step 2.7 Rule 3b) — proves `startBookingCancel`
// actually works from its SECOND call site: the Home Hub «Найближчий запис»
// card's «Скасувати» button (`home_hub_screen.dart`'s `onCancel`).
//
// WHY THIS FILE EXISTS
// ---------------------
// `booking_cancel_navigation.dart`'s `startBookingCancel` helper was extracted
// from `BookingDetailScreen._confirmCancel` so the Home Hub card could reuse
// the exact same dialog → cancelBooking → invalidate flow. The extraction was
// claimed to be behaviour-preserving, and `booking_detail_screen_test.dart`'s
// `cancel flow` group DOES exercise the helper — but only through the DETAIL
// screen's call site. Nothing pumped the REAL `HomeHubScreen` with a populated
// `nextAppointmentProvider` and tapped ITS cancel button:
//   • `home_hub_screen_test.dart`'s "cancel button has correct key" test pumps
//     a bare `NextAppointmentCard` with `onCancel: _noop` — the callback is
//     never real.
//   • `next_appointment_card_test.dart` also stubs `onCancel: () {}`.
// A refactor that broke the wiring ONLY for the home-hub call site (e.g. a
// typo passing the wrong bookingId, or dropping the `unawaited(...)` call
// entirely) would have shipped green. These tests pump the REAL
// `HomeHubScreen` (not the leaf card in isolation) with the shared helper's
// real dependencies overridden, and tap the REAL button.
//
// The end-to-end journey (live data → cancel → card returns to empty) is
// covered at the integration tier (`client_home_hub_flow_test.dart`); this
// file is the fast, isolated widget-tier counterpart plus two paths an
// integration flow would be slow/awkward to cover per-branch:
//   • the confirmation dialog dismissed → no-op (nothing written);
//   • `cancelBooking` failing → an error SnackBar, never a silent success;
//   • the booking failing to even LOAD before the dialog can show.
//
// VIEWPORT: the default 800×600 `pumpApp` surface is too short to fit the
// dialog's bottom «Не скасовувати» button on screen (see
// `cancel_booking_dialog_test.dart`'s own `pumpDialog` helper, which enlarges
// the surface for exactly this reason) — `_pumpHubWithAppointment` does the
// same here.
//
// KEY POLICY: taps are key-based; the only raw-string assertions are on
// l10n.errUnknown (an explicit error-surface check) and fixture data
// (master/service names), matching this repo's convention.

import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/features/booking/application/booking_detail_notifier.dart';
import 'package:beautica_mobile/features/booking/data/booking_providers.dart';
import 'package:beautica_mobile/features/booking/data/booking_repository.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/home/application/home_hub_notifier.dart';
import 'package:beautica_mobile/features/home/domain/home_hub_models.dart';
import 'package:beautica_mobile/features/home/presentation/home_hub_screen.dart';
import 'package:beautica_mobile/features/rating/application/my_rating_notifier.dart';
import 'package:beautica_mobile/features/rating/domain/client_rating.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/booking_fixture_dates.dart';
import '../../../helpers/pump_app.dart';

class _NoOpScreenProtection extends ScreenProtectionManager {
  @override
  void acquire() {}
  @override
  void release() {}
  @override
  void reset() {}
}

class _MockBookingRepository extends Mock implements BookingRepository {}

/// Mutable single-slot counter — a plain `int` param would be captured BY
/// VALUE inside the `nextAppointmentProvider` override closure below, so it
/// could never observe more than one rebuild. This box is captured by
/// reference instead.
class _BuildCounter {
  int value = 0;
}

const String _kApptId = 'appt-cancel-1';

Booking _bookingFixture({BookingStatus status = BookingStatus.confirmed}) {
  final DateTime start = futureBookingStart();
  return Booking(
    id: _kApptId,
    masterId: 'm-1',
    masterFirstName: 'Марія',
    masterLastName: 'Іванюк',
    masterType: 'INDEPENDENT_MASTER',
    serviceId: 's-1',
    serviceName: 'Манікюр',
    durationMinutes: 60,
    price: 500,
    startAt: start,
    endAt: start.add(const Duration(hours: 1)),
    status: status,
    canReview: false,
  );
}

NextAppointment _appointment() {
  final DateTime start = futureBookingStart();
  return NextAppointment(
    id: _kApptId,
    masterName: 'Марія Іванюк',
    service: 'Манікюр',
    dateLabel: '20 червня',
    timeLabel: '15:00',
    location: 'Центр, Львів',
    startsAt: start,
    endsAt: start.add(const Duration(hours: 1)),
    masterInitials: 'МІ',
  );
}

/// Pumps the REAL `HomeHubScreen` (wrapped in a `Scaffold` so
/// `ScaffoldMessenger.showSnackBar` — the error surface `startBookingCancel`
/// falls back to — has somewhere to attach) with a populated next-appointment
/// card, the shared cancel helper's dependencies overridden, and every other
/// card stubbed to an empty/no-op state so only the cancel wiring under test
/// can drive the tree.
///
/// `pumpAndSettle()` is safe to use throughout this file, including while the
/// confirm dialog is left open, as of Phase 225 audit-fix cycle 3
/// (mobile-perf LOW): the obscured card button's spinner now mutes its
/// `TickerMode` for exactly the dialog-open window (see
/// `bookingCancelDialogVisibleProvider` / `HubOutlineButton.spinnerPaused`),
/// so it stops scheduling frames instead of ticking indefinitely behind the
/// barrier. Before that fix this file used a bounded, non-`pumpAndSettle()`
/// pump sequence for exactly this reason — see git history if reviving that
/// pattern is ever needed.
Future<void> _pumpHubWithAppointment(
  WidgetTester tester, {
  required _BuildCounter nextApptBuilds,
  BookingRepository? repo,
  AsyncValue<Booking> Function()? bookingDetail,
  Future<Booking>? bookingDetailFuture,
}) async {
  // Tall surface so the dialog's bottom «Не скасовувати» button is on-screen
  // and hit-testable without scrolling — see the file header.
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final NextAppointment appt = _appointment();
  await tester.pumpApp(
    const Scaffold(body: HomeHubScreen()),
    overrides: <Object>[
      screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
      myRatingProvider.overrideWith((ref) async => const ClientRating()),
      clientProfileProvider.overrideWith(
        (ref) async => const ClientProfileSummary(
          firstName: 'Олена',
          lastName: 'Тест',
          city: 'Львів',
          phone: '+380 97 000 00 00',
          clientRating: null,
          memberSinceYear: 2026,
        ),
      ),
      nextAppointmentProvider.overrideWith((ref) async {
        nextApptBuilds.value++;
        return appt;
      }),
      favoriteMastersProvider.overrideWith(
        (ref) async => const <FavoriteMasterItem>[],
      ),
      beautyTimelineProvider.overrideWith(
        (ref) async => const <TimelineEntry>[],
      ),
      unlikeFavoriteMasterProvider.overrideWith(() => UnlikeFavoriteMaster()),
      if (repo != null) bookingRepositoryProvider.overrideWithValue(repo),
      bookingDetailProvider(appt.id).overrideWith((ref) async {
        if (bookingDetailFuture != null) return bookingDetailFuture;
        final AsyncValue<Booking> result =
            bookingDetail?.call() ?? AsyncData<Booking>(_bookingFixture());
        return result.when(
          data: (Booking b) => b,
          loading: () => throw StateError('unused — never built loading'),
          error: (Object e, StackTrace st) => throw e,
        );
      }),
    ],
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1100)); // staggered reveal
}

void main() {
  setUpAll(() {
    registerFallbackValue(BookingStatus.confirmed);
  });

  group('Home Hub cancel wiring (startBookingCancel, 2nd call site)', () {
    testWidgets(
      'tapping the card «Скасувати» opens the SAME cancel dialog, confirming '
      'calls cancelBooking with this booking id + note, and refreshes '
      'nextAppointmentProvider',
      (tester) async {
        final _MockBookingRepository repo = _MockBookingRepository();
        when(
          () => repo.cancelBooking(any(), reason: any(named: 'reason')),
        ).thenAnswer((_) async {});

        final _BuildCounter builds = _BuildCounter();
        await _pumpHubWithAppointment(
          tester,
          nextApptBuilds: builds,
          repo: repo,
        );
        expect(
          builds.value,
          1,
          reason: 'sanity: the card must have built once before any tap',
        );

        expect(
          find.byKey(const Key('next_appointment_populated')),
          findsOneWidget,
        );
        final Finder cancelButton = find.byKey(
          const Key('next_appt_cancel_button'),
        );
        expect(cancelButton, findsOneWidget);
        await tester.ensureVisible(cancelButton);
        await tester.tap(cancelButton);
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('cancel-booking-dialog')),
          findsOneWidget,
          reason:
              'the home-hub card must open the SAME cancellation-note dialog '
              'the detail screen uses',
        );

        await tester.enterText(
          find.byKey(const Key('cancel-booking-note-field')),
          'Захворіла.',
        );
        await tester.tap(find.byKey(const Key('cancel-booking-confirm')));
        await tester.pumpAndSettle();

        verify(
          () => repo.cancelBooking(_kApptId, reason: 'Захворіла.'),
        ).called(1);

        expect(
          builds.value,
          greaterThanOrEqualTo(2),
          reason:
              'a successful cancel from the HOME HUB call site must invalidate '
              'nextAppointmentProvider (the newest entry in '
              "startBookingCancel's invalidation fan-out) — this is the "
              'specific line the extraction added for this call site, and '
              'only rebuilding proves it actually fired from here',
        );
      },
    );

    testWidgets(
      'backing out of the dialog with «Не скасовувати» calls cancelBooking '
      'nothing, closes the dialog, and leaves the card populated',
      (tester) async {
        final _MockBookingRepository repo = _MockBookingRepository();

        final _BuildCounter builds = _BuildCounter();
        await _pumpHubWithAppointment(
          tester,
          nextApptBuilds: builds,
          repo: repo,
        );

        final Finder cancelButton = find.byKey(
          const Key('next_appt_cancel_button'),
        );
        await tester.ensureVisible(cancelButton);
        await tester.tap(cancelButton);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('cancel-booking-dialog')), findsOneWidget);

        final Finder keepButton = find.byKey(const Key('cancel-booking-keep'));
        await tester.ensureVisible(keepButton);
        await tester.tap(keepButton);
        await tester.pumpAndSettle();

        verifyNever(
          () => repo.cancelBooking(any(), reason: any(named: 'reason')),
        );
        expect(
          find.byKey(const Key('cancel-booking-dialog')),
          findsNothing,
          reason: 'backing out must close the dialog',
        );
        expect(
          find.byKey(const Key('next_appointment_populated')),
          findsOneWidget,
          reason: 'the card must stay populated — nothing was cancelled',
        );
        expect(
          builds.value,
          1,
          reason:
              'backing out must NOT invalidate nextAppointmentProvider — '
              'nothing changed server-side',
        );

        // Stranding risk (mobile-security LOW, Phase 225 audit-fix cycle 2):
        // the widened in-flight window must clear on the back-out path same
        // as any other exit — otherwise the button is stuck disabled forever.
        // Proven by re-opening the dialog a second time from the same button.
        await tester.ensureVisible(cancelButton);
        await tester.tap(cancelButton);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('cancel-booking-dialog')),
          findsOneWidget,
          reason:
              'the cancel button must be re-tappable after backing out — a '
              'stranded in-flight flag would permanently disable it',
        );
      },
    );

    testWidgets(
      'a cancelBooking failure surfaces the error SnackBar instead of '
      'silently succeeding — the card stays populated and is NOT refreshed',
      (tester) async {
        final _MockBookingRepository repo = _MockBookingRepository();
        when(
          () => repo.cancelBooking(any(), reason: any(named: 'reason')),
        ).thenThrow(Exception('network blip'));

        final _BuildCounter builds = _BuildCounter();
        await _pumpHubWithAppointment(
          tester,
          nextApptBuilds: builds,
          repo: repo,
        );

        final Finder cancelButton = find.byKey(
          const Key('next_appt_cancel_button'),
        );
        await tester.ensureVisible(cancelButton);
        await tester.tap(cancelButton);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('cancel-booking-confirm')));
        await tester.pumpAndSettle();

        final AppLocalizations l10n = AppLocalizations.of(
          tester.element(find.byType(HomeHubScreen)),
        );
        expect(
          find.text(l10n.errUnknown),
          findsOneWidget,
          reason:
              'a repository failure must surface the unknown-error SnackBar '
              '— never fail silently while the caller believes it succeeded',
        );
        expect(
          find.byKey(const Key('cancel-booking-dialog')),
          findsNothing,
          reason: 'the dialog itself must have closed before the write ran',
        );
        expect(
          find.byKey(const Key('next_appointment_populated')),
          findsOneWidget,
          reason:
              'the card must still show the booking as upcoming — the write '
              'never succeeded',
        );
        expect(
          builds.value,
          1,
          reason:
              'a FAILED cancel must NOT invalidate nextAppointmentProvider — '
              'there is nothing new to refresh, and re-fetching would only '
              'mask the failure',
        );

        // Stranding risk (mobile-security LOW, Phase 225 audit-fix cycle 2):
        // the widened in-flight window must clear on write-failure same as
        // any other exit — otherwise the button is stuck disabled forever
        // after the very first failed cancel attempt.
        await tester.ensureVisible(cancelButton);
        await tester.tap(cancelButton);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('cancel-booking-dialog')),
          findsOneWidget,
          reason:
              'the cancel button must be re-tappable after a write failure '
              '— a stranded in-flight flag would permanently disable it',
        );
      },
    );

    testWidgets(
      'a bookingDetail load failure surfaces the error SnackBar and never '
      'opens the cancel dialog',
      (tester) async {
        final _MockBookingRepository repo = _MockBookingRepository();

        final _BuildCounter builds = _BuildCounter();
        await _pumpHubWithAppointment(
          tester,
          nextApptBuilds: builds,
          repo: repo,
          bookingDetail: () =>
              const AsyncError<Booking>(NetworkFailure(), StackTrace.empty),
        );

        final Finder cancelButton = find.byKey(
          const Key('next_appt_cancel_button'),
        );
        await tester.ensureVisible(cancelButton);
        await tester.tap(cancelButton);
        await tester.pumpAndSettle();

        final AppLocalizations l10n = AppLocalizations.of(
          tester.element(find.byType(HomeHubScreen)),
        );
        expect(
          find.text(l10n.errUnknown),
          findsOneWidget,
          reason:
              'when the helper cannot even load the booking, it must still '
              'surface an error — not fail silently',
        );
        expect(
          find.byKey(const Key('cancel-booking-dialog')),
          findsNothing,
          reason:
              'the confirmation dialog must never open when the booking '
              'failed to load — there is nothing to confirm cancelling',
        );
        verifyNever(
          () => repo.cancelBooking(any(), reason: any(named: 'reason')),
        );
      },
    );

    // ── QA follow-up (mobile-perf MEDIUM, FIXED — Phase 225 fix pass) ───────
    //
    // mobile-perf found that `onCancel` on the home-hub card had no
    // re-entrancy guard: a double-tap before the first `startBookingCancel`
    // call finished loading `bookingDetailProvider` could stack two confirm
    // dialogs, and — if both were confirmed — fire two `cancelBooking` writes
    // for the same booking. `startBookingCancel` now reads
    // `bookingCancelInFlightProvider` FIRST and short-circuits a re-entrant
    // call (see `booking_cancel_navigation.dart` /
    // `booking_cancel_in_flight_notifier.dart`), mirroring the existing
    // reschedule guard exactly. This test PINS the desired behaviour (single
    // dialog) and now passes green against the guarded production code.
    //
    // A Completer (not a plain `async {}` override) is required to make this
    // deterministic: with an instantly-resolving fake, the FIRST tap's own
    // `await tester.tap(...)` already drains enough of the microtask queue
    // for the dialog to open before the SECOND tap dispatches — that made an
    // earlier draft of this test "pass" for the wrong reason (the second tap
    // missing the now-obscured button, not a guard). Holding the future open
    // across BOTH taps reproduces the actual race mobile-perf found.
    testWidgets(
      'double-tapping «Скасувати» before the booking-detail load resolves '
      'opens only ONE dialog',
      (tester) async {
        final _MockBookingRepository repo = _MockBookingRepository();
        when(
          () => repo.cancelBooking(any(), reason: any(named: 'reason')),
        ).thenAnswer((_) async {});
        final Completer<Booking> loadGate = Completer<Booking>();

        final _BuildCounter builds = _BuildCounter();
        await _pumpHubWithAppointment(
          tester,
          nextApptBuilds: builds,
          repo: repo,
          bookingDetailFuture: loadGate.future,
        );

        final Finder cancelButton = find.byKey(
          const Key('next_appt_cancel_button'),
        );
        await tester.ensureVisible(cancelButton);
        // Both taps land on the SAME still-unobscured button — the
        // bookingDetail load is deliberately stuck on `loadGate`, so NEITHER
        // dialog can have opened yet by the time of the second tap.
        await tester.tap(cancelButton);
        await tester.pump();
        await tester.tap(cancelButton);
        await tester.pump();

        // Release the gate — both (unguarded) or one (guarded) pending loads
        // resolve now. The dialog this opens is left showing (no further tap
        // in this test) — safe with plain pumpAndSettle() per this file's
        // header note (the obscured card button's spinner mutes its ticker
        // while the dialog covers it).
        loadGate.complete(_bookingFixture());
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('cancel-booking-dialog')),
          findsOneWidget,
          reason:
              'exactly ONE confirm dialog must be showing after a double-tap '
              '— two stacked dialogs (or two eventual cancelBooking writes) '
              'is the MEDIUM finding this test pins the fix for',
        );
      },
    );

    // ── QA follow-up (mobile-security LOW, Phase 225 audit-fix cycle 2) ────
    //
    // mobile-security found that the in-flight guard above only covered the
    // booking-detail LOAD: `inFlight.end()` fired the instant that load
    // settled, i.e. BEFORE the confirmation dialog even opened, so the flag
    // stayed cleared through the dialog AND through the `cancelBooking`
    // write itself. The dialog's own modal barrier blocks a second tap while
    // it's open, but once the user confirms and the write is in flight, the
    // card's «Скасувати» button was un-guarded and re-tappable — a second tap
    // there re-entered `startBookingCancel`, reloaded the (already cached)
    // booking, showed a SECOND confirm dialog, and could fire a second
    // `cancelBooking` write concurrent with the first.
    //
    // `startBookingCancel` now holds `bookingCancelInFlightProvider` from
    // `begin()` through the outer `finally` that wraps load + dialog + write
    // (see `booking_cancel_navigation.dart`). This test pins that: with the
    // FIRST confirm's `cancelBooking` gated open on a `Completer`, a second
    // tap on the still-visible button while that write is pending must NOT
    // open a second dialog and must NOT issue a second `cancelBooking` call.
    testWidgets(
      'a second tap on «Скасувати» while the FIRST confirm cancelBooking '
      'write is still pending opens no second dialog and fires no second '
      'cancelBooking call',
      (tester) async {
        final _MockBookingRepository repo = _MockBookingRepository();
        final Completer<void> writeGate = Completer<void>();
        when(
          () => repo.cancelBooking(any(), reason: any(named: 'reason')),
        ).thenAnswer((_) => writeGate.future);

        final _BuildCounter builds = _BuildCounter();
        await _pumpHubWithAppointment(
          tester,
          nextApptBuilds: builds,
          repo: repo,
        );

        final Finder cancelButton = find.byKey(
          const Key('next_appt_cancel_button'),
        );
        await tester.ensureVisible(cancelButton);
        await tester.tap(cancelButton);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('cancel-booking-dialog')), findsOneWidget);

        await tester.enterText(
          find.byKey(const Key('cancel-booking-note-field')),
          'Захворіла.',
        );
        await tester.tap(find.byKey(const Key('cancel-booking-confirm')));
        // The dialog pops immediately on confirm; `cancelBooking` is now
        // pending on `writeGate`. Bounded, NOT pumpAndSettle() — unlike the
        // dialog-open windows elsewhere in this file, the card button is
        // UNCOVERED here (the dialog already closed) and its spinner is
        // genuinely, deliberately still ticking for as long as the write is
        // unresolved (see `HubOutlineButton.spinnerPaused`'s doc — this is
        // one of the two bounded windows the spinner is meant to animate
        // through). pumpAndSettle() would hang exactly as it always would
        // for a real indeterminate spinner mid-flight.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          find.byKey(const Key('cancel-booking-dialog')),
          findsNothing,
          reason: 'the dialog must have closed before the write started',
        );

        // Second tap lands on the SAME still-visible card button while the
        // FIRST write is still in flight — the pre-fix code left the flag
        // cleared here, so this tap would re-enter the flow and stack a
        // second dialog.
        await tester.tap(cancelButton);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(
          find.byKey(const Key('cancel-booking-dialog')),
          findsNothing,
          reason:
              'a second tap during the pending write must NOT open a second '
              'confirm dialog — this is the mobile-security LOW finding '
              '(Phase 225 audit-fix cycle 2) this test pins the fix for',
        );

        // Release the write — settles normally, flag clears, exactly ONE
        // cancelBooking call total across the whole test.
        writeGate.complete();
        await tester.pumpAndSettle();
        verify(
          () => repo.cancelBooking(_kApptId, reason: 'Захворіла.'),
        ).called(1);
      },
    );
  });
}
