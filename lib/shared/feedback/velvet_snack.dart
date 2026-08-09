// Phase — VelvetSnack: the unified Beautica in-app transient-feedback
// surface. Transcribed verbatim (geometry, spine, icon plate, motion curves,
// colours) from the approved preview app at
// `docs/signup-designs/VelvetSnack/lib/widgets/velvet_snack.dart`. This file
// is the purely presentational widget — no timers, no overlay, no animation.
// See `velvet_snack_host.dart` for the `Overlay`-driven host that animates,
// positions and auto-dismisses it, and `show_velvet_snack.dart` for the
// call-site-facing API.
//
// ## Why it looks the way it does
//
// VelvetTouch has exactly one surface tone, so a floating panel cannot
// separate itself from the page by changing its fill — a darker slab (what
// Material's default `SnackBar` does) would be the single most foreign
// object in the app. Separation is therefore built from three cheap,
// on-system parts:
//
// 1. **A non-offset halo** ([VelvetShadows.snackLift]) — reads as lift and,
//    critically, cannot produce the Impeller-GLES corner artifact that an
//    offset opaque shadow produces on a rounded decoration. A floating
//    surface is the exact case where that artifact would land on top of
//    real content — see `velvet_geometry.dart`'s Impeller safety note.
// 2. **A hairline stroke** in the variant accent at low alpha — gives the
//    eye a crisp boundary when the snack overlaps a same-toned card behind
//    it.
// 3. **A 4dp accent spine** on the leading edge — the signature. It is the
//    snack's only saturated element, it encodes severity at the very edge of
//    peripheral vision, and it survives when the message is truncated.

import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';

/// The four semantic registers a [VelvetSnack] can speak in.
///
/// Each carries its own accent hue and glyph. Meaning is never carried by
/// hue alone — every variant pairs colour with a distinct icon AND an
/// announced [AppLocalizations] prefix (resolved in [VelvetSnack.build],
/// since a `BuildContext` is required to read it), which is the VelvetTouch
/// accessibility rule already applied to inline field feedback.
enum VelvetSnackVariant {
  /// Something the user asked for completed. «Зміни збережено».
  success(
    accent: BrandColors.success,
    // Default weight 400 / fill 0 — a plain const IconData reference, same
    // house style as `calendar_button.dart` (keeps `--tree-shake-icons` and
    // const-folding straightforward).
    icon: Symbols.check_circle_rounded,
  ),

  /// Something failed and the user must know. «Не вдалося зберегти».
  error(accent: BrandColors.error, icon: Symbols.error_rounded),

  /// Neutral acknowledgement, no action needed. «Скоро буде доступно».
  info(accent: BrandColors.accent, icon: Symbols.info_rounded),

  /// A limit or a consequence the user should notice. «Досягнуто ліміт».
  warning(accent: BrandColors.accentLatte, icon: Symbols.warning_rounded);

  const VelvetSnackVariant({required this.accent, required this.icon});

  /// The one saturated hue this variant is allowed to introduce. Painted on
  /// the spine, the glyph and the action label — nowhere else.
  final Color accent;

  final IconData icon;

  /// Spoken before the message by screen readers, so the register survives
  /// when the colour and the glyph do not. Localised via [l10n] rather than a
  /// fixed `const` enum field, since resolving an [AppLocalizations] string
  /// requires a `BuildContext`.
  String semanticPrefix(AppLocalizations l10n) => switch (this) {
    VelvetSnackVariant.success => l10n.velvetSnackPrefixSuccess,
    VelvetSnackVariant.error => l10n.velvetSnackPrefixError,
    VelvetSnackVariant.info => l10n.velvetSnackPrefixInfo,
    VelvetSnackVariant.warning => l10n.velvetSnackPrefixWarning,
  };
}

/// The unified Beautica in-app notification surface.
///
/// A purely presentational widget so it can be laid out statically in a
/// gallery / golden test without pumping a controller. See
/// `show_velvet_snack.dart` for the function every screen actually calls.
class VelvetSnack extends StatelessWidget {
  const VelvetSnack({
    super.key,
    required this.variant,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.onDismiss,
    this.maxLines = 2,
  }) : assert(
         (actionLabel == null) == (onAction == null),
         'actionLabel and onAction must be supplied together.',
       );

  final VelvetSnackVariant variant;

  /// Kept to one short sentence. Ukrainian runs ~25% longer than English —
  /// anything past ~60 characters will truncate at [maxLines].
  final String message;

  /// Optional trailing action, e.g. «Повторити» / «Скасувати».
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Optional explicit dismiss affordance. When null the close button is
  /// omitted and the snack relies on auto-dismiss + swipe-down.
  final VoidCallback? onDismiss;

  /// Message line budget before ellipsis. Two by default — a third line
  /// pushes the snack tall enough to cover the primary action of the screen
  /// behind it.
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final Color accent = variant.accent;
    final bool hasAction = actionLabel != null;

