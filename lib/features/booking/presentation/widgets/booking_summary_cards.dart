// Phase 14.2 — BookingSummaryCards: the shared, read-only booking summary
// shown on the confirmation screen (one last read before sending) and the
// success screen (the confirmed recap under the celebration) of BOTH the
// independent-master AND the salon booking flows.
//
// Originally ported from `docs/signup-designs/BookingConfirmSuccess/lib/
// widgets/booking_details.dart` (`BookingSummaryCards`) for the independent
// flow alone, transcribed verbatim aside from two deliberate adaptations:
//   1. Took the real domain [Master] / [MasterService] directly instead of
//      the preview's flat name/role/rating/address strings — mirrors the
//      `MasterStrip` precedent (`widgets/master_strip.dart`).
//   2. The booked window's total minutes came straight from
//      `MasterService.durationMinutes` (an int already on hand) rather than
//      round-tripping through `BookingRecap`'s internal parsed-string totals.
//
// GENERALIZATION (salon booking rework): the widget's CORE constructor is now
// data-agnostic — it takes a prebuilt [masterCard] widget, plain
// [addressLine]/[addressDetail]/[dateLabel]/[timeLabel] strings, and a
// [selections] list, instead of a [Master]/[MasterService] pair. Two named
// factory constructors keep every EXISTING call site's rendering BYTE-FOR-
// BYTE IDENTICAL to before this change:
//   - [BookingSummaryCards.fromMaster] — the independent flow's original
//     `Master`/`MasterService`/`start` triple, still with the exact same
//     `Hero(tag: 'master-strip-<id>')` wrapper and the exact same
//     "street, buildingNo, city" address composition (now
//     [formatStreetCityLine], promoted to a shared formatter now that the
//     salon flow needs the identical join for a [Salon] — see that
//     formatter's own file for why it isn't typed to [Master]).
//   - [BookingSummaryCards.fromSchedule] — the salon flow's per-master
//     `SalonMasterSchedule`/`start` pair, feeding the SAME details card (no
//     `Hero` — the salon flow has no shared-element transition to continue
//     here). Defaults `showAddress` to `false`: a salon booking shows its ONE
//     shared salon address ONCE, above every appointment card, rather than
//     repeating it per master (see `salon_booking_confirm_screen.dart` /
//     `salon_booking_success_screen.dart`).
//
// A future change to the CORE widget (spacing, the details-card chrome, the
// Адреса/Дата/Час row order) now reaches BOTH flows automatically — that is
// the entire point of this generalization. Is the single source of truth for
// every screen that renders a booking recap so they can never drift.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/formatters/booking_date_labels.dart';
import 'package:beautica_mobile/shared/formatters/duration_minutes.dart';
import 'package:beautica_mobile/shared/formatters/service_price_display.dart';
import 'package:beautica_mobile/shared/formatters/street_city_line.dart';

import '../../domain/salon_master_schedule.dart';
import 'booking_recap.dart';
import 'labelled_row.dart';
import 'master_strip.dart';
import 'section_rule.dart';

/// The shared, read-only booking summary card stack.
///
/// 1. an optional **master card** ([masterCard]) — typically the same
///    [MasterStrip] context card rendered on the Step 2a/2b slot-picker
///    screens (`showRole: true, showRating: true`: avatar + name + muted role
///    + camel ★ rating), so the "who you're booking with" identity looks
///    identical across the whole booking flow instead of this screen
///    carrying its own bespoke header. `null` renders no master card at all
///    (the independent success screen; the salon confirm screen, which
///    builds its own bespoke `SalonAppointmentCard` instead of this widget).
/// 2. a **booking-details card** — a base-tone [NeumorphicCard] carrying the
///    optional Адреса row, the Дата / Час label→value rows, the flat
///    per-service [BookingRecap] table and its bold "Разом" total, divided by
///    thin hairline [SectionRule]s.
class BookingSummaryCards extends StatelessWidget {
  const BookingSummaryCards({
    super.key,
    this.masterCard,
    this.salonName,
    this.showAddress = true,
    this.addressLine,
    this.addressDetail,
    this.locationNote,
    this.hideAddressWhenEmpty = false,
    required this.dateLabel,
    required this.timeLabel,
    this.selections = const <BookingSelection>[],
    this.singleSelection,
    this.dense = false,
    this.showBorder = false,
    this.compactText = false,
    this.showPrice = true,
    this.trailingAction,
  });

