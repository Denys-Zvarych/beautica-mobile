// `BookingsDayQuery.showsAllOccupancy` — the occupancy-completeness
// invariant behind the false-«Вільно» fix (user-reported, 2026-08-13).
//
// WHY IT LIVES HERE AND NOT IN THE WIDGET SUITE
// ---------------------------------------------
// The bug was not in `DeclaredTimeCards`' merge; it was that NOTHING asked
// whether the fetched list could see every booking occupying the master's
// clock. That question is a property of the QUERY, so the predicate lives on
// the query — next to `BookingStatus.dayListWireStatuses`, whose
// "«Скасовані» REPLACES the default set" mapping created the situation — and
// is pinned here directly rather than only through a rendered card.
//
// EVERY ROW BELOW IS BUILT THROUGH `BookingsDayQuery.dayList`, deliberately:
// the getter reads WIRE statuses, and `dayList` is the only thing that turns
// a master's raw selection into one. Asking it of a `.of(...)` query built
// from a raw selection would answer a different question — see the getter's
// own ⚠ note.
//
// KEEP IN LOCKSTEP: the `containsAll` set the getter tests is exactly
// `declared_time_cards.dart`'s `consumesDeclaredTimes` allowlist. The last
// group below fails if that allowlist grows without this predicate growing
// with it — MECHANICALLY: it imports and CALLS that function rather than
// restating it as a literal, which is what an earlier revision of this file
// did (and which therefore could not fail).

import 'package:flutter_test/flutter_test.dart';

import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/domain/bookings_day_query.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/declared_time_cards.dart'
    show consumesDeclaredTimes;

final DateTime _day = DateTime(2026, 8, 13);

BookingsDayQuery _dayList({
  Set<BookingStatus> statuses = const <BookingStatus>{},
  Set<String> serviceIds = const <String>{},
}) => BookingsDayQuery.dayList(
  day: _day,
  statuses: statuses,
  serviceIds: serviceIds,
);

