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
// SCOPE NOTE: the preview app was designed for a (since-superseded)
// multi-service booking model. The Phase 14.0 data layer + Phase 14.1
// slot-picker/confirm-args scope boundary (see `slot_picker_screen.dart`'s
// file header) locks booking creation to exactly ONE service per booking, so
// every real call site in `beautica-mobile` feeds this widget a
// SINGLE-element `selections` list. The multi-item rendering path (hairline
// dividers between rows) is kept verbatim anyway — it degrades gracefully to
// a single row + "1 послуга" count and costs nothing to keep faithful to the
// approved design, and it is exercised as-is (not dead code) any time the
// selection list has more than one entry.
//
// Pure widget/presentation logic — no Riverpod, no networking. [selection]
// display strings are built by the call site from the real domain
// [MasterService] via the existing `ServicePriceDisplay.format` /
// `DurationMinutes.format` formatters (both already Ukrainian, and their
// output is compatible with the [_parsePrice] / [parseDurationMinutes]
// round-trip parsing below — see those formatters' own files).

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/formatters/service_count_label.dart';

/// One selected service carried into the booking recap. [price] is a
/// *display* string and may be a single value ("500 грн") OR a hyphenated
/// range ("200 - 600 грн"); [duration] is a display string ("1 год 30 хв",
/// "3 год") — both built by the call site via the shared formatters.
@immutable
class BookingSelection {
  const BookingSelection({
    required this.name,
    required this.price,
    required this.duration,
  });

  /// Service name, e.g. "Манікюр з покриттям".
  final String name;

  /// Price display string — single ("500 грн") or ranged ("200 - 600 грн").
  final String price;

  /// Duration display string, e.g. "1 год 30 хв" or "3 год".
  final String duration;
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
  });

  /// The services carried from the selection step (1..n — see file header
  /// SCOPE NOTE for why every real call site passes exactly 1).
  final List<BookingSelection> selections;

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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final _BookingTotals totals = _BookingTotals.from(selections);
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
        _TotalRow(
          label: l10n.bookingTotalLabel,
          semanticsLabel: l10n.bookingTotalSemantics(
            totals.durationLabel ?? '',
            totals.priceLabel,
          ),
          price: totals.priceLabel,
          duration: totals.durationLabel,
          compactText: compactText,
        ),
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
  });

  final BookingSelection selection;
  final bool dense;

  /// See [BookingRecap.compactText] — shrinks the name/duration/price text a
  /// further notch (success screen only).
  final bool compactText;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      label: l10n.bookingServiceTileSemantics(
        selection.name,
        selection.duration,
        selection.price,
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
            const SizedBox(width: VelvetSpacing.md),
            Text(
              selection.price,
              style: compactText
                  ? VelvetText.bookAccentBold135
                  : VelvetText.bookAccentBold15,
            ),
          ],
        ),
      ),
    );
  }
}

/// The bold "Разом" total line: [label] (left) with the muted total
/// [duration] beside it (the appointment length), and the summed [price] on
/// the right in camel/bold (a range when any per-service price was a range).
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
  final String price;
  final String? duration;

  /// See [BookingRecap.compactText] — shrinks the total row's text a further
  /// notch (success screen only).
  final bool compactText;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticsLabel,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: <Widget>[
          Text(
            label,
            style: compactText
                ? VelvetText.bookName145w800
                : VelvetText.bookName16w800,
          ),
          if (duration != null) ...<Widget>[
            const SizedBox(width: VelvetSpacing.sm),
            Text(
              duration!,
              style: compactText
                  ? VelvetText.feedbackMutedXs
                  : VelvetText.feedbackMutedSm,
            ),
          ],
          const Spacer(),
          Text(
            price,
            style: compactText
                ? VelvetText.bookAccentBold155
                : VelvetText.bookPriceMd,
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
class _BookingTotals {
  const _BookingTotals({required this.priceLabel, required this.durationLabel});

  final String priceLabel;
  final String? durationLabel;

  factory _BookingTotals.from(List<BookingSelection> selections) {
    int minSum = 0;
    int maxSum = 0;
    int minutes = 0;
    for (final BookingSelection s in selections) {
      final (int lo, int hi) = _parsePrice(s.price);
      minSum += lo;
      maxSum += hi;
      minutes += parseDurationMinutes(s.duration);
    }
    final String priceLabel = minSum == maxSum
        ? '$minSum грн'
        : '$minSum–$maxSum грн';
    return _BookingTotals(
      priceLabel: priceLabel,
      durationLabel: minutes > 0 ? _formatDuration(minutes) : null,
    );
  }
}

/// Parses a price display string into a (low, high) pair. "500 грн" → (500,
/// 500); a ranged "200 - 600 грн" / "200–600 грн" → (200, 600).
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

/// Formats total minutes back into Ukrainian "X год Y хв" (dropping a zero
/// part).
String _formatDuration(int minutes) {
  final int h = minutes ~/ 60;
  final int m = minutes % 60;
  if (h > 0 && m > 0) return '$h год $m хв';
  if (h > 0) return '$h год';
  return '$m хв';
}
