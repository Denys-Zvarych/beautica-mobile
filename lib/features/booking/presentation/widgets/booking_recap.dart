// Phase 14.2 — BookingRecap: the "Послуги" + "Разом" table shared by the
// booking confirmation and success summary cards.
//
// Ported from `docs/signup-designs/BookingConfirmSuccess/lib/widgets/
// booking_summary.dart` (`BookingSelection` + `BookingRecap` + the
// `_BookingTotals`/`_parsePrice`/[parseDurationMinutes] helpers), transcribed
// verbatim aside from the token-name swap (`VelvetColors` → [BrandColors];
// `VelvetSpacing`/`VelvetText` already share the exact same names in this
// project's `core/theme/`).
//
// SCOPE NOTE (independent-master flow): the Phase 14.0 data layer + Phase
// 14.1 slot-picker/confirm-args scope boundary (see `slot_picker_screen.dart`'s
// file header) locks booking creation to exactly ONE service per booking, so
// `BookingSummaryCards.fromMaster` always feeds this widget a SINGLE-element
// `selections` list there.
//
// MULTI-SERVICE SCOPE UPDATE (salon booking rework): the salon flow's
// N-master model is a REAL multi-item caller — each assigned master can carry
// 2+ services, so `SalonAppointmentCard` and `BookingSummaryCards.fromSchedule`
// feed this widget that master's FULL assigned-service list. The multi-item
// rendering path (hairline dividers between rows, the plural "N послуги"
// count) is therefore exercised in production on the salon flow, not merely
// "kept faithful to the approved design" as a dormant fallback the way it was
// before this rework.
//
// [totalOnly] adds a second render mode: the salon confirm/success screens'
// GRAND total (summing every service across every appointed master) reuses
// this widget's exact `_TotalRow`/[_BookingTotals] treatment instead of
// re-implementing a second "Разом" band from scratch — see [totalOnly]'s own
// doc comment.
//
// Pure widget/presentation logic — no Riverpod, no networking. [selection]
// display strings are built by the call site: the independent flow derives
// them from the real domain [MasterService] via the existing
// `ServicePriceDisplay.format` / `DurationMinutes.format` formatters, while
// the salon flow derives them from a [SalonCatalogService] via
// [BookingSelection.fromSalonCatalogService] — that type's `priceDisplay` /
// `durationLabel` are ALREADY server/mapper-formatted display strings (see
// `salon_service_catalog.dart`'s file header), so no separate formatter call
// is needed there. Both sources are compatible with the [_parsePrice] /
// [parseDurationMinutes] round-trip parsing below.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/features/salon/domain/salon_service_catalog.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/formatters/booking_price_labels.dart';
import 'package:beautica_mobile/shared/formatters/service_count_label.dart';

/// One selected service carried into the booking recap. [price] is a
/// *display* string and may be a single value ("500 ₴") OR a hyphenated
/// range ("200 - 600 ₴"); [duration] is a display string ("1 год 30 хв",
/// "3 год") — both built by the call site via the shared formatters.
@immutable
class BookingSelection {
  const BookingSelection({
    required this.name,
    required this.price,
    required this.duration,
    this.durationMinutes,
    this.priceMin,
    this.priceMax,
  });

  /// Builds a selection straight from a salon catalogue service. Its
  /// [SalonCatalogService.priceDisplay] / [SalonCatalogService.durationLabel]
  /// are already server/mapper-formatted display strings (see
  /// `salon_service_catalog.dart`'s file header) — unlike the independent
  /// flow's [MasterService], which routes through `ServicePriceDisplay.format`
  /// / `DurationMinutes.format` at its own call site, no formatter call is
  /// needed here. Also carries the catalogue's typed [durationMinutes] /
  /// [priceMin] / [priceMax] straight through so [_BookingTotals.from] can sum
  /// them directly instead of regex-reparsing [price] / [duration] (mobile-
  /// perf MEDIUM, Phase 14.18 salon-confirm audit).
  BookingSelection.fromSalonCatalogService(SalonCatalogService service)
    : name = service.name,
      price = service.priceDisplay,
      duration = service.durationLabel,
      durationMinutes = service.durationMinutes,
      priceMin = service.priceMin,
      priceMax = service.priceMax;

  /// Service name, e.g. "Манікюр з покриттям".
  final String name;

  /// Price display string — single ("500 ₴") or ranged ("200 - 600 ₴").
  final String price;

