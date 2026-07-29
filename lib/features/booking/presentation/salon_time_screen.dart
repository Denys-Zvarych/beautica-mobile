// MO-4 (single-master single-visit rework) — SalonTimeScreen: salon booking
// flow step 3 of 4 ("Час") — ONE date + ONE start time for the whole visit.
//
// The salon flow now books ONE visit against ONE chosen master (step 2), so
// this is a single date→time picker (no `PageView`, no per-master slider) —
// the same shape as the independent-master flow's `SlotDateScreen`/
// `SlotTimeScreen`, hosting a single [MasterSchedulePage] body. Availability is
// requested for the chosen master with ALL selected service ids (ordered) as a
// summed block.
//
// «Далі» (the pinned `BookingSummaryBar`) mints the visit idempotency key ONCE
// (CSPRNG-backed `Uuid().v4()`), snapshots the chosen slot into
// `SalonBookingConfirmArgs`, and pushes `RouteNames.salonBookingConfirm` — the
// single `POST /appointments` submit runs there (`AppointmentSubmit.submitVisit`).
// Backing out and re-picking a time mints a FRESH key (a new push); the confirm
// screen reuses the SAME key on a retry so an ambiguously-failed create
// de-duplicates.
//
// SEC: renders selected service names + prices via `SelectedServicesShelf` —
// acquires the app-wide screenshot guard in `initState`.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/formatters/booking_date_labels.dart';

import '../application/salon_booking_schedule_notifier.dart';
import '../domain/booking_slot.dart';
import '../domain/salon_booking_args.dart';
import '../domain/salon_booking_confirm_args.dart';
import '../domain/salon_master_schedule.dart';
import 'widgets/booking_summary_bar.dart';
import 'widgets/master_schedule_page.dart';
import 'widgets/salon_avatar_gradients.dart';
import 'widgets/selected_services_shelf.dart';

const Uuid _kUuid = Uuid();

/// Salon booking flow step 3 — single date/time picker for the chosen master.
class SalonTimeScreen extends ConsumerStatefulWidget {
  const SalonTimeScreen({super.key, required this.args});

  final SalonBookingTimeArgs args;

  @override
  ConsumerState<SalonTimeScreen> createState() => _SalonTimeScreenState();
}

class _SalonTimeScreenState extends ConsumerState<SalonTimeScreen> {
  late final ScreenProtectionManager _screenProtection;

  SalonMasterSchedule get _visit => widget.args.visit;

  @override
  void initState() {
    super.initState();
    _screenProtection = ref.read(screenProtectionProvider)..acquire();
  }

  @override
  void dispose() {
    _screenProtection.release();
    super.dispose();
  }

  void _exitTimePhase() {
    ref.read(salonBookingScheduleProvider.notifier).clearDate();
  }

  void _handleTopBarBack(bool inTimePhase) {
    if (inTimePhase) {
      _exitTimePhase();
      return;
    }
    context.pop();
  }

  /// Snapshots the chosen slot into `SalonBookingConfirmArgs` and pushes the
  /// step-4 confirmation. The visit idempotency key is minted HERE, once per
  /// tap that reaches confirm — reused unchanged by the confirm screen on a
  /// retry, freshly minted again on a re-pick (a new push).
  void _confirm(BookingSlot slot) {
    context.push(
      RouteNames.salonBookingConfirm,
      extra: SalonBookingConfirmArgs(
        salonId: widget.args.salonId,
        visit: _visit,
        startAt: slot.startAt,
        idempotencyKey: _kUuid.v4(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final SalonBookingScheduleState schedule = ref.watch(
      salonBookingScheduleProvider,
    );
    final bool inTimePhase = schedule.date != null;
    final BookingSlot? slot = schedule.slot;

    final List<MasterService> shelfServices = <MasterService>[
      for (final s in _visit.services) salonServiceForShelf(s),
    ];

    final String? windowLabel = slot == null
        ? null
        : formatBookingWindow(
            slot.startAt,
            slot.startAt.add(Duration(minutes: _visit.summedDurationMinutes)),
          );

    return PopScope(
      // While in the time-slot phase, block the real pop and step back to the
      // date/calendar phase instead; otherwise allow a normal pop to master
      // selection.
      canPop: !inTimePhase,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) _exitTimePhase();
      },
      child: Scaffold(
        backgroundColor: BrandColors.base,
        bottomNavigationBar: BookingSummaryBar(
          services: shelfServices,
          ctaLabel: l10n.bookingConfirmCta,
          ctaIcon: Icons.check_circle_outline_rounded,
          enabled: slot != null,
          showChosenWindow: true,
          chosenWindowLabel: windowLabel,
          onAction: slot == null ? () {} : () => _confirm(slot),
        ),
        body: SafeArea(
          bottom: false,
          child: Column(
            children: <Widget>[
              _TopBar(
                title: l10n.salonBookingTimeTitle,
                backSemantics: inTimePhase
                    ? l10n.salonBookingTimeBackToCalendarSemantics
                    : l10n.salonBookingTimeBackSemantics,
                onBack: () => _handleTopBarBack(inTimePhase),
              ),
              Expanded(
                child: MasterSchedulePage(
                  schedule: _visit,
                  avatarGradient: salonAvatarGradient(0),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Top bar + step indicator
// ---------------------------------------------------------------------------

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.backSemantics,
    required this.onBack,
  });

  final String title;
  final String backSemantics;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        VelvetSpacing.lg,
        VelvetSpacing.md,
        VelvetSpacing.lg,
        VelvetSpacing.sm,
      ),
      child: SizedBox(
        height: 56,
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            Align(
              alignment: Alignment.centerLeft,
              child: NeumorphicIconButton(
                key: const Key('salon-time-back'),
                icon: Icons.arrow_back_ios_new_rounded,
                semanticLabel: backSemantics,
                onTap: onBack,
              ),
            ),
            Text(
              title,
              style: VelvetText.subheading(),
              textAlign: TextAlign.center,
            ),
            const Align(
              alignment: Alignment.centerRight,
              child: _StepIndicator(current: 3, total: 4),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.current, required this.total});

  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      label: l10n.salonBookingStepLabel(current, total),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: VelvetSpacing.sm + 2,
              vertical: 3,
            ),
            decoration: BoxDecoration(
              color: BrandColors.base,
              borderRadius: BorderRadius.circular(VelvetRadii.pill),
              boxShadow: VelvetShadows.extrudedSmall,
            ),
            child: Text(
              l10n.salonBookingStepLabel(current, total),
              style: VelvetText.stepPillLabel,
            ),
          ),
          const SizedBox(height: VelvetSpacing.sm),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (int i = 1; i <= total; i++) ...<Widget>[
                Container(
                  height: 4,
                  width: i == current ? 20 : 12,
                  decoration: BoxDecoration(
                    color: i <= current
                        ? BrandColors.accent
                        : BrandColors.faint.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(VelvetRadii.pill),
                  ),
                ),
                if (i < total) const SizedBox(width: 4),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
