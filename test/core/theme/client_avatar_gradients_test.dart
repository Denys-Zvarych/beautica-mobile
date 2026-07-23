// Phase 7.10 timeline audit (mobile-perf MEDIUM-2) — pins
// [ClientAvatarGradients.forKey]'s determinism contract directly.
//
// Historically `MasterBookingCard` resolved this ONCE per card lifetime
// (`initState`) on the assumption that "same key -> same gradient, every
// time". The compact-timeline pass (2026-07-20) dropped that card's avatar
// row entirely, so `MasterBookingCard` no longer calls [forKey] at all —
// [ClientAvatarGradients] is kept as a public, shared utility for any future
// card that wants the gradient-avatar treatment (see
// `master_booking_card.dart`'s `_ClientAvatar` doc). This file's assertions
// are unaffected either way: nothing in the widget tier ever asserted the
// hashing/memoisation is correct in isolation — a widget test pumping two
// cards for the same client would pass even if [forKey] returned a RANDOM
// gradient on every call, as long as both cards happened to call it with the
// SAME already-cached first result — the memo cache (`_cache`) masks a
// non-deterministic hash on every call after the first. This file isolates
// [forKey] from any widget tree so a regression in the hash itself, or in the
// cache's interaction with it, cannot hide behind a coincidentally-passing
// widget test.
//
// Pure Dart: no `flutter_test` widget pumping needed for the hash/memo
// behaviour, but the suite still runs under `flutter_test` (this repo's
// convention for every test file) since [Color] is a Flutter type.

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ClientAvatarGradients.forKey determinism', () {
    test('the same key returns the identical gradient across many calls', () {
      const String key = 'client-abc-123';
      final List<Color> first = ClientAvatarGradients.forKey(key);

      for (int i = 0; i < 5; i++) {
        expect(
          ClientAvatarGradients.forKey(key),
          equals(first),
          reason:
              'call #$i for the same key must resolve to the exact same '
              'gradient — a client\'s avatar must never change colour '
              'between rebuilds, screens, or app restarts',
        );
      }
    });

    test(
      'two DIFFERENT keys can resolve to different gradients (the palette is '
      'actually being indexed, not collapsed to one constant entry)',
      () {
        // A broad spread of distinct keys — if [forKey] degenerated to
        // "always return palette[0]" (or any other constant), every one of
        // these would collapse to the SAME gradient, which the assertion
        // below catches.
        final List<List<Color>> resolved = <String>[
          'client-1',
          'client-2',
          'client-3',
          'client-4',
          'client-5',
          'client-6',
          'client-7',
          'client-8',
        ].map(ClientAvatarGradients.forKey).toList();

        final Set<List<Color>> distinct = resolved.toSet();
        expect(
          distinct.length,
          greaterThan(1),
          reason:
              'at least two of these 8 keys must land on different palette '
              'entries — a constant-gradient regression would make every '
              'client\'s avatar look identical',
        );
      },
    );

    test('every resolved gradient is exactly 2 colours, all drawn from '
        'BrandColors (never an out-of-palette colour)', () {
      const List<Color> allowed = <Color>[
        BrandColors.accentLogo,
        BrandColors.accentDeep,
        BrandColors.accent,
        BrandColors.accentLatte,
        BrandColors.placeholder,
        BrandColors.textSecondary,
        BrandColors.faint,
        BrandColors.muted,
        BrandColors.text,
      ];

      for (final String key in <String>[
        'a',
        'bb',
        'ccc',
        'guest-booking-id-xyz',
        '',
      ]) {
        final List<Color> gradient = ClientAvatarGradients.forKey(key);
        expect(gradient.length, 2);
        for (final Color c in gradient) {
          expect(
            allowed,
            contains(c),
            reason:
                'forKey("$key") returned $c, which is not one of the locked '
                'VelvetTouch tones — a client avatar must never drift '
                'outside the palette',
          );
        }
      }
    });

    test('the empty string is a valid key and does not throw (a nameless guest '
        'booking can fall back to its booking id, which is never empty in '
        'practice, but forKey itself must not assume a non-empty key)', () {
      expect(() => ClientAvatarGradients.forKey(''), returnsNormally);
    });

    test('repeated resolution of the SAME key does not grow the memo cache '
        'unboundedly — re-resolving 100 times for one key behaves identically '
        'to resolving it once', () {
      const String key = 'repeat-key';
      final List<Color> baseline = ClientAvatarGradients.forKey(key);
      for (int i = 0; i < 100; i++) {
        expect(ClientAvatarGradients.forKey(key), same(baseline));
      }
    });

    test(
      'mobile-perf LOW-6 (2026-07-20): the memo cache is BOUNDED — resolving '
      'more than debugMaxCachedKeys distinct keys never lets the cache grow '
      'past that ceiling, on a shared device / long-lived process where the '
      'client roster keeps growing for the whole session',
      () {
        // +50 past the cap so the assertion cannot pass by coincidence (e.g.
        // an off-by-one that only trips right at the boundary).
        const int keysToInsert = ClientAvatarGradients.debugMaxCachedKeys + 50;
        for (int i = 0; i < keysToInsert; i++) {
          ClientAvatarGradients.forKey('distinct-client-$i');
        }

        expect(
          ClientAvatarGradients.debugCacheLength,
          lessThanOrEqualTo(ClientAvatarGradients.debugMaxCachedKeys),
          reason:
              'an unbounded cache would grow to $keysToInsert entries here — '
              'small in this test, but resident for the WHOLE process '
              'lifetime in a real long session on a shared device',
        );
      },
    );
  });
}
