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

import '../../../../helpers/booking_fixture_dates.dart';

final AppLocalizations _uk = lookupAppLocalizations(const Locale('uk'));
final AppLocalizations _en = lookupAppLocalizations(const Locale('en'));

Booking _booking({required BookingStatus status, String? salonName}) {
  // Now-relative, never an absolute future literal (this file was
  // grandfathered into `scripts/.stale_future_date_allow` for the old
  // `DateTime.utc(2026, 7, 20, 15)` here, and is DELISTED as of 2026-07-22).
  // Nothing in `BookingStatusVisual.of` reads the wall clock, so the instant
  // is immaterial — which is exactly why there is no reason to keep a literal
  // that can expire.
  final DateTime start = futureBookingStart();
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

  // ===========================================================================
  // mobile-qa (2026-07-22) — the `unknown` arm had ZERO coverage.
  // ===========================================================================
  //
  // `BookingStatusVisual.of` grew a `case BookingStatus.unknown` (security S1
  // — a status this build does not recognise, e.g. a backend that shipped a
  // new state first). Its whole contract is to be HONEST rather than
  // decorative, and every part of that contract is silent-failure shaped: a
  // `switch` arm that fell through to `confirmed`'s green check, or reused
  // `error` red, would render a perfectly plausible badge making a claim the
  // build cannot support. Nothing throws, nothing overflows, no other test in
  // the suite constructs an `unknown` booking at all.
  group('unknown status (security S1) — the badge must not assert anything', () {
    test('reads the non-committal «Статус уточнюється», never another '
        'status\'s label', () {
      final BookingStatusVisual v = _visual(BookingStatus.unknown);

      expect(v.label, _uk.bookingStatusUnknown);
      // Explicitly NOT any real status's copy — a fall-through switch arm is
      // exactly how this regresses.
      expect(v.label, isNot(_uk.bookingStatusConfirmed));
      expect(v.label, isNot(_uk.bookingStatusCompleted));
      expect(v.label, isNot(_uk.bookingStatusCancelled));
      expect(v.label, isNot(_uk.bookingStatusNotCompleted));
    });

    test(
      'carries the help glyph — not a check, a cross, or a provider mark',
      () {
        final BookingStatusVisual v = _visual(BookingStatus.unknown);

        expect(v.icon, Icons.help_outline_rounded);
        expect(v.icon, isNot(_visual(BookingStatus.confirmed).icon));
        expect(v.icon, isNot(_visual(BookingStatus.completed).icon));
        expect(v.icon, isNot(_visual(BookingStatus.cancelled).icon));
        expect(v.icon, isNot(_visual(BookingStatus.notCompleted).icon));
        expect(
          v.icon,
          isNot(_visual(BookingStatus.declined, salonName: 'S').icon),
        );
      },
    );

    test('uses the MUTED accent at the ORDINARY wash alpha — the quietest cap '
        'in the set, and never a real status\'s colour', () {
      final BookingStatusVisual v = _visual(BookingStatus.unknown);

      expect(v.accent, BrandColors.muted);
      // A green check or a red cap would assert precisely the thing this
      // build does not know.
      expect(v.accent, isNot(BrandColors.success));
      expect(v.accent, isNot(BrandColors.error));
      expect(v.accent, isNot(BrandColors.accentLatte));
      expect(v.accent, isNot(BrandColors.accentDeep));
      expect(v.accent, isNot(BrandColors.text));

      // The wash is the accent at the ORDINARY alpha (0.10), not the
      // EXCEPTIONAL one (0.14) reserved for the two statuses that deserve to
      // be found while scanning. An unknown status is not an alarm.
      expect(v.wash, BrandColors.muted.withValues(alpha: 0.10));
      expect(
        v.wash,
        isNot(BrandColors.muted.withValues(alpha: 0.14)),
        reason:
            'the unknown badge was promoted to the exceptional wash — it '
            'would then compete for attention with a no-show and a '
            'provider cancellation',
      );
    });

    test('the label colour is still the uniform AA-passing one — the status '
        'colour never touches text', () {
      // Pins the file header's measured-contrast rule for the arm added last:
      // `muted` as a text colour would not clear 4.5:1.
      expect(BookingStatusVisual.labelColor, BrandColors.textSecondary);
      expect(
        _visual(BookingStatus.unknown).accent,
        isNot(BookingStatusVisual.labelColor),
      );
    });

    test('the copy resolves in English too (ARB parity)', () {
      final BookingStatusVisual v = _visual(BookingStatus.unknown, l10n: _en);
      expect(v.label, _en.bookingStatusUnknown);
      expect(v.label, isNot(_en.bookingStatusConfirmed));
      expect(v.label, isNot(_en.bookingStatusCancelled));
    });
  });
}
