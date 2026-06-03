// Pure-Dart unit tests for numeric_validators.dart.
// Hardened 2026-06-03 — bounds now mirror the backend
// CreateServiceDefinitionRequest contract (duration ≤ 480, buffer 0–120,
// price 0.01–99 999 999.99 with ≤ 2 decimals, RANGE max > min).
//
// No widget pump needed. A minimal _FakeL10n supplies hardcoded strings so
// validators can be exercised without spinning up a Flutter widget tree.

import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/validators/numeric_validators.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Fake l10n — hardcoded strings avoid a widget tree in pure unit tests.
// ---------------------------------------------------------------------------

final class _FakeL10n extends Fake implements AppLocalizations {
  @override
  String get errRequired => 'required';

  @override
  String get errDurationPositive => 'duration positive';

  @override
  String get errDurationMax => 'duration max';

  @override
  String get errBufferRange => 'buffer range';

  @override
  String get errPricePositive => 'price positive';

  @override
  String get errPriceMax => 'price max';

  @override
  String get errPriceDecimals => 'price decimals';

  @override
  String get errPriceMaxGtMin => 'max gt min';

  @override
  String get errPriceMinRequired => 'min required';

  @override
  String get errPriceMaxRequired => 'max required';
}

void main() {
  final l10n = _FakeL10n();

  group('validateDurationMinutes', () {
    test('errRequired for null / blank / whitespace', () {
      expect(validateDurationMinutes(null, l10n), 'required');
      expect(validateDurationMinutes('', l10n), 'required');
      expect(validateDurationMinutes('   ', l10n), 'required');
    });

    test('errDurationPositive for zero, negative, and non-numeric', () {
      expect(validateDurationMinutes('0', l10n), 'duration positive');
      expect(validateDurationMinutes('-1', l10n), 'duration positive');
      expect(validateDurationMinutes('abc', l10n), 'duration positive');
      // Non-integer (decimal) is rejected as non-integer.
      expect(validateDurationMinutes('12.5', l10n), 'duration positive');
      // Internal whitespace makes the value non-parseable as an int → rejected
      // (defends the "must be a clean integer" contract — the 1123 bug class).
      expect(validateDurationMinutes('4 80', l10n), 'duration positive');
    });

    test('null for the valid range boundaries (1 and 480)', () {
      expect(validateDurationMinutes('1', l10n), isNull);
      expect(validateDurationMinutes('480', l10n), isNull);
      expect(validateDurationMinutes(' 60 ', l10n), isNull); // trims
    });

    test('errDurationMax above the 480 cap — the originating bug (1123)', () {
      expect(validateDurationMinutes('481', l10n), 'duration max');
      expect(validateDurationMinutes('1123', l10n), 'duration max');
      expect(validateDurationMinutes('1440', l10n), 'duration max');
    });
  });

  group('validateBufferMinutes (optional 0–120)', () {
    test('null for empty / whitespace (optional field)', () {
      expect(validateBufferMinutes(null, l10n), isNull);
      expect(validateBufferMinutes('', l10n), isNull);
      expect(validateBufferMinutes('   ', l10n), isNull);
    });

    test('null for in-range values', () {
      expect(validateBufferMinutes('0', l10n), isNull);
      expect(validateBufferMinutes('120', l10n), isNull);
    });

    test('errBufferRange for out-of-range, negative, or non-integer', () {
      expect(validateBufferMinutes('-1', l10n), 'buffer range');
      expect(validateBufferMinutes('121', l10n), 'buffer range');
      expect(validateBufferMinutes('abc', l10n), 'buffer range');
      expect(validateBufferMinutes('10.5', l10n), 'buffer range');
    });
  });

  group('parsePrice', () {
    test('parses integer and decimal forms', () {
      expect(parsePrice('500'), 500.0);
      expect(parsePrice('500.5'), 500.5);
      expect(parsePrice('500.55'), 500.55);
    });

    test('normalises comma separator and strips spaces / glyph', () {
      expect(parsePrice('500,55'), 500.55);
      expect(parsePrice(' 1 200 '), 1200.0);
      expect(parsePrice('300₴'), 300.0);
    });

    test('null for >2 decimals, empty, or non-numeric', () {
      expect(parsePrice('500.555'), isNull);
      expect(parsePrice(''), isNull);
      expect(parsePrice('abc'), isNull);
      expect(parsePrice('-5'), isNull);
    });
  });

  group('validatePriceAmount', () {
    test('returns requiredMessage for blank', () {
      expect(
        validatePriceAmount(
          '',
          l10n,
          requiredMessage: l10n.errPriceMinRequired,
        ),
        'min required',
      );
      expect(
        validatePriceAmount('  ', l10n, requiredMessage: l10n.errRequired),
        'required',
      );
    });

    test('errPriceDecimals for >2 decimals or non-numeric', () {
      expect(
        validatePriceAmount('10.999', l10n, requiredMessage: l10n.errRequired),
        'price decimals',
      );
      expect(
        validatePriceAmount('abc', l10n, requiredMessage: l10n.errRequired),
        'price decimals',
      );
    });

    test('errPricePositive below the 0.01 floor', () {
      expect(
        validatePriceAmount('0', l10n, requiredMessage: l10n.errRequired),
        'price positive',
      );
      expect(
        validatePriceAmount('0.00', l10n, requiredMessage: l10n.errRequired),
        'price positive',
      );
    });

    test('errPriceMax above 99 999 999.99', () {
      expect(
        validatePriceAmount(
          '100000000',
          l10n,
          requiredMessage: l10n.errRequired,
        ),
        'price max',
      );
    });

    test('null for valid amounts (boundaries included)', () {
      expect(
        validatePriceAmount('0.01', l10n, requiredMessage: l10n.errRequired),
        isNull,
      );
      expect(
        validatePriceAmount('500.55', l10n, requiredMessage: l10n.errRequired),
        isNull,
      );
      expect(
        validatePriceAmount(
          '99999999.99',
          l10n,
          requiredMessage: l10n.errRequired,
        ),
        isNull,
      );
    });
  });

  group('validatePriceMax (cross-field)', () {
    test('required / format / bounds surface first (delegates to amount)', () {
      expect(
        validatePriceMax(
          '',
          '100',
          l10n,
          requiredMessage: l10n.errPriceMaxRequired,
        ),
        'max required',
      );
      expect(
        validatePriceMax(
          '10.999',
          '5',
          l10n,
          requiredMessage: l10n.errPriceMaxRequired,
        ),
        'price decimals',
      );
    });

    test('errPriceMaxGtMin when max <= min', () {
      expect(
        validatePriceMax(
          '500',
          '800',
          l10n,
          requiredMessage: l10n.errPriceMaxRequired,
        ),
        'max gt min',
      );
      expect(
        validatePriceMax(
          '500',
          '500',
          l10n,
          requiredMessage: l10n.errPriceMaxRequired,
        ),
        'max gt min',
      );
    });

    test('null when max strictly greater than min', () {
      expect(
        validatePriceMax(
          '800',
          '500',
          l10n,
          requiredMessage: l10n.errPriceMaxRequired,
        ),
        isNull,
      );
      expect(
        validatePriceMax(
          '500.50',
          '500.25',
          l10n,
          requiredMessage: l10n.errPriceMaxRequired,
        ),
        isNull,
      );
    });
  });
}
