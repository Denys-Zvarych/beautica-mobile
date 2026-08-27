// Regression guard for the 2026-08 reversal of the date stub's vertical
// placement: `BookingCard`'s outer `Row` (stub + gutter + Expanded body)
// changed `crossAxisAlignment` from `.start` (top-pinned) to `.center` (true
// centring), and the `Padding(top: _stubTopOffset)` wrapper that used to hold
// the stub to a fixed offset was deleted along with the constant itself. See
// the library doc's "date column" section in `booking_card.dart` for the full
// reasoning — this reverses an earlier deliberate "pin, don't centre"
// decision.
//
// Every PRE-EXISTING geometry assertion in this directory (including this
// file's sibling, `..._time_position_test.dart`) is relative WITHIN the stub
// (time below the day number, time's x-centre matching the day number's) or
// about the body's right edge — all of those are invariant to top-pin vs.
// true-centre by construction, so none of them would have caught this change
// landing OR being silently reverted. This file exists to close that gap:
// it pins the stub's ABSOLUTE vertical position relative to the card's own
// content height, which is exactly the property top-pin and true-centre
// disagree on.
//
// A sibling file rather than an extension of `..._time_position_test.dart`:
// that file guards the stub's INTERNAL composition (which line sits where
// inside the stub's own column); this one guards the stub's position
// relative to the surrounding card, and needs two fixtures with genuinely
// different body heights to do it — a different axis of concern with its own
// fixture shape, not a natural addition to that file's single-fixture setup.
//
// Per this directory's convention (see the sibling file's header),
// `_DateStub` is private, so measurements go through the same stable
// `ValueKey`s that file already established (`stub-day-$id`, `time-$id`) —
// never `find.byType(_DateStub)` and never `find.text` (Cyrillic labels trip
// `scripts/forbid_cyrillic_finder.sh`).

import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';

// The stub's caption geometry is deliberately exercised at its worst case:
// November renders the genitive «листопада», one of only three months (with
// березня/вересня) whose caption wraps the stub to two lines (see
// _DateStub.width in booking_card.dart) — pinning the month keeps that
// two-line case deterministic across every run, rather than depending on
// which month `DateTime.now()` happens to land in when the suite runs.
// future-date-ok: pinned to a two-line-wrapping month so the stub's worst-case internal line-stacking geometry (asserted below) stays deterministic instead of depending on which month DateTime.now() lands in.
final DateTime _start = DateTime.utc(2026, 11, 28, 15);

/// Minimal body: one-line name, no professional title, no salon (an
/// `INDEPENDENT_MASTER` booking never has one). The shortest identity block
/// the card can render — the 52 dp photo, not the text column, defines the
/// identity row's height here.
Booking _minimalBodyBooking() {
  return Booking(
    id: 'stub-centre-min',
    masterId: 'master-stub-centre-min',
    masterFirstName: 'Ана',
    masterLastName: 'Ко',
    masterAvatarUrl: null, // initials disc → no Image.network in the test
    masterType: 'INDEPENDENT_MASTER',
    salonName: null,
    serviceId: 'service-stub-centre-min',
    serviceName: 'Манікюр',
    categoryName: 'NAIL_SERVICE',
    cityLabel: 'Львів',
    districtLabel: 'Залізничний район',
    street: 'вулиця Тестова',
    buildingNo: '1',
    durationMinutes: 60,
    price: 500,
    startAt: _start,
    endAt: _start.add(const Duration(minutes: 60)),
    status: BookingStatus.confirmed,
    canReview: false,
    masterProfessionalTitle: null,
  );
}

/// Maximal body: a master name long enough to wrap to its `maxLines: 2`
/// ceiling (same over-long fixture `booking_surfaces_overflow_test.dart`
/// uses, reused here for the same guaranteed-wrap property — see that
/// file's `_longFirstName`/`_longLastName` comment), plus a professional
/// title AND a salon name, so the identity text column — not the 52 dp
/// photo — defines the identity row's height, and both optional lines are
/// present.
Booking _maximalBodyBooking() {
  return Booking(
    id: 'stub-centre-max',
    masterId: 'master-stub-centre-max',
    masterFirstName: 'Олександра-Валентина',
    masterLastName: 'Коваленко-Тестівська-Довгопрізвищенко',
    masterAvatarUrl: null, // initials disc → no Image.network in the test
    masterType: 'SALON_MASTER',
    salonName: 'Салон краси «Прекрасна Довга Мить»',
    serviceId: 'service-stub-centre-max',
    serviceName: 'Манікюр з покриттям',
    categoryName: 'NAIL_SERVICE',
    cityLabel: 'Львів',
    districtLabel: 'Залізничний район',
    street: 'вулиця Тестова',
    buildingNo: '15А',
    durationMinutes: 90,
    price: 650,
    startAt: _start,
    endAt: _start.add(const Duration(minutes: 90)),
    status: BookingStatus.confirmed,
    canReview: false,
    masterProfessionalTitle: 'Провідна майстриня манікюру',
  );
}

