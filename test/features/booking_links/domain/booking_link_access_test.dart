// Phase 414 — client-side booking-link access rule (user decision
// 2026-10-20): INDEPENDENT_MASTER → MASTER links only; SALON_OWNER and
// SALON_ADMIN → SALON links only; SALON_MASTER / CLIENT / signed out → none.

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/booking_links/domain/booking_link.dart';
import 'package:beautica_mobile/features/booking_links/domain/booking_link_access.dart';
import 'package:flutter_test/flutter_test.dart';

const BookingLink _master = BookingLink(
  kind: BookingLinkKind.master,
  slug: 'anna-x7k2',
  url: 'https://beautica.app/book/anna-x7k2',
  displayName: 'Anna',
  bookable: true,
);

const BookingLink _salonA = BookingLink(
  kind: BookingLinkKind.salon,
  slug: 'lumiere',
  url: 'https://beautica.app/book/s/lumiere',
  displayName: 'Lumière',
  salonId: 'a',
  bookable: true,
);

const BookingLink _salonB = BookingLink(
  kind: BookingLinkKind.salon,
  slug: 'loft',
  url: 'https://beautica.app/book/s/loft',
  displayName: 'Loft',
  salonId: 'b',
  bookable: false,
);

const BookingLinks _all = BookingLinks(
  shareEnabled: true,
  links: <BookingLink>[_master, _salonA, _salonB],
);

void main() {
  group('bookingLinksAllowedFor', () {
    final Map<UserRole?, bool> expected = <UserRole?, bool>{
      UserRole.independentMaster: true,
      UserRole.salonOwner: true,
      UserRole.salonAdmin: true,
      UserRole.salonMaster: false,
      UserRole.client: false,
      null: false,
    };
    expected.forEach((UserRole? role, bool allowed) {
      test('${role?.name ?? 'signed out'} → $allowed', () {
        expect(bookingLinksAllowedFor(role), allowed);
      });
    });

    test('covers every UserRole', () {
      expect(
        expected.keys.whereType<UserRole>().toSet(),
        UserRole.values.toSet(),
      );
    });
  });

  group('scopeBookingLinksToRole', () {
    test('INDEPENDENT_MASTER keeps only its MASTER link', () {
      expect(
        scopeBookingLinksToRole(_all, UserRole.independentMaster).links,
        <BookingLink>[_master],
      );
    });

    test('SALON_OWNER keeps only SALON links, in backend order — no master '
        'card', () {
      expect(
        scopeBookingLinksToRole(_all, UserRole.salonOwner).links,
        <BookingLink>[_salonA, _salonB],
      );
    });

    test('SALON_ADMIN keeps only SALON links', () {
      expect(
        scopeBookingLinksToRole(_all, UserRole.salonAdmin).links,
        <BookingLink>[_salonA, _salonB],
      );
    });

    for (final UserRole? role in <UserRole?>[
      UserRole.salonMaster,
      UserRole.client,
      null,
    ]) {
      test('${role?.name ?? 'signed out'} → hidden (no links, switch off)', () {
        final BookingLinks scoped = scopeBookingLinksToRole(_all, role);
        expect(scoped, BookingLinks.hidden);
        expect(scoped.isVisible, isFalse);
      });
    }

    test('the kill-switch is preserved for an allowed role', () {
      const BookingLinks off = BookingLinks(
        shareEnabled: false,
        links: <BookingLink>[_master],
      );
      final BookingLinks scoped = scopeBookingLinksToRole(
        off,
        UserRole.independentMaster,
      );
      expect(scoped.shareEnabled, isFalse);
      expect(scoped.isVisible, isFalse);
    });

    test(
      'an owner whose server still sends only a MASTER link sees nothing',
      () {
        const BookingLinks onlyMaster = BookingLinks(
          shareEnabled: true,
          links: <BookingLink>[_master],
        );
        expect(
          scopeBookingLinksToRole(onlyMaster, UserRole.salonOwner).isVisible,
          isFalse,
        );
      },
    );
  });
}