    return Semantics(
      liveRegion: true,
      container: true,
      label: '${variant.semanticPrefix(l10n)}. $message',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: BrandColors.base,
          borderRadius: BorderRadius.circular(VelvetRadii.card),
          // Hairline in the variant hue. Low alpha so it defines the edge
          // without turning the snack into a coloured box.
          border: Border.all(color: accent.withValues(alpha: 0.28), width: 1),
          // Non-offset only — see VelvetShadows.snackLift's doc comment and
          // the Impeller safety note in velvet_geometry.dart.
          boxShadow: VelvetShadows.snackLift,
        ),
        child: ClipRRect(
          // Clipped so the spine takes the container's own corner curvature
          // instead of sitting as a rectangle inside a rounded box.
          borderRadius: BorderRadius.circular(VelvetRadii.card - 1),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                // --- Signature: the accent spine. -------------------------
                Container(width: VelvetSizes.snackSpine, color: accent),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      VelvetSpacing.sm + VelvetSpacing.xs, // 12
                      VelvetSpacing.sm + VelvetSpacing.xs,
                      VelvetSpacing.sm + VelvetSpacing.xs,
                      VelvetSpacing.sm + VelvetSpacing.xs,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: <Widget>[
                        _IconHolder(variant: variant),
                        const SizedBox(
                          width: VelvetSpacing.sm + VelvetSpacing.xs,
                        ),
                        Expanded(
                          // The plain message Text otherwise emits its OWN
                          // auto-generated semantics node, which — since
                          // this whole tile is only a `container:true`
                          // Semantics boundary, not `excludeSemantics:true`
                          // (that would also swallow the action/close
                          // buttons' own explicit button semantics below) —
                          // merges UP into the outer node's `label` on top
                          // of the explicit `'$prefix. $message'` label,
                          // doubling the announcement (mobile-qa,
                          // `test/shared/feedback/velvet_snack_test.dart`'s
                          // semantics test, caught red before this fix).
                          // Excluding just this leaf keeps the explicit
                          // outer label as the ONLY thing a screen reader
                          // speaks for the message, while leaving the
                          // action/close affordances independently
                          // announceable.
                          child: ExcludeSemantics(
                            child: Text(
                              message,
                              style: VelvetText.snackMessage(),
                              maxLines: maxLines,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        if (hasAction) ...<Widget>[
                          const SizedBox(width: VelvetSpacing.sm),
                          _SnackAction(
                            label: actionLabel!,
                            accent: accent,
                            onPressed: onAction!,
                          ),
                        ],
                        if (onDismiss != null) ...<Widget>[
                          SizedBox(
                            width: hasAction
                                ? VelvetSpacing.xs
                                : VelvetSpacing.sm,
                          ),
                          _SnackClose(onPressed: onDismiss!),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The leading glyph in a softened square tint well.
///
/// Deliberately **flat-tinted rather than extruded**: the snack is already a
/// floating shadowed surface, and nesting a second offset shadow pair inside
/// it muddies both. The tint plate is the same trick VelvetTouch uses for
/// status chips, so it stays on-system.
class _IconHolder extends StatelessWidget {
  const _IconHolder({required this.variant});

  final VelvetSnackVariant variant;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: VelvetSizes.snackIconHolder,
      width: VelvetSizes.snackIconHolder,
      decoration: BoxDecoration(
        color: variant.accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(VelvetRadii.snackIcon),
      ),
      child: Icon(variant.icon, size: 18, color: variant.accent),
    );
  }
}

/// The trailing action — a bare text button, no chip, no border.
///
/// A boxed button here would compete with the spine and with whatever CTA
/// sits on the screen behind the snack. Weight + hue carry the affordance
/// instead; the tap target is padded out to 44dp so the restraint costs
/// nothing.
class _SnackAction extends StatelessWidget {
  const _SnackAction({
    required this.label,
    required this.accent,
    required this.onPressed,
  });

  final String label;
  final Color accent;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        key: const ValueKey<String>('velvet_snack_action'),
        onTap: onPressed,
        borderRadius: BorderRadius.circular(VelvetRadii.field),
        splashColor: accent.withValues(alpha: 0.14),
        highlightColor: accent.withValues(alpha: 0.08),
        child: Container(
          constraints: const BoxConstraints(minHeight: 32),
          padding: const EdgeInsets.symmetric(
            horizontal: VelvetSpacing.sm + VelvetSpacing.xs,
            vertical: VelvetSpacing.sm,
          ),
          alignment: Alignment.center,
          child: Text(label, style: VelvetText.snackAction(accent)),
        ),
      ),
    );
  }
}

/// The optional close affordance. Muted, never accented — dismissing is not
/// the snack's message, so it must not compete with the spine or the action.
class _SnackClose extends StatelessWidget {
  const _SnackClose({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Semantics(
      button: true,
      label: l10n.velvetSnackDismissSemantic,
      child: InkWell(
        key: const ValueKey<String>('velvet_snack_close'),
        onTap: onPressed,
        borderRadius: BorderRadius.circular(VelvetRadii.pill),
        splashColor: BrandColors.accent.withValues(alpha: 0.14),
        child: const Padding(
          padding: EdgeInsets.all(VelvetSpacing.sm),
          child: Icon(
            Symbols.close_rounded,
            size: 16,
            color: BrandColors.muted,
          ),
        ),
      ),
    );
  }
}