Finder _dayNumberFinder(String id) =>
    find.byKey(ValueKey<String>('stub-day-$id'));
Finder _timeFinder(String id) => find.byKey(ValueKey<String>('time-$id'));

Future<void> _pumpCard(WidgetTester tester, Booking booking) async {
  await tester.pumpApp(
    Scaffold(
      body: BookingCard(booking: booking, onOpenDetails: () {}),
    ),
    width: 360,
  );
  await tester.pump();
}

void main() {
  group('BookingCard — date stub vertical centring (2026-08 pin→centre)', () {
    testWidgets(
      'the day number sits lower on a card with a taller body than on a '
      'card with a minimal body',
      (tester) async {
        await _pumpCard(tester, _minimalBodyBooking());
        final double minimalDayNumberY = tester
            .getTopLeft(_dayNumberFinder('stub-centre-min'))
            .dy;

        await _pumpCard(tester, _maximalBodyBooking());
        final double maximalDayNumberY = tester
            .getTopLeft(_dayNumberFinder('stub-centre-max'))
            .dy;

        // Under the OLD top-pinned layout (`CrossAxisAlignment.start` +
        // `Padding(top: _stubTopOffset)`) the day number's y is a FIXED
        // offset independent of the body's height, so this would fail with
        // `minimalDayNumberY == maximalDayNumberY` (equal, not merely
        // close) — see the mutation-test evidence in the QA audit that
        // authored this file. Only true centring against the card's own
        // content height makes the taller card's stub sit strictly lower.
        expect(
          maximalDayNumberY,
          greaterThan(minimalDayNumberY),
          reason:
              'the maximal-body card (2-line name + title + salon) must '
              "push the centred stub's day number strictly below where it "
              'sits on the minimal-body card (1-line name, no title, no '
              'salon) — a difference of ~0 here means the stub reverted to '
              'a fixed top-pin instead of tracking the body height',
        );
      },
    );

    testWidgets(
      "the stub's vertical centre coincides with the card's own content "
      'vertical centre',
      (tester) async {
        final Booking booking = _maximalBodyBooking();
        await _pumpCard(tester, booking);

        // The card's rendered box IS the content box plus the outer
        // `Padding` — `EdgeInsets.fromLTRB(_railWidth + _stubInset,
        // VelvetSpacing.sm, VelvetSpacing.sm, VelvetSpacing.sm)` in
        // `booking_card.dart` — and that padding is the SAME `sm` value on
        // the top and the bottom. An equal top/bottom inset does not shift
        // a midpoint, so the card's own vertical centre already equals the
        // padded content Row's vertical centre; no extra arithmetic (and no
        // dependency on the padding's actual dp value) is needed to derive
        // one from the other.
        final Rect cardRect = tester.getRect(find.byType(BookingCard));
        final double contentCentreY = cardRect.center.dy;

        // The stub's own vertical centre, measured directly from its first
        // and last rendered lines — the day number's top edge and the
        // time's bottom edge — rather than restated from the source's own
        // `_DateStub` column arithmetic.
        final double stubTop = tester
            .getTopLeft(_dayNumberFinder('stub-centre-max'))
            .dy;
        final double stubBottom = tester
            .getBottomLeft(_timeFinder('stub-centre-max'))
            .dy;
        final double stubCentreY = (stubTop + stubBottom) / 2;

        expect(
          stubCentreY,
          closeTo(contentCentreY, 2.0),
          reason:
              "the stub's measured vertical centre (day-number top to "
              'time bottom) must coincide with the card content\'s measured '
              'vertical centre — under the old top-pinned layout the stub '
              'sat near the CARD TOP regardless of body height, which on '
              'this tall fixture is far outside this tolerance',
        );
      },
    );
  });
}
