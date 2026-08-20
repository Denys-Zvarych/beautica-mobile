// Phase 252 — unit tests for [CreateMasterBookingRequest]'s `masterServiceIds`
// field: widened from a scalar `masterServiceId` to an ORDERED, duplicate-
// tolerant `List<String>` (backend track 22.8–22.16 — the walk-in create
// endpoint now creates a multi-service VISIT).
//
// WHAT THIS FILE DOES *NOT* COVER, AND WHY
// -----------------------------------------
// The phase doc (`docs/mobile-phases/phase-252-walkin-multi-service-data-
// layer.md`, D1) asks for emptiness/cap ("rejects empty", "rejects 11 ids",
// "accepts exactly 10") validation "at construction". That validation does
// NOT live on this freezed class — see `create_master_booking_request.dart`'s
// file header ("Emptiness/cap validation lives in the REPOSITORY, not here")
// for why: `maxServicesPerVisit` lives in `data/slot_repository.dart`, which
// imports `package:flutter/foundation.dart`, and this domain file is pure
// Dart with no Flutter dependency, by the project's own layering rule
// (`domain/` never imports `data/`). The guard lives at
// `HttpBookingRepository.createMasterBooking`'s wire boundary instead — see
// `booking_repository_test.dart`'s `createMasterBooking` group for the
// "empty → ArgumentError" / "11 → ArgumentError" / "10 → accepted" coverage
// the phase doc asks for. This file covers only what the freezed class
// itself is responsible for: holding the list AS GIVEN — order and
// duplicates untouched — with no `Set`/sort silently applied.
//
// Pure Dart: no ProviderScope, no widget tree.

import 'package:beautica_mobile/features/booking/domain/create_master_booking_request.dart';
import 'package:flutter_test/flutter_test.dart';

// A fixed PAST literal, not `futureBookingStart()` — nothing here exercises
// `BookingDisplayX.isPast`/"upcoming" rendering (that's the pure freezed
// shape only), and a past instant can never expire into a stale-fixture
// false negative the way an absolute future one would (see
// `scripts/forbid_stale_future_date_fixture.sh`'s doc).
CreateMasterBookingRequest _build(List<String> masterServiceIds) =>
    CreateMasterBookingRequest(
      masterServiceIds: masterServiceIds,
      startsAt: DateTime.utc(2020, 7, 10, 11),
      guest: const WalkInGuest(
        name: 'Іван',
        surname: 'Петренко',
        phone: '+380501234567',
      ),
    );

void main() {
  test('preserves the given order — never re-sorted', () {
    final req = _build(<String>['service-c', 'service-a', 'service-b']);

    expect(req.masterServiceIds, <String>[
      'service-c',
      'service-a',
      'service-b',
    ]);
  });

  test('preserves duplicates — never de-duplicated into a Set', () {
    final req = _build(<String>['service-a', 'service-a', 'service-b']);

    expect(req.masterServiceIds, <String>[
      'service-a',
      'service-a',
      'service-b',
    ]);
    expect(req.masterServiceIds, hasLength(3));
  });

  test('accepts a single-element list (the pre-252 single-service shape, '
      'now wrapped)', () {
    final req = _build(<String>['service-1']);

    expect(req.masterServiceIds, <String>['service-1']);
  });

  test('accepts exactly 10 ids (at maxServicesPerVisit) — freezed itself '
      'imposes no cap; the repository enforces it', () {
    final ids = List<String>.generate(10, (i) => 'service-$i');
    final req = _build(ids);

    expect(req.masterServiceIds, ids);
  });

  test('two requests with the same fields in the same order are equal '
      '(freezed value equality) — order-sensitive: same ids in a different '
      'order are NOT equal', () {
    final a = _build(<String>['service-a', 'service-b']);
    final b = _build(<String>['service-a', 'service-b']);
    final reordered = _build(<String>['service-b', 'service-a']);

    expect(a, b);
    expect(a, isNot(reordered));
  });
}
