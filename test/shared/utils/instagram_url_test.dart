// Unit tests for [canonicalInstagramUri] — the STRICT, security-critical
// Instagram allow-list.
//
// This helper is the single sanitization gate between verbatim user input and
// `launchUrl`. Anything that is not provably a safe Instagram destination MUST
// resolve to `null`. These tests pin the full accept/reject matrix so a future
// refactor cannot silently widen the allow-list (e.g. accept `http://`, an
// arbitrary host, or a homoglyph host) and launder a hostile string to the
// platform launcher.
//
// Pure Dart — no widget tree, no Flutter binding required.

import 'package:beautica_mobile/shared/utils/instagram_url.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('canonicalInstagramUri — ACCEPT (bare / @ handles)', () {
    test('bare handle composes canonical https://instagram.com/<handle>', () {
      final uri = canonicalInstagramUri('olena_nails');
      expect(uri, isNotNull);
      expect(uri.toString(), 'https://instagram.com/olena_nails');
      expect(uri!.scheme, 'https');
      expect(uri.host, 'instagram.com');
    });

    test('leading "@" is stripped (single @)', () {
      final uri = canonicalInstagramUri('@olena_nails');
      expect(uri.toString(), 'https://instagram.com/olena_nails');
    });

    test('handle with periods is accepted', () {
      final uri = canonicalInstagramUri('olena.nails.kyiv');
      expect(uri.toString(), 'https://instagram.com/olena.nails.kyiv');
    });

    test('handle with underscores is accepted', () {
      final uri = canonicalInstagramUri('__olena__');
      expect(uri.toString(), 'https://instagram.com/__olena__');
    });

    test('handle with digits is accepted', () {
      final uri = canonicalInstagramUri('olena2024');
      expect(uri.toString(), 'https://instagram.com/olena2024');
    });

    test('30-char handle (upper boundary) is accepted', () {
      final handle = 'a' * 30;
      final uri = canonicalInstagramUri(handle);
      expect(uri.toString(), 'https://instagram.com/$handle');
    });

    test('surrounding whitespace is trimmed before composing', () {
      final uri = canonicalInstagramUri('   olena_nails   ');
      expect(uri.toString(), 'https://instagram.com/olena_nails');
    });
  });

  group('canonicalInstagramUri — ACCEPT (full URLs, echoed as-is)', () {
    test('https://instagram.com/x is returned unchanged', () {
      final uri = canonicalInstagramUri('https://instagram.com/olena_nails');
      expect(uri.toString(), 'https://instagram.com/olena_nails');
      expect(uri!.host, 'instagram.com');
    });

    test('https://www.instagram.com/x is returned unchanged', () {
      final uri = canonicalInstagramUri(
        'https://www.instagram.com/olena_nails',
      );
      expect(uri.toString(), 'https://www.instagram.com/olena_nails');
      expect(uri!.host, 'www.instagram.com');
    });

    test(
      'uppercase host https://INSTAGRAM.COM/x is accepted — Uri lowercases '
      'the host, so it matches the allow-list (documented behavior)',
      () {
        final uri = canonicalInstagramUri('https://INSTAGRAM.COM/olena');
        // Uri parsing normalizes the host to lower-case, so the exact-match
        // allow-list ('instagram.com') still admits it. The returned Uri also
        // carries the lower-cased host. This is intentional and safe — it is
        // still the canonical Instagram host, not a look-alike.
        expect(uri, isNotNull);
        expect(uri!.host, 'instagram.com');
        expect(uri.scheme, 'https');
      },
    );
  });

  group('canonicalInstagramUri — REJECT (empty / sentinel / null)', () {
    test('null → null', () {
      expect(canonicalInstagramUri(null), isNull);
    });

    test('empty string → null', () {
      expect(canonicalInstagramUri(''), isNull);
    });

    test('whitespace-only → null', () {
      expect(canonicalInstagramUri('   '), isNull);
    });

    test('dash sentinel "—" → null', () {
      expect(canonicalInstagramUri('—'), isNull);
    });
  });

  group('canonicalInstagramUri — REJECT (non-https schemes)', () {
    test('http://instagram.com/x → null (only https allowed)', () {
      expect(canonicalInstagramUri('http://instagram.com/x'), isNull);
    });

    test('javascript:// → null', () {
      expect(canonicalInstagramUri('javascript://instagram.com'), isNull);
    });

    test('tel: → null', () {
      // No "://" — falls into the handle branch and fails the charset check
      // because of the colon, so it is rejected either way.
      expect(canonicalInstagramUri('tel:123'), isNull);
    });

    test('data: URI → null', () {
      expect(
        canonicalInstagramUri('data:text/html,<script>alert(1)</script>'),
        isNull,
      );
    });
  });

  group('canonicalInstagramUri — REJECT (host allow-list bypass attempts)', () {
    test('other host https://evil.com → null', () {
      expect(canonicalInstagramUri('https://evil.com'), isNull);
    });

    test('subdomain-suffix host https://instagram.com.evil.com → null', () {
      // The real host is evil.com; instagram.com is only a label prefix.
      expect(canonicalInstagramUri('https://instagram.com.evil.com'), isNull);
    });

    test('prefix-glued host https://evilinstagram.com → null', () {
      expect(canonicalInstagramUri('https://evilinstagram.com'), isNull);
    });

    test('scheme-relative //evil.com → null', () {
      // No "://" so this enters the handle branch; the slashes are not in the
      // Instagram charset → rejected (never composed into a host).
      expect(canonicalInstagramUri('//evil.com'), isNull);
    });
  });

  group('canonicalInstagramUri — REJECT (handle charset / length)', () {
    test('handle longer than 30 chars → null', () {
      final tooLong = 'a' * 31;
      expect(canonicalInstagramUri(tooLong), isNull);
    });

    test('handle containing a space → null', () {
      expect(canonicalInstagramUri('olena nails'), isNull);
    });

    test('handle containing a slash → null', () {
      expect(canonicalInstagramUri('olena/nails'), isNull);
    });

    test('handle containing a unicode homoglyph → null', () {
      // Fullwidth Latin small letter i (U+FF49) — looks like "i" but is not in
      // [A-Za-z0-9._]. Must be rejected, never composed into a URL.
      expect(canonicalInstagramUri('ｉnstagram'), isNull);
    });

    test('empty handle after stripping a lone "@" → null', () {
      expect(canonicalInstagramUri('@'), isNull);
    });
  });
}
