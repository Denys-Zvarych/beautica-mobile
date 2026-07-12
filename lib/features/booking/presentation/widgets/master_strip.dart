// MasterStrip — the ONE "who you're booking with" identity card, shared by
// every booking screen in both flows (independent-master AND salon).
//
// Transcribed verbatim (tokens, layout, shadows) from
// `docs/signup-designs/BookingServiceSelection/lib/widgets/selection_widgets.dart`
// (`MasterStrip`) / `docs/signup-designs/BookingSlotPicker/lib/widgets/master_strip.dart`.
//
// Content model: avatar · name · title-or-role sub-line · ★ rating (+ review
// count). The card is DATA-AGNOSTIC — it takes primitives, so it can be fed
// from a [Master] ([MasterStrip.fromMaster]), a [SalonMasterSchedule]
// ([MasterStrip.fromSchedule]) or a bare `SalonMasterSummary` (the salon
// master picker, which passes primitives directly). Every booking screen —
// service selector, date, time, confirm, success, salon master picker, salon
// date/time, salon confirm, salon success — renders THIS widget, so a change
// here reaches all of them.
//
// The outer frame (surface, paddings, avatar badge, Hero-flight `Material`
// guard) lives in [MasterStripShell]; any `Hero(tag:)` stays OUTSIDE both, at
// the call sites that own it (`slot_picker_screen.dart`,
// `booking_summary_cards.dart`).

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';

import '../../domain/salon_master_schedule.dart';
import 'master_strip_shell.dart';

/// Resolves a display label for [type]. Shared by every booking-flow screen
/// that renders a [MasterStrip] / day-header chip so the wording never drifts
/// from `PublicMasterProfileScreen`'s own `_roleLabel`.
String masterRoleLabel(MasterType type, AppLocalizations l10n) {
  switch (type) {
    case MasterType.independentMaster:
      return l10n.masterRoleIndependent;
    case MasterType.salonMaster:
      return l10n.masterRoleSalonMaster;
    case MasterType.salonOwner:
      return l10n.masterRoleSalonOwner;
  }
}

/// A compact "who you're booking with" strip — a camel-wash card with a small
/// raised avatar glyph, the master's name, their title/role sub-line and their
/// ★ rating.
///
/// [showRole] adds the muted sub-line under the name (the master's own
/// [professionalTitle] when set, else the generic [masterRoleLabel] for their
/// [type]); [showRating] adds the trailing camel-★ + [avgRating] readout (plus
/// a muted `(reviewCount)` suffix when there is at least one review). Both
/// default to `false` so a call site can opt into the name-only card.
///
/// A `null` [avgRating] renders the [noRatingLabel] em-dash — the salon
/// roster's convention for "no reviews yet" (`SalonMasterSummary.avgRating` is
/// null exactly then). The independent flow's [Master.avgRating] is
/// non-nullable, so [MasterStrip.fromMaster] never takes that branch.
class MasterStrip extends StatelessWidget {
  const MasterStrip({
    super.key,
    required this.name,
    required this.type,
    this.professionalTitle,
    this.avgRating,
    this.reviewCount = 0,
    this.showLabel = true,
    this.showRole = false,
    this.showRating = false,
    this.avatarGradient,
    this.avatarBordered = false,
  });

  /// Builds the strip from the independent flow's [Master] domain entity.
  MasterStrip.fromMaster(
    Master master, {
    super.key,
    this.showLabel = true,
    this.showRole = false,
    this.showRating = false,
    this.avatarGradient,
    this.avatarBordered = false,
  }) : name = '${master.firstName} ${master.lastName}'.trim(),
       type = master.type,
       professionalTitle = master.professionalTitle,
       avgRating = master.avgRating,
       reviewCount = master.reviewCount;

  /// Builds the strip from the salon flow's per-master [SalonMasterSchedule]
  /// (the "Час" slide header, the confirm card, the success card).
  MasterStrip.fromSchedule(
    SalonMasterSchedule schedule, {
    super.key,
    this.showLabel = true,
    this.showRole = false,
    this.showRating = false,
    this.avatarGradient,
    this.avatarBordered = false,
  }) : name = '${schedule.firstName} ${schedule.lastName}'.trim(),
       type = schedule.type,
       professionalTitle = schedule.professionalTitle,
       avgRating = schedule.avgRating,
       reviewCount = schedule.reviewCount;

  /// Master display name (already joined — "Олена Ковальчук").
  final String name;

  /// Role / tenure type — the sub-line fallback when no title is set.
  final MasterType type;

  /// The master's own professional title, preferred over the generic role
  /// label whenever it is non-blank.
  final String? professionalTitle;

  /// Average review rating, or `null` when the master has no reviews yet.
  final double? avgRating;

  /// Total number of reviews — rendered as the muted `(n)` suffix when > 0.
  final int reviewCount;

  /// Renders the muted «Запис до майстра» caption above the name. Off on the
  /// salon master PICKER, where no master has been chosen yet, so the caption
  /// would be both untrue and repeated once per row.
  final bool showLabel;

  /// Adds the muted title/role sub-line under the name.
  final bool showRole;

  /// Adds the trailing ★ rating (+ review count) readout.
  final bool showRating;

  /// Two-stop diagonal avatar gradient; `null` falls back to the independent
  /// flow's default camel→mocha wash.
  final List<Color>? avatarGradient;

  /// Adds the salon flow's translucent-white avatar ring.
  final bool avatarBordered;

  /// Shown in place of the rating when the master has no reviews yet. Public
  /// so a call site that must build its own semantics label for a row wrapping
  /// this card (`SalonMasterSelectionScreen`) reads the same placeholder.
  static const String noRatingLabel = '—';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Prefer the master's own professional title; fall back to the generic
    // role label only when no title is set. Mirrors the same idiom used on
    // `SalonMasterSelectionScreen` / `PublicSalonProfileScreen`.
    final String? title = professionalTitle?.trim();
    final String subtitle = (title != null && title.isNotEmpty)
        ? title
        : masterRoleLabel(type, l10n);
    final double? rating = avgRating;
    final String ratingLabel = rating == null
        ? noRatingLabel
        : rating.toStringAsFixed(1);

    final String semanticsLabel = showRating
        ? l10n.bookingSummaryMasterSemantics(
            name,
            subtitle,
            ratingLabel,
            l10n.salonReviewCountLabel(reviewCount),
          )
        : l10n.bookingMasterStripSemantics(name, subtitle);

    return MasterStripShell(
      semanticsLabel: semanticsLabel,
      name: name,
      topLabel: showLabel ? l10n.bookingMasterStripLabel : null,
      avatarGradient: avatarGradient,
      avatarBordered: avatarBordered,
      middleLine: showRole
          ? Text(
              subtitle,
              style: VelvetText.feedbackMutedSm,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            )
          : null,
      trailing: showRating
          ? Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                const Icon(
                  Icons.star_rounded,
                  size: 16,
                  color: BrandColors.accent,
                ),
                const SizedBox(width: 2),
                Text(ratingLabel, style: VelvetText.bodyStrong14),
                if (reviewCount > 0) ...<Widget>[
                  const SizedBox(width: 3),
                  Text(
                    '($reviewCount)',
                    style: VelvetText.bookFeedbackMuted115,
                  ),
                ],
              ],
            )
          : null,
    );
  }
}