  /// Duration display string, e.g. "1 год 30 хв" or "3 год".
  final String duration;

  /// Typed duration in minutes, mirroring [duration] — when present,
  /// [_BookingTotals.from] sums this directly instead of regex-parsing
  /// [duration]. `null` for a caller that only has the display string (e.g.
  /// an older fixture), which falls back to [parseDurationMinutes].
  final int? durationMinutes;

  /// Typed price floor in UAH, mirroring [price] — when present,
  /// [_BookingTotals.from] sums this (and [priceMax]) directly instead of
  /// regex-parsing [price]. `null` falls back to [_parsePrice].
  final double? priceMin;

  /// Typed price ceiling in UAH for a RANGE-priced service; `null` for a
  /// FIXED-priced service (where [priceMin] alone is the price) or when the
  /// caller only has the display string.
  final double? priceMax;
}

/// The "Послуги" multi-service list + "Разом" total, rendered as a flat,
/// scannable table. Each picked service is a single text row — name + muted
/// duration on the left, price pinned right — divided from the next by a thin
/// hairline. Below a slightly stronger hairline the bold "Разом" line carries
/// the SUMMED price band and SUMMED duration.
class BookingRecap extends StatelessWidget {
  const BookingRecap({
    super.key,
    required this.selections,
    this.dense = false,
    this.compactText = false,
    this.totalOnly = false,
    this.showPrice = true,
  }) : _single = null;

  /// Phase 14.3 — «Деталі запису» single-booking mode. **A booking has
  /// exactly ONE service** (`Booking` carries a single `masterServiceId` /
  /// `serviceName` / `priceAtBooking`) — the multi-row «Послуги» table + «N
  /// послуг» count + dividers + «Разом» total below are the SELECTION
  /// screen's shape (the salon flow lets a client pick several services in
  /// one sitting, which becomes several *bookings*, not one booking with
  /// several services). Mirroring that table here would be the app counting
  /// to one.
  ///
  /// So this constructor renders ONLY: a singular [l10n.bookingServiceLabel]
  /// heading (no count) above one [_ServiceRow] — no dividers, no total row.
  /// [showPrice] lets the detail page suppress money on the statuses where it
  /// is not a true statement (cancelled / declined / a no-show — see
  /// `Booking.showsPrice`); the booking-FLOW screens always have a price and
  /// leave it at the default `true`.
  const BookingRecap.single({
    super.key,
    required BookingSelection selection,
    this.dense = false,
    this.compactText = false,
    this.showPrice = true,
  }) : _single = selection,
       selections = const <BookingSelection>[],
       totalOnly = false;

  /// The services carried from the selection step (1..n — see file header
  /// MULTI-SERVICE SCOPE UPDATE for which flow/call site feeds >1). Ignored
  /// when this was built via [BookingRecap.single].
  final List<BookingSelection> selections;

  /// Set only by [BookingRecap.single] — the booking's one service. `null`
  /// for the ordinary multi/list mode.
  final BookingSelection? _single;

  /// Compact spacing — tighter service rows — so the success screen fits one
  /// viewport without scrolling. The confirmation screen leaves it `false`.
  final bool dense;

  /// Shrinks the "Послуги" header, service rows, and "Разом" total a further
  /// notch on top of [dense]'s spacing tightening. Deliberately separate from
  /// [dense] — see `BookingSummaryCards.compactText`'s doc: `dense` is shared
  /// by both the confirm and success screens for spacing only, while
  /// [compactText] is opted into by the success screen alone. Defaults to
  /// `false`.
  final bool compactText;

  /// Renders ONLY the bold "Разом" total row — no "Послуги" header, no
  /// per-service rows, no hairline dividers. The salon booking confirm/
  /// success screens use this for the GRAND total across every appointed
  /// master's services: it needs the exact same summed-price-band +
  /// summed-duration treatment [_TotalRow] already gives a single
  /// appointment's own subtotal, without duplicating [_BookingTotals]'s
  /// parse/sum logic in a second widget. Defaults to `false` (the existing
  /// full "Послуги" + "Разом" rendering, unaffected).
  final bool totalOnly;

