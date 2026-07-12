// Shared booking label→value row.
//
// Extracted from the byte-identical private `_LabelledRow` that lived in BOTH
// `widgets/booking_summary_cards.dart` (independent-master flow) and
// `widgets/salon_appointment_card.dart` (salon flow) so the two flows compose
// the SAME atom — edit the row once, both flows change.
//
// A plain muted [label] above its strong [value], with an optional muted
// [detail] sub-line. [compactText] shrinks all three a notch (the success
// screen's tighter recap); leaving it `false` with a null [detail] reproduces
// the salon card's simpler label/value pair verbatim.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/velvet_text.dart';

/// A plain label → value pair — the muted [label] (e.g. "Адреса", "Дата",
/// "Час") above its strong [value], with an optional muted [detail] sub-line.
class LabelledRow extends StatelessWidget {
  const LabelledRow({
    super.key,
    required this.label,
    required this.value,
    this.detail,
    this.compactText = false,
    this.maxLines,
    this.overflow,
  });

  final String label;
  final String value;
  final String? detail;

  /// Shrinks label/value/detail a further notch (success screen only).
  final bool compactText;

  /// Optional bound on [value]'s line count — defaults to `null`
  /// (unbounded), matching every pre-existing call site byte-for-byte.
  ///
  /// Set alongside [overflow] when [value] is free text authored by another
  /// entity (e.g. a master/salon-picked service or master name) rather than
  /// backend-formatted content, so an unusually long or newline-heavy string
  /// cannot flood the surrounding card/dialog layout.
  final int? maxLines;

  /// Optional overflow handling for [value], paired with [maxLines].
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          label,
          style: compactText ? VelvetText.label11 : VelvetText.label(),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          maxLines: maxLines,
          overflow: overflow,
          style: compactText
              ? VelvetText.bookCardValue135
              : VelvetText.bookCardValue15,
        ),
        if (detail != null) ...<Widget>[
          const SizedBox(height: 1),
          Text(
            detail!,
            style: compactText
                ? VelvetText.bookFeedbackMuted115
                : VelvetText.bookFeedbackMuted125,
          ),
        ],
      ],
    );
  }
}
