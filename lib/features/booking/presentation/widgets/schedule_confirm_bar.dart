// Phase 14.17 — ScheduleConfirmBar: the pinned summary shelf for the salon
// booking flow's step-3 "Час" screen.
//
// Ports `docs/signup-designs/SalonBookingTime/lib/widgets/schedule_confirm_bar.dart`
// onto real typed data: a «Разом» total summed across EVERY assigned
// master's services (typed `priceMin`/`priceMax`/`priceType`/
// `durationMinutes` fields — never a re-parsed display string, mirroring
// `_AssignConfirmBar._totals` on `SalonMasterSelectionScreen`), a progress
// hint («X з Y заплановано») with a slim camel rail, and one CTA that reads
// «Далі» while stepping through a master's date/time and only becomes
// «Підтвердити» once EVERY assigned master has a date AND a time — see
// [onNext]/[nextEnabled]'s doc comments for the exact per-phase contract.
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
import '../../../services/domain/master_service.dart';
import '../../domain/salon_master_schedule.dart';
import 'schedule_progress_hint.dart';
import 'selected_services_shelf.dart';

/// The pinned "Разом" + progress + CTA shelf for the salon "Час" screen.
class ScheduleConfirmBar extends StatelessWidget {
  const ScheduleConfirmBar({
    super.key,
    required this.schedules,
    required this.selectedServices,
    required this.scheduledCount,
    required this.totalCount,
    required this.onConfirm,
    this.onNext,
    this.nextEnabled = false,
  });

  /// Every assigned master's schedule slide — drives the «Разом» total.
  final List<SalonMasterSchedule> schedules;

  /// Display adapter of every selected service across every assigned
  /// master's [schedules], feeding the pinned [SelectedServicesShelf] so the
  /// client never loses sight of what they picked while scheduling. See
  /// `salonServiceForShelf`'s doc comment — display-only, never used for the
  /// booking write path.
  final List<MasterService> selectedServices;

  /// How many masters have BOTH a date and a time chosen.
  final int scheduledCount;

  /// Total number of assigned masters to schedule.
  final int totalCount;

  /// Fires only once every master is scheduled and the CTA is tapped — pure
  /// forward navigation, never a booking-creation call. See this file's
  /// header.
  final VoidCallback onConfirm;

  /// The step-3 CTA's intermediate action — commits the active slide's DATE
  /// phase into its TIME phase, or advances the pager to the next
  /// unscheduled master, depending which phase the caller's active slide is
  /// in (see `SalonTimeScreen._handleNext`). `null` (the default) preserves
  /// this bar's ORIGINAL behaviour exactly: the CTA always reads
  /// «Підтвердити» and stays disabled until every master is scheduled — no
  /// existing caller that omits this needs to change. Non-null callers (only
  /// `SalonTimeScreen` today) get the «Далі» label on every step before the
  /// final one, per the product decision that forward navigation off the
  /// date/time pages is CTA-driven, never automatic on a date/slot tap.
  final VoidCallback? onNext;

  /// Whether [onNext] fires when the CTA is tapped in the "not all scheduled
  /// yet" state — i.e. the active slide's current phase has a valid
  /// selection (a picked date on the DATE phase, a picked slot on the TIME
  /// phase). Ignored when [onNext] is `null`. Defaults to `false`, matching
  /// this bar's original always-disabled-until-`_allScheduled` behaviour for
  /// any caller that doesn't pass [onNext].
  final bool nextEnabled;

  static const Color _shelfSurface = Color(0xFFEDE4D5);

  bool get _allScheduled => scheduledCount >= totalCount && totalCount > 0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final (String price, String? durationLabel) = _totals(schedules);
    // The final step («Підтвердити») stays distinct from every intermediate
    // one («Далі»): once every master is scheduled, the CTA always confirms
    // — regardless of [onNext] — and never reverts to «Далі» again. Before
    // that, a caller that wired [onNext] gets «Далі» (enabled only once
    // [nextEnabled]); a caller that didn't (every existing caller of this
    // bar before this change) keeps the original always-«Підтвердити»,
    // always-disabled-until-`_allScheduled` shape exactly.
    final bool allScheduled = _allScheduled;
    final String ctaLabel = allScheduled || onNext == null
        ? l10n.bookingConfirmCta
        : l10n.bookingNextCta;
    final VoidCallback? ctaHandler = allScheduled
        ? onConfirm
        : (onNext != null && nextEnabled ? onNext : null);
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
              // The same expandable "Послуги та ціни" shelf the
              // service-selection step shows, so the client never loses
              // sight of what they picked while scheduling. No `onRemove`:
              // deselecting a service here — after a date/time may already
              // be scheduled around it — would invalidate that schedule, so
              // the itemized list is read-only on this step.
              SelectedServicesShelf(services: selectedServices),
              const SizedBox(height: VelvetSpacing.md),
              Container(
                height: 1,
                color: BrandColors.faint.withValues(alpha: 0.5),
              ),
              const SizedBox(height: VelvetSpacing.sm + 2),
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
              ScheduleProgressHint(
                scheduled: scheduledCount,
                total: totalCount,
              ),
              const SizedBox(height: VelvetSpacing.md),
              NeumorphicButton(
                key: const Key('schedule-confirm-cta'),
                label: ctaLabel,
                icon: Icons.check_circle_outline_rounded,
                onPressed: ctaHandler,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Sums typed price/duration fields across EVERY assigned service of
  /// EVERY assigned master — never a re-parsed display string.
  ///
  /// Goes through [formatBookingTotalsFromTerms] rather than summing first and
  /// calling [formatBookingTotals] on the totals: a sum-level check alone lets
  /// two out-of-range figures that cancel (`1e30 + -1e30 == 0.0`) render a
  /// fictional «0 ₴». See that function's doc for the full rationale.
  (String, String?) _totals(List<SalonMasterSchedule> schedules) {
    final ({String priceLabel, String? durationLabel}) totals =
        formatBookingTotalsFromTerms(
          schedules.expand(
            (SalonMasterSchedule schedule) =>
                schedule.services.map((SalonCatalogService s) {
                  final double lo = s.priceMin ?? 0;
                  return (
                    min: lo,
                    max: s.priceType == ServicePriceType.range
                        ? (s.priceMax ?? lo)
                        : lo,
                    minutes: s.durationMinutes ?? 0,
                  );
                }),
          ),
        );
    return (totals.priceLabel, totals.durationLabel);
  }
}

// The progress well previously lived here as a private `_ProgressHint` — it
// was PROMOTED to `ScheduleProgressHint` (`schedule_progress_hint.dart`,
// Phase 275) so the salon schedule hub's footer could reuse the exact same
// widget instead of a near-duplicate. See that file's header.