  /// Whether money is a true statement here at all — forwarded to every
  /// [_ServiceRow] (single AND list mode) and to the "Разом" total. The
  /// booking-FLOW screens always have a price (you're mid-agreement to it)
  /// and leave this at the default `true`; «Деталі запису» sets it `false`
  /// on a cancelled / declined / missed booking (see `Booking.showsPrice`) —
  /// printing a sum there would assert a debt that does not exist.
  final bool showPrice;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    final BookingSelection? single = _single;
    if (single != null) {
      // Phase 14.3 single-booking mode — see the constructor's doc.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            l10n.bookingServiceLabel,
            style: compactText ? VelvetText.label11 : VelvetText.label(),
          ),
          const SizedBox(height: VelvetSpacing.xs),
          _ServiceRow(
            selection: single,
            dense: dense,
            compactText: compactText,
            showPrice: showPrice,
          ),
        ],
      );
    }

    final _BookingTotals totals = _BookingTotals.from(selections);
    final Widget totalRow = _TotalRow(
      label: l10n.bookingTotalLabel,
      // Gated on [showPrice] for the same reason [_ServiceRow]'s label is: the
      // semantics tree is a readable surface, so announcing a suppressed
      // «Разом» band would leak exactly what the visual gate suppresses.
      semanticsLabel: showPrice
          ? l10n.bookingTotalSemantics(
              totals.durationLabel ?? '',
              totals.priceLabel,
            )
          : l10n.bookingTotalSemanticsNoPrice(totals.durationLabel ?? ''),
      price: showPrice ? totals.priceLabel : null,
      duration: totals.durationLabel,
      compactText: compactText,
    );

    if (totalOnly) return totalRow;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(
              l10n.bookingServicesRecapLabel,
              style: compactText ? VelvetText.label11 : VelvetText.label(),
            ),
            const Spacer(),
            Text(
              formatServiceCountUk(selections.length),
              style: compactText
                  ? VelvetText.feedbackMutedXs
                  : VelvetText.feedbackMutedSm,
            ),
          ],
        ),
        const SizedBox(height: VelvetSpacing.xs),
        for (int i = 0; i < selections.length; i++) ...<Widget>[
          _ServiceRow(
            selection: selections[i],
            dense: dense,
            compactText: compactText,
            showPrice: showPrice,
          ),
          if (i < selections.length - 1)
            Divider(
              height: 1,
              thickness: 1,
              color: BrandColors.faint.withValues(alpha: 0.32),
            ),
        ],
        SizedBox(height: dense ? VelvetSpacing.xs + 2 : VelvetSpacing.sm),
        Container(height: 1, color: BrandColors.faint.withValues(alpha: 0.6)),
        SizedBox(height: dense ? VelvetSpacing.sm : VelvetSpacing.sm + 2),
        totalRow,
      ],
    );
  }
}

/// One flat service row — the service name (espresso, ellipsised) with its
/// muted duration on a tight sub-line, and the price pinned right in
/// camel/bold (single value or range). No background, no chip, no inset:
/// just text.
class _ServiceRow extends StatelessWidget {
  const _ServiceRow({
    required this.selection,
    this.dense = false,
    this.compactText = false,
    this.showPrice = true,
  });

  final BookingSelection selection;
  final bool dense;

  /// See [BookingRecap.compactText] — shrinks the name/duration/price text a
  /// further notch (success screen only).
  final bool compactText;

