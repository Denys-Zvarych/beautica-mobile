// Phase 13.8 — BEAUTY PASSPORT domain unit tests.
//
// Pure-Dart coverage of the [Passport] value object and its [BudgetBand]:
//   • Passport.empty() is the canonical empty state (bookingsConsidered == 0,
//     no derived data) and reports isEmpty == true.
//   • A populated passport (bookingsConsidered > 0) reports isEmpty == false.
//   • isEmpty keys ONLY off bookingsConsidered, not off whether the derived
//     lists happen to be empty — a passport with history but (transiently) no
//     procedures is still NOT empty.
//   • copyWith / value equality behave as freezed guarantees.
//   • BudgetBand defaults currency to UAH and preserves the avg/min/max
//     envelope.

import 'package:beautica_mobile/features/passport/domain/passport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Passport.empty()', () {
    test('has no derived data, zero history, and reports isEmpty', () {
      final Passport p = Passport.empty();

      expect(p.bookingsConsidered, 0);
      expect(p.favoriteProcedures, isEmpty);
      expect(p.favoriteDistricts, isEmpty);
      expect(p.budget, isNull);
      expect(p.reviewsLeft, 0);
      expect(p.memberSinceYear, isNull);
      expect(p.isEmpty, isTrue);
    });

    test('two empties are value-equal', () {
      expect(Passport.empty(), equals(Passport.empty()));
    });
  });

  group('Passport.isEmpty', () {
    test('is false once any completed booking was considered', () {
      const Passport p = Passport(
        favoriteProcedures: <String>['Манікюр'],
        favoriteDistricts: <String>['Центр'],
        budget: BudgetBand(avg: 600, min: 400, max: 800),
        bookingsConsidered: 3,
      );

      expect(p.isEmpty, isFalse);
    });

    test('keys off bookingsConsidered, not off empty derived lists '
        '(history present but lists transiently empty ⇒ NOT empty)', () {
      const Passport p = Passport(
        favoriteProcedures: <String>[],
        favoriteDistricts: <String>[],
        budget: null,
        bookingsConsidered: 2,
      );

      expect(p.isEmpty, isFalse);
    });

    test('is true exactly when bookingsConsidered == 0', () {
      const Passport p = Passport(
        favoriteProcedures: <String>['Брови'],
        favoriteDistricts: <String>['Сихів'],
        budget: BudgetBand(avg: 500, min: 500, max: 500),
        bookingsConsidered: 0,
      );

      // Even with derived data present, zero considered history ⇒ empty.
      expect(p.isEmpty, isTrue);
    });
  });

  group('Passport copyWith / equality', () {
    test('copyWith overrides only the named fields', () {
      final Passport base = Passport.empty();

      final Passport next = base.copyWith(
        bookingsConsidered: 5,
        favoriteProcedures: <String>['Педикюр'],
        reviewsLeft: 2,
        memberSinceYear: 2024,
      );

      expect(next.bookingsConsidered, 5);
      expect(next.favoriteProcedures, <String>['Педикюр']);
      expect(next.reviewsLeft, 2);
      expect(next.memberSinceYear, 2024);
      // Untouched fields preserved.
      expect(next.favoriteDistricts, isEmpty);
      expect(next.budget, isNull);
      expect(next.isEmpty, isFalse);
    });

    test('value equality / hashCode hold for identical field sets', () {
      const Passport a = Passport(
        favoriteProcedures: <String>['Манікюр', 'Брови'],
        favoriteDistricts: <String>['Центр'],
        budget: BudgetBand(avg: 600, min: 400, max: 900),
        bookingsConsidered: 4,
        reviewsLeft: 3,
        memberSinceYear: 2023,
      );
      const Passport b = Passport(
        favoriteProcedures: <String>['Манікюр', 'Брови'],
        favoriteDistricts: <String>['Центр'],
        budget: BudgetBand(avg: 600, min: 400, max: 900),
        bookingsConsidered: 4,
        reviewsLeft: 3,
        memberSinceYear: 2023,
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
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
