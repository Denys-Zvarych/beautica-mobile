// QA (Phase 240 rating visibility) — the RENDER half of the rating fold.
//
// WHY THIS FILE EXISTS, SEPARATELY FROM THE UNIT TESTS
// ----------------------------------------------------
// `master_rating_x_test.dart` and `booking_display_x_test.dart` pin what the
// two derivations RETURN. Neither proves the returned null reaches the screen
// as «—»: a factory that computes `displayRating` correctly and then hands
// `MasterRatingReadout` the RAW `avgRating` would pass both unit suites and
// still print «0.0» to the client. That wiring — factory → readout → glyph —
// is the whole of the reported bug's display half, and it is only observable
// here.
//
// Both factories are driven, because they take DIFFERENT routes to the same
// readout:
//   • `MasterStrip.fromMaster` → `MasterRatingX.displayRating`
//   • `MasterStrip.fromBooking` → `BookingDisplayX.masterDisplayRating`
// A regression that fixes one and not the other is exactly what "the rating
// shows on the profile but not on the booking" looked like.
//
// Finder policy: the rating READOUT is a number/em-dash glyph, not localized
// UI copy, so `find.text` is the correct finder for it here (M2 targets
// locale-coupled COPY). The strip itself is located structurally, by type.

import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/domain/salon_master_schedule.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_strip.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/salon/domain/salon_service_catalog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/booking_fixture_dates.dart';
import '../../../../helpers/pump_app.dart';

Master _master({required double? avgRating, required int reviewCount}) =>
    Master(
      id: 'm1',
      firstName: 'Оксана',
      lastName: 'Коваль',
      avgRating: avgRating,
      reviewCount: reviewCount,
      type: MasterType.independentMaster,
    );

Booking _booking({
  required double? masterAvgRating,
  required int? masterReviewCount,
  String masterId = 'master-aaa',
}) {
  // Now-relative, per `forbid_stale_future_date_fixture.sh`. Nothing in this
  // file asserts on a DATE — the window only exists because `Booking` requires
  // one — but a fixed literal is a trap that expires on a calendar date rather
  // than a code change, so it does not get to live in a booking fixture. Both
  // the fixture and anything reading a clock here are live (M15: the bug is
  // MIXING a pinned fixture clock with a live app clock, not reading the host
  // clock).
  final DateTime start = futureBookingStart();
  return Booking(
    id: 'b1',
    masterId: masterId,
    masterFirstName: 'Софія',
    masterLastName: 'Бондар',
    masterAvatarUrl: null,
    masterType: 'INDEPENDENT_MASTER',
    salonName: null,
    serviceId: 's1',
    serviceName: 'Манікюр',
    categoryName: 'NAIL_SERVICE',
    cityLabel: 'Київ',
    districtLabel: null,
    street: null,
    buildingNo: null,
    durationMinutes: 90,
    price: 650,
    startAt: start,
    endAt: start.add(const Duration(minutes: 90)),
    status: BookingStatus.completed,
    canReview: true,
    clientComment: null,
    providerComment: null,
    clientCancellationNote: null,
    masterProfessionalTitle: null,
    locationNote: null,
    masterAvgRating: masterAvgRating,
    masterReviewCount: masterReviewCount,
  );
}

Future<void> _pumpStrip(WidgetTester tester, Widget strip) async {
  await tester.pumpApp(Center(child: strip));
  await tester.pumpAndSettle();
  expect(find.byType(MasterStrip), findsOneWidget);
}

