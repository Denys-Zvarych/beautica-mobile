// Phase 413 — BookingLinkUrl.withUtm (D5).

import 'package:beautica_mobile/features/booking_links/domain/booking_link.dart';
import 'package:beautica_mobile/features/booking_links/domain/booking_link_url.dart';
import 'package:flutter_test/flutter_test.dart';

const String _masterUrl = 'https://beautica.app/book/anna-k';
const String _salonUrl = 'https://beautica.app/book/s/velvet-lviv';

void main() {
  group('BookingLinkUrl.withUtm — kind × source', () {
    final List<
      ({
        BookingLinkKind kind,
        BookingLinkShareSource source,
        String url,
        String expected,
      })
    >
    cases =
        <
          ({
            BookingLinkKind kind,
            BookingLinkShareSource source,
            String url,
            String expected,
          })
        >[
          (
            kind: BookingLinkKind.master,
            source: BookingLinkShareSource.copy,
            url: _masterUrl,
            expected:
                '$_masterUrl?utm_source=copy&utm_medium=social'
                '&utm_campaign=master_link',
          ),
          (
            kind: BookingLinkKind.master,
            source: BookingLinkShareSource.share,
            url: _masterUrl,
            expected:
                '$_masterUrl?utm_source=share&utm_medium=social'
                '&utm_campaign=master_link',
          ),
          (
            kind: BookingLinkKind.salon,
            source: BookingLinkShareSource.copy,
            url: _salonUrl,
            expected:
                '$_salonUrl?utm_source=copy&utm_medium=social'
                '&utm_campaign=salon_link',
          ),
          (
            kind: BookingLinkKind.salon,
            source: BookingLinkShareSource.share,
            url: _salonUrl,
            expected:
                '$_salonUrl?utm_source=share&utm_medium=social'
                '&utm_campaign=salon_link',
          ),
        ];

    for (final c in cases) {
      test('${c.kind.name} / ${c.source.name}', () {
        expect(
          BookingLinkUrl.withUtm(c.url, kind: c.kind, source: c.source),
          c.expected,
        );
      });
    }
  });

  group('BookingLinkUrl.withUtm — query handling', () {
    test('an existing query is preserved, with exactly one "?"', () {
      final String out = BookingLinkUrl.withUtm(
        '$_masterUrl?ref=ig&lang=uk',
        kind: BookingLinkKind.master,
        source: BookingLinkShareSource.copy,
      );

      expect('?'.allMatches(out).length, 1);
      final Uri uri = Uri.parse(out);
      expect(uri.path, '/book/anna-k');
      expect(uri.queryParameters, <String, String>{
        'ref': 'ig',
        'lang': 'uk',
        'utm_source': 'copy',
        'utm_medium': 'social',
        'utm_campaign': 'master_link',
      });
      expect(out, startsWith('$_masterUrl?ref=ig&lang=uk&utm_source=copy'));
    });

    test('repeated existing keys survive', () {
      final Uri uri = Uri.parse(
        BookingLinkUrl.withUtm(
          '$_masterUrl?tag=a&tag=b',
          kind: BookingLinkKind.master,
          source: BookingLinkShareSource.share,
        ),
      );
      expect(uri.queryParametersAll['tag'], <String>['a', 'b']);
    });

    test('a pre-existing utm_* value is overwritten, never duplicated', () {
      final Uri uri = Uri.parse(
        BookingLinkUrl.withUtm(
          '$_salonUrl?utm_source=old&utm_campaign=x',
          kind: BookingLinkKind.salon,
          source: BookingLinkShareSource.share,
        ),
      );
      expect(uri.queryParametersAll['utm_source'], <String>['share']);
      expect(uri.queryParametersAll['utm_campaign'], <String>['salon_link']);
      expect(uri.queryParametersAll['utm_medium'], <String>['social']);
    });

    test('a plain ASCII slug path is left byte-identical', () {
      const String url = 'https://beautica.app/book/maria-ivanenko-2';
      final String out = BookingLinkUrl.withUtm(
        url,
        kind: BookingLinkKind.master,
        source: BookingLinkShareSource.copy,
      );
      expect(out, startsWith('$url?'));
    });

    test('existing query values that need encoding stay encoded', () {
      final String out = BookingLinkUrl.withUtm(
        '$_masterUrl?note=a%20b%26c',
        kind: BookingLinkKind.master,
        source: BookingLinkShareSource.copy,
      );
      expect(Uri.parse(out).queryParameters['note'], 'a b&c');
      expect(out, isNot(contains('a b&c')));
    });

    test('a fragment is kept after the query', () {
      final String out = BookingLinkUrl.withUtm(
        '$_masterUrl#services',
        kind: BookingLinkKind.master,
        source: BookingLinkShareSource.copy,
      );
      expect(out, endsWith('utm_campaign=master_link#services'));
    });

    test('an unparseable url throws, never passes through unchanged', () {
      const String broken = 'http://[::1';
      expect(
        () => BookingLinkUrl.withUtm(
          broken,
          kind: BookingLinkKind.master,
          source: BookingLinkShareSource.copy,
        ),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => e.name,
            'name',
            'url',
          ),
        ),
      );
    });
  });

  test('campaignFor maps every kind', () {
    expect(BookingLinkUrl.campaignFor(BookingLinkKind.master), 'master_link');
    expect(BookingLinkUrl.campaignFor(BookingLinkKind.salon), 'salon_link');
  });
}
