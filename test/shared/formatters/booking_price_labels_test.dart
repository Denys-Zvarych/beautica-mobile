// Unit tests for the shared `formatBookingTotals` "Разом" label builder
// (`lib/shared/formatters/booking_price_labels.dart`).
//
// Extracted verbatim from the two confirm bars' private totals-string builders
// (`_BookingTotals.from` in `booking_summary_bar.dart`, `ScheduleConfirmBar.
// _totals` in `schedule_confirm_bar.dart`) as part of the widget-consolidation
// refactor. Both bars now delegate their price-band + duration formatting here,
// so this pure-Dart test pins the exact contract both call sites depend on:
//   • degenerate band (min == max)  → "<sum> грн"
//   • real band (min != max)        → "<min>–<max> грн"
//   • duration is null iff minutes == 0, else DurationMinutes.format(minutes).

import 'package:beautica_mobile/shared/formatters/booking_price_labels.dart';
import 'package:beautica_mobile/shared/formatters/duration_minutes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatBookingTotals — price band', () {
    test('degenerate band (min == max) collapses to a single "<sum> грн"', () {
      final result = formatBookingTotals(minSum: 500, maxSum: 500, minutes: 60);

      expect(result.priceLabel, '500 грн');
    });

    test(
      'a real band (min != max) renders "<min>–<max> грн" with an en-dash',
      () {
        final result = formatBookingTotals(
          minSum: 200,
          maxSum: 600,
          minutes: 90,
        );

        expect(result.priceLabel, '200–600 грн');
      },
    );

    test(
      'summed doubles are printed with no fractional part (toStringAsFixed(0))',
      () {
        // The callers sum doubles (priceMin/priceMax are doubles); the label must
        // never leak a ".0" tail.
        final result = formatBookingTotals(
          minSum: 1250.0,
          maxSum: 1250.0,
          minutes: 45,
        );

        expect(result.priceLabel, '1250 грн');
        expect(result.priceLabel.contains('.'), isFalse);
      },
    );

    test('a zero total still renders a valid degenerate band', () {
      final result = formatBookingTotals(minSum: 0, maxSum: 0, minutes: 0);

      expect(result.priceLabel, '0 грн');
    });
  });

  group('formatBookingTotals — duration', () {
    test('minutes == 0 yields a null durationLabel (nothing to show)', () {
      final result = formatBookingTotals(minSum: 500, maxSum: 500, minutes: 0);

      expect(result.durationLabel, isNull);
    });

    test('a positive duration delegates to DurationMinutes.format', () {
      final result = formatBookingTotals(minSum: 500, maxSum: 500, minutes: 90);

      expect(result.durationLabel, DurationMinutes.format(90));
      expect(result.durationLabel, '1 год 30 хв');
    });

    test('a sub-hour duration is formatted in minutes', () {
      final result = formatBookingTotals(minSum: 300, maxSum: 300, minutes: 45);

      expect(result.durationLabel, '45 хв');
    });

    test('price band and duration are independent — a real band with zero '
        'minutes still nulls only the duration', () {
      final result = formatBookingTotals(minSum: 200, maxSum: 600, minutes: 0);

      expect(result.priceLabel, '200–600 грн');
      expect(result.durationLabel, isNull);
    });
  });
}
