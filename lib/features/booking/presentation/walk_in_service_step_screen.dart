// Phase 264 — WalkInServiceStepScreen: the SECOND screen of the routed
// walk-in chain (`/master/bookings/new/services`), replacing the old
// single-screen wizard's `service` step.
//
// REUSE-FIRST: this screen contains no new catalogue or selection logic. It
// is a thin `Scaffold` + [BookingTopBar] + [ServiceStep] (multi-select arm,
// unchanged, `booking_wizard_steps.dart:401`) + a [BookingSummaryBar] footer
// (the SAME pinned "Разом" shelf `SlotDateScreen` uses, `slot_picker_screen
// .dart:275-281`) — moved verbatim from `master_create_booking_screen.dart`
// (the cap guard at its old `:200-218`), not copied: the wizard is deleted
// in the very next phase, so there is never a moment with two copies of this
// logic in the tree.
//
// D7 — ordering matters end to end: [_selected] is an ORDERED (tap-order,
// not catalogue-order) list, because it drives `serviceIds` on the
// downstream slot-availability request and `masterServiceIds` on the
// eventual `POST /bookings/staff` (Phase 262 D1).
//
// D8 — [masterProfileProvider] is resolved HERE, not on the guest step: this
// screen needs both the services list AND the [Master] object to build
// [BookingSlotPickerArgs].
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_notifier.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/feedback/show_velvet_snack.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';

import '../data/slot_repository.dart' show maxServicesPerVisit;
import '../domain/booking_slot_picker_args.dart';
import '../domain/create_master_booking_request.dart' show WalkInGuest;
import 'widgets/booking_summary_bar.dart';
import 'widgets/booking_top_bar.dart';
import 'widgets/booking_wizard_steps.dart' show ServiceStep;
import 'widgets/service_catalogue_accordion.dart'
    show CatalogueSelectionController;

/// «Новий запис» step 2 — the guest's service multi-selection, seeded with
/// the [guest] identity collected by [WalkInGuestStepScreen].
class WalkInServiceStepScreen extends ConsumerStatefulWidget {
  const WalkInServiceStepScreen({super.key, required this.guest});

  final WalkInGuest guest;

  @override
  ConsumerState<WalkInServiceStepScreen> createState() =>
      _WalkInServiceStepScreenState();
}

class _WalkInServiceStepScreenState
    extends ConsumerState<WalkInServiceStepScreen> {
  final CatalogueSelectionController _selectionController =
      CatalogueSelectionController();
  final List<MasterService> _selected = <MasterService>[];

  @override
  void dispose() {
    _selectionController.dispose();
    super.dispose();
  }

  /// Toggles [service] in/out of the visit selection, capped at
  /// [maxServicesPerVisit] — moved verbatim from
  /// `master_create_booking_screen.dart`'s `_onToggleService` (the same
  /// pattern `service_selector_sheet.dart`'s `_onToggleService` uses for the
  /// client flow): an ADD that would exceed the cap is refused with a
  /// friendly snack; a REMOVE is never blocked, even while already at the
  /// cap.
  void _onToggleService(MasterService service) {
    final bool willAdd = !_selectionController.isSelected(service.id);
    if (willAdd && _selectionController.value.length >= maxServicesPerVisit) {
      final l10n = AppLocalizations.of(context);
      showWarningSnack(
        context,
        l10n.bookingMaxServicesReached(maxServicesPerVisit),
      );
      return;
    }
    setState(() {
      if (willAdd) {
        _selected.add(service);
      } else {
        _selected.removeWhere((MasterService s) => s.id == service.id);
      }
    });
    _selectionController.toggleService(service.id);
  }

  void _onNext(Master master) {
    context.push(
      RouteNames.bookingSlots,
      extra: BookingSlotPickerArgs(
        masterId: master.id,
        master: master,
        // Ordering matters end to end — tap order is performance order (D7).
        services: List<MasterService>.unmodifiable(_selected),
        guest: widget.guest,
        hideMasterIdentity: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final AsyncValue<Master> masterAsync = ref.watch(masterProfileProvider);

    return Scaffold(
      backgroundColor: BrandColors.base,
      bottomNavigationBar: masterAsync.maybeWhen(
        data: (Master master) => BookingSummaryBar(
          services: _selected,
          ctaLabel: l10n.bookingNextCta,
          ctaIcon: Icons.arrow_forward_rounded,
          enabled: _selected.isNotEmpty,
          onAction: () => _onNext(master),
          // Same toggle the catalogue card uses, so both removal paths
          // converge on identical end-state (mirrors
          // `service_selector_sheet.dart`'s `onRemove` wiring).
          onRemove: _onToggleService,
        ),
        orElse: () => null,
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            BookingTopBar(
              title: l10n.masterCreateBookingServiceTitle,
              backSemantics: l10n.registerBackStep,
              backKey: const Key('walk-in-service-back'),
              onBack: () => context.pop(),
            ),
            Expanded(
              child: masterAsync.when(
                data: (Master master) => ServiceStep(
                  selectedServiceIds: _selectionController,
                  onToggleService: _onToggleService,
                ),
                loading: () => const Center(
                  key: ValueKey<String>('walk-in-service-master-loading'),
                  child: CircularProgressIndicator(color: BrandColors.accent),
                ),
                error: (Object e, StackTrace _) => ErrorState(
                  key: const Key('walk-in-service-master-error'),
                  failure: e is Failure ? e : UnknownFailure(cause: e),
                  onRetry: () => ref.invalidate(masterProfileProvider),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
