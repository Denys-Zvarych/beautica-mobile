// Phase 14.17 — ScheduleConfirmBar: the pinned summary shelf for the salon
// booking flow's step-3 "Час" screen.
//
// Ports `docs/signup-designs/SalonBookingTime/lib/widgets/schedule_confirm_bar.dart`
// onto real typed data: a «Разом» total summed across EVERY assigned
// master's services (typed `priceMin`/`priceMax`/`priceType`/
// `durationMinutes` fields — never a re-parsed display string, mirroring
// `_AssignConfirmBar._totals` on `SalonMasterSelectionScreen`), a progress
// hint («X з Y заплановано») with a slim camel rail, and the «Підтвердити»
// CTA — enabled only once EVERY assigned master has a date AND a time.
//
// Per-master done/undone state is NOT rendered a second time inside this
// bar — the approved preview's `ScheduleConfirmBar` itself has no per-master
// dots (only the aggregate progress rail); that per-master detail already
// lives in `SalonTimeScreen`'s pager indicator (the dots beside the ‹ ›
// arrows), matching the design source exactly.
//
// NO booking-creation call happens here: [onConfirm] is wired by
// `SalonTimeScreen` to a pure `context.push(RouteNames.salonBookingComingSoon,
// ...)` navigation — never a repository method.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/formatters/booking_price_labels.dart';

import '../../../salon/domain/salon_service_catalog.dart';
import '../../../services/domain/master_service.dart' show ServicePriceType;
import '../../domain/salon_master_schedule.dart';

/// The pinned "Разом" + progress + CTA shelf for the salon "Час" screen.
class ScheduleConfirmBar extends StatelessWidget {
  const ScheduleConfirmBar({
    super.key,
    required this.schedules,
    required this.scheduledCount,
    required this.totalCount,
    required this.onConfirm,
  });

  /// Every assigned master's schedule slide — drives the «Разом» total.
  final List<SalonMasterSchedule> schedules;

  /// How many masters have BOTH a date and a time chosen.
  final int scheduledCount;

  /// Total number of assigned masters to schedule.
  final int totalCount;

  /// Fires only once every master is scheduled and the CTA is tapped — pure
  /// forward navigation, never a booking-creation call. See this file's
  /// header.
  final VoidCallback onConfirm;

  static const Color _shelfSurface = Color(0xFFEDE4D5);

  bool get _allScheduled => scheduledCount >= totalCount && totalCount > 0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final (String price, String? durationLabel) = _totals(schedules);
    return Container(
      decoration: const BoxDecoration(
        color: _shelfSurface,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(VelvetRadii.card),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: BrandColors.shadowDarkCard,
            offset: Offset(0, -9),
            blurRadius: 24,
          ),
          BoxShadow(
            color: BrandColors.shadowLightStrong,
            offset: Offset(0, -1),
            blurRadius: 3,
            spreadRadius: -1,
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            VelvetSpacing.lg,
            VelvetSpacing.lg,
            VelvetSpacing.lg,
            VelvetSpacing.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Semantics(
                label:
                    '${l10n.bookingTotalLabel} ${durationLabel ?? ''} $price',
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: <Widget>[
                    Text(
                      l10n.bookingTotalLabel,
                      style: VelvetText.bodyStrong(),
                    ),
                    if (durationLabel != null) ...<Widget>[
                      const SizedBox(width: VelvetSpacing.sm),
                      Text(
                        durationLabel,
                        style: VelvetText.scheduleConfirmDurationLabel,
                      ),
                    ],
                    const Spacer(),
                    Text(price, style: VelvetText.scheduleConfirmPriceLabel),
                  ],
                ),
              ),
              const SizedBox(height: VelvetSpacing.md),
              _ProgressHint(scheduled: scheduledCount, total: totalCount),
              const SizedBox(height: VelvetSpacing.md),
              NeumorphicButton(
                key: const Key('schedule-confirm-cta'),
                label: l10n.bookingConfirmCta,
                icon: Icons.check_circle_outline_rounded,
                onPressed: _allScheduled ? onConfirm : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Sums typed price/duration fields across EVERY assigned service of
  /// EVERY assigned master — never a re-parsed display string.
  (String, String?) _totals(List<SalonMasterSchedule> schedules) {
    double minSum = 0;
    double maxSum = 0;
    int minutes = 0;
    for (final SalonMasterSchedule schedule in schedules) {
      for (final SalonCatalogService s in schedule.services) {
        final double lo = s.priceMin ?? 0;
        final double hi = s.priceType == ServicePriceType.range
            ? (s.priceMax ?? lo)
            : lo;
        minSum += lo;
        maxSum += hi;
        minutes += s.durationMinutes ?? 0;
      }
    }
    final ({String priceLabel, String? durationLabel}) totals =
        formatBookingTotals(minSum: minSum, maxSum: maxSum, minutes: minutes);
    return (totals.priceLabel, totals.durationLabel);
  }
}

/// A recessed well carrying the scheduling progress: a camel/check glyph,
/// the «X з Y заплановано» count, and a slim camel rail.
class _ProgressHint extends StatelessWidget {
  const _ProgressHint({required this.scheduled, required this.total});

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
