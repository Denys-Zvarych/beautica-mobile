// 2026-08-13 — the DOMAIN tier of the "CANCELLED/DECLINED are hidden from the
// master's day list by default" decision.
//
// This file is the one `integration_test/master_bookings_flow_test.dart:2415`
// names as the tier that "pins `visibleInDayListByDefault` as a DERIVATION of
// `filterable` (a pure-Dart constant, no wire)". It did not exist — the E2E
// comment described a tier that had never been written, so the derivation and
// the non-idempotence hazard were carried by prose alone.
//
// ## What this tier owns, and what it deliberately does not
//
// Pure Dart, no widget tree, no repository. The WIRE half — that the resolved
// set actually reaches `GET /bookings/me` as repeated `status` params — is
// `master_bookings_filter_wiring_test.dart`'s job, and the rendered half is the
// E2E's. What only this tier can prove is that the three constants and the one
// mapping function are internally COHERENT: a derived constant that silently
// evaluates to the wrong set is the failure mode here, and it is invisible to
// every higher tier, because they compare the derived set against itself.
//
// That is also why the expected sets below are written as LITERAL enum
// members, never as `filterable.where(...)` re-derivations. A test that
// re-derives the constant it is checking passes for any value the constant
// takes.

import 'package:flutter_test/flutter_test.dart';

import 'package:beautica_mobile/features/booking/domain/booking_status.dart';

