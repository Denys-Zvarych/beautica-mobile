// IndependentScheduleConfirmBar — the pinned bottom shelf for the
// independent-master booking flow's per-service time step (`BookingTimeScreen`).
//
// The independent analogue of `ScheduleConfirmBar` (the salon "Час" step's
// bar): the SAME expandable "Послуги та ціни" shelf ([SelectedServicesShelf])
// pinned above a «Разом» total + the «Підтвердити» CTA, so the client never
// loses sight of what they picked while scheduling — the shelf the independent
// flow carried before the multi-service PageView rework replaced it with a bare
// CTA footer.
//
// Kept as its OWN widget rather than reusing `ScheduleConfirmBar` because that
// one is bound to the salon domain (`SalonMasterSchedule` slides, a per-master
// «X з Y заплановано» progress rail). The independent flow already renders its
// scheduling progress in the BODY (`_ServicePager`'s dots + counter), so this
// bar carries no progress rail — only the shelf, the total, and the CTA. The
// shelf itemises per-SERVICE chosen windows via [SelectedServicesShelf.chosenLabelFor]
// (the independent flow's distinguishing UX: a separate date/time per service),
// which the salon bars never supply.
//
// NO `POST /bookings` CALL HERE: [onConfirm] is wired by `BookingTimeScreen` to
// pure forward navigation to `/booking/confirm` — never a repository method.

import 'package:flutter/material.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/formatters/booking_price_labels.dart';

import 'selected_services_shelf.dart';

/// The pinned "Послуги та ціни" + «Разом» + «Підтвердити» shelf for the
/// independent-master "Час" screen.
class IndependentScheduleConfirmBar extends StatelessWidget {
  const IndependentScheduleConfirmBar({
    super.key,
    required this.services,
    required this.chosenWindowByServiceId,
    required this.enabled,
    required this.onConfirm,
    required this.ctaKey,
  });

  /// The client's selected service(s) — drives the itemised shelf and the
  /// «Разом» total (summed from the typed price/duration fields, never a
  /// re-parsed display string).
  final List<MasterService> services;

  /// serviceId → chosen appointment-window label (e.g.
  /// "вт, 14 лип · 14:00–15:00") for every service the client has already
  /// scheduled. A service absent from this map has no pick yet and shows no
  /// third line in its shelf row.
  final Map<String, String> chosenWindowByServiceId;

  /// Whether the CTA is tappable — the caller passes `allScheduled` (every
  /// service has a date AND a time).
  final bool enabled;

  /// Fires only once every service is scheduled and the CTA is tapped — pure
  /// forward navigation, never a booking-creation call. See this file's header.
  final VoidCallback onConfirm;

  /// Key applied to the CTA button — the host screen keeps its established
  /// `booking-time-confirm-cta` key here so its widget tests still find the CTA.
  final Key ctaKey;

  static const Color _shelfSurface = Color(0xFFEDE4D5);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final (String price, String? durationLabel) = _totals(services);
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
              // No `onRemove`: deselecting a service here — after a date/time
              // may already be scheduled around it — would invalidate that
              // schedule, so the itemised list is read-only on this step
              // (mirrors `ScheduleConfirmBar`).
              SelectedServicesShelf(
                services: services,
                chosenLabelFor: (MasterService s) =>
                    chosenWindowByServiceId[s.id],
              ),
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
              NeumorphicButton(
                key: ctaKey,
                label: l10n.bookingConfirmCta,
                icon: Icons.check_circle_outline_rounded,
                onPressed: enabled ? onConfirm : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Sums the typed price/duration fields across every selected service —
  /// never a re-parsed display string (mirrors `BookingSummaryBar` /
  /// `ScheduleConfirmBar`).
  (String, String?) _totals(List<MasterService> services) {
    double minSum = 0;
    double maxSum = 0;
    int minutes = 0;
    for (final MasterService s in services) {
      final double lo = s.priceMin;
      final double hi = s.priceType == ServicePriceType.range
          ? (s.priceMax ?? lo)
          : lo;
      minSum += lo;
      maxSum += hi;
      minutes += s.durationMinutes;
    }
    final ({String priceLabel, String? durationLabel}) totals =
        formatBookingTotals(minSum: minSum, maxSum: maxSum, minutes: minutes);
    return (totals.priceLabel, totals.durationLabel);
  }
}