void main() {
  group('showsAllOccupancy — the occupancy-complete selections', () {
    test('the DEFAULT view (master picked nothing) is complete', () {
      // Resolves to {CONFIRMED, COMPLETED, NOT_COMPLETED} — it contains both
      // allowlisted statuses, which is why the default view never showed the
      // bug. That was a coincidence until this predicate stated it.
      expect(_dayList().showsAllOccupancy, isTrue);
    });

    test('SELECT-ALL (every filterable group ticked) is complete', () {
      // Resolves to the EMPTY wire set — no `status` param at all, so the
      // response is genuinely unfiltered. Empty means MORE here, not less.
      expect(
        _dayList(statuses: BookingStatus.filterable.toSet()).showsAllOccupancy,
        isTrue,
      );
    });

    test('a selection that happens to cover CONFIRMED + COMPLETED is '
        'complete', () {
      expect(
        _dayList(
          statuses: const <BookingStatus>{
            BookingStatus.confirmed,
            BookingStatus.completed,
          },
        ).showsAllOccupancy,
        isTrue,
      );
    });
  });

  group('showsAllOccupancy — THE BUG TABLE (every broken selection)', () {
    // One case per row of the reported blast radius. Each is a wire set that
    // hides at least one CONFIRMED-or-COMPLETED booking, so a free card drawn
    // from such a list would be a claim the query cannot back.
    for (final (String label, Set<BookingStatus> selected)
        in <(String, Set<BookingStatus>)>[
          ('«Скасовані» only', <BookingStatus>{BookingStatus.cancelled}),
          ('«Завершені» only', <BookingStatus>{BookingStatus.completed}),
          ('«Підтверджені» only', <BookingStatus>{BookingStatus.confirmed}),
          ('«Не відбулися» only', <BookingStatus>{BookingStatus.notCompleted}),
        ]) {
      test('$label is INCOMPLETE — free cards must be suppressed', () {
        expect(
          _dayList(statuses: selected).showsAllOccupancy,
          isFalse,
          reason:
              '$label cannot see every occupying booking; claiming a declared '
              'time is «Вільно» from it is the reported bug',
        );
      });
    }
  });

  group('showsAllOccupancy — the service filter is INDEPENDENT', () {
    test('a service filter alone falsifies it, even on the DEFAULT status '
        'view', () {
      // The second, independent instance of the same bug: `serviceId` goes on
      // the wire too, so narrowing to one service hides every booking of
      // another — with no status filter involved at all.
      expect(
        _dayList(serviceIds: const <String>{'svc-1'}).showsAllOccupancy,
        isFalse,
      );
    });

    test('a service filter falsifies it even under SELECT-ALL statuses', () {
      expect(
        _dayList(
          statuses: BookingStatus.filterable.toSet(),
          serviceIds: const <String>{'svc-1'},
        ).showsAllOccupancy,
        isFalse,
        reason:
            'the empty wire status set means "all statuses", never "all '
            'services"',
      );
    });
  });

  group('showsAllOccupancy vs hasFilters — different questions', () {
    test('the default view has filters on the wire yet IS complete', () {
      final BookingsDayQuery q = _dayList();
      expect(q.hasFilters, isTrue, reason: 'the default exclusion is a filter');
      expect(q.showsAllOccupancy, isTrue);
    });

    test('select-all has NO wire filters and is also complete', () {
      final BookingsDayQuery q = _dayList(
        statuses: BookingStatus.filterable.toSet(),
      );
      expect(q.hasFilters, isFalse);
      expect(q.showsAllOccupancy, isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // THE LOCKSTEP GUARD. `showsAllOccupancy` must demand exactly the statuses
  // `consumesDeclaredTimes` (declared_time_cards.dart) treats as occupying
  // the clock. A status added to that allowlist without being added to the
  // predicate would let a filter excluding it draw free cards over occupied
  // slots again — the reported bug, reopened.
  //
  // `occupying` below is DERIVED BY CALLING the real allowlist, never copied.
  // The previous revision of this group declared the same set as a test-local
  // literal, which made it a restatement of the predicate against a hand-copy
  // of itself: `consumesDeclaredTimes` was file-private and no expression in
  // this file read it, so growing the allowlist could not turn anything red.
  // It can now — mutation-verified by adding `notCompleted => true` to the
  // allowlist and watching the first test below fail.
  //
  // The allowlist is `@visibleForTesting` for this one purpose; nothing here
  // exercises it as behaviour (pass 1b's drop rule is
  // `declared_time_cards_test.dart`'s job), only as the OTHER HALF of a
  // coupling this file's predicate cannot see.
  // ═══════════════════════════════════════════════════════════════════════
  group('lockstep with consumesDeclaredTimes', () {
    // The real allowlist, read through the real function. `filterable` is the
    // right domain: it is exactly the set a wire status set can be built from
    // (`BookingStatus.unknown` is unfilterable and is pinned separately at the
    // end of this group).
    final Set<BookingStatus> occupying = BookingStatus.filterable
        .where(consumesDeclaredTimes)
        .toSet();

    test('a wire set missing ANY occupying status is incomplete', () {
      expect(
        occupying,
        isNotEmpty,
        reason:
            'an empty allowlist would make this whole group vacuous — nothing '
            'would occupy the clock and every filter would be "complete"',
      );
      for (final BookingStatus dropped in occupying) {
        final Set<BookingStatus> withoutOne = BookingStatus.filterable
            .where((BookingStatus s) => s != dropped)
            .toSet();
        expect(
          _dayList(statuses: withoutOne).showsAllOccupancy,
          isFalse,
          reason:
              'dropping ${dropped.name} from the selection hides bookings '
              'that DO take the master\'s time — consumesDeclaredTimes says '
              'it occupies the clock, so showsAllOccupancy must demand it',
        );
      }
    });

    test('a wire set carrying every occupying status is complete, however '
        'many non-occupying ones it drops', () {
      expect(_dayList(statuses: occupying).showsAllOccupancy, isTrue);
    });

    test('a status the allowlist does NOT claim never falsifies the '
        'predicate on its own', () {
      // The other direction of the same coupling: the predicate must not
      // demand more than the allowlist does, or it would suppress free cards
      // on a filter that can in fact see every occupying booking.
      for (final BookingStatus free in BookingStatus.filterable.where(
        (BookingStatus s) => !consumesDeclaredTimes(s),
      )) {
        expect(
          _dayList(
            statuses: occupying.union(<BookingStatus>{free}),
          ).showsAllOccupancy,
          isTrue,
          reason:
              '${free.name} does not consume a declared time, so adding or '
              'omitting it cannot change occupancy completeness',
        );
      }
    });

    test('an UNFILTERABLE status may never join the allowlist', () {
      // The hole `filterable.where(...)` cannot express: `unknown` can never
      // appear in a wire status set (the backend 400s on it), so if it ever
      // started consuming a declared time, NO selection could be
      // occupancy-complete and `showsAllOccupancy` would have no honest way
      // to say so. `consumesDeclaredTimes`' own doc pins `unknown => false`
      // as deliberate; this is that decision made mechanical.
      for (final BookingStatus s in BookingStatus.values.where(
        (BookingStatus s) => !BookingStatus.filterable.contains(s),
      )) {
        expect(
          consumesDeclaredTimes(s),
          isFalse,
          reason:
              '${s.name} cannot be sent on the wire, so it must not be able '
              'to occupy the clock',
        );
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // LOCKSTEP 2, MADE FAILABLE — the implication behind
  // `bookings_discovery_view.dart:1140`'s
  // `assert(showsAllOccupancy || hasFilters)`.
  //
  // That assert is the ONLY statement of the rule the empty gate below it
  // depends on: a free-card-suppressed day is routed to
  // `MasterBookingsNoResultsState` (which carries the «Скинути фільтри» CTA)
  // purely because `!showsAllOccupancy` implies THE MASTER FILTERED. It is
  // structurally unreachable today, so nothing exercises it — an assert
  // nobody can fire is documentation, and documentation does not fail a
  // build. This group is the failable form.
  //
  // TWO DIFFERENT SETS, deliberately, and this is the whole subtlety:
  //   * `showsAllOccupancy` is asked of the WIRE query (`_liveQuery`);
  //   * `hasFilters` at the gate is `_hasUserFilters` — the master's RAW
  //     selection (`bookings_discovery_view.dart:275`), NOT
  //     `BookingsDayQuery.hasFilters`, which is a wire-shape question and
  //     genuinely disagrees (the default view has wire filters and no user
  //     ones). Restating this against `q.hasFilters` would be a DIFFERENT,
  //     weaker claim that the mutation below cannot break — so every row
  //     here is phrased over the RAW selection the screen actually holds.
  //
  // WHAT THE SWEEP DOES AND DOES NOT BUY (stated plainly rather than left to
  // look bigger than it is). `_hasUserFilters` is `statuses.isNotEmpty ||
  // serviceIds.isNotEmpty`, so EVERY non-empty selection satisfies the
  // consequent definitionally — the EMPTY selection is the only one of the 32
  // that can ever violate the implication, and it is the only row the
  // mutation below actually reddens. The powerset walk is therefore a proof
  // that the exposure is exactly ONE row, not extra assertions: it is what
  // lets the third test below name that row as "the one that matters most"
  // without hand-waving. Cheap enough (32 pure-Dart evaluations) to state
  // mechanically instead of in a comment.
  //
  // MUTATION-VERIFIED: adding `confirmed` to
  // `BookingStatus.hiddenFromDayListByDefault` (the exact drift lockstep 2
  // names) turns the empty-selection row RED — the default wire set loses
  // CONFIRMED, an untouched screen stops being occupancy-complete, and a day
  // the master never filtered would render the no-filter empty state with no
  // way out of a filter they never set.
  // ═══════════════════════════════════════════════════════════════════════
  group('!showsAllOccupancy implies the MASTER filtered (the empty gate)', () {
    /// Every subset of [BookingStatus.filterable], the master's raw selection
    /// space in the filter sheet.
    Iterable<Set<BookingStatus>> rawSelections() sync* {
      const List<BookingStatus> all = BookingStatus.filterable;
      // DERIVED from `filterable.length`, never the literal 32: a new
      // filterable status must widen the sweep automatically, or this group
      // would silently stop covering the selections that status unlocks.
      for (int mask = 0; mask < (1 << all.length); mask++) {
        yield <BookingStatus>{
          for (int i = 0; i < all.length; i++)
            if (mask & (1 << i) != 0) all[i],
        };
      }
    }

    test('holds for every one of the 32 status selections', () {
      int checked = 0;
      for (final Set<BookingStatus> selected in rawSelections()) {
        checked++;
        // `_hasUserFilters` for a status-only selection.
        final bool hasUserFilters = selected.isNotEmpty;
        if (_dayList(statuses: selected).showsAllOccupancy) continue;
        expect(
          hasUserFilters,
          isTrue,
          reason:
              'the wire set for raw selection '
              '{${selected.map((BookingStatus s) => s.name).join(', ')}} '
              'cannot see all occupancy, yet the master narrowed nothing — '
              'the empty gate would render MasterBookingsEmptyState (no '
              'clear-filters CTA) on a day it suppressed the free cards of, '
              'stranding the master with a blank screen',
        );
      }
      expect(
        checked,
        1 << BookingStatus.filterable.length,
        reason:
            'the powerset must be walked in full, or this proves less than it '
            'claims — a generator that yielded nothing would make the loop '
            'above vacuously green',
      );
    });

    test('holds for every status selection combined with a service filter', () {
      for (final Set<BookingStatus> selected in rawSelections()) {
        // ONLY THE ANTECEDENT IS ASSERTED HERE, deliberately. The consequent
        // ("a service filter is itself a user filter") is DEFINITIONAL:
        // `_hasUserFilters` is `_statuses.isNotEmpty || _serviceIds.isNotEmpty`
        // (`bookings_discovery_view.dart:275`), so a non-empty `serviceIds`
        // satisfies it unconditionally and no production change reachable from
        // this file can falsify it. An `expect` restating it would be a
        // tautology over literals — green through any bug, and worse than no
        // line at all because it reads like a guard. The FAILABLE half is the
        // one below: a service filter must knock the query out of
        // occupancy-completeness for EVERY status selection, including the ones
        // that pass the status half on their own. That is the half the assert's
        // own message does not mention and the one that made the bug reachable
        // in the DEFAULT view.
        final BookingsDayQuery q = _dayList(
          statuses: selected,
          serviceIds: const <String>{'svc-1'},
        );
        expect(q.showsAllOccupancy, isFalse);
      }
    });

    test('the DEFAULT (untouched) screen is the row that matters most', () {
      // Called out separately from the loop above because it is the only row
      // whose violation is INVISIBLE to the master: every other failing
      // selection at least shows a funnel badge. Spelled out so a future
      // reader sees the claim without decoding the powerset.
      expect(
        _dayList().showsAllOccupancy,
        isTrue,
        reason:
            'an untouched screen has no filter to clear, so it MUST be '
            'occupancy-complete — otherwise the free cards vanish and the '
            'empty gate picks the CTA-less copy',
      );
    });
  });
}
