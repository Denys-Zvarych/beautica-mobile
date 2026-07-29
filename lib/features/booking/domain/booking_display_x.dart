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
import 'package:beautica_mobile/shared/formatters/booking_price_labels.dart';
import 'package:beautica_mobile/shared/formatters/duration_minutes.dart';

import 'booking.dart';
import 'booking_status.dart';

extension BookingDisplayX on Booking {
  /// Joined display name — "Марія Іванюк".
  String get masterName => '$masterFirstName $masterLastName'.trim();

  /// Phase 7.2 — the joined CLIENT display name for the provider view, or
  /// `null` when the booking carries no client name at all.
  ///
  /// Returns `null` rather than an empty string or a hardcoded «Гість» because
  /// this file is pure Dart with no `AppLocalizations` in scope — the caller
  /// (`BookingCounterpartyHeader`) supplies the localized guest fallback. A
  /// guest/LINK booking normally DOES land here with a real name: the backend
  /// resolves `guestName`/`guestSurname` into `clientFirstName`/
  /// `clientLastName` server-side, so the null case is a genuinely nameless
  /// row, not the ordinary guest flow.
  String? get clientName {
    final String joined = '${clientFirstName ?? ''} ${clientLastName ?? ''}'
        .trim();
    return joined.isEmpty ? null : joined;
  }

  /// Two-letter CLIENT avatar-fallback initials, or `null` when there is no
  /// name to derive them from (the caller renders a generic person glyph).
  String? get clientInitials {
    final String f = (clientFirstName ?? '').isNotEmpty
        ? clientFirstName![0]
        : '';
    final String l = (clientLastName ?? '').isNotEmpty
        ? clientLastName![0]
        : '';
    final String initials = '$f$l'.toUpperCase();
    return initials.isEmpty ? null : initials;
  }

  /// Whether this is a guest/LINK booking — the client has no registered
  /// account (`client_id IS NULL`). Independent of whether a NAME is present:
  /// a guest booking almost always has one.
  bool get isGuestBooking => clientId == null;

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

  /// HOW the price reads — «300 ₴» for a single price, «300–500 ₴» when the
  /// master left this service as a genuine RANGE at booking time
  /// ([Booking.priceMax] non-null). Delegates to the shared
  /// [formatBookingPrice] so the client card, the master timeline card, «Деталі
  /// запису»'s recap and its add-to-calendar description can never drift on
  /// separator, rounding or currency suffix.
  ///
  /// Orthogonal to [showsPrice], which decides WHETHER money is shown at all —
  /// every call site still gates on that first, and a band is gated
  /// identically to a single figure.
  String get priceLabel => formatBookingPrice(price: price, priceMax: priceMax);

  /// Add-to-calendar only makes sense for an appointment you still have to
  /// show up to.
  ///
  /// ⚠ Security-load-bearing (finding S1): this is the one capability on
  /// `Booking` with NO server round-trip to re-validate it — it writes to the
  /// device calendar, which any app holding `READ_CALENDAR` can read. So it
  /// must stay an ALLOWLIST (`== confirmed`), never a denylist of terminal
  /// statuses. Written as a denylist, [BookingStatus.unknown] — and every
  /// future backend status — would fall through to `true` and leak an
  /// appointment this build cannot even identify. Do not "simplify" it.
  bool get canAddToCalendar => status == BookingStatus.confirmed;

  /// Whether this booking's end instant is already in the PAST relative to the
  /// device clock — a PRESENTATION-ONLY signal.
  ///
  /// Used to flip a CONFIRMED booking's «Деталі запису» to read-only once its
  /// slot has elapsed: hide Reschedule / Cancel / add-to-calendar and offer
  /// «Записатись знову» instead (the terminal states' affordance). It is NOT an
  /// authorization gate — the SERVER owns the real rule: a CONFIRMED booking
  /// whose `endsAt` is before the SERVER clock returns HTTP 409
  /// `BOOKING_ALREADY_ELAPSED` on reschedule/cancel (mapped to
  /// `BookingAlreadyElapsedFailure`). A device-clock rollback can therefore
  /// only soften this UI; it can never actually reschedule or cancel an elapsed
  /// booking.
  ///
  /// Compares absolute instants — [endAt] is canonical UTC and `DateTime.now()`
  /// is the device instant, and `isBefore` orders by microsecondsSinceEpoch
  /// regardless of each operand's zone. No Kyiv-pinned `toBeauticaTime`
  /// conversion is needed here: that pin governs wall-clock DISPLAY
  /// (`.hour`/`.minute`), not instant ORDERING, which is timezone-agnostic.
  bool get isPast => endAt.isBefore(DateTime.now());

  /// Whether this booking's START instant is already at-or-past the device
  /// clock — a PRESENTATION-ONLY signal for the PROVIDER footer (track 27.x
  /// Wave A).
  ///
  /// Mirrors the backend's Phase 27.1 `BookingTemporalGuard` predicates,
  /// which compare `startsAt` (never `endsAt`):
  ///   * `assertFutureForProviderCancel` — decline requires `now < startsAt`
  ///     (strictly future); once elapsed, 409.
  ///   * `assertElapsedForComplete` — complete requires `now >= startsAt`;
  ///     while still future, 409.
  ///   * `assertCurrentNotElapsedForReschedule` — the provider arm of
  ///     reschedule shares decline's predicate.
  ///
  /// This is deliberately a DIFFERENT field than [isPast] (which compares
  /// `endAt`, for the CLIENT's own elapsed-guard question — a client may act
  /// right up until the appointment has fully ENDED). Do not conflate the
  /// two or reuse [isPast] for the provider footer: a booking can be
  /// `hasStarted == true` while `isPast == false` (the appointment is
  /// currently underway), and the provider footer must show «Завершити», not
  /// «Перенести»/«Скасувати», for exactly that window.
  ///
  /// Like [isPast], this is UX-only — the SERVER clock is authoritative. A
  /// stale screen or a rolled-back device clock can still let a tap through
  /// to a 409 (`ProviderDeclineWindowClosedFailure` /
  /// `ProviderCompleteNotStartedFailure`), which the screen catches and
  /// resolves by refetching so the footer re-renders correctly.
  bool get hasStarted => !startAt.isAfter(DateTime.now());

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
