// Shared "Коментар для майстра" note field.
//
// Extracted from the private `_CommentField` duplicated in BOTH
// `booking_confirm_screen.dart` (independent-master flow) and
// `salon_booking_confirm_screen.dart` (salon flow) so the two flows compose
// the SAME field.
//
// Counter isolation is baked in: the live "x / <max>" counter listens to the
// [controller] through a narrow [ValueListenableBuilder], so typing rebuilds
// ONLY the counter Text — never the host screen. The salon flow already did
// this; the independent flow previously drove the counter via a screen-level
// `setState` listener. Baking it here gives both flows the isolation for free
// (the independent confirm screen no longer needs its comment listener /
// setState at all).

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';

/// Optional note for the master — a muted label above a multi-line [TextField]
/// inside a [NeumorphicInset], with a live "x / [maxLength]" counter that
/// updates independently of the host screen.
class BookingCommentField extends StatelessWidget {
  const BookingCommentField({
    super.key,
    required this.controller,
    required this.fieldKey,
    this.maxLength = 500,
  });

  final TextEditingController controller;

  /// Key applied to the inner [TextField] — distinct per flow
  /// (`booking-confirm-comment-field` / `salon-confirm-comment-field`) so
  /// widget tests keep targeting the exact field they always did.
  final Key fieldKey;

  final int maxLength;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(l10n.bookingCommentLabel, style: VelvetText.label()),
        const SizedBox(height: VelvetSpacing.xs),
        NeumorphicInset(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: VelvetSpacing.md,
              vertical: VelvetSpacing.sm,
            ),
            child: TextField(
              key: fieldKey,
              controller: controller,
              maxLines: 3,
              minLines: 2,
              maxLength: maxLength,
              cursorColor: BrandColors.accentDeep,
              style: VelvetText.bodyStrong14,
              buildCounter:
                  (
                    BuildContext context, {
                    required int currentLength,
                    required int? maxLength,
                    required bool isFocused,
                  }) => null,
              decoration: InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
                hintText: l10n.bookingCommentHint,
                hintStyle: VelvetText.bookCommentHint,
              ),
            ),
          ),
        ),
        const SizedBox(height: VelvetSpacing.xs),
        Align(
          alignment: Alignment.centerRight,
          // Only the counter Text listens to the controller — the rest of the
          // screen stays static while typing (no screen-level setState).
          child: ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (BuildContext context, TextEditingValue value, Widget? _) {
              return Text(
                '${value.text.characters.length} / $maxLength',
                style: VelvetText.feedbackMutedXs,
              );
            },
          ),
        ),
      ],
    );
  }
}
