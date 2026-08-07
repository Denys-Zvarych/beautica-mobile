// Phase 13.8 wire-up — TIER 1 unit tests for [PassportMapper.fromDto].
//
// WHY THIS FILE EXISTS
// --------------------
// Until the 13.8 wire-up there was no `fromDto` at all: the mapper exposed
// `PassportMapper.placeholder()`, which returned `Passport.empty()` for every
// client forever. Nothing in `test/` mapped a wire payload onto [Passport], so
// the mapper had ZERO coverage and the always-empty screen was invisible to a
// green suite. This file pins the DTO→domain contract so the mapping can never
// silently degrade back to "empty for everyone".
//
// The generated [api.PassportResponse] / [api.BudgetBand] declare EVERY field
// nullable (SpringDoc emits no `required` list), so the mapper is the single
// place that decides the domain's non-null shape. Each absent-value policy
// documented in `passport_mapper.dart` gets its own case here — a policy with
// no test is a comment, not a contract.
//
// Pure Dart: no ProviderScope, no widget tree, no Dio.

import 'package:beautica_api/beautica_api.dart' as api;
import 'package:beautica_mobile/features/passport/data/passport_mapper.dart';
import 'package:beautica_mobile/features/passport/domain/passport.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// DTO builders
// ---------------------------------------------------------------------------

/// A FULLY POPULATED wire payload. Every value is deliberately distinguishable
/// from the empty passport AND from every other value in the fixture, so an
/// assertion cannot pass by coincidence (no shared 0s, no repeated strings, no
/// min == max). `avg`/`min`/`max` are supplied as `int` literals on purpose —
/// the DTO types them `num?` and Jackson serialises a whole-hryvnia figure as a
/// JSON integer, so the `num → double` widening is exercised for real.
api.PassportResponse _populatedDto() => api.PassportResponse(
  (b) => b
    ..favoriteProcedures.replace(<String>['Манікюр', 'Брови', 'Педикюр'])
    ..favoriteDistricts.replace(<String>['Центр', 'Сихів', 'Франківський'])
    ..bookingsConsidered = 7
    ..budget.avg = 600
    ..budget.min = 400
    ..budget.max = 800
    ..budget.currency = 'UAH',
);

/// The wire shape a brand-new client gets back: lists present but empty, no
/// budget band, zero completed bookings considered.
api.PassportResponse _emptyDto() => api.PassportResponse(
  (b) => b
    ..favoriteProcedures.replace(const <String>[])
    ..favoriteDistricts.replace(const <String>[])
    ..bookingsConsidered = 0,
);

/// A payload where EVERY key is omitted — the worst case the mapper promises
/// never to throw on.
api.PassportResponse _allNullDto() => api.PassportResponse((b) => b);

