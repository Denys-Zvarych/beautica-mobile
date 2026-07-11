// Phase 14.1 — MasterStrip: the "who you're booking with" context card.
//
// Transcribed verbatim (tokens, layout, shadows) from
// `docs/signup-designs/BookingServiceSelection/lib/widgets/selection_widgets.dart`
// (`MasterStrip`) / `docs/signup-designs/BookingSlotPicker/lib/widgets/master_strip.dart`
// — both preview apps carry an identical copy. Reused across the service
// selector (Step 1) and the date screen (Step 2a); the time screen (Step 2b)
// folds the same name/role onto its slimmer day-header chip instead.
//
// Takes the domain [Master] directly (rather than separate name/role strings)
// so every call site derives the display name + role label the exact same
// way.
//
// Unification follow-up: [showRole]/[showRating] extend this SAME card
// (rather than forking a parallel widget) to also cover the "who you're
// booking with" identity across Step 2a/2b (`SlotDateScreen`/`SlotTimeScreen`
// in `slot_picker_screen.dart`) AND Step 3a (`BookingConfirmScreen`, via
// `BookingSummaryCards`'s master card) — replacing that screen's previous
// bespoke `_MasterHeader` (60x60 avatar, no top label) so all three booking
// screens render the identical `#EDE4D5` card rather than two visually
// different "who" cards. `showRole`/`showRating` default to `false` so
// `ServiceSelectorSheet` (Step 1, not part of this unification) keeps its
// exact original look with zero changes at its call site.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';

import 'master_avatar_badge.dart';

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
/// raised avatar glyph + the master's name and role.
///
/// [showRole] adds a muted role sub-line right under the name (independent
/// master / salon master / salon owner, via [masterRoleLabel]); [showRating]
/// adds a trailing camel-★ + [Master.avgRating] readout (plus a muted
/// `(reviewCount)` suffix when there is at least one review), matching the
/// rating treatment previously shipped on the confirmation screen's
/// (now-removed) `_MasterHeader`. Both default to `false` so the Step 1
/// service-selector call site — out of scope for this unification — keeps
/// rendering the original label+name-only card unchanged.
class MasterStrip extends StatelessWidget {
  const MasterStrip({
    super.key,
    required this.master,
    this.showRole = false,
    this.showRating = false,
  });

  final Master master;

  /// Adds the muted role sub-line under the name.
  final bool showRole;

  /// Adds the trailing ★ rating (+ review count) readout.
  final bool showRating;

  /// Camel-wash surface — the same lighter taupe used by the pinned booking
  /// summary shelf, so the strip reads as sitting on its own elevated card.
  static const Color _stripSurface = Color(0xFFEDE4D5);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final String name = '${master.firstName} ${master.lastName}'.trim();
    final String role = masterRoleLabel(master.type, l10n);
    final String ratingLabel = master.avgRating.toStringAsFixed(1);

    final String semanticsLabel = showRating
        ? l10n.bookingSummaryMasterSemantics(
            name,
            role,
            ratingLabel,
            l10n.salonReviewCountLabel(master.reviewCount),
          )
        : l10n.bookingMasterStripSemantics(name, role);

    return Semantics(
      label: semanticsLabel,
      child: Material(
        // Guards against the Hero-flight shuttle rendering this subtree
        // outside any Material ancestor: without one, every Text below
        // resolves against MaterialApp's literal error DefaultTextStyle
        // (underlined, no explicit height) for the duration of the flight,
        // producing a brief flash of underlined/tight-line-height text on
        // the master's name. `transparency` paints nothing itself — it only
        // installs the ambient Theme/DefaultTextStyle — so it doesn't
        // interfere with NeumorphicCard's own shadow/decoration painting.
        type: MaterialType.transparency,
        child: NeumorphicCard(
          color: _stripSurface,
          padding: const EdgeInsets.all(VelvetSpacing.sm + 4),
          child: Row(
            children: <Widget>[
              const MasterAvatarBadge(),
              const SizedBox(width: VelvetSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      l10n.bookingMasterStripLabel,
                      style: VelvetText.contactPlatformLabel,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      name,
                      style: VelvetText.subheading16,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (showRole) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(
                        role,
                        style: VelvetText.feedbackMutedSm,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              if (showRating) ...<Widget>[
                const SizedBox(width: VelvetSpacing.sm),
                Row(
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
                    if (master.reviewCount > 0) ...<Widget>[
                      const SizedBox(width: 3),
                      Text(
                        '(${master.reviewCount})',
                        style: VelvetText.bookFeedbackMuted115,
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
