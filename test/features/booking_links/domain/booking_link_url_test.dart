// Phase 413 — BookingLinkUrl (D5); phase 418 — no UTM, and the share-time
// guard enforces the canonical shape (security LOW, cycle 1); phase 419 —
// output is the canonical link + exactly one channel flag (`?s=c` / `?s=s`).

import 'package:beautica_mobile/features/booking_links/domain/booking_link_url.dart';
import 'package:flutter_test/flutter_test.dart';

const String _origin = 'https://beautica.app';
const String _masterUrl = '$_origin/book/anna-k';
const String _salonUrl = '$_origin/book/s/velvet-lviv';

String _share(
  String url, {
  BookingLinkChannel channel = BookingLinkChannel.copy,
}) => BookingLinkUrl.forSharing(url, origin: _origin, channel: channel);

Matcher get _throwsUrlArgumentError => throwsA(
  isA<ArgumentError>().having((ArgumentError e) => e.name, 'name', 'url'),
);

void main() {
  group('BookingLinkUrl.forSharing', () {
    test('channel flags are exactly c (copy) and s (share)', () {
      expect(BookingLinkChannel.values, hasLength(2));
      expect(BookingLinkChannel.copy.flag, 'c');
      expect(BookingLinkChannel.share.flag, 's');
    });

    final Map<String, String> canonical = <String, String>{
      'master': _masterUrl,
      'salon': _salonUrl,
      'plain ASCII slug': '$_origin/book/maria-ivanenko-2',
    };
    canonical.forEach((String label, String url) {
      test('$label + copy → canonical + exactly "?s=c"', () {
        final String out = _share(url);
        expect(out, '$url?s=c');
        expect('?'.allMatches(out), hasLength(1));
        expect(out, isNot(contains('&')));
        expect(out, isNot(contains('utm_')));
      });

      test('$label + share → canonical + exactly "?s=s"', () {
        final String out = _share(url, channel: BookingLinkChannel.share);
        expect(out, '$url?s=s');
        expect('?'.allMatches(out), hasLength(1));
        expect(out, isNot(contains('&')));
        expect(out, isNot(contains('utm_')));
      });
    });

    test('an unparseable url throws, never passes through unchanged', () {
      expect(() => _share('http://[::1'), _throwsUrlArgumentError);
    });

    final Map<String, String> rejected = <String, String>{
      'foreign host': 'https://evil.example/book/anna-k',
      'look-alike host': 'https://beautica.app.evil.example/book/anna-k',
      'http scheme': 'http://beautica.app/book/anna-k',
      'javascript: scheme': 'javascript:alert(1)',
      'query': '$_masterUrl?r=1',
      'query on salon': '$_salonUrl?utm_source=x',
      'flag already present (no double flag)': '$_masterUrl?s=c',
      'share flag already present': '$_salonUrl?s=s',
      'unknown flag value': '$_masterUrl?s=x',
      'flag plus extra param': '$_masterUrl?s=c&r=1',
      'empty query': '$_masterUrl?',
      'fragment': '$_masterUrl#top',
      'fragment on salon': '$_salonUrl#x',
      'userinfo': 'https://user@beautica.app/book/anna-k',
      'port': 'https://beautica.app:8443/book/anna-k',
      'uppercase slug': '$_origin/book/Anna-K',
      'extra path segment': '$_origin/book/anna-k/extra',
      'salon extra segment': '$_origin/book/s/velvet-lviv/x',
      'dot-segment': '$_origin/book/../book/anna-k',
      'percent-encoded slug': '$_origin/book/anna%2Fk',
      'empty slug': '$_origin/book/',
      'empty salon slug': '$_origin/book/s/',
      'wrong path': '$_origin/master/anna-k',
      'empty string': '',
    };
    for (final MapEntry<String, String> e in rejected.entries) {
      test('throws for ${e.key} (both channels)', () {
        expect(() => _share(e.value), _throwsUrlArgumentError);
        expect(
          () => _share(e.value, channel: BookingLinkChannel.share),
          _throwsUrlArgumentError,
        );
      });
    }

    test('slug over 60 chars throws; exactly 60 passes', () {
      final String max = 'a' * 60;
      expect(_share('$_origin/book/$max'), '$_origin/book/$max?s=c');
      expect(() => _share('$_origin/book/${max}a'), _throwsUrlArgumentError);
    });
  });

  group('isValidBookingSlug', () {
    test('slug validator accepts the backend format only', () {
      expect(isValidBookingSlug('anna-k'), isTrue);
      expect(isValidBookingSlug('-anna'), isFalse);
      expect(isValidBookingSlug('anna-'), isFalse);
      expect(isValidBookingSlug('a'), isFalse);
    });
  });
}
