// MO-5 — display-derived getters on [Appointment], the visit analogue of
// `booking_display_x.dart`.
//
// Pure Dart extension getters computed from the raw enriched visit fields, so
// the visit detail screen never inlines a Cyrillic literal or re-derives an
// address / money rule the single-booking surfaces already own. Kept off the
// generated freezed class itself.
//
// Pure Dart: no Flutter imports.

import 'package:beautica_mobile/shared/formatters/booking_address_block.dart';
import 'package:beautica_mobile/shared/formatters/booking_price_labels.dart';
import 'package:beautica_mobile/shared/formatters/duration_minutes.dart';

import 'appointment.dart';
import 'booking_status.dart';

extension AppointmentDisplayX on Appointment {
  /// Joined master display name — "Марія Іванюк".
  String get masterName => '$masterFirstName $masterLastName'.trim();

  /// Two-letter avatar-fallback initials — "МІ".
  String get masterInitials {
    final String f = masterFirstName.isNotEmpty ? masterFirstName[0] : '';
    final String l = masterLastName.isNotEmpty ? masterLastName[0] : '';
    final String initials = '$f$l'.toUpperCase();
    return initials.isEmpty ? '?' : initials;
  }

  /// A salon visit (`salonName != null`) was acted on BY THE SALON; an
  /// independent-master visit BY THE MASTER — mirrors `BookingDisplayX.atSalon`.
  bool get atSalon => salonName != null;

  /// The provider in the genitive, for the no-show subline: «…майстра» vs
  /// «…салону». Mirrors `BookingDisplayX.providerGenitive`.
  String get providerGenitive => atSalon ? 'салону' : 'майстра';

  /// Whether the price is still a TRUE statement about money — shown only on
  /// CONFIRMED / COMPLETED (mirrors `BookingDisplayX.showsPrice`).
  bool get showsPrice =>
      status == BookingStatus.confirmed || status == BookingStatus.completed;

  /// The visit total price label — «650 ₴» or the summed band «300–500 ₴». See
  /// `Appointment.totalPriceMax` for why a null ceiling means single total.
  String get totalPriceLabel =>
      formatBookingPrice(price: totalPrice, priceMax: totalPriceMax);

  /// «1 год 30 хв» — the whole visit's summed length.
  String get durationLabel => DurationMinutes.format(totalDurationMinutes);

  /// Whether the visit's end instant is already in the PAST — a presentation-
  /// only signal, mirroring `BookingDisplayX.isPast`.
  bool get isPast => endAt.isBefore(DateTime.now());

  /// The four location fields as a `(value, detail)` pair for the detail card.
  (String?, String?) get addressBlock => composeAddressBlock(
    cityLabel: cityLabel,
    districtLabel: districtLabel,
    street: street,
    buildingNo: buildingNo,
  );
}
