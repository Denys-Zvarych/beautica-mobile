// Phase 325 — the management-action card pair (schedule + services) on the
// salon-staff profile screen.
//
// Design source: `docs/signup-designs/SalonServicesEntryPath/lib/widgets/
// entry_widgets.dart:12-130` (`ManagementActionCard`, variant **B · пара
// дій** — the ONLY approved variant of that preview). Transcribed literally,
// swapping the preview's own `VelvetColors`/`VelvetText` tokens for this
// app's [BrandColors]/[VelvetText] — see that file's own header for why
// `Theme.of(context).colorScheme` is never used here (`ColorScheme.fromSeed`
// derives a MOCHA-tonal `primary`, not the camel accent this card needs).
//
// A vertical raised card — distinct from the horizontal [SettingsRow] it
// replaces on this screen: a 40x40 inset glyph well + chevron on the top
// row, then the label, then the (promoted-to-readable) value. Exactly one
// card in a pair may carry [emphasis] — the camel wash — per the design's
// own "spend the boldness in one place" rule.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/pressable_surface.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';

/// The [ManagementActionCard] label line's key. Not unique in a tree — a pair
/// of cards mounts two — so scope any lookup to one card's own key with
/// `find.descendant`.
const Key kManagementActionCardLabelKey = ValueKey<String>(
  'management_action_card_label',
);

/// The [ManagementActionCard] value line's key. Same non-uniqueness caveat as
/// [kManagementActionCardLabelKey].
const Key kManagementActionCardValueKey = ValueKey<String>(
  'management_action_card_value',
);

/// A tappable raised card: inset glyph well + chevron on top, label + value
/// below. The vertical sibling of `SettingsRow` used where a pair of
/// management actions sits side by side (e.g. «Графік роботи» / «Послуги» on
/// `SalonStaffProfileScreen`).
class ManagementActionCard extends StatelessWidget {
  const ManagementActionCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
    this.enabled = true,
    this.emphasis = false,
    this.loading = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  /// Present-but-not-yet-available, same contract as `SettingsRow.enabled` —
  /// dims the card and absorbs taps rather than omitting it.
  final bool enabled;

  /// The camel-washed treatment. Exactly one card in a pair may carry it —
  /// spend the boldness in one place (design source's own rule).
  final bool emphasis;

  /// Additive, defaults `false` — NOT part of the approved static preview
  /// (a demo app has no live async fetch to be "loading"). Mirrors
  /// `SettingsRow.loading`'s exact idiom (swap the trailing chevron for a
  /// small spinner, absorb taps) so the schedule card can keep the
  /// pre-existing mutation-critical AsyncLoading contract
  /// (`salon_staff_profile_screen_test.dart`'s `'AsyncLoading (unresolved,
  /// no value yet) → loading spinner...'` case) without a new visual
  /// treatment — every caller that omits it renders exactly per the
  /// approved design.
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final bool inert = loading || !enabled;

    // 2026-09-14 (defect 12) — the a11y label used to be an unconditional
    // '<label>: <value>', which announced «Графік роботи: » with a trailing
    // colon and nothing after it for the whole time the schedule was in
    // flight (the call site passes `value: ''` while loading). Announce the
    // loading state instead, and drop the separator entirely when there is
    // no value to read.
    final String semanticsLabel;
    if (loading) {
      semanticsLabel = '$label: ${AppLocalizations.of(context).loadingLabel}';
    } else if (value.isEmpty) {
      semanticsLabel = label;
    } else {
      semanticsLabel = '$label: $value';
    }

    // 2026-09-14 (defect 6, REUSE-FIRST) — the press / dim / absorb shell is
    // the shared [PressableSurface], the SAME one `SettingsRow` composes;
    // this card only overrides the three constants where the approved design
    // differs from a row (a slightly deeper press on a bigger target).
    return PressableSurface(
      semanticsLabel: semanticsLabel,
      inert: inert,
      onTap: onTap,
      color: emphasis ? BrandColors.baseEmphasis : BrandColors.base,
      borderRadius: BorderRadius.circular(VelvetRadii.card),
      shadow: VelvetShadows.extrudedCard,
      padding: const EdgeInsets.all(VelvetSpacing.md),
      pressedScale: 0.975,
      pressDuration: const Duration(milliseconds: 120),
      inertOpacity: 0.55,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              NeumorphicGlyphWell(
                size: 40,
                child: Icon(icon, size: 19, color: BrandColors.accentDeep),
              ),
              const Spacer(),
              if (loading)
                const ActionSpinner(
                  key: ValueKey<String>('management_action_card_loading'),
                )
              else
                const Icon(
                  Icons.chevron_right_rounded,
                  color: BrandColors.faint,
                ),
            ],
          ),
          const SizedBox(height: VelvetSpacing.sm + 2),
          // 2026-09-14 (defects 1+2) — BOTH lines may wrap. The card is
          // half the screen minus its own and the row's padding, so the
          // text column is only 116 dp at 360 dp and 96 dp at 320 dp (143
          // dp at 414 dp). At the old literal 15 sp «Графік роботи» (124.2
          // dp) truncated at <=375 dp and «Пн–Пт · 09:00–18:00» (145.5 dp,
          // 175.1 dp when the days are non-contiguous) ellipsized on EVERY
          // shipped width — the value being «the reason to tap» in the
          // approved design's own words. Wrapping, not a smaller size, is
          // the fix: a value short enough to always fit one line would be
          // unreadable. Both cards sit inside an `IntrinsicHeight` row, so
          // a taller card never desynchronises the pair.
          Text(
            label,
            // 2026-09-14 (mobile-qa) — keyed so a test can reach the real
            // laid-out `RenderParagraph` and assert `didExceedMaxLines`.
            // An ellipsized `Text` is NOT a `RenderFlex` overflow, so
            // `overflow_guard.dart` and the `forbid_*` gates are blind to
            // this defect class; reading the paragraph is the only assertion
            // that can see it. Keys are duplicated across the two cards in a
            // pair on purpose — scope the lookup with `find.descendant` under
            // the card's own key.
            key: kManagementActionCardLabelKey,
            style: VelvetText.managementCardLabel,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: VelvetSpacing.xs),
          Text(
            value,
            key: kManagementActionCardValueKey,
            style: VelvetText.managementCardValue,
            // Three, not two: MEASURED (probe, 2026-09-14) — at 320 dp with
            // textScale 1.3 a non-contiguous summary («Пн, Ср, Пт ·
            // 10:00–19:00») needs a third line, and truncating the value is
            // the exact defect this change exists to remove. `Text` only
            // ever occupies the lines it needs, so at 1.0x every shipped
            // width still renders one or two.
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
