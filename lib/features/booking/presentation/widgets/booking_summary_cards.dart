// Phase 14.2 — BookingSummaryCards: the shared, read-only booking summary
// shown on BOTH the confirmation screen (one last read before sending) and
// the success screen (the confirmed recap under the celebration).
//
// Ported from `docs/signup-designs/BookingConfirmSuccess/lib/widgets/
// booking_details.dart` (`BookingSummaryCards`), transcribed verbatim aside
// from two deliberate adaptations:
//   1. Takes the real domain [Master] / [MasterService] directly instead of
//      the preview's flat name/role/rating/address strings — mirrors the
//      existing `MasterStrip` precedent in this feature
//      (`widgets/master_strip.dart`'s header: "Takes the domain Master
//      directly ... so every call site derives the display name + role label
//      the exact same way").
//   2. The booked window's total minutes come straight from
//      `MasterService.durationMinutes` (an int already on hand) rather than
//      round-tripping through `BookingRecap`'s internal parsed-string totals
//      — avoids depending on a string-parse for a value the domain layer
//      already has as a typed int. `BookingRecap`'s own "Разом" total row
//      still performs its own (verbatim, preview-identical) parse/sum for
//      RENDERING, since with a single service that total is always exactly
//      consistent with the domain int by construction.
//
// Is the single source of truth for BOTH the confirm and success screens so
// they can never drift — a caller only passes the raw booking (master,
// service, start).

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

import 'booking_recap.dart';
import 'master_strip.dart';

/// The shared, read-only booking summary card stack.
///
/// 1. an optional **master card** — the same [MasterStrip] context card
///    rendered on the Step 2a/2b slot-picker screens (`showRole: true,
///    showRating: true`: avatar + name + muted role + camel ★ rating), so the
///    "who you're booking with" identity looks identical across the whole
///    booking flow instead of this screen carrying its own bespoke header.
///    Hidden via [showMasterCard] on the success screen (the client just
///    chose the master — the recap there focuses on the appointment).
/// 2. a **booking-details card** — a base-tone [NeumorphicCard] carrying the
///    Адреса / Дата / Час label→value rows, the flat per-service
///    [BookingRecap] table and its bold "Разом" total, divided by thin
///    hairline [_SectionRule]s.
class BookingSummaryCards extends StatelessWidget {
  const BookingSummaryCards({
    super.key,
    required this.master,
    required this.service,
    required this.start,
    this.showMasterCard = true,
    this.dense = false,
  });

  /// The target master, rendered by the (optional) master card.
  final Master master;

  /// The single booked service (Phase 14.0/14.1 scope boundary — see
  /// `booking_recap.dart`'s file header). Rendered as a 1-item
  /// [BookingRecap] list.
  final MasterService service;

  /// The chosen appointment start (date + clock time).
  final DateTime start;

  /// Whether to lead with the soft `#EDE4D5` master card. The confirmation
  /// screen shows it; the success screen hides it.
  final bool showMasterCard;

  /// Compact spacing — tighter section rules + service rows — so the success
  /// screen fits in one viewport without scrolling. The confirmation screen
  /// leaves it `false` (its approved, roomier spacing).
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final String dateLabel = formatFullDate(start);
    final String timeLabel = formatTimeRange(start, service.durationMinutes);
    final List<BookingSelection> selections = <BookingSelection>[
      BookingSelection(
        name: service.name,
        price: ServicePriceDisplay.format(service),
        duration: DurationMinutes.format(service.durationMinutes),
      ),
    ];
    final String? addressLine = _masterAddressLine(master);
    final String? addressDetail =
        (master.locationNote?.trim().isNotEmpty ?? false)
        ? master.locationNote!.trim()
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (showMasterCard) ...<Widget>[
          // Hero (jank fix): continues the SAME `master-strip-<id>` shared-
          // element transition `SlotDateScreen`/`SlotTimeScreen` already fly
          // (`slot_picker_screen.dart`) — this card is the exact `MasterStrip`
          // instance those two screens' `Hero`-wrapped cards land on when the
          // client reaches `BookingConfirmScreen`. Without this wrapper the
          // card used to just swap in unanimated the instant the push
          // transition settled, at a slightly different y-offset (see
          // `BookingConfirmScreen`'s own top-bar/scroll-padding normalization
          // in the same pass).
          Hero(
            tag: 'master-strip-${master.id}',
            child: MasterStrip(
              master: master,
              showRole: true,
              showRating: true,
            ),
          ),
          const SizedBox(height: VelvetSpacing.md),
        ],
        NeumorphicCard(
          padding: EdgeInsets.all(
            dense ? VelvetSpacing.sm + 4 : VelvetSpacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _LabelledRow(
                label: l10n.bookingAddressLabel,
                value: addressLine ?? l10n.bookingAddressUnknown,
                detail: addressDetail,
              ),
              _SectionRule(dense: dense),
              _LabelledRow(label: l10n.bookingDateLabel, value: dateLabel),
              SizedBox(height: dense ? VelvetSpacing.sm : VelvetSpacing.sm + 4),
              _LabelledRow(label: l10n.bookingTimeLabel, value: timeLabel),
              _SectionRule(dense: dense),
              BookingRecap(selections: selections, dense: dense),
            ],
          ),
        ),
      ],
    );
  }
}

/// Composes the "street, buildingNo, city" address line, or `null` when
/// nothing is available so the caller falls back to a placeholder string.
/// Mirrors `PublicMasterProfileScreen._buildLocationLine` — kept as a local,
/// duplicated helper (rather than promoted to a shared formatter) since these
/// are currently the only two call sites; see that screen's private method
/// for the twin logic.
String? _masterAddressLine(Master master) {
  final String? street = (master.street?.isNotEmpty ?? false)
      ? master.street
      : null;
  final String? building = (master.buildingNo?.isNotEmpty ?? false)
      ? master.buildingNo
      : null;
  final String? city = (master.city?.isNotEmpty ?? false) ? master.city : null;

  if (street == null && city == null) return null;

  final StringBuffer buf = StringBuffer();
  if (street != null) {
    buf.write(street);
    if (building != null) {
      buf
        ..write(', ')
        ..write(building);
    }
    if (city != null) {
      buf
        ..write(', ')
        ..write(city);
    }
  } else {
    buf.write(city);
  }
  return buf.toString();
}

/// A thin hairline separating two sections of the booking-details card — the
/// only "structure" inside the card.
class _SectionRule extends StatelessWidget {
  const _SectionRule({this.dense = false});

  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: dense ? VelvetSpacing.sm + 2 : VelvetSpacing.md,
      ),
      child: Container(
        height: 1,
        color: BrandColors.faint.withValues(alpha: 0.5),
      ),
    );
  }
}

/// A plain label → value pair — the muted [label] (e.g. "Адреса", "Дата",
/// "Час") above its strong [value], with an optional muted [detail] sub-line.
class _LabelledRow extends StatelessWidget {
  const _LabelledRow({required this.label, required this.value, this.detail});

  final String label;
  final String value;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(label, style: VelvetText.label()),
        const SizedBox(height: 3),
        Text(
          value,
          style: VelvetText.bodyStrong().copyWith(fontSize: 15, height: 1.3),
        ),
        if (detail != null) ...<Widget>[
          const SizedBox(height: 1),
          Text(
            detail!,
            style: VelvetText.feedback(
              BrandColors.muted,
            ).copyWith(fontSize: 12.5),
          ),
        ],
      ],
    );
  }
}