  /// Builds the cards from the independent flow's [Master] / [MasterService]
  /// domain entities — byte-for-byte identical to this widget's original,
  /// pre-generalization rendering.
  factory BookingSummaryCards.fromMaster({
    Key? key,
    required Master master,
    required MasterService service,
    required DateTime start,
    bool showMasterCard = true,
    bool dense = false,
    bool showBorder = false,
    bool compactText = false,
  }) {
    final List<BookingSelection> selections = <BookingSelection>[
      BookingSelection(
        name: service.name,
        price: ServicePriceDisplay.format(service),
        duration: DurationMinutes.format(service.durationMinutes),
        // Typed fields so `BookingRecap`'s `_BookingTotals.from` sums the
        // real numeric values instead of regex-reparsing the two display
        // strings just built above (mobile-perf MEDIUM, Phase 14.18 audit).
        durationMinutes: service.durationMinutes,
        priceMin: service.priceMin,
        priceMax: service.priceMax,
      ),
    ];
    final String? addressLine = formatStreetCityLine(
      street: master.street,
      buildingNo: master.buildingNo,
      city: master.city,
    );
    final String? addressDetail =
        (master.locationNote?.trim().isNotEmpty ?? false)
        ? master.locationNote!.trim()
        : null;

    return BookingSummaryCards(
      key: key,
      // Hero (jank fix): continues the SAME `master-strip-<id>` shared-
      // element transition `SlotDateScreen`/`SlotTimeScreen` already fly
      // (`slot_picker_screen.dart`) — this card is the exact `MasterStrip`
      // instance those two screens' `Hero`-wrapped cards land on when the
      // client reaches `BookingConfirmScreen`.
      masterCard: showMasterCard
          ? Hero(
              tag: 'master-strip-${master.id}',
              child: MasterStrip.fromMaster(
                master,
                showRole: true,
                showRating: true,
              ),
            )
          : null,
      addressLine: addressLine,
      addressDetail: addressDetail,
      dateLabel: formatFullDate(start),
      timeLabel: formatTimeRange(start, service.durationMinutes),
      selections: selections,
      dense: dense,
      showBorder: showBorder,
      compactText: compactText,
    );
  }

  /// Builds the cards from the salon flow's per-master [SalonMasterSchedule]
  /// — the success screen's per-appointment recap card. Unlike
  /// [BookingSummaryCards.fromMaster], the master card here is NOT
  /// `Hero`-wrapped (the salon flow has no shared-element transition to
  /// continue) and [showAddress] defaults to `false` (the salon success
  /// screen shows its one shared salon address ONCE, above every appointment
  /// card, rather than repeating it per master).
  factory BookingSummaryCards.fromSchedule({
    Key? key,
    required SalonMasterSchedule schedule,
    required DateTime start,
    required List<Color> avatarGradient,
    bool showMasterCard = true,
    bool showAddress = false,
    String? addressLine,
    String? addressDetail,
    bool dense = false,
    bool showBorder = false,
    bool compactText = false,
  }) {
    final List<BookingSelection> selections = schedule.services
        .map(BookingSelection.fromSalonCatalogService)
        .toList();

    return BookingSummaryCards(
      key: key,
      masterCard: showMasterCard
          ? MasterStrip.fromSchedule(
              schedule,
              showRole: true,
              showRating: true,
              avatarGradient: avatarGradient,
              avatarBordered: true,
            )
          : null,
      showAddress: showAddress,
      addressLine: addressLine,
      addressDetail: addressDetail,
      dateLabel: formatFullDate(start),
      timeLabel: formatTimeRange(start, schedule.summedDurationMinutes),
      selections: selections,
      dense: dense,
      showBorder: showBorder,
      compactText: compactText,
    );
  }

  /// Prebuilt master-identity card widget — a [Hero]-wrapped [MasterStrip]
  /// for the independent flow, a bare [MasterStrip] for the salon flow (see
  /// the two factory constructors). `null` renders no master card at all.
  final Widget? masterCard;

  /// Phase 14.3 addition — an optional «Салон» row, rendered above «Адреса»
  /// (closed by its own [SectionRule]). Null for an independent-master
  /// booking — no row built at all, never an empty one.
  ///
  /// The booking-FLOW screens (`fromMaster` / `fromSchedule`) never set this:
  /// mid-flow the client already knows which salon they're in. «Деталі
  /// запису», looked up months later, does not — a salon is a *party to the
  /// appointment* and belongs with identity, not with the address.
  final String? salonName;

  /// Whether to render the Адреса row at all. Defaults to `true` (every
  /// pre-generalization call site's original behaviour). The salon success
  /// screen's PER-APPOINTMENT cards set this `false` since the shared salon
  /// address is already shown ONCE, separately, above the appointment list.
  final bool showAddress;