void main() {
  group('PassportMapper.fromDto — populated payload', () {
    // THE REGRESSION CASE. Under the deleted placeholder this expectation was
    // unreachable by construction: there was no code path from a wire payload
    // to a non-empty Passport. Verified RED by re-pointing the call site at a
    // `Passport.empty()`-returning stub — every assertion below fails.
    test('maps every derived field off the wire onto the domain model', () {
      final Passport p = PassportMapper.fromDto(_populatedDto());

      expect(p.favoriteProcedures, <String>['Манікюр', 'Брови', 'Педикюр']);
      expect(p.favoriteDistricts, <String>['Центр', 'Сихів', 'Франківський']);
      expect(p.bookingsConsidered, 7);
      expect(p.budget, isNotNull);
      expect(p.budget!.avg, 600.0);
      expect(p.budget!.min, 400.0);
      expect(p.budget!.max, 800.0);
      expect(p.budget!.currency, 'UAH');

      // The whole point of the wire-up: a client WITH history must not read as
      // empty. `isEmpty` is what selects the encouraging empty-passport screen
      // variant, so this is the assertion that separates "wired" from "not".
      expect(
        p.isEmpty,
        isFalse,
        reason:
            'a populated wire payload must not map to the empty-passport '
            'state — that collapse is the Phase 13.8 bug this file guards',
      );
      expect(p, isNot(Passport.empty()));
    });

    test('rank order of both derived lists is preserved, not re-sorted', () {
      final Passport p = PassportMapper.fromDto(_populatedDto());

      // The backend ranks most-frequent-first and caps at 3; the mapper must
      // not reorder. Asserting `first`/`last` explicitly so an alphabetical or
      // reversed copy fails rather than passing a set-equality check.
      expect(p.favoriteProcedures.first, 'Манікюр');
      expect(p.favoriteProcedures.last, 'Педикюр');
      expect(p.favoriteDistricts.first, 'Центр');
      expect(p.favoriteDistricts.last, 'Франківський');
    });

    test('widens the num bounds to double even for integral JSON numbers', () {
      final Passport p = PassportMapper.fromDto(_populatedDto());

      // `BudgetBand` types its bounds `double`; the DTO types them `num?`. A
      // missing `.toDouble()` throws at runtime rather than failing at compile
      // time, so the runtime type is asserted directly.
      expect(p.budget!.avg, isA<double>());
      expect(p.budget!.min, isA<double>());
      expect(p.budget!.max, isA<double>());
    });

    test('carries fractional bounds through unrounded', () {
      final api.PassportResponse dto = api.PassportResponse(
        (b) => b
          ..bookingsConsidered = 3
          ..budget.avg = 612.5
          ..budget.min = 399.99
          ..budget.max = 850.25,
      );

      final Passport p = PassportMapper.fromDto(dto);

      expect(p.budget!.avg, 612.5);
      expect(p.budget!.min, 399.99);
      expect(p.budget!.max, 850.25);
    });
  });

  group('PassportMapper.fromDto — empty and absent payloads', () {
    test('an empty-but-present payload maps to the empty passport', () {
      final Passport p = PassportMapper.fromDto(_emptyDto());

      expect(p.favoriteProcedures, isEmpty);
      expect(p.favoriteDistricts, isEmpty);
      expect(p.budget, isNull);
      expect(p.bookingsConsidered, 0);
      expect(p.isEmpty, isTrue);
      expect(p, Passport.empty());
    });

    test(
      'an all-keys-absent payload maps to the empty passport, never throws',
      () {
        final Passport p = PassportMapper.fromDto(_allNullDto());

        expect(p, Passport.empty());
        expect(p.isEmpty, isTrue);
      },
    );

    test('absent favoriteProcedures becomes an empty list, not null', () {
      final api.PassportResponse dto = api.PassportResponse(
        (b) => b
          ..favoriteDistricts.replace(<String>['Центр'])
          ..bookingsConsidered = 2,
      );

      final Passport p = PassportMapper.fromDto(dto);

      expect(p.favoriteProcedures, isEmpty);
      // The sibling list is unaffected — an omitted key must not blank the
      // whole aggregate.
      expect(p.favoriteDistricts, <String>['Центр']);
      expect(p.bookingsConsidered, 2);
    });

    test('absent favoriteDistricts becomes an empty list, not null', () {
      final api.PassportResponse dto = api.PassportResponse(
        (b) => b
          ..favoriteProcedures.replace(<String>['Манікюр'])
          ..bookingsConsidered = 2,
      );

      final Passport p = PassportMapper.fromDto(dto);

      expect(p.favoriteDistricts, isEmpty);
      expect(p.favoriteProcedures, <String>['Манікюр']);
    });

    test('absent bookingsConsidered defaults to 0 (the conservative read)', () {
      final api.PassportResponse dto = api.PassportResponse(
        (b) => b..favoriteProcedures.replace(<String>['Манікюр']),
      );

      final Passport p = PassportMapper.fromDto(dto);

      expect(p.bookingsConsidered, 0);
      expect(
        p.isEmpty,
        isTrue,
        reason: 'no count means no derivable history — do not guess one',
      );
    });
  });

  group('PassportMapper.fromDto — budget band nullability policy', () {
    test('an absent budget band maps to null', () {
      final api.PassportResponse dto = api.PassportResponse(
        (b) => b..bookingsConsidered = 4,
      );

      expect(PassportMapper.fromDto(dto).budget, isNull);
    });

    // The DELIBERATE decision, per the mapper's file header: a partially filled
    // band is NOT renderable as a spend envelope, and defaulting a missing
    // bound to 0 would fabricate a figure the client never spent. All three
    // single-hole permutations are pinned so a future "just default it" edit
    // cannot slip through by only being tested on one of them.
    test(
      'a band missing avg maps the WHOLE band to null (no fabricated bound)',
      () {
        final api.PassportResponse dto = api.PassportResponse(
          (b) => b
            ..bookingsConsidered = 4
            ..budget.min = 400
            ..budget.max = 800,
        );

        expect(PassportMapper.fromDto(dto).budget, isNull);
      },
    );

    test('a band missing min maps the WHOLE band to null', () {
      final api.PassportResponse dto = api.PassportResponse(
        (b) => b
          ..bookingsConsidered = 4
          ..budget.avg = 600
          ..budget.max = 800,
      );

      expect(PassportMapper.fromDto(dto).budget, isNull);
    });

    test('a band missing max maps the WHOLE band to null', () {
      final api.PassportResponse dto = api.PassportResponse(
        (b) => b
          ..bookingsConsidered = 4
          ..budget.avg = 600
          ..budget.min = 400,
      );

      expect(PassportMapper.fromDto(dto).budget, isNull);
    });

    test('a band present but wholly empty maps to null', () {
      final api.PassportResponse dto = api.PassportResponse(
        (b) => b
          ..bookingsConsidered = 4
          // Touching the nested builder materialises an all-null BudgetBand on
          // the wire object — the shape SpringDoc allows and the mapper must
          // survive.
          ..budget.currency = 'UAH',
      );

      expect(dto.budget, isNotNull);
      expect(PassportMapper.fromDto(dto).budget, isNull);
    });

    test('an absent currency defaults to UAH (Ukrainian market)', () {
      final api.PassportResponse dto = api.PassportResponse(
        (b) => b
          ..bookingsConsidered = 4
          ..budget.avg = 600
          ..budget.min = 400
          ..budget.max = 800,
      );

      expect(PassportMapper.fromDto(dto).budget!.currency, 'UAH');
    });

    test(
      'a non-UAH currency on the wire is carried through, not overwritten',
      () {
        final api.PassportResponse dto = api.PassportResponse(
          (b) => b
            ..bookingsConsidered = 4
            ..budget.avg = 60
            ..budget.min = 40
            ..budget.max = 80
            ..budget.currency = 'EUR',
        );

        // Proves the 'UAH' fallback is a FALLBACK and not an unconditional
        // overwrite — a test using only UAH could not tell the two apart.
        expect(PassportMapper.fromDto(dto).budget!.currency, 'EUR');
      },
    );
  });

  group('PassportMapper.fromDto — fields NOT on the wire contract', () {
    test('reviewsLeft and memberSinceYear keep their domain defaults', () {
      // The backend record carries neither. The mapper must not synthesise
      // them: a fabricated review count would be a lie, and the screen already
      // has a fallback for an absent member-since year.
      final Passport p = PassportMapper.fromDto(_populatedDto());

      expect(p.reviewsLeft, 0);
      expect(p.memberSinceYear, isNull);
    });
  });
}
