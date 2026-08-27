// Phase 275 — ScheduleProgressHint: promoted out of `schedule_confirm_bar
// .dart`'s private `_ProgressHint` (Phase 14.17) into its own shared file —
// REUSE-FIRST: a private widget is promoted, never copied, so any future
// consumer can render the EXACT SAME "X з Y заплановано" well instead of a
// near-duplicate. `ScheduleConfirmBar` (the salon per-master "Час" screen's
// pinned bar) is rewired onto this promoted widget below and renders
// byte-identically to before the promotion — same classes, same keys, same
// styles, only the private class moved file.
//
// A recessed well carrying the scheduling progress: a camel/check glyph,
// the «X з Y заплановано» count (flipping to «Усе заплановано» once done),
// and a slim camel progress rail.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';

/// Renders the shared "X з Y заплановано" / "Усе заплановано" progress well.
/// See the file header — promoted out of `ScheduleConfirmBar` (salon "Час"
/// screen, per-master), which remains its consumer.
class ScheduleProgressHint extends StatelessWidget {
  const ScheduleProgressHint({
    super.key,
    required this.scheduled,
    required this.total,
  });

  final int scheduled;
  final int total;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final bool done = scheduled >= total && total > 0;
    final double fraction = total == 0 ? 0 : scheduled / total;
    return Semantics(
      label: l10n.salonScheduleProgressSemantics(scheduled, total),
      child: NeumorphicInset(
        radius: VelvetRadii.field,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: VelvetSpacing.md,
            vertical: VelvetSpacing.sm + 4,
          ),
          child: Row(
            children: <Widget>[
              Icon(
                done
                    ? Icons.check_circle_rounded
                    : Icons.event_available_outlined,
                size: 18,
                color: done ? BrandColors.success : BrandColors.accentDeep,
              ),
              const SizedBox(width: VelvetSpacing.sm),
              Text(
                done
                    ? l10n.salonScheduleAllScheduledLabel
                    : l10n.salonScheduleProgress(scheduled, total),
                style: VelvetText.scheduleProgressHintLabel,
              ),
              const SizedBox(width: VelvetSpacing.md),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(VelvetRadii.pill),
                  child: Stack(
                    children: <Widget>[
                      Container(
                        height: 5,
                        color: BrandColors.faint.withValues(alpha: 0.5),
                      ),
                      AnimatedFractionallySizedBox(
                        duration: const Duration(milliseconds: 320),
                        curve: Curves.easeOutCubic,
                        widthFactor: fraction.clamp(0.0, 1.0),
                        child: Container(
                          height: 5,
                          decoration: const BoxDecoration(
                            borderRadius: BorderRadius.all(
                              Radius.circular(VelvetRadii.pill),
                            ),
                            gradient: LinearGradient(
                              colors: <Color>[
                                BrandColors.accentLatte,
                                BrandColors.accentDeep,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