  /// The composed "street, buildingNo, city" address line, or `null` to fall
  /// back to [AppLocalizations.bookingAddressUnknown] (or, when
  /// [hideAddressWhenEmpty] is `true`, to omit the whole block). Ignored
  /// entirely when [showAddress] is `false`.
  final String? addressLine;

  /// An optional muted sub-line under the address (e.g. a locality note).
  /// Ignored entirely when [showAddress] is `false`.
  final String? addressDetail;

  /// Phase 14.3 addition — the provider's free-text arrival hint («3-й
  /// поверх, код на дверях 1234»), rendered via [ArrivalNote] directly under
  /// the address, inside the SAME [SectionRule]-closed block (no rule
  /// between them — it is the last thing you read before setting off). Null
  /// (the common case — most providers never write one) builds nothing.
  ///
  /// NOT part of the composed address — `composeAddressLine` /
  /// `formatStreetCityLine` must never see this field. It is an
  /// *instruction*, not a postal address; see [ArrivalNote]'s doc for the
  /// full "three registers" reasoning.
  final String? locationNote;

  /// Phase 14.3 addition — when `true`, the entire Адреса block (row +
  /// [locationNote] + its closing [SectionRule]) is omitted when
  /// [addressLine] is `null`, instead of falling back to
  /// [AppLocalizations.bookingAddressUnknown]. Defaults to `false` (every
  /// pre-existing booking-FLOW call site is unaffected — mid-flow the
  /// address is always known, so the fallback string is dead code there
  /// anyway). «Деталі запису» opts in: a provider with genuinely no address
  /// on file gets no row at all, not a "не вказано" placeholder — mirrors
  /// every other optional field on this card (see [salonName]).
  final bool hideAddressWhenEmpty;

  /// The chosen appointment date, already formatted (e.g. "понеділок, 14
  /// липня" via [formatFullDate]).
  final String dateLabel;

  /// The chosen appointment time range, already formatted (e.g.
  /// "14:00–15:30" via [formatTimeRange]).
  final String timeLabel;

  /// The service(s) rendered by the inner [BookingRecap] — a single-element
  /// list for the independent flow ([BookingSummaryCards.fromMaster]), the
  /// master's full assigned-service list for the salon flow
  /// ([BookingSummaryCards.fromSchedule]). Ignored when [singleSelection] is
  /// set.
  final List<BookingSelection> selections;

  /// Phase 14.3 addition — «Деталі запису»'s single-booking mode. **A
  /// booking has exactly ONE service** — see `BookingRecap.single`'s doc for
  /// why a single-element [selections] list is the wrong shape (it would
  /// still render the "N послуг" count / dividers / "Разом" total built for
  /// a multi-service SELECTION). When set, [selections] is ignored and the
  /// recap renders via [BookingRecap.single].
  final BookingSelection? singleSelection;

  /// Compact spacing — tighter details-card padding + section-rule gaps —
  /// so the success screens fit one viewport without excess scroll. The
  /// confirmation screens leave it `false` (the roomier default).
  final bool dense;

  /// Forwarded to the details [NeumorphicCard]'s `showBorder` — adds a
  /// subtle hairline stroke so the card reads as a distinct shape even when
  /// its fill exactly matches the surrounding background. Defaults to
  /// `false` (the confirmation screen's card sits on a different background
  /// and doesn't need it); the success screens opt in — see
  /// `NeumorphicCard.showBorder`'s doc for why.
  final bool showBorder;

  /// Shrinks the card's row text a further notch (address/date/time labels +
  /// values, plus the forwarded [BookingRecap] row/total text) on top of
  /// [dense]'s spacing tightening, so the whole success page needs less
  /// scroll room. Deliberately a SEPARATE flag from [dense]: `dense` is
  /// shared for spacing only — only the success screens opt into
  /// [compactText] too. Defaults to `false`.
  final bool compactText;

  /// Phase 14.3 addition — forwarded to [BookingRecap]/[BookingRecap.single].
  /// Whether money is a true statement about this card at all (see
  /// `Booking.showsPrice`). The booking-FLOW screens always have a price and
  /// leave this at the default `true`; «Деталі запису» sets it `false` on a
  /// cancelled / declined / missed booking.
  final bool showPrice;

