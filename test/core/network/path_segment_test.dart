// Unit tests for [encodePathSegment] (`lib/core/network/path_segment.dart`).
//
// WHY THIS FILE EXISTS (2026-09-17, cycle-2 finding B2)
// ----------------------------------------------------
// `encodePathSegment` is the single encoder every HAND-BUILT `/api/v1/…` path
// in the app routes its ids through, and
// `scripts/forbid_unencoded_path_interpolation.sh` fails the build on any
// literal that skips it. It had NO unit test of its own — `find test -name
// "*path_segment*"` returned nothing. The gate proved the CALL happens; only
// this file proves the call does anything.
//
// The contract under test (`path_segment.dart:91-108`) is deliberately
// REJECT-not-sanitise, because these ids are server-issued UUIDs and a
// dot-segment is a programming error, not user input to repair. Each rejected
// shape below gets its own test so removing one clause of the `if` reddens
// exactly one test rather than smearing across the file.
//
// Pure Dart: no ProviderScope, no widget tree, no Dio.

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/path_segment.dart';
import 'package:flutter_test/flutter_test.dart';

/// Matches the exact failure shape the helper promises: an [UnknownFailure]
/// (NOT a raw [ArgumentError] — a repository must never leak an unmapped error
/// type past its boundary) wrapping an [ArgumentError] that names the offending
/// parameter and carries the rejected value.
Matcher _rejects(String name, Object? value) => throwsA(
  isA<UnknownFailure>().having(
    (UnknownFailure f) => f.cause,
    'cause',
    isA<ArgumentError>()
        .having((ArgumentError e) => e.name, 'name', name)
        .having((ArgumentError e) => e.invalidValue, 'invalidValue', value),
  ),
);

