// Phase 413 — BookingLink / BookingLinks value semantics.
//
// `bookingLinksProvider` consumers compare these by value (Riverpod skips a
// rebuild on an equal value; the provider tests compare against
// [BookingLinks.hidden]), so equality must be deep over `links` and cover
// every field of [BookingLink].

import 'package:beautica_mobile/features/booking_links/domain/booking_link.dart';
import 'package:flutter_test/flutter_test.dart';

const BookingLink _salon = BookingLink(
  kind: BookingLinkKind.salon,
  slug: 'studio',
  url: 'https://beautica.app/book/s/studio',
  displayName: 'Studio',
  salonId: 'salon-1',
  bookable: false,
);

void main() {
  group('BookingLink equality', () {
    test('two links with the same fields are equal with equal hashCodes', () {
      final BookingLink copy = _salon.copyWith();

      expect(copy, _salon);
      expect(copy.hashCode, _salon.hashCode);
    });

    final Map<String, BookingLink Function()> changed =
        <String, BookingLink Function()>{
          'kind': () => _salon.copyWith(kind: BookingLinkKind.master),
          'slug': () => _salon.copyWith(slug: 'other'),
          'url': () => _salon.copyWith(url: 'https://beautica.app/book/s/x'),
          'displayName': () => _salon.copyWith(displayName: 'Other'),
          'salonId': () => _salon.copyWith(salonId: null),
          'bookable': () => _salon.copyWith(bookable: true),
        };
    for (final MapEntry<String, BookingLink Function()> e in changed.entries) {
      test('a different ${e.key} makes the links unequal', () {
        expect(e.value(), isNot(_salon));
      });
    }
  });

  group('BookingLinks', () {
    test('equality is deep over links, not list identity', () {
      // Growable, non-const lists: two distinct list instances.
      final BookingLinks a = BookingLinks(
        shareEnabled: true,
        links: List<BookingLink>.of(<BookingLink>[_salon]),
      );
      final BookingLinks b = BookingLinks(
        shareEnabled: true,
        links: <BookingLink>[_salon.copyWith()],
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('a different link list makes the values unequal', () {
      const BookingLinks one = BookingLinks(
        shareEnabled: true,
        links: <BookingLink>[_salon],
      );

      expect(
        one,
        isNot(const BookingLinks(shareEnabled: true, links: <BookingLink>[])),
      );
      expect(
        one,
        isNot(
          const BookingLinks(shareEnabled: false, links: <BookingLink>[_salon]),
        ),
      );
    });

    test('hidden is kill-switch off with no links, and not visible', () {
      expect(BookingLinks.hidden.shareEnabled, isFalse);
      expect(BookingLinks.hidden.links, isEmpty);
      expect(BookingLinks.hidden.isVisible, isFalse);
    });

    test('the links list cannot be mutated through the model', () {
      // A growable caller list — freezed must still hand back a read-only view.
      final BookingLinks links = BookingLinks(
        shareEnabled: true,
        links: List<BookingLink>.of(<BookingLink>[_salon]),
      );

      expect(() => links.links.add(_salon), throwsUnsupportedError);
    });
  });

  group('phase 415 — status', () {
    const BookingLink revokedMaster = BookingLink(
      kind: BookingLinkKind.master,
      slug: null,
      url: null,
      displayName: 'Anna',
      bookable: false,
      status: BookingLinkStatus.revoked,
    );

    test('status defaults to active; equality covers it', () {
      expect(_salon.status, BookingLinkStatus.active);
      expect(_salon.isRevoked, isFalse);
      expect(_salon, isNot(_salon.copyWith(status: BookingLinkStatus.revoked)));
    });

    test('isVisible stays true with only revoked links (D5)', () {
      const BookingLinks links = BookingLinks(
        shareEnabled: true,
        links: <BookingLink>[revokedMaster],
      );
      expect(links.isVisible, isTrue);
    });

    test('keyId: slug when active, a stable revoked id otherwise', () {
      expect(_salon.keyId, 'studio');
      expect(revokedMaster.keyId, 'revoked-master');
      expect(
        _salon
            .copyWith(slug: null, url: null, status: BookingLinkStatus.revoked)
            .keyId,
        'revoked-salon-salon-1',
      );
    });
  });
}
