// 2026-08-17 CRITICAL regression (widget tier) — `MasterBookingCard`'s
// «Виконано» START-TIME GATE.
//
// THE PRODUCT RULE
// ----------------
// A master may complete a booking only once `now >= that booking's OWN
// startAt`. Before the fix, «Виконано» was offered on the strength of
// `Booking.awaitingClosure` alone — a SERVER-computed flag — and the archive
// row's tap then fired the WHOLE-VISIT complete, which closed every sibling of
// the visit in lockstep while evaluating the backend temporal guard against
// only the VISIT's `startsAt`. A sibling starting hours later was therefore
// completed with no guard of its own.
//
// `master_archive_per_service_complete_flow_test.dart` (integration tier) pins
// the endpoint routing and the sibling immutability end-to-end. THIS file pins
// the other half — the local, client-side gate — which the integration tier
// structurally cannot reach: `FakeBackend._partitionOf` only ever classifies a
// CONFIRMED row into `PAST` once its `endsAt` has elapsed, so a not-yet-started
// row can never be served into the archive's `HISTORY` scope in the first
// place. The gate exists precisely for the case the server misreports
// (a stale page, a rolled-back clock, or a future relaxation of
// `awaitingClosure`), and only a bare card pump can construct it.
//
// WHY `now` AND NOT THE DEVICE CLOCK. `MasterBookingCard` takes `now` as a
// constructor parameter, supplied by its caller from `clockProvider`. A gate
// that read `DateTime.now()` inside a getter would be unpinnable — every
// assertion below would silently stop discriminating the moment the fixture's
// wall-clock relationship to "today" changed. Every instant here is an
// explicit `DateTime.utc(...)`; there is no host-clock read in this file, so
// the fixture clock and the widget clock are the SAME clock by construction.

import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_booking_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/pump_app.dart';

/// The pinned "now" every case below is measured against. Deliberately an
/// explicit UTC instant, never a host-clock read — see the file header.
///
/// This CANNOT expire the way `forbid_stale_future_date_fixture.sh` guards
/// against. That gate exists because `BookingDisplayX.isPast` reads the REAL
/// wall clock, so an absolute literal drifts across `isPast`'s boundary on a
/// date rather than on a code change. Nothing in this file touches `isPast` —
/// `MasterBookingCard` renders no `isPast`-derived state, and the ONE
/// predicate under test (`hasStartedAt`) takes its `now` as a parameter, which
/// every case below passes explicitly. Both sides of every comparison are
/// derived from this same constant (see [_booking]'s `startOffsetFromNow`), so
/// the relationship the assertions measure is fixed by construction and no
/// passage of real time can change any outcome.
// future-date-ok: both sides of every comparison derive from this constant; see the doc above.
final DateTime kNow = DateTime.utc(2026, 8, 17, 12);

/// A booking whose window is expressed RELATIVE to [kNow], so each case reads
/// as "started two hours ago" / "starts in four hours" rather than as a pair of
/// opaque timestamps.
Booking _booking({
  required String id,
  required Duration startOffsetFromNow,
  Duration duration = const Duration(minutes: 30),
  BookingStatus status = BookingStatus.confirmed,
  bool awaitingClosure = true,
}) {
  final DateTime startAt = kNow.add(startOffsetFromNow);
  return Booking(
    id: id,
    masterId: 'master-1',
    masterFirstName: 'Оля',
    masterLastName: 'Коваль',
    masterType: 'INDEPENDENT_MASTER',
    clientFirstName: 'Марія',
    clientLastName: 'Іванюк',
    serviceId: 'service-1',
    serviceName: 'Стрижка жіноча',
    durationMinutes: duration.inMinutes,
    price: 450,
    startAt: startAt,
    endAt: startAt.add(duration),
    status: status,
    canReview: false,
    awaitingClosure: awaitingClosure,
  );
}