void main() {
  group('accepts', () {
    test(
      'a server-issued UUID is returned byte-identical (encode is a no-op)',
      () {
        const uuid = '3f2504e0-4f89-41d3-9a0c-0305e82c3301';

        final String encoded = encodePathSegment(uuid, 'salonId', logTag: 't');

        // The no-op property is what makes hardening every call site free: if
        // this ever stopped holding, every hand-built path in the app would start
        // addressing a different resource.
        expect(encoded, uuid);
      },
    );

    test(
      'percent-encodes a path-significant character instead of emitting it',
      () {
        // `/` is THE character that would otherwise split one segment into two
        // and retarget the request.
        expect(encodePathSegment('a/b', 'id', logTag: 't'), 'a%2Fb');
        expect(encodePathSegment('a b', 'id', logTag: 't'), 'a%20b');
        expect(encodePathSegment('a?b', 'id', logTag: 't'), 'a%3Fb');
        expect(encodePathSegment('a#b', 'id', logTag: 't'), 'a%23b');
      },
    );

    test(
      'a composite value merely CONTAINING dot-segments is safe and passes',
      () {
        // Documented in the helper: the separators encode to `%2F`, and Dio's
        // `normalizePath()` splits on LITERAL `/` only — so `..` buried inside
        // one segment can never be collapsed. Rejecting this would be a false
        // positive, so the pass is asserted, not merely tolerated.
        expect(
          encodePathSegment('a/../../b', 'id', logTag: 't'),
          'a%2F..%2F..%2Fb',
        );
      },
    );

    test('a single "." or ".." SURVIVING inside a longer value passes', () {
      expect(encodePathSegment('..x', 'id', logTag: 't'), '..x');
      expect(encodePathSegment('x..', 'id', logTag: 't'), 'x..');
      expect(encodePathSegment('...', 'id', logTag: 't'), '...');
    });

    test(
      'a whitespace-only value encodes to %20 and is NOT treated as empty',
      () {
        // Pins that the emptiness check runs on the ENCODED string, not on a
        // trimmed input: `' '` is a (useless but well-formed) segment, and
        // silently widening the reject clause to `trim().isEmpty` would change
        // behaviour here.
        expect(encodePathSegment(' ', 'id', logTag: 't'), '%20');
      },
    );
  });

  group('rejects', () {
    test('an EMPTY id — the branch the empty-path behaviour change rests on', () {
      // This is the clause that changed `fetchCities('')` from issuing
      // `/api/v1/locations/oblasts//cities` to throwing before the wire. It was
      // untested everywhere until this file.
      expect(
        () => encodePathSegment('', 'oblastId', logTag: 'location.repository'),
        _rejects('oblastId', ''),
      );
    });

    test('a bare "." — Dio normalizePath() deletes its own segment', () {
      expect(
        () => encodePathSegment('.', 'masterId', logTag: 't'),
        _rejects('masterId', '.'),
      );
    });

    test(
      'a bare ".." — Dio normalizePath() collapses the segment BEFORE it',
      () {
        // The measured case in the helper's doc: `masterId` and `serviceDefId`
        // both `'..'` turn `DELETE /api/v1/salons/S/masters/../services/..` into
        // `DELETE /api/v1/salons/S/`.
        expect(
          () => encodePathSegment('..', 'serviceDefId', logTag: 't'),
          _rejects('serviceDefId', '..'),
        );
      },
    );

    test('Uri.encodeComponent alone would NOT have caught "." or ".."', () {
      // The reason this helper exists rather than a bare encoder call. If this
      // ever fails, `Uri.encodeComponent` started escaping `.` and the four
      // `PASS A` sites the guard flags would no longer be a real hazard —
      // which is a finding in its own right, not a reason to relax the gate.
      expect(Uri.encodeComponent('..'), '..');
      expect(Uri.encodeComponent('.'), '.');
    });

    test('the error type is a Failure, never a raw ArgumentError', () {
      // A repository hoists this call OUTSIDE its `try`, so whatever is thrown
      // reaches the caller unreshaped — it MUST already be a `Failure`.
      Object? thrown;
      try {
        encodePathSegment('..', 'id', logTag: 't');
      } catch (e) {
        thrown = e;
      }
      expect(thrown, isA<Failure>());
      expect(thrown, isNot(isA<ArgumentError>()));
    });
  });

  group('the "/" survivor clause', () {
    test('is unreachable through Uri.encodeComponent, and is documented as '
        'forward cover for a laxer encoder', () {
      // `path_segment.dart:93-95` keeps `encoded.contains("/")` even though
      // `encodeComponent` always escapes `/` to `%2F`. This pins BOTH halves
      // of that comment so a future swap onto a laxer encoder (`encodeFull`
      // does not escape `/`) trips the clause instead of shipping a path
      // split — and so nobody deletes the clause as dead code on the
      // strength of the first half alone.
      expect(Uri.encodeComponent('a/b'), 'a%2Fb');
      expect(Uri.encodeComponent('a/b').contains('/'), isFalse);
      // `encodeFull`, the laxer encoder the comment names, is the shape the
      // clause exists to catch.
      expect(Uri.encodeFull('a/b').contains('/'), isTrue);
    });
  });

  group('requirePathIdToken', () {
    Matcher rejectsName(String name) => throwsA(
      isA<ValidationFailure>().having(
        (ValidationFailure f) => f.fieldErrors,
        'fieldErrors',
        <String, String>{name: 'invalid'},
      ),
    );

    test('accepts UUIDs and slugs, returning the value unchanged', () {
      for (final String ok in <String>[
        '3f2504e0-4f89-11d3-9a0c-0305e82c3301',
        'salon-1',
        'a_B-9',
        'x' * 64,
      ]) {
        expect(requirePathIdToken(ok, 'id'), ok);
      }
    });

    test(
      'rejects empty, dot-segments, separators, spaces, trailing newline, over-length',
      () {
        for (final String bad in <String>[
          '',
          '.',
          '..',
          'a/b',
          'a?x=1',
          'a b',
          '../x',
          'a%2Fb',
          'abc\n',
          'x' * 65,
        ]) {
          expect(
            () => requirePathIdToken(bad, 'salonId'),
            rejectsName('salonId'),
          );
        }
      },
    );
  });
}
