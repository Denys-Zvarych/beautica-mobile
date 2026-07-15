// Phase 14.3 — display-derived getters on [Booking].
//
// Pure Dart extension getters computed from the raw enriched fields — kept
// off the generated freezed class itself (no behaviour on a freezed data
// class) but centralised here so "when does money apply", "who is the
// actor", "what's the composed address" can never drift between the card,
// the detail screen, and the notes system, each of which needs the exact
// same derivation.
//
// Pure Dart: no Flutter imports.

import 'package:beautica_mobile/shared/formatters/booking_address_block.dart';
import 'package:beautica_mobile/shared/formatters/duration_minutes.dart';

import 'booking.dart';
import 'booking_status.dart';

extension BookingDisplayX on Booking {
  /// Joined display name — "Марія Іванюк".
  String get masterName => '$masterFirstName $masterLastName'.trim();

  /// Two-letter avatar-fallback initials — "МІ".
  String get masterInitials {
    final String f = masterFirstName.isNotEmpty ? masterFirstName[0] : '';
    final String l = masterLastName.isNotEmpty ? masterLastName[0] : '';
    final String initials = '$f$l'.toUpperCase();
    return initials.isEmpty ? '?' : initials;
  }

  /// A salon booking (`salonName != null`) was acted on BY THE SALON; an
  /// independent-master booking was acted on BY THE MASTER. The cancelled /
  /// declined LABEL no longer varies on this (both read the neutral
  /// «Скасовано» since 2026-07-15); it still drives the decline glyph
  /// (storefront vs scissors) and «Коментар салону» vs «Коментар майстра» —
  /// see `booking_notes.dart`.
  bool get atSalon => salonName != null;

  /// The provider in the genitive, for a note heading: «Коментар **салону**»
  /// vs «Коментар **майстра**». The ONLY axis the provider's note heading
  /// varies on — it names who actually wrote the words, never the status.
  String get providerGenitive => atSalon ? 'салону' : 'майстра';

  /// Whether the price is still a TRUE statement about money.
  ///
  ///   * [BookingStatus.confirmed] — you will pay it.
  ///   * [BookingStatus.completed] — you paid it.
  ///   * [BookingStatus.cancelled] / [BookingStatus.declined] — the
  ///     appointment did not happen; no sum is owed.
  ///   * [BookingStatus.notCompleted] — a no-show. Genuinely ambiguous
  ///     whether the provider charges for it — showing OR striking the price
  ///     would be the app taking a side it has no standing to take. So it
  ///     says nothing.
  ///
  /// `false` collapses the price everywhere it is consumed — not greyed, not
  /// struck through, not "—". Simply not built.
  bool get showsPrice =>
      status == BookingStatus.confirmed || status == BookingStatus.completed;

  /// Add-to-calendar only makes sense for an appointment you still have to
  /// show up to.
  bool get canAddToCalendar => status == BookingStatus.confirmed;

  /// The four location fields composed into one line, or `null` when the
  /// provider has no usable location on file. See [composeAddressLine].
  String? get addressLine => composeAddressLine(
    cityLabel: cityLabel,
    districtLabel: districtLabel,
    street: street,
    buildingNo: buildingNo,
  );

  /// The same four fields as a `(value, detail)` pair for «Деталі запису»,
  /// which shows the full chain. See [composeAddressBlock].
  (String?, String?) get addressBlock => composeAddressBlock(
    cityLabel: cityLabel,
    districtLabel: districtLabel,
    street: street,
    buildingNo: buildingNo,
  );

  /// «1 год 30 хв».
  String get durationLabel => DurationMinutes.format(durationMinutes);

  /// Whether there is anything at all to say about *where to go* — either a
  /// venue name, an address, or both.
  bool get hasDestination => salonName != null || addressLine != null;
}