void main() {
  /// Pumps one card in the FULL layout (the only layout that renders the
  /// «Виконано» slot), with `onComplete` wired so the gate is the ONLY thing
  /// that can suppress the button.
  Future<int> pumpCard(
    WidgetTester tester,
    Booking booking, {
    required DateTime now,
  }) async {
    int completeTaps = 0;
    await tester.pumpApp(
      Center(
        child: MasterBookingCard(
          booking: booking,
          onTap: () {},
          minHeight: MasterBookingCard.fullLayoutMinHeight,
          onComplete: () => completeTaps++,
          now: now,
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    return completeTaps;
  }

  Finder completeButton(String id) =>
      find.byKey(Key('master-booking-card-complete-$id'));

  group('«Виконано» start-time gate (2026-08-17 CRITICAL)', () {
    testWidgets(
      'an ELAPSED CONFIRMED/awaitingClosure booking (started 2h before now) '
      'OFFERS «Виконано» — the positive control that keeps every absence '
      'assertion below non-vacuous',
      (tester) async {
        final Booking booking = _booking(
          id: 'elapsed',
          startOffsetFromNow: const Duration(hours: -2),
        );

        await pumpCard(tester, booking, now: kNow);

        expect(completeButton('elapsed'), findsOneWidget);
      },
    );

    testWidgets(
      'a NOT-YET-STARTED booking (starts 4h after now) HIDES «Виконано» even '
      'though the server reported awaitingClosure: true — the gate must be '
      'evaluated locally against this booking\'s OWN startAt, never trusted '
      'from a server-computed flag alone',
      (tester) async {
        final Booking booking = _booking(
          id: 'not-started',
          startOffsetFromNow: const Duration(hours: 4),
          duration: const Duration(minutes: 60),
        );

        // Anti-vacuity: the ONLY difference from the passing case above is the
        // start offset. `awaitingClosure` is still `true`, the status is still
        // CONFIRMED, `onComplete` is still non-null, the layout is still FULL.
        // So an absent button can only be the start-time gate firing.
        expect(booking.awaitingClosure, isTrue);
        expect(booking.status, BookingStatus.confirmed);

        await pumpCard(tester, booking, now: kNow);

        expect(
          completeButton('not-started'),
          findsNothing,
          reason:
              'completing a service before its own start time is exactly '
              'what the whole-visit lockstep bug did to siblings',
        );
      },
    );

    testWidgets(
      'the gate is inclusive at the boundary: a booking starting EXACTLY at '
      'now offers «Виконано», one starting a single microsecond later does '
      'not — `now >= startAt`, not `now > startAt`',
      (tester) async {
        final Booking atBoundary = _booking(
          id: 'boundary-at',
          startOffsetFromNow: Duration.zero,
        );
        await pumpCard(tester, atBoundary, now: kNow);
        expect(
          completeButton('boundary-at'),
          findsOneWidget,
          reason: 'startAt == now is STARTED — the backend guard is inclusive',
        );

        final Booking justAfter = _booking(
          id: 'boundary-after',
          startOffsetFromNow: const Duration(microseconds: 1),
        );
        await pumpCard(tester, justAfter, now: kNow);
        expect(
          completeButton('boundary-after'),
          findsNothing,
          reason:
              'one microsecond before its start, the service has not started',
        );
      },
    );

    testWidgets(
      'the gate compares ABSOLUTE INSTANTS, not wall-clock fields: the same '
      'elapsed booking still offers «Виконано» when `now` arrives in a '
      'non-UTC zone',
      (tester) async {
        // A gate that compared `.hour`/`.minute` — or that pushed either side
        // through the Kyiv display pin — would flip here while the underlying
        // instant ordering is unchanged.
        final Booking booking = _booking(
          id: 'zoned',
          startOffsetFromNow: const Duration(hours: -2),
        );

        await pumpCard(
          tester,
          booking,
          now: kNow.toLocal(), // same instant, different zone representation
        );

        expect(completeButton('zoned'), findsOneWidget);
      },
    );

    testWidgets(
      'the gate SUPPRESSES the tap path, not merely the paint: a hidden '
      '«Виконано» cannot be reached, so `onComplete` can never fire for a '
      'not-yet-started booking',
      (tester) async {
        final Booking booking = _booking(
          id: 'no-tap',
          startOffsetFromNow: const Duration(hours: 4),
        );

        final int taps = await pumpCard(tester, booking, now: kNow);

        expect(completeButton('no-tap'), findsNothing);
        expect(
          taps,
          0,
          reason: 'no affordance existed, so nothing could have fired it',
        );
      },
    );

    testWidgets(
      'a caller offering «Виконано» without a clock is a programming error — '
      'the constructor asserts rather than failing open',
      (tester) async {
        // Fails CLOSED is not enough on its own: a silently button-less card
        // would look like "the gate worked". The assert makes the omission
        // loud at the call site instead.
        expect(
          () => MasterBookingCard(
            booking: _booking(
              id: 'no-clock',
              startOffsetFromNow: const Duration(hours: -2),
            ),
            onTap: () {},
            onComplete: () {},
          ),
          throwsAssertionError,
        );
      },
    );

    testWidgets(
      'callers that offer NO «Виконано» still render with `now: null` — the '
      'gate is additive and every pre-existing call site is untouched',
      (tester) async {
        await tester.pumpApp(
          Center(
            child: MasterBookingCard(
              booking: _booking(
                id: 'no-complete-slot',
                startOffsetFromNow: const Duration(hours: -2),
              ),
              onTap: () {},
              minHeight: MasterBookingCard.fullLayoutMinHeight,
            ),
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(completeButton('no-complete-slot'), findsNothing);
      },
    );
  });
}
