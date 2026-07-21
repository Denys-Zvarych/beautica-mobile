// Unit tests for the shared `formatBookingTotals` "Разом" label builder
// (`lib/shared/formatters/booking_price_labels.dart`).
//
// Extracted verbatim from the two confirm bars' private totals-string builders
// (`_BookingTotals.from` in `booking_summary_bar.dart`, `ScheduleConfirmBar.
// _totals` in `schedule_confirm_bar.dart`) as part of the widget-consolidation
// refactor. Both bars now delegate their price-band + duration formatting here,
// so this pure-Dart test pins the exact contract both call sites depend on:
//   • degenerate band (min == max)  → "<sum> ₴"
//   • real band (min != max)        → "<min>–<max> ₴"
//   • duration is null iff minutes == 0, else DurationMinutes.format(minutes).
//
// The currency suffix is asserted via `bookingPriceCurrencySuffix` (exported
// by the formatter under test) rather than a hardcoded literal — this file is
// pure Dart with no BuildContext/l10n access, so referencing the formatter's
// own public constant is the single source of truth for the symbol.

import 'dart:convert';

import 'package:beautica_mobile/shared/formatters/booking_price_labels.dart';
import 'package:beautica_mobile/shared/formatters/duration_minutes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatBookingTotals — price band', () {
    test('degenerate band (min == max) collapses to a single "<sum> ₴"', () {
      final result = formatBookingTotals(minSum: 500, maxSum: 500, minutes: 60);

      expect(result.priceLabel, '500 $bookingPriceCurrencySuffix');
    });

    test(
      'a real band (min != max) renders "<min>–<max> ₴" with an en-dash',
      () {
        final result = formatBookingTotals(
          minSum: 200,
          maxSum: 600,
          minutes: 90,
        );

        expect(result.priceLabel, '200–600 $bookingPriceCurrencySuffix');
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

        expect(result.priceLabel, '1250 $bookingPriceCurrencySuffix');
        expect(result.priceLabel.contains('.'), isFalse);
      },
    );

    test('a zero total still renders a valid degenerate band', () {
      final result = formatBookingTotals(minSum: 0, maxSum: 0, minutes: 0);

      expect(result.priceLabel, '0 $bookingPriceCurrencySuffix');
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

      expect(result.priceLabel, '200–600 $bookingPriceCurrencySuffix');
      expect(result.durationLabel, isNull);
    });
  });

  // ── formatBookingPrice — ONE already-booked record's frozen price ────────
  //
  // The contract is locked SERVER-side (`priceAtBooking` + `priceMaxAtBooking`
  // on `BookingDetailResponse`/`BookingResponse`): a null ceiling means SINGLE
  // PRICE, not a missing value. These tests pin that null is rendered as the
  // floor alone and never re-derived into a band from anything else.
  group('formatBookingPrice — a booking\'s frozen price', () {
    test('a null ceiling is a SINGLE price, not a missing value', () {
      expect(formatBookingPrice(price: 300), '300 $bookingPriceCurrencySuffix');
    });

    test('a real ceiling renders the band with the SAME en-dash '
        'formatBookingTotals uses', () {
      expect(
        formatBookingPrice(price: 300, priceMax: 500),
        '300–500 $bookingPriceCurrencySuffix',
      );
      // Explicitly NOT the hyphen-space `ServicePriceDisplay.format` uses for
      // an unbooked SERVICE's range — the two must not be unified.
      expect(
        formatBookingPrice(price: 300, priceMax: 500).contains(' - '),
        isFalse,
      );
    });

    test('a degenerate band (floor == ceiling) collapses to the single '
        'figure', () {
      expect(
        formatBookingPrice(price: 300, priceMax: 300),
        '300 $bookingPriceCurrencySuffix',
      );
    });

    test('an inverted band (ceiling < floor) collapses to the floor rather '
        'than printing «500–300 ₴»', () {
      expect(
        formatBookingPrice(price: 500, priceMax: 300),
        '500 $bookingPriceCurrencySuffix',
      );
    });

    test('neither figure leaks a fractional tail', () {
      expect(
        formatBookingPrice(price: 1250.0, priceMax: 1800.0),
        '1250–1800 $bookingPriceCurrencySuffix',
      );
      expect(
        formatBookingPrice(price: 1250.0, priceMax: 1800.0).contains('.'),
        isFalse,
      );
    });
  });

  // ── formatBookingPrice — unrenderable wire values ────────────────────────
  //
  // Both figures arrive as JSON numbers and `jsonDecode` is permissive:
  // `jsonDecode('1e400')` returns `double.infinity` WITHOUT throwing (pinned
  // below so the premise can't silently stop being true). Anything that
  // cannot be stated as plain, non-negative digits must be treated as ABSENT
  // rather than stringified — this label is written into a device calendar
  // event via `add_2_calendar`, so it leaves the app.
  group('formatBookingPrice — non-finite / negative / exponent inputs', () {
    test('PREMISE — jsonDecode admits Infinity without throwing', () {
      expect(jsonDecode('1e400'), double.infinity);
      expect((jsonDecode('1e400') as double).isFinite, isFalse);
    });

    test(
      'an infinite CEILING collapses to the floor — never «300–Infinity ₴»',
      () {
        expect(
          formatBookingPrice(price: 300, priceMax: double.infinity),
          '300 $bookingPriceCurrencySuffix',
        );
      },
    );

    test('a NaN ceiling collapses to the floor', () {
      expect(
        formatBookingPrice(price: 300, priceMax: double.nan),
        '300 $bookingPriceCurrencySuffix',
      );
    });

    test('an exponent-notation ceiling (>=1e21) collapses to the floor — '
        'never «300–1e+21 ₴»', () {
      // Pins the threshold's premise as well as the guard: `toStringAsFixed`
      // is fine at 1e20 and abandons plain digits at 1e21.
      expect((1e20).toStringAsFixed(0), '100000000000000000000');
      expect((1e21).toStringAsFixed(0), '1e+21');
      expect(
        formatBookingPrice(price: 300, priceMax: 1e21),
        '300 $bookingPriceCurrencySuffix',
      );
    });

    test('a negative ceiling collapses to the floor — the minus would collide '
        'with the band en-dash', () {
      expect(
        formatBookingPrice(price: 300, priceMax: -500),
        '300 $bookingPriceCurrencySuffix',
      );
    });

    test('an unrenderable FLOOR yields the neutral label with NO currency '
        'suffix — nothing to fall back to, and «₴» would assert an amount', () {
      for (final double bad in <double>[
        double.infinity,
        double.negativeInfinity,
        double.nan,
        -500,
        1e21,
      ]) {
        final String label = formatBookingPrice(price: bad, priceMax: 900);
        expect(label, priceUnavailableLabel, reason: 'floor $bad');
        expect(
          label.contains(bookingPriceCurrencySuffix),
          isFalse,
          reason: 'floor $bad must not assert a hryvnia amount',
        );
      }
    });

    test('no output ever contains Infinity, NaN or exponent notation', () {
      for (final ({double p, double? m}) c in <({double p, double? m})>[
        (p: double.infinity, m: null),
        (p: 300, m: double.infinity),
        (p: double.nan, m: double.nan),
        (p: 1e21, m: 2e21),
        (p: -500, m: -300),
      ]) {
        final String label = formatBookingPrice(price: c.p, priceMax: c.m);
        expect(label, isNot(contains('Infinity')));
        expect(label, isNot(contains('NaN')));
        expect(label, isNot(contains('e+')));
      }
    });

    test('the guard leaves every well-formed value untouched', () {
      expect(formatBookingPrice(price: 0), '0 $bookingPriceCurrencySuffix');
      expect(
        formatBookingPrice(price: 300, priceMax: 500),
        '300–500 $bookingPriceCurrencySuffix',
      );
      expect(
        formatBookingPrice(price: 1e20),
        '100000000000000000000 $bookingPriceCurrencySuffix',
      );
    });

    // NEGATIVE ZERO — the hole the first version of this guard left open.
    // `-0.0 >= 0` is `true` in IEEE-754, so the original `value >= 0` waved it
    // through, and `(-0.0).toStringAsFixed(0)` is `'-0'` — the exact minus/
    // en-dash collision the guard exists to prevent («-0–500 ₴»). Reachable
    // from the wire: `jsonDecode('-0.0')` yields `-0.0` and
    // `booking_mapper.dart` passes `priceAtBooking` through unclamped, so on a
    // CONFIRMED booking (`showsPrice == true`) it egresses to the device
    // calendar. The fix tests `!value.isNegative` instead.
    test('PREMISE — -0.0 is admitted by jsonDecode, passes an arithmetic '
        '>= 0 check, and stringifies with a leading minus', () {
      expect(jsonDecode('-0.0'), -0.0);
      expect((jsonDecode('-0.0') as double).isNegative, isTrue);
      // The exact comparison the old guard used — this is why it was not
      // enough.
      expect(-0.0 >= 0, isTrue);
      expect((-0.0).toStringAsFixed(0), '-0');
    });

    test('a -0.0 FLOOR yields the neutral label, never «-0 ₴»', () {
      final String label = formatBookingPrice(price: -0.0);
      expect(label, priceUnavailableLabel);
      expect(label, isNot(contains('-0')));
    });

    test('a -0.0 FLOOR with a ceiling never renders «-0–500 ₴»', () {
      expect(
        formatBookingPrice(price: -0.0, priceMax: 500),
        priceUnavailableLabel,
      );
    });

    test('a -0.0 CEILING collapses to the floor', () {
      expect(
        formatBookingPrice(price: 300, priceMax: -0.0),
        '300 $bookingPriceCurrencySuffix',
      );
    });

    test('POSITIVE zero is still perfectly renderable — the fix must not '
        'sweep up the legitimate 0', () {
      expect(formatBookingPrice(price: 0.0), '0 $bookingPriceCurrencySuffix');
      expect(
        formatBookingPrice(price: 0.0, priceMax: 500),
        '0–500 $bookingPriceCurrencySuffix',
      );
    });
  });

  // ── formatBookingTotals — the SAME guard, the other formatter ────────────
  //
  // This file's header declares the two formatters share "one set of
  // conventions"; shipping one hardened and one not is the drift it exists to
  // prevent. Summation is NOT protective: `+` propagates Infinity and a single
  // negative term drags the whole minSum negative.
  group('formatBookingTotals — non-finite / negative / exponent sums', () {
    test(
      'PREMISE — summation preserves Infinity and propagates a negative',
      () {
        expect(300.0 + double.infinity, double.infinity);
        expect((300.0 + -500.0).isNegative, isTrue);
      },
    );

    test('an unrenderable maxSum collapses to the minSum alone', () {
      for (final double bad in <double>[
        double.infinity,
        double.nan,
        1e21,
        -0.0,
      ]) {
        expect(
          formatBookingTotals(minSum: 300, maxSum: bad, minutes: 0).priceLabel,
          '300 $bookingPriceCurrencySuffix',
          reason: 'maxSum $bad',
        );
      }
    });

    test('an unrenderable minSum yields the neutral label with NO currency '
        'suffix', () {
      for (final double bad in <double>[
        double.infinity,
        double.negativeInfinity,
        double.nan,
        -500,
        -0.0,
        1e21,
      ]) {
        final String label = formatBookingTotals(
          minSum: bad,
          maxSum: 900,
          minutes: 60,
        ).priceLabel;
        expect(label, priceUnavailableLabel, reason: 'minSum $bad');
        expect(
          label.contains(bookingPriceCurrencySuffix),
          isFalse,
          reason: 'minSum $bad must not assert a hryvnia amount',
        );
      }
    });

    test('no output ever contains Infinity, NaN, exponent notation or a '
        'leading minus', () {
      for (final ({double lo, double hi}) c in <({double lo, double hi})>[
        (lo: double.infinity, hi: double.infinity),
        (lo: 300, hi: double.infinity),
        (lo: double.nan, hi: double.nan),
        (lo: 1e21, hi: 2e21),
        (lo: -500, hi: -300),
        (lo: -0.0, hi: 500),
      ]) {
        final String label = formatBookingTotals(
          minSum: c.lo,
          maxSum: c.hi,
          minutes: 30,
        ).priceLabel;
        expect(label, isNot(contains('Infinity')), reason: '${c.lo}/${c.hi}');
        expect(label, isNot(contains('NaN')), reason: '${c.lo}/${c.hi}');
        expect(label, isNot(contains('e+')), reason: '${c.lo}/${c.hi}');
        expect(label, isNot(contains('-')), reason: '${c.lo}/${c.hi}');
      }
    });

    test('the DURATION half is untouched by the price guard — an unrenderable '
        'sum must not also swallow the minutes label', () {
      final ({String priceLabel, String? durationLabel}) totals =
          formatBookingTotals(
            minSum: double.infinity,
            maxSum: double.infinity,
            minutes: 90,
          );
      expect(totals.priceLabel, priceUnavailableLabel);
      expect(totals.durationLabel, isNotNull);
    });

    test('the guard leaves every well-formed total untouched', () {
      expect(
        formatBookingTotals(minSum: 700, maxSum: 700, minutes: 0).priceLabel,
        '700 $bookingPriceCurrencySuffix',
      );
      expect(
        formatBookingTotals(minSum: 300, maxSum: 900, minutes: 0).priceLabel,
        '300–900 $bookingPriceCurrencySuffix',
      );
      expect(
        formatBookingTotals(minSum: 0, maxSum: 0, minutes: 0).priceLabel,
        '0 $bookingPriceCurrencySuffix',
      );
    });
  });
}