void main() {
  group('MasterStrip.fromMaster — the Master-side fold reaches the glyph', () {
    testWidgets('a null avgRating renders the em-dash, never «0.0»', (
      tester,
    ) async {
      await _pumpStrip(
        tester,
        MasterStrip.fromMaster(
          _master(avgRating: null, reviewCount: 0),
          showRating: true,
        ),
      );

      expect(find.text(MasterStrip.noRatingLabel), findsOneWidget);
      expect(
        find.text('0.0'),
        findsNothing,
        reason: 'an unreviewed master must never be shown zero stars',
      );
    });

    testWidgets('a stale 0.0 avgRating WITH a non-zero count still renders the '
        'em-dash — the count-only guard would have printed «0.0» here', (
      tester,
    ) async {
      await _pumpStrip(
        tester,
        MasterStrip.fromMaster(
          _master(avgRating: 0, reviewCount: 7),
          showRating: true,
        ),
      );

      expect(find.text(MasterStrip.noRatingLabel), findsOneWidget);
      expect(find.text('0.0'), findsNothing);
    });

    testWidgets('a known-zero reviewCount renders the em-dash even with a '
        'number in avgRating', (tester) async {
      await _pumpStrip(
        tester,
        MasterStrip.fromMaster(
          _master(avgRating: 4.8, reviewCount: 0),
          showRating: true,
        ),
      );

      expect(find.text(MasterStrip.noRatingLabel), findsOneWidget);
      expect(find.text('4.8'), findsNothing);
    });

    testWidgets('a LEGITIMATE low rating (1.00) renders «1.0» — it is a real '
        'score, not an artefact, and must survive the fold', (tester) async {
      await _pumpStrip(
        tester,
        MasterStrip.fromMaster(
          _master(avgRating: 1, reviewCount: 3),
          showRating: true,
        ),
      );

      expect(find.text('1.0'), findsOneWidget);
      expect(
        find.text(MasterStrip.noRatingLabel),
        findsNothing,
        reason: 'a one-star master has a rating; it is simply a bad one',
      );
      expect(
        find.text('(3)'),
        findsOneWidget,
        reason: 'the muted review-count suffix rides alongside a real rating',
      );
    });
  });

  group('MasterStrip.fromBooking — the Booking-side fold reaches the glyph', () {
    testWidgets('a null masterAvgRating renders the em-dash', (tester) async {
      await _pumpStrip(
        tester,
        MasterStrip.fromBooking(
          _booking(masterAvgRating: null, masterReviewCount: 0),
        ),
      );

      expect(find.text(MasterStrip.noRatingLabel), findsOneWidget);
      expect(find.text('0.0'), findsNothing);
    });

    testWidgets('a stale 0.0 average with an ABSENT count renders the em-dash '
        '— the precise hole a count-only guard leaves open', (tester) async {
      await _pumpStrip(
        tester,
        MasterStrip.fromBooking(
          _booking(masterAvgRating: 0, masterReviewCount: null),
        ),
      );

      expect(find.text(MasterStrip.noRatingLabel), findsOneWidget);
      expect(find.text('0.0'), findsNothing);
    });

    testWidgets('a known-zero count renders the em-dash and suppresses the '
        '«(0)» suffix — the dash already says it', (tester) async {
      await _pumpStrip(
        tester,
        MasterStrip.fromBooking(
          _booking(masterAvgRating: 4.8, masterReviewCount: 0),
        ),
      );

      expect(find.text(MasterStrip.noRatingLabel), findsOneWidget);
      expect(find.text('(0)'), findsNothing);
    });

    testWidgets('a LEGITIMATE low rating (1.00) renders «1.0» on a booking '
        'surface too', (tester) async {
      await _pumpStrip(
        tester,
        MasterStrip.fromBooking(
          _booking(masterAvgRating: 1, masterReviewCount: 2),
        ),
      );

      expect(find.text('1.0'), findsOneWidget);
      expect(find.text(MasterStrip.noRatingLabel), findsNothing);
      expect(find.text('(2)'), findsOneWidget);
    });

    testWidgets('the DIVERGENCE renders: a real average with an UNKNOWN (null) '
        'count shows the rating with no count suffix — an omitted field must '
        'not hide a genuine score', (tester) async {
      await _pumpStrip(
        tester,
        MasterStrip.fromBooking(
          _booking(masterAvgRating: 4.9, masterReviewCount: null),
        ),
      );

      expect(
        find.text('4.9'),
        findsOneWidget,
        reason:
            'null count means UNKNOWN on the booking wire. Suppressing here '
            'would re-create the reported invisibility in mirror image.',
      );
      expect(find.text(MasterStrip.noRatingLabel), findsNothing);
      expect(
        find.text('(0)'),
        findsNothing,
        reason: 'an unknown count must not be printed as «(0)»',
      );
    });

    testWidgets('showRating defaults to TRUE on .fromBooking — the factory '
        'exists BECAUSE a booking finally carries the rating, so a call site '
        'must not have to remember to opt in', (tester) async {
      await _pumpStrip(
        tester,
        MasterStrip.fromBooking(
          _booking(masterAvgRating: 4.9, masterReviewCount: 24),
        ),
      );

      expect(find.text('4.9'), findsOneWidget);
      expect(find.text('(24)'), findsOneWidget);
    });
  });

  // ── The THIRD factory — the salon roster ────────────────────────────────
  //
  // `MasterStrip.fromSchedule` gained its own fold in this change
  // (`(schedule.reviewCount > 0) ? schedule.avgRating : null`). It is a
  // DIFFERENT guard from the other two — count-only, because
  // `SalonMasterSchedule.avgRating` is already null-when-unrated on the wire
  // — and it was shipped untested. Same bug class as the reported one: a
  // salon master with no reviews rendering «0.0».
  group('MasterStrip.fromSchedule — the salon roster fold', () {
    SalonMasterSchedule schedule({
      required double? avgRating,
      required int reviewCount,
    }) => SalonMasterSchedule(
      masterId: 'sm1',
      firstName: 'Ірина',
      lastName: 'Бондаренко',
      type: MasterType.salonMaster,
      avgRating: avgRating,
      reviewCount: reviewCount,
      services: const <SalonCatalogService>[],
      orderedMasterServiceIds: const <String>[],
    );

    testWidgets('a zero reviewCount renders the em-dash even when avgRating '
        'carries a stale number', (tester) async {
      await _pumpStrip(
        tester,
        MasterStrip.fromSchedule(
          schedule(avgRating: 4.7, reviewCount: 0),
          showRating: true,
        ),
      );

      expect(find.text(MasterStrip.noRatingLabel), findsOneWidget);
      expect(find.text('4.7'), findsNothing);
    });

    testWidgets('a null avgRating renders the em-dash', (tester) async {
      await _pumpStrip(
        tester,
        MasterStrip.fromSchedule(
          schedule(avgRating: null, reviewCount: 0),
          showRating: true,
        ),
      );

      expect(find.text(MasterStrip.noRatingLabel), findsOneWidget);
      expect(find.text('0.0'), findsNothing);
    });

    testWidgets('a LEGITIMATE low rating (1.00) survives on the roster too', (
      tester,
    ) async {
      await _pumpStrip(
        tester,
        MasterStrip.fromSchedule(
          schedule(avgRating: 1, reviewCount: 4),
          showRating: true,
        ),
      );

      expect(find.text('1.0'), findsOneWidget);
      expect(find.text('(4)'), findsOneWidget);
      expect(find.text(MasterStrip.noRatingLabel), findsNothing);
    });
  });
}