  /// See [BookingRecap.showPrice]. `false` on «Деталі запису» for a
  /// cancelled / declined / missed booking — the price is simply not built,
  /// and the name column takes the full width (no reserved gap, no "—").
  ///
  /// It gates the SEMANTICS label as well as the visual [Text], via the
  /// price-less `bookingServiceTileSemanticsNoPrice` variant. Announcing a
  /// suppressed price would be a real leak, not a cosmetic mismatch: the
  /// semantics tree is a readable surface (TalkBack/VoiceOver, and any
  /// accessibility-service app on the device), so a screen reader would have
  /// read out «300–500 ₴» for a booking whose whole point is that no money is
  /// owed. The accessibility tree must state exactly what the visual tree
  /// states — keep the two gated on this one flag.
  final bool showPrice;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      label: showPrice
          ? l10n.bookingServiceTileSemantics(
              selection.name,
              selection.duration,
              selection.price,
            )
          : l10n.bookingServiceTileSemanticsNoPrice(
              selection.name,
              selection.duration,
            ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          vertical: dense ? VelvetSpacing.xs + 1 : VelvetSpacing.sm,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    selection.name,
                    style: compactText
                        ? VelvetText.bodyStrong13
                        : VelvetText.bodyStrong145,
                  ),
                  const SizedBox(height: 1),
                  Text(
                    selection.duration,
                    style: compactText
                        ? VelvetText.feedbackMutedXs
                        : VelvetText.feedbackMutedSm,
                  ),
                ],
              ),
            ),
            if (showPrice) ...<Widget>[
              const SizedBox(width: VelvetSpacing.md),
              Text(
                selection.price,
                style: compactText
                    ? VelvetText.bookAccentBold135
                    : VelvetText.bookAccentBold15,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The bold "Разом" total line: [label] (left) with the muted total
/// [duration] beside it (the appointment length), and the summed [price] on
/// the right in camel/bold (a range when any per-service price was a range).
///
/// ## Why the row is flexible (the 320 dp × 2.0 overflow)
///
/// Every one of the three texts used to be an UNFLEXED child of a `Row` whose
/// only elastic member was a `Spacer`. A `Spacer` only ever *donates* space, so
/// once the three intrinsic widths summed past the card, the row had no way to
/// give: on the booking-success grand-total card at 320 dp × textScaler 2.0 the
/// card offers 248 dp of content width while «Разом» (70.1) + `sm` gap (8) +
/// «2 год 15 хв» (121.7) + «1200 ₴» (83.3) want 283.1 — a hard
/// `RenderFlex overflowed by 35 pixels on the right`.
///
/// The row now states an explicit order of sacrifice:
///   * **[price] never yields.** It is the number the client is agreeing to;
///     truncating or shrinking it is not an option at any scale, so it stays
///     an unflexed child (laid out at its intrinsic width first) and merely
///     carries a `sm` left padding as its minimum gap.
///   * **[duration] wraps.** It is the only member that can lose a line break
///     without losing information — «2 год 15 хв» becomes two lines rather than
///     an ellipsis, so no minute is ever hidden.
///   * **[label] holds its intrinsic width**, as the row's anchor word.
///
/// `MainAxisAlignment.spaceBetween` replaces the old `Spacer`: a `Spacer` is an
/// `Expanded`, so leaving it in place would have split the free space with the
/// flexible left group instead of yielding it. With `spaceBetween` the loose
/// left group takes only what it needs and the surplus still pushes the price
/// hard against the right margin — byte-identical placement at ordinary text
/// scales, elastic only once the row genuinely runs out of room.
class _TotalRow extends StatelessWidget {
  const _TotalRow({
    required this.label,
    required this.semanticsLabel,
    required this.price,
    required this.duration,
    this.compactText = false,
  });

  final String label;
  final String semanticsLabel;

  /// `null` when [BookingRecap.showPrice] is `false` — the band is simply not
  /// built, exactly as [_ServiceRow] drops its own price. Not an empty string
  /// and not a placeholder: «Деталі запису» on a cancelled / declined / missed
  /// booking must assert no sum at all, and the caller has already swapped the
  /// [semanticsLabel] for the price-less variant to match.
  final String? price;
  final String? duration;

  /// See [BookingRecap.compactText] — shrinks the total row's text a further
  /// notch (success screen only).
  final bool compactText;

  @override
  Widget build(BuildContext context) {
    final String? durationLabel = duration;
    final String? priceLabel = price;
    return Semantics(
      label: semanticsLabel,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        // Stands in for the row's former trailing `Spacer` — see the class doc.
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Flexible(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: <Widget>[
                Text(
                  label,
                  style: compactText
                      ? VelvetText.bookName145w800
                      : VelvetText.bookName16w800,
                ),
                if (durationLabel != null) ...<Widget>[
                  const SizedBox(width: VelvetSpacing.sm),
                  // The one member allowed to give: it WRAPS (no `maxLines`,
                  // no ellipsis) so a squeezed «2 год 15 хв» costs a line, not
                  // a minute.
                  Flexible(
                    child: Text(
                      durationLabel,
                      style: compactText
                          ? VelvetText.feedbackMutedXs
                          : VelvetText.feedbackMutedSm,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (priceLabel != null)
            Padding(
              // Minimum breathing room once the left group expands to fill —
              // NOT a second `SizedBox` child, which `spaceBetween` would turn
              // into a second gap and unpin the price from the right margin.
              padding: const EdgeInsets.only(left: VelvetSpacing.sm),
              child: Text(
                priceLabel,
                style: compactText
                    ? VelvetText.bookAccentBold155
                    : VelvetText.bookPriceMd,
              ),
            ),
        ],
      ),
    );
  }
}

/// Aggregated totals derived from the carried services. Prices are summed as
/// a (low, high) band so any ranged price carries through to the total; when
/// the band collapses (low == high) the label is a single value. Durations
/// are summed in minutes and re-formatted to Ukrainian "X год Y хв".
///
/// ## The label is built by the SHARED formatter, and every term is gated
///
/// This used to coerce the wire doubles to `int` (`.round()`) and hand-build
/// its own `'$minSum–$maxSum ₴'` — a third private copy of conventions
/// `booking_price_labels.dart` already owns, and one that sat OUTSIDE that
/// family's [isRenderablePrice] gate. [BookingSelection.priceMin]/[priceMax]
/// are unclamped wire doubles (`master_service_mapper.dart` and
/// `salon_mapper.dart` both pass the decoded value straight through, and
/// `jsonDecode('1e400')` yields `double.infinity` without throwing), so the
/// coercion failed two ways:
///
///   * `double.infinity.round()` / `double.nan.round()` THROW
///     (`UnsupportedError: Infinity or NaN toInt`). This runs inside
///     [BookingRecap.build], so the booking confirm / success / salon-confirm
///     screen degraded to an error widget.
///   * `(1e30).round()` does NOT throw — it saturates to int64 max. One such
///     service rendered «9223372036854775807 ₴»; two wrapped `minSum +=`
///     around to a NEGATIVE total («-2 ₴») on the very screen where the
///     client is agreeing to a price.
///
/// So the sums stay `double` (no saturation, no wrap) and the label comes
/// from [formatBookingTotalsFromTerms] — the same en-dash/«₴» conventions, the
/// same guard, one copy, and the per-TERM gate applied on the way into the
/// accumulator. That per-term gate lives in the shared formatter rather than
/// here because all four «Разом» surfaces need it identically; see its doc for
/// why `+` is not protective and why an unstatable term poisons the whole band
/// instead of being dropped.
class _BookingTotals {
  const _BookingTotals({required this.priceLabel, required this.durationLabel});

  final String priceLabel;
  final String? durationLabel;

  factory _BookingTotals.from(List<BookingSelection> selections) {
    final ({String priceLabel, String? durationLabel}) totals =
        formatBookingTotalsFromTerms(
          selections.map((BookingSelection s) {
            // Prefer the typed fields (populated by every current call site —
            // see `BookingSelection.fromSalonCatalogService` /
            // `BookingSummaryCards.fromMaster`); regex-reparsing the display
            // strings is kept ONLY as a fallback for a selection built without
            // them (e.g. an older fixture), per-selection so a mixed list still
            // sums correctly.
            final double? typedMin = s.priceMin;
            if (typedMin != null) {
              return (
                min: typedMin,
                max: s.priceMax ?? typedMin,
                minutes: s.durationMinutes ?? parseDurationMinutes(s.duration),
              );
            }
            final (int parsedLo, int parsedHi) = _parsePrice(s.price);
            return (
              min: parsedLo.toDouble(),
              max: parsedHi.toDouble(),
              minutes: s.durationMinutes ?? parseDurationMinutes(s.duration),
            );
          }),
        );
    return _BookingTotals(
      priceLabel: totals.priceLabel,
      durationLabel: totals.durationLabel,
    );
  }
}

/// Parses a price display string into a (low, high) pair. "500 ₴" → (500,
/// 500); a ranged "200 - 600 ₴" / "200–600 ₴" → (200, 600).
(int, int) _parsePrice(String price) {
  final List<int> nums = RegExp(
    r'\d+',
  ).allMatches(price).map((Match m) => int.parse(m.group(0)!)).toList();
  if (nums.isEmpty) return (0, 0);
  if (nums.length == 1) return (nums.first, nums.first);
  return (nums.first, nums[1]);
}

/// Parses a duration display string ("1 год 30 хв", "3 год") into total
/// minutes. Public so [BookingSummaryCards] can derive the appointment's
/// booked window without a second parallel computation.
int parseDurationMinutes(String duration) {
  int minutes = 0;
  final RegExpMatch? h = RegExp(r'(\d+)\s*год').firstMatch(duration);
  final RegExpMatch? m = RegExp(r'(\d+)\s*хв').firstMatch(duration);
  if (h != null) minutes += int.parse(h.group(1)!) * 60;
  if (m != null) minutes += int.parse(m.group(1)!);
  return minutes;
}