  /// An optional action rendered as the details card's LAST block, below the
  /// price recap and behind its own [SectionRule] — the booking-success
  /// screen's per-appointment «Додати в календар» pill.
  ///
  /// It lives INSIDE the card on purpose. This card's whole grammar is
  /// "hairline rules separate the blocks of ONE appointment's facts", so an
  /// action placed in that rhythm is unmistakably scoped to THAT appointment
  /// — the entire point when a multi-service success recap stacks N of these
  /// cards and each carries its own calendar export. Floated BELOW the card
  /// instead, on the bare taupe base, it would read as a page-level control
  /// again, which is exactly the ambiguity the old single page-level pill
  /// below the recap had.
  ///
  /// `null` (every other call site — both confirm screens, the salon success
  /// screen, «Деталі запису») renders nothing at all: no rule, no gap.
  final Widget? trailingAction;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    final bool renderAddress =
        showAddress && !(hideAddressWhenEmpty && addressLine == null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (masterCard != null) ...<Widget>[
          masterCard!,
          const SizedBox(height: VelvetSpacing.md),
        ],
        NeumorphicCard(
          padding: EdgeInsets.all(
            dense ? VelvetSpacing.sm + 4 : VelvetSpacing.md,
          ),
          showBorder: showBorder,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (salonName != null) ...<Widget>[
                LabelledRow(
                  label: l10n.bookingSalonLabel,
                  value: salonName!,
                  compactText: compactText,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                SectionRule(dense: dense),
              ],
              if (renderAddress) ...<Widget>[
                LabelledRow(
                  label: l10n.bookingAddressLabel,
                  value: addressLine ?? l10n.bookingAddressUnknown,
                  detail: addressDetail,
                  compactText: compactText,
                ),
                if (locationNote != null) ...<Widget>[
                  const SizedBox(height: VelvetSpacing.sm),
                  ArrivalNote(text: locationNote!),
                ],
                SectionRule(dense: dense),
              ],
              LabelledRow(
                label: l10n.bookingDateLabel,
                value: dateLabel,
                compactText: compactText,
              ),
              SizedBox(height: dense ? VelvetSpacing.sm : VelvetSpacing.sm + 4),
              LabelledRow(
                label: l10n.bookingTimeLabel,
                value: timeLabel,
                compactText: compactText,
              ),
              SectionRule(dense: dense),
              singleSelection != null
                  ? BookingRecap.single(
                      selection: singleSelection!,
                      dense: dense,
                      compactText: compactText,
                      showPrice: showPrice,
                    )
                  : BookingRecap(
                      selections: selections,
                      dense: dense,
                      compactText: compactText,
                      showPrice: showPrice,
                    ),
              if (trailingAction != null) ...<Widget>[
                SectionRule(dense: dense),
                trailingAction!,
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Phase 14.3 — the provider's **arrival hint**: «3-й поверх, код на дверях
/// 1234», «вхід з двору, дзвонити двічі».
///
/// ## The third register
///
/// «Деталі запису» carries three *kinds* of text, and each announces which
/// kind it is structurally, before a word is read:
///
///   * **A fact** — the app stating a field: a muted [LabelledRow] label
///     above a strong value (Салон · Адреса · Дата · Час · Послуга).
///   * **An instruction** — a property of the place: a glyph, no label, no
///     container. *This widget.*
///   * **Correspondence** — a human's words: an author heading + a container
///     (recessed well = received, hairline rule = sent).
///
/// This note is emphatically the middle row: it is not addressed to anyone
/// and nobody is speaking to the client — a door code is as impersonal as
/// the street name. So it gets NEITHER note container (the recessed well /
/// hairline rule are the only carriers of the sent/received distinction on
/// the page; spending one on a building's entry code would blunt that
/// signal) and NO author heading (there is no author to name). What it gets
/// instead is a **door glyph** — wayfinding signage, not speech.
///
/// Set in `body()` (12 sp / textSecondary), one notch above the address's
/// muted 11 sp coarse-locator sub-line, because it is the one line on the
/// page you might act on while standing in the street. The glyph is mocha
/// (`accentDeep`) — the brand's "something for you to do" colour.
///
/// ## No clamp — deliberately
///
/// The correspondence notes ([InboundNote]/[OutboundNote] in
/// `booking_notes.dart`) clamp to 6 lines because they run to 1000 chars.
/// This one does **not** clamp at all: it wraps freely and is never
/// truncated. An arrival hint is short by nature, and it is the one string
/// on this page where an ellipsis could genuinely strand somebody at a
/// locked door — «3-й поверх, код на дверях…» is worse than useless.
class ArrivalNote extends StatelessWidget {
  const ArrivalNote({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      label: l10n.bookingArrivalNoteSemantics(text),
      excludeSemantics: true,
      child: Row(
        key: const Key('arrival-note'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(
              Icons.meeting_room_outlined,
              size: 14,
              color: BrandColors.accentDeep,
            ),
          ),
          const SizedBox(width: VelvetSpacing.xs),
          Expanded(child: Text(text, style: VelvetText.body())),
        ],
      ),
    );
  }
}
