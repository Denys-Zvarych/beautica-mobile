// mobile-qa (booking-UI collapse, 2026-07-15) — the label-collapse regression
// guard for `BookingStatusVisual`.
//
// Product decision 2026-07-15 collapsed the who-cancelled copy: CANCELLED (the
// client backed out) and DECLINED (the provider backed out — salon OR
// independent master) now share ONE neutral label, «Скасовано». The domain
// STATUS split is intentionally preserved; only the visible LABEL collapses.
// This suite locks that in so a future re-split (re-introducing «Ви скасував» /
// «Салон скасував» / «Майстер скасував») fails loudly here:
//   • all three cancel/decline permutations resolve the SAME label, and that
//     label is `l10n.bookingStatusCancelled`;
//   • the non-text distinction is still carried — glyph + accent differ between
//     a client cancellation and a provider decline, and a salon decline vs an
//     independent-master decline differ by glyph;
//   • the other three statuses keep their own labels (no accidental spillover).
//
// A pure-domain resolution test: `BookingStatusVisual.of` needs only a `Booking`
// + an `AppLocalizations`, so l10n is loaded synchronously via
// `lookupAppLocalizations` — no widget tree, no pump.

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/features/booking/domain/booking.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/booking_status_badge.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final AppLocalizations _uk = lookupAppLocalizations(const Locale('uk'));
final AppLocalizations _en = lookupAppLocalizations(const Locale('en'));

Booking _booking({required BookingStatus status, String? salonName}) {
  final DateTime start = DateTime.utc(2026, 7, 20, 15);
  return Booking(
    id: 'b1',
    masterId: 'm1',
    masterFirstName: 'Марія',
    masterLastName: 'Іванюк',
    masterType: salonName != null ? 'SALON_MASTER' : 'INDEPENDENT_MASTER',
    salonName: salonName,
    serviceId: 's1',
    serviceName: 'Манікюр',
    durationMinutes: 60,
    price: 500,
    startAt: start,
    endAt: start.add(const Duration(minutes: 60)),
    status: status,
    canReview: false,
  );
}

BookingStatusVisual _visual(
  BookingStatus status, {
  String? salonName,
  AppLocalizations? l10n,
}) => BookingStatusVisual.of(
  _booking(status: status, salonName: salonName),
  l10n ?? _uk,
);

void main() {
  group('cancelled / declined label collapse (2026-07-15)', () {
    test('a CLIENT cancellation reads the neutral «Скасовано»', () {
      expect(
        _visual(BookingStatus.cancelled).label,
        _uk.bookingStatusCancelled,
      );
    });

    test('a SALON decline reads the SAME neutral «Скасовано»', () {
      expect(
        _visual(BookingStatus.declined, salonName: 'Lviv Nails Studio').label,
        _uk.bookingStatusCancelled,
      );
    });

    test(
      'an INDEPENDENT-master decline reads the SAME neutral «Скасовано»',
      () {
        expect(
          _visual(BookingStatus.declined).label,
          _uk.bookingStatusCancelled,
        );
      },
    );

    test(
      'all three cancel/decline permutations resolve ONE identical label — the '
      'regression guard against a future who-cancelled re-split',
      () {
        final String cancelled = _visual(BookingStatus.cancelled).label;
        final String declinedSalon = _visual(
          BookingStatus.declined,
          salonName: 'S',
        ).label;
        final String declinedMaster = _visual(BookingStatus.declined).label;

        expect(cancelled, declinedSalon);
        expect(cancelled, declinedMaster);
      },
    );

    test('the collapse holds in English too (ARB parity)', () {
      expect(
        _visual(BookingStatus.cancelled, l10n: _en).label,
        _en.bookingStatusCancelled,
      );
      expect(
        _visual(BookingStatus.declined, salonName: 'S', l10n: _en).label,
        _en.bookingStatusCancelled,
      );
      expect(
        _visual(BookingStatus.declined, l10n: _en).label,
        _en.bookingStatusCancelled,
      );
    });
  });

  group('non-text channels still distinguish the collapsed statuses', () {
    test(
      'client cancellation vs provider decline differ by glyph AND accent',
      () {
        final BookingStatusVisual cancelled = _visual(BookingStatus.cancelled);
        final BookingStatusVisual declined = _visual(
          BookingStatus.declined,
          salonName: 'S',
        );

        // Client cancellation: person glyph, warm mocha — a blameless act.
        expect(cancelled.icon, Icons.person_rounded);
        expect(cancelled.accent, BrandColors.accentDeep);

        // Provider decline: red — the one status that took something away.
        expect(declined.accent, BrandColors.error);
        expect(
          declined.accent,
          isNot(cancelled.accent),
          reason: 'colour must still separate a client cancel from a decline',
        );
        expect(declined.icon, isNot(cancelled.icon));
      },
    );

    test(
      'a salon decline vs an independent-master decline differ by glyph',
      () {
        final BookingStatusVisual salon = _visual(
          BookingStatus.declined,
          salonName: 'S',
        );
        final BookingStatusVisual independent = _visual(BookingStatus.declined);

        expect(salon.icon, Icons.storefront_rounded);
        expect(independent.icon, Icons.content_cut_rounded);
        // Same label, same accent — only the provider glyph separates them.
        expect(salon.label, independent.label);
        expect(salon.accent, independent.accent);
      },
    );
  });

  group('the other statuses keep their own labels (no collapse spillover)', () {
    test('CONFIRMED keeps «Підтверджено»', () {
      final BookingStatusVisual v = _visual(BookingStatus.confirmed);
      expect(v.label, _uk.bookingStatusConfirmed);
      expect(v.label, isNot(_uk.bookingStatusCancelled));
    });

    test('COMPLETED keeps «Завершено»', () {
      expect(
        _visual(BookingStatus.completed).label,
        _uk.bookingStatusCompleted,
      );
    });

    test('NOT_COMPLETED keeps its own no-show label', () {
      final BookingStatusVisual v = _visual(BookingStatus.notCompleted);
      expect(v.label, _uk.bookingStatusNotCompleted);
      expect(v.label, isNot(_uk.bookingStatusCancelled));
    });
  });
}