void main() {
  group('the day-list default status sets', () {
    // MUTATION: added `notCompleted` to `hiddenFromDayListByDefault`
    // (`booking_status.dart:91`) → 4 tests in this file failed, this one with:
    //   Expected: equals [...] unordered
    //     Actual: Set:[BookingStatus.confirmed, BookingStatus.completed]
    //      Which: has too few elements (2 < 3)
    // Restored.
    test('visibleInDayListByDefault is exactly CONFIRMED + COMPLETED + '
        'NOT_COMPLETED', () {
      expect(
        BookingStatus.visibleInDayListByDefault,
        unorderedEquals(<BookingStatus>{
          BookingStatus.confirmed,
          BookingStatus.completed,
          BookingStatus.notCompleted,
        }),
        reason:
            'the derived default view — written out as literals, never as a '
            're-derivation of `filterable`, or this test would compare the '
            'constant against itself and pass for any value it takes',
      );
    });

    // The half of the locked decision most likely to regress silently. Hiding
    // «Скасовані» and hiding the no-show look like the same "tidy the day list"
    // change, and the 3-status wire assertion elsewhere would still read as
    // plausible with NOT_COMPLETED swapped out for something else. Asserted
    // here on its own so the reason it stays is attached to the assertion.
    //
    // MUTATION: as above (`notCompleted` added to the hidden set) → this test
    // failed:
    //   Expected: contains BookingStatus:<BookingStatus.notCompleted>
    //     Actual: Set:[BookingStatus.confirmed, BookingStatus.completed]
    //      Which: does not contain BookingStatus:<BookingStatus.notCompleted>
    // Restored.
    test('a no-show stays VISIBLE without the master filtering', () {
      expect(
        BookingStatus.visibleInDayListByDefault,
        contains(BookingStatus.notCompleted),
        reason:
            "NOT_COMPLETED is the master's own record of a client who did not "
            'turn up and it feeds the two-sided client rating — it is '
            'deliberately NOT hidden alongside CANCELLED/DECLINED',
      );
      expect(
        BookingStatus.hiddenFromDayListByDefault,
        isNot(contains(BookingStatus.notCompleted)),
      );
    });

    // CANCELLED and DECLINED render the identical «Скасовано» badge and the
    // sheet selects them as ONE row, so hiding one without the other makes the
    // «Скасовані» filter row a lie.
    test('hiddenFromDayListByDefault is exactly DECLINED + CANCELLED', () {
      expect(
        BookingStatus.hiddenFromDayListByDefault,
        unorderedEquals(<BookingStatus>{
          BookingStatus.declined,
          BookingStatus.cancelled,
        }),
      );
    });

    // The derivation must be TOTAL and DISJOINT over `filterable`. This is what
    // catches the mistake the literal assertions above cannot: a member added
    // to `hiddenFromDayListByDefault` that is not in `filterable` at all (a
    // typo, or `unknown`) leaves `visibleInDayListByDefault` looking correct
    // while the two sets no longer partition the filterable universe.
    //
    // MUTATION: added `BookingStatus.unknown` to `hiddenFromDayListByDefault`
    // → BOTH visible-set assertions above stayed GREEN (subtracting a
    // non-member of `filterable` changes nothing about the visible set), which
    // is precisely the blind spot this test exists for. It failed with:
    //   Expected: equals [...5 filterable members...] unordered
    //     Actual: Set:[..., BookingStatus.unknown]
    //      Which: has too many elements (6 > 5)
    // Restored.
    test('hidden and visible PARTITION filterable — total and disjoint', () {
      final Set<BookingStatus> union = <BookingStatus>{
        ...BookingStatus.hiddenFromDayListByDefault,
        ...BookingStatus.visibleInDayListByDefault,
      };

      expect(
        union,
        unorderedEquals(BookingStatus.filterable),
        reason:
            'every filterable status must be either hidden-by-default or '
            'visible-by-default, and nothing outside `filterable` may appear '
            'in either set — `unknown` in particular would be a 400 on the wire',
      );
      expect(
        BookingStatus.hiddenFromDayListByDefault.intersection(
          BookingStatus.visibleInDayListByDefault,
        ),
        isEmpty,
      );
    });

    test('neither default set can carry the decode-only `unknown` member', () {
      expect(
        BookingStatus.visibleInDayListByDefault,
        isNot(contains(BookingStatus.unknown)),
      );
      expect(
        BookingStatus.hiddenFromDayListByDefault,
        isNot(contains(BookingStatus.unknown)),
      );
    });
  });

  group('dayListWireStatuses — the selection → wire mapping', () {
    // MUTATION: made the empty branch return `const <BookingStatus>{}`
    // (`booking_status.dart:179`) → 3 tests failed, this one with:
    //   Expected: equals [...] unordered
    //     Actual: Set:[]
    //      Which: has too few elements (0 < 3)
    // Restored.
    test('no selection resolves to the default-visible set', () {
      expect(
        BookingStatus.dayListWireStatuses(const <BookingStatus>{}),
        unorderedEquals(<BookingStatus>{
          BookingStatus.confirmed,
          BookingStatus.completed,
          BookingStatus.notCompleted,
        }),
      );
    });

    // MUTATION: made the containsAll branch return `selected`
    // (`booking_status.dart:180`) → 4 tests failed, this one with:
    //   Expected: empty
    //     Actual: Set:[...5 filterable members...]
    // Restored.
    test('selecting EVERY filterable status resolves to the EMPTY set', () {
      expect(
        BookingStatus.dayListWireStatuses(BookingStatus.filterable.toSet()),
        isEmpty,
        reason:
            'the maximal filter must OMIT `status` from the request entirely, '
            'so a status the backend gained after this build shipped is still '
            'reachable — naming the five statuses this build knows would make '
            'even "select all" an inclusion list',
      );
    });

    test('a partial selection is honoured VERBATIM — replace, never union', () {
      expect(
        BookingStatus.dayListWireStatuses(<BookingStatus>{
          BookingStatus.cancelled,
          BookingStatus.declined,
        }),
        unorderedEquals(<BookingStatus>{
          BookingStatus.cancelled,
          BookingStatus.declined,
        }),
        reason:
            'ticking «Скасовані» must send exactly the two hidden statuses — '
            'a union with the default set would hand the master the whole day '
            'back instead of the cancelled bookings they asked for',
      );
    });

    test(
      'a selection that already equals the default set is not re-resolved',
      () {
        expect(
          BookingStatus.dayListWireStatuses(
            BookingStatus.visibleInDayListByDefault.toSet(),
          ),
          unorderedEquals(BookingStatus.visibleInDayListByDefault),
        );
      },
    );
  });

  // ── The hazard the function's own doc warns about, made EXECUTABLE ────────
  //
  // `dayListWireStatuses` is NOT idempotent, and its doc says so in prose:
  // "Apply it exactly ONCE, at query construction". Prose does not fail a
  // build. mobile-security called a second application point a
  // security-relevant SILENT SUPPRESSION bug — the master is shown fewer
  // bookings than they asked for, with no error and no visible filter.
  //
  // These tests do not prevent a second application on their own. The CALL-SITE
  // guard for that already exists and was mutation-verified 2026-08-13:
  // swapping `MasterBookingsScreen:142`'s seed from `BookingsDayQuery.of` to
  // `.dayList` — the "consistency" change this track's own docs argue for, and
  // the one place it is wrong — turns SIX existing tests red across
  // `master_bookings_filter_wiring_test.dart` (5, on the funnel badge and the
  // post-filter wire sets) and `master_bookings_screen_test.dart` (1, the
  // true-empty copy). That regression is well covered; a seventh detector for
  // it was drafted here and deliberately dropped as duplicate.
  //
  // What these tests add instead is the exact WRONG OUTPUT a double
  // application produces, so that a future reader who wonders "is applying
  // this twice actually harmful?" gets an executable answer instead of a doc
  // comment — and so that anyone who "simplifies" `dayListWireStatuses` into
  // an idempotent shape (a natural-looking cleanup) has to delete an explicit,
  // reasoned assertion to do it.
  group('dayListWireStatuses is deliberately NOT idempotent', () {
    // The round trip that actually bites: the master ticks EVERY group, asking
    // to see everything including cancelled. One application resolves that to
    // `{}` (send no `status` param). Feeding that result back in reads it as
    // "no selection" and resolves it to the default-visible set — CANCELLED and
    // DECLINED silently RE-HIDDEN, having been explicitly requested.
    test(
      'double-applying a SELECT-ALL selection silently re-hides CANCELLED and '
      'DECLINED',
      () {
        final Set<BookingStatus> once = BookingStatus.dayListWireStatuses(
          BookingStatus.filterable.toSet(),
        );
        expect(
          once,
          isEmpty,
          reason: 'fixture guard — one application is `{}`',
        );

        final Set<BookingStatus> twice = BookingStatus.dayListWireStatuses(
          once,
        );

        expect(
          twice,
          unorderedEquals(BookingStatus.visibleInDayListByDefault),
          reason:
              'THIS IS THE BUG SHAPE, pinned so it is recognisable: the second '
              'application cannot tell "the master asked for everything" from '
              '"the master asked for nothing", because both are spelled `{}`',
        );
        expect(
          twice,
          isNot(contains(BookingStatus.cancelled)),
          reason:
              'the master explicitly ticked «Скасовані» as part of select-all '
              'and would be shown a day list with those bookings missing, with '
              'no error and no active-filter badge to explain it',
        );
        expect(twice, isNot(contains(BookingStatus.declined)));
      },
    );

    // Select-all is the ONLY non-idempotent input, and that is worth stating
    // precisely rather than as a blanket "f(f(x)) != f(x)". An earlier draft of
    // this test asserted the blanket form and failed on the empty selection:
    // `{}` resolves to the default-visible set, which is a PARTIAL selection
    // and so passes through verbatim on a second application. The empty seed
    // reaches a fixed point after one step; only select-all does not.
    test(
      'select-all is the only input that moves under a second application',
      () {
        final Set<BookingStatus> selectAllOnce =
            BookingStatus.dayListWireStatuses(BookingStatus.filterable.toSet());
        expect(
          BookingStatus.dayListWireStatuses(selectAllOnce),
          isNot(unorderedEquals(selectAllOnce)),
          reason:
              'select-all resolves to `{}`, and `{}` is ALSO the spelling of '
              '"the master selected nothing" — so a second application reads '
              'the maximal filter as the minimal one',
        );

        // The empty seed, by contrast, is stable — pinned so the asymmetry is
        // documented rather than looking like an oversight.
        final Set<BookingStatus> emptyOnce = BookingStatus.dayListWireStatuses(
          const <BookingStatus>{},
        );
        expect(
          BookingStatus.dayListWireStatuses(emptyOnce),
          unorderedEquals(emptyOnce),
          reason:
              'the default-visible set is a PARTIAL selection, so it passes '
              'through verbatim — the empty seed is a fixed point after one '
              'step and the hazard is select-all alone',
        );
      },
    );

    // The collapse stated as the property that actually matters: after a double
    // application, two OPPOSITE master intents — "show me everything" and "I
    // picked nothing" — become the same request. That is what makes the bug
    // silent; there is no state left that distinguishes them.
    test(
      'double application collapses «show everything» onto «show default»',
      () {
        expect(
          BookingStatus.dayListWireStatuses(
            BookingStatus.dayListWireStatuses(BookingStatus.filterable.toSet()),
          ),
          unorderedEquals(
            BookingStatus.dayListWireStatuses(const <BookingStatus>{}),
          ),
          reason:
              'the maximal and the minimal selection become indistinguishable — '
              'the master who ticked every group gets the default view back, '
              'and nothing downstream can tell that is not what they asked for',
        );
      },
    );
  });
}
