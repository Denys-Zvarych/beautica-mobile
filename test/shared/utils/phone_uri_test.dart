// Unit tests for [canonicalTelUri] — the STRICT, security-critical phone
// allow-list.
//
// This helper is the single sanitization gate between a verbatim stored contact
// value and `launchUrl`. Anything that is not provably a safe dialable number
// MUST resolve to `null`. These tests pin the full accept/reject matrix so a
// future refactor cannot silently widen the allow-list (e.g. admit a foreign
// scheme like `javascript:` / `tel:`, a DTMF-injection separator, or a
// non-numeric payload) and launder a hostile string to the platform launcher.
//
// Pure Dart — no widget tree, no Flutter binding required.

import 'package:beautica_mobile/shared/utils/phone_uri.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('canonicalTelUri — ACCEPT (normalize separators)', () {
    test('E.164 with spaces "+380 67 123 45 67" → tel:+380671234567', () {
      final uri = canonicalTelUri('+380 67 123 45 67');
      expect(uri, isNotNull);
      expect(uri!.scheme, 'tel');
      expect(uri.path, '+380671234567');
      expect(uri.toString(), 'tel:+380671234567');
    });

    test('plain local digits "0671234567" → tel:0671234567', () {
      final uri = canonicalTelUri('0671234567');
      expect(uri, isNotNull);
      expect(uri!.scheme, 'tel');
      expect(uri.path, '0671234567');
    });

    test('parens + hyphens "(067) 123-45-67" → tel:0671234567', () {
      final uri = canonicalTelUri('(067) 123-45-67');
      expect(uri, isNotNull);
      expect(uri!.scheme, 'tel');
      expect(uri.path, '0671234567');
    });
  });

  group('canonicalTelUri — ACCEPT/REJECT (digit-count boundaries 7..15)', () {
    test('exactly 7 digits (lower boundary) is accepted', () {
      final uri = canonicalTelUri('1234567');
      expect(uri, isNotNull);
      expect(uri!.path, '1234567');
    });

    test('exactly 15 digits (upper boundary) is accepted', () {
      final fifteen = '123456789012345';
      final uri = canonicalTelUri(fifteen);
      expect(uri, isNotNull);
      expect(uri!.path, fifteen);
    });

    test('6 digits (below lower boundary) → null', () {
      expect(canonicalTelUri('123456'), isNull);
    });

    test('16 digits (above upper boundary) → null', () {
      expect(canonicalTelUri('1234567890123456'), isNull);
    });
  });

  group('canonicalTelUri — ACCEPT/REJECT (leading "+" placement)', () {
    test('leading "+" then 7 digits "+1234567" is accepted', () {
      final uri = canonicalTelUri('+1234567');
      expect(uri, isNotNull);
      expect(uri!.path, '+1234567');
    });

    test('"+" not at the start "12+34567" → null', () {
      // The pattern only allows a single optional "+" at position 0; an interior
      // "+" is not a separator and is not a digit, so the whole value fails.
      expect(canonicalTelUri('12+34567'), isNull);
    });
  });

  group('canonicalTelUri — REJECT (empty / sentinel / null)', () {
    test('null → null', () {
      expect(canonicalTelUri(null), isNull);
    });

    test('empty string → null', () {
      expect(canonicalTelUri(''), isNull);
    });

    test('whitespace-only "   " → null', () {
      expect(canonicalTelUri('   '), isNull);
    });

    test('dash sentinel "—" → null', () {
      expect(canonicalTelUri('—'), isNull);
    });
  });

  group('canonicalTelUri — REJECT (foreign scheme / non-numeric payload)', () {
    test('"javascript:1234567" → null (colon + alpha not in charset)', () {
      expect(canonicalTelUri('javascript:1234567'), isNull);
    });

    test('"tel:1234567" → null (the "tel:" prefix is not re-admitted)', () {
      // The helper composes the tel: scheme itself; a value that already carries
      // "tel:" contains a colon + alpha and must be rejected, never re-wrapped.
      expect(canonicalTelUri('tel:1234567'), isNull);
    });

    test('DTMF/voicemail suffix "1234567;voicemail" → null', () {
      // ";" and the alpha tail are outside the dialable charset — rejected so a
      // post-dial control string can never reach the dialer.
      expect(canonicalTelUri('1234567;voicemail'), isNull);
    });

    test('pause-comma injection "0671234567,,,9999" → null', () {
      // "," is not a recognised separator; the value fails the strict shape.
      expect(canonicalTelUri('0671234567,,,9999'), isNull);
    });

    test('alpha-bearing "067ABC4567" → null', () {
      expect(canonicalTelUri('067ABC4567'), isNull);
    });
  });

  group('canonicalTelUri — SECURITY regression (control-char stripping)', () {
    // SECURITY: the separator class is `[\s\-().]`. `\s` matches the embedded
    // newline in "12345\n67", so it is STRIPPED before validation and the
    // remaining "1234567" PASSES as tel:1234567. This is the CURRENT, intended-
    // by-regex behavior. It is a known LOW (control-char stripping rather than
    // rejection) tracked in docs/mobile-phases/mobile-backlog.md. This test
    // PINS today's behavior so any change to the separator/validation logic is
    // caught and re-reviewed. Do NOT "fix" production here — change the backlog
    // item first.
    test(
      'embedded newline "12345\\n67" is stripped → tel:1234567 (known LOW)',
      () {
        final uri = canonicalTelUri('12345\n67');
        expect(uri, isNotNull);
        expect(uri!.scheme, 'tel');
        expect(uri.path, '1234567');
      },
    );
  });
}
