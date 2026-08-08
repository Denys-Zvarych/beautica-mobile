// Phase 13.8 / 235 — BEAUTY PASSPORT domain unit tests.
//
// Pure-Dart coverage of the [Passport] value object and its [BudgetBand]:
//   • Passport.empty() is the canonical empty state (bookingsConsidered == 0,
//     no derived data) and reports isEmpty == true.
//   • A populated passport (bookingsConsidered > 0) reports isEmpty == false.
//   • isEmpty keys ONLY off bookingsConsidered, not off whether the derived
//     lists happen to be empty — a passport with history but (transiently) no
//     districts is still NOT empty.
//   • copyWith / value equality behave as freezed guarantees.
//   • BudgetBand defaults currency to UAH and preserves the avg/min/max
//     envelope.
//
// PHASE 235 — `memberSinceYear` is a REQUIRED non-null `int`, on the model AND
// on `Passport.empty()`. That is the type-level half of the "never fabricate a
// year" rule: with no nullable slot there is nowhere for a
// `?? DateTime.now().year` fallback to attach. The empty-passport test below
// passes an explicit year for exactly that reason — an empty passport means
// "no bookings yet", never "no account yet".

import 'package:beautica_mobile/features/passport/domain/passport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Passport.empty()', () {
    test('has no derived data, zero history, and reports isEmpty', () {
      final Passport p = Passport.empty(memberSinceYear: 2024);

      expect(p.bookingsConsidered, 0);
      expect(p.favoriteDistricts, isEmpty);
      expect(p.favoriteCities, isEmpty);
      expect(p.budget, isNull);
      expect(p.reviewsWritten, 0);
      expect(p.isEmpty, isTrue);
    });

    test('carries the caller-supplied join year, never a synthesised one', () {
      // The join year is known even with zero bookings, so `empty()` must not
      // become a back door for a fabricated one. Asserting a year that is NOT
      // the current year is the point: a `DateTime.now().year` default would
      // pass an `isNotNull` check but fail this.
      final Passport p = Passport.empty(memberSinceYear: 2019);

      expect(p.memberSinceYear, 2019);
      expect(
        p.memberSinceYear,
        isNot(DateTime.now().year), // instant-ok: asserting NON-fabrication
        reason:
            'the empty passport must echo the supplied year, not default to '
            'the current one — Phase 235 deleted that fabrication',
      );
    });

    test('two empties with the same join year are value-equal', () {
      expect(
        Passport.empty(memberSinceYear: 2024),
        equals(Passport.empty(memberSinceYear: 2024)),
      );
    });

    test('empties differing only in join year are NOT equal', () {
      expect(
        Passport.empty(memberSinceYear: 2024),
        isNot(equals(Passport.empty(memberSinceYear: 2023))),
      );
    });
  });

  group('Passport.isEmpty', () {
    test('is false once any completed booking was considered', () {
      const Passport p = Passport(
        favoriteDistricts: <String>['Центр'],
        favoriteCities: <String>['Львів'],
        budget: BudgetBand(avg: 600, min: 400, max: 800),
        bookingsConsidered: 3,
        reviewsWritten: 1,
        memberSinceYear: 2024,
      );

      expect(p.isEmpty, isFalse);
    });

    test('keys off bookingsConsidered, not off empty derived lists '
        '(history present but lists transiently empty ⇒ NOT empty)', () {
      const Passport p = Passport(
        favoriteDistricts: <String>[],
        favoriteCities: <String>[],
        budget: null,
        bookingsConsidered: 2,
        reviewsWritten: 0,
        memberSinceYear: 2024,
      );

      expect(p.isEmpty, isFalse);
    });

    test('is true exactly when bookingsConsidered == 0', () {
      const Passport p = Passport(
        favoriteDistricts: <String>['Сихів'],
        favoriteCities: <String>['Львів'],
        budget: BudgetBand(avg: 500, min: 500, max: 500),
        bookingsConsidered: 0,
        reviewsWritten: 4,
        memberSinceYear: 2024,
      );

      // Even with derived data present, zero considered history ⇒ empty.
      expect(p.isEmpty, isTrue);
    });
  });

  group('Passport copyWith / equality', () {
    test('copyWith overrides only the named fields', () {
      final Passport base = Passport.empty(memberSinceYear: 2020);

      final Passport next = base.copyWith(
        bookingsConsidered: 5,
        favoriteCities: <String>['Львів'],
        reviewsWritten: 2,
      );

      expect(next.bookingsConsidered, 5);
      expect(next.favoriteCities, <String>['Львів']);
      expect(next.reviewsWritten, 2);
      // Untouched fields preserved — including the join year, which copyWith
      // must carry through rather than re-derive.
      expect(next.memberSinceYear, 2020);
      expect(next.favoriteDistricts, isEmpty);
      expect(next.budget, isNull);
      expect(next.isEmpty, isFalse);
    });

    test('value equality / hashCode hold for identical field sets', () {
      const Passport a = Passport(
        favoriteDistricts: <String>['Центр'],
        favoriteCities: <String>['Львів', 'Київ'],
        budget: BudgetBand(avg: 600, min: 400, max: 900),
        bookingsConsidered: 4,
        reviewsWritten: 3,
        memberSinceYear: 2023,
      );
      const Passport b = Passport(
        favoriteDistricts: <String>['Центр'],
        favoriteCities: <String>['Львів', 'Київ'],
        budget: BudgetBand(avg: 600, min: 400, max: 900),
        bookingsConsidered: 4,
        reviewsWritten: 3,
        memberSinceYear: 2023,
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('favoriteCities participates in equality (not an ignored field)', () {
      const Passport a = Passport(
        favoriteDistricts: <String>[],
        favoriteCities: <String>['Львів'],
        budget: null,
        bookingsConsidered: 4,
        reviewsWritten: 0,
        memberSinceYear: 2023,
      );
      final Passport b = a.copyWith(favoriteCities: <String>['Київ']);

      // A freezed field omitted from the constructor's generated `==` would
      // make these two compare equal — the failure mode this pins.
      expect(a, isNot(equals(b)));
    });
  });

  group('BudgetBand', () {
    test('defaults currency to UAH and preserves the avg/min/max envelope', () {
      const BudgetBand band = BudgetBand(avg: 650, min: 400, max: 900);

      expect(band.currency, 'UAH');
      expect(band.avg, 650);
      expect(band.min, 400);
      expect(band.max, 900);
    });

    test('honours an explicit currency override', () {
      const BudgetBand band = BudgetBand(
        avg: 50,
        min: 30,
        max: 80,
        currency: 'EUR',
      );

      expect(band.currency, 'EUR');
    });
  });
}
