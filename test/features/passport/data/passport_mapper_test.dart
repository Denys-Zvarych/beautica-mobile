// Phase 13.8 wire-up / 235 — TIER 1 unit tests for [PassportMapper.fromDto].
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
// PHASE 235 added `favoriteCities`, renamed `reviewsLeft` → `reviewsWritten`,
// and made `memberSinceYear` a REQUIRED non-null int. The last one changes the
// mapper's contract from "never throws" to "throws on exactly one omission":
// there is no honest default for a join year, and the alternative the screen
// used to run — `?? DateTime.now().year` — fabricated the current year for
// every client. The throw is pinned below so nobody can reintroduce a default.
//
// Pure Dart: no ProviderScope, no widget tree, no Dio.

import 'package:beautica_api/beautica_api.dart' as api;
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/passport/data/passport_mapper.dart';
import 'package:beautica_mobile/features/passport/domain/passport.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// DTO builders
// ---------------------------------------------------------------------------

/// The join year every fixture carries. Deliberately NOT the current year: a
/// `?? DateTime.now().year` fallback sneaking back into the mapper would still
/// satisfy an `isNotNull` assertion, but it cannot produce 2021.
const int _joinYear = 2021;

/// A FULLY POPULATED wire payload. Every value is deliberately distinguishable
/// from the empty passport AND from every other value in the fixture, so an
/// assertion cannot pass by coincidence (no shared 0s, no repeated strings, no
/// min == max). `avg`/`min`/`max` are supplied as `int` literals on purpose —
/// the DTO types them `num?` and Jackson serialises a whole-hryvnia figure as a
/// JSON integer, so the `num → double` widening is exercised for real.
api.PassportResponse _populatedDto() => api.PassportResponse(
  (b) => b
    ..memberSinceYear = _joinYear
    ..favoriteProcedures.replace(<String>['Манікюр', 'Брови', 'Педикюр'])
    ..favoriteDistricts.replace(<String>['Центр', 'Сихів', 'Франківський'])
    ..favoriteCities.replace(<String>['Львів', 'Київ', 'Одеса'])
    ..bookingsConsidered = 7
    ..reviewsWritten = 5
    ..budget.avg = 600
    ..budget.min = 400
    ..budget.max = 800
    ..budget.currency = 'UAH',
);

/// The wire shape a brand-new client gets back: lists present but empty, no
/// budget band, zero completed bookings considered.
api.PassportResponse _emptyDto() => api.PassportResponse(
  (b) => b
    ..memberSinceYear = _joinYear
    ..favoriteProcedures.replace(const <String>[])
    ..favoriteDistricts.replace(const <String>[])
    ..favoriteCities.replace(const <String>[])
    ..bookingsConsidered = 0
    ..reviewsWritten = 0,
);

/// A payload where EVERY key is omitted. Since Phase 235 this is the ONE shape
/// the mapper rejects: with no `memberSinceYear` there is nothing honest to
/// map, so it throws instead of inventing a year.
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
      expect(p.favoriteCities, <String>['Львів', 'Київ', 'Одеса']);
      expect(p.bookingsConsidered, 7);
      expect(p.reviewsWritten, 5);
      expect(p.memberSinceYear, _joinYear);
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
      expect(p, isNot(Passport.empty(memberSinceYear: _joinYear)));
    });

    test(
      'rank order of all three derived lists is preserved, not re-sorted',
      () {
        final Passport p = PassportMapper.fromDto(_populatedDto());

        // The backend ranks most-frequent-first and caps at 3; the mapper must
        // not reorder. Asserting `first`/`last` explicitly so an alphabetical or
        // reversed copy fails rather than passing a set-equality check.
        expect(p.favoriteProcedures.first, 'Манікюр');
        expect(p.favoriteProcedures.last, 'Педикюр');
        expect(p.favoriteDistricts.first, 'Центр');
        expect(p.favoriteDistricts.last, 'Франківський');
        // Львів is first by frequency; alphabetically it would sort last of the
        // three, so a stray `..sort()` fails here rather than passing.
        expect(p.favoriteCities.first, 'Львів');
        expect(p.favoriteCities.last, 'Одеса');
      },
    );

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
          ..memberSinceYear = _joinYear
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
      expect(p.favoriteCities, isEmpty);
      expect(p.budget, isNull);
      expect(p.bookingsConsidered, 0);
      expect(p.reviewsWritten, 0);
      expect(p.isEmpty, isTrue);
      expect(p, Passport.empty(memberSinceYear: _joinYear));
    });

    // PHASE 235 — this case USED to assert "never throws". It now asserts the
    // opposite for one specific reason: `memberSinceYear` has no honest
    // default. Everything else on an all-keys-absent payload still degrades
    // gracefully; the join year alone is fatal, because the only way to supply
    // one is to invent it.
    test(
      'an all-keys-absent payload throws ServerFailure (no fabricated year)',
      () {
        expect(
          () => PassportMapper.fromDto(_allNullDto()),
          throwsA(isA<ServerFailure>()),
        );
      },
    );

    test('absent favoriteCities becomes an empty list, not null', () {
      final api.PassportResponse dto = api.PassportResponse(
        (b) => b
          ..memberSinceYear = _joinYear
          ..favoriteDistricts.replace(<String>['Центр'])
          ..bookingsConsidered = 2,
      );

      final Passport p = PassportMapper.fromDto(dto);

      expect(p.favoriteCities, isEmpty);
      // The sibling list is unaffected — an omitted key must not blank the
      // whole aggregate.
      expect(p.favoriteDistricts, <String>['Центр']);
    });

    test('favoriteCities present maps through verbatim', () {
      final api.PassportResponse dto = api.PassportResponse(
        (b) => b
          ..memberSinceYear = _joinYear
          ..favoriteCities.replace(<String>['Львів', 'Тернопіль'])
          ..bookingsConsidered = 6,
      );

      final Passport p = PassportMapper.fromDto(dto);

      // Asserted against a fixture DISTINCT from `favoriteDistricts` so a
      // copy-paste that maps districts into cities fails here.
      expect(p.favoriteCities, <String>['Львів', 'Тернопіль']);
      expect(p.favoriteDistricts, isEmpty);
    });

    test('absent favoriteProcedures becomes an empty list, not null', () {
      final api.PassportResponse dto = api.PassportResponse(
        (b) => b
          ..memberSinceYear = _joinYear
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
          ..memberSinceYear = _joinYear
          ..favoriteProcedures.replace(<String>['Манікюр'])
          ..bookingsConsidered = 2,
      );

      final Passport p = PassportMapper.fromDto(dto);

      expect(p.favoriteDistricts, isEmpty);
      expect(p.favoriteProcedures, <String>['Манікюр']);
    });

    test('absent bookingsConsidered defaults to 0 (the conservative read)', () {
      final api.PassportResponse dto = api.PassportResponse(
        (b) => b
          ..memberSinceYear = _joinYear
          ..favoriteProcedures.replace(<String>['Манікюр']),
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

  group('PassportMapper.fromDto — client standing (Phase 235)', () {
    test('maps reviewsWritten off the wire', () {
      final api.PassportResponse dto = api.PassportResponse(
        (b) => b
          ..memberSinceYear = _joinYear
          ..bookingsConsidered = 9
          ..reviewsWritten = 4,
      );

      // 4 ≠ 9 and 4 ≠ 0, so neither a bookingsConsidered mix-up nor a silent
      // fallback to the default can satisfy this.
      expect(PassportMapper.fromDto(dto).reviewsWritten, 4);
    });

    test('absent reviewsWritten defaults to 0 (nothing is invented)', () {
      final api.PassportResponse dto = api.PassportResponse(
        (b) => b
          ..memberSinceYear = _joinYear
          ..bookingsConsidered = 9,
      );

      // 0 is honest here: "wrote none" and "count omitted" mean the same thing
      // on screen. Contrast with memberSinceYear, where 0 would be a lie.
      expect(PassportMapper.fromDto(dto).reviewsWritten, 0);
    });

    test('maps memberSinceYear off the wire verbatim', () {
      final api.PassportResponse dto = api.PassportResponse(
        (b) => b
          ..memberSinceYear = 2019
          ..bookingsConsidered = 3,
      );

      final Passport p = PassportMapper.fromDto(dto);

      expect(p.memberSinceYear, 2019);
      // The regression guard. `DateTime.now().year` was the live fallback in
      // `passport_screen.dart` until Phase 235; a mapper that re-derived the
      // year instead of reading it would pass the equality above only by
      // accident in 2019.
      expect(
        p.memberSinceYear,
        isNot(DateTime.now().year), // instant-ok: asserting NON-fabrication
        reason: 'the join year must come off the wire, never from the clock',
      );
    });

    test(
      'throws ServerFailure when memberSinceYear is missing from an otherwise '
      'complete payload',
      () {
        // Everything else present — this isolates the year as the sole cause,
        // so the test cannot pass because of some unrelated null.
        final api.PassportResponse dto = api.PassportResponse(
          (b) => b
            ..favoriteProcedures.replace(<String>['Манікюр'])
            ..favoriteDistricts.replace(<String>['Центр'])
            ..favoriteCities.replace(<String>['Львів'])
            ..bookingsConsidered = 7
            ..reviewsWritten = 2
            ..budget.avg = 600
            ..budget.min = 400
            ..budget.max = 800,
        );

        expect(
          () => PassportMapper.fromDto(dto),
          throwsA(
            isA<ServerFailure>().having(
              (ServerFailure f) => f.statusCode,
              'statusCode',
              isNull,
            ),
          ),
          reason:
              'a broken payload must surface the screen error state — the '
              'alternative is inventing a year, which the design forbids',
        );
      },
    );
  });

  group('PassportMapper.fromDto — budget band nullability policy', () {
    test('an absent budget band maps to null', () {
      final api.PassportResponse dto = api.PassportResponse(
        (b) => b
          ..memberSinceYear = _joinYear
          ..bookingsConsidered = 4,
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
            ..memberSinceYear = _joinYear
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
          ..memberSinceYear = _joinYear
          ..bookingsConsidered = 4
          ..budget.avg = 600
          ..budget.max = 800,
      );

      expect(PassportMapper.fromDto(dto).budget, isNull);
    });

    test('a band missing max maps the WHOLE band to null', () {
      final api.PassportResponse dto = api.PassportResponse(
        (b) => b
          ..memberSinceYear = _joinYear
          ..bookingsConsidered = 4
          ..budget.avg = 600
          ..budget.min = 400,
      );

      expect(PassportMapper.fromDto(dto).budget, isNull);
    });

    test('a band present but wholly empty maps to null', () {
      final api.PassportResponse dto = api.PassportResponse(
        (b) => b
          ..memberSinceYear = _joinYear
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
          ..memberSinceYear = _joinYear
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
            ..memberSinceYear = _joinYear
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

  group('PassportMapper.fromDto — favoriteProcedures (removal pending)', () {
    test('still maps favoriteProcedures while the wire still carries it', () {
      // The approved page dropped the «Улюблені процедури» column, but backend
      // 250 has not yet removed the field and it is GATED on this port landing.
      // Until both sides drop it, silently discarding it here would be an
      // undocumented contract change. Delete this test with the field.
      final Passport p = PassportMapper.fromDto(_populatedDto());

      expect(p.favoriteProcedures, <String>['Манікюр', 'Брови', 'Педикюр']);
    });
  });
}
