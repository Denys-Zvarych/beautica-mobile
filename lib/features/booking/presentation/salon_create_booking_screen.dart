// Phase 250 — SalonCreateBookingScreen: the SALON «Новий запис» 6-step
// wizard — a walk-in / phone booking a `SALON_OWNER`/`SALON_ADMIN` creates
// on behalf of the salon, choosing which of the salon's masters performs it.
//
// DESIGN SOURCE (locked): transcribed from `docs/signup-designs/
// SalonManagementDesign/lib/screens/create_booking_screen.dart` (2026-07-09).
// This is the SAME design Phase 247 ported for the INDEPENDENT_MASTER
// variant — that phase DROPPED the `masters` step (an independent master is
// the only possible master). This is the variant the design was actually
// drawn for: the `masters` step is restored, and it is where TIME selection
// lives (see `widgets/salon_booking_wizard_steps.dart`'s header for why
// `dateTime` here is DATE-ONLY).
//
// Steps: `client → service → dateTime → masters → confirm → done`.
//
// ## REUSE-FIRST — what this screen is actually built from
//
//   * `client` / `service` / `confirm` — the SAME [ClientStep] / [ServiceStep]
//     / [ConfirmStep] the master wizard uses, promoted in Phase 249
//     (`widgets/booking_wizard_steps.dart`). [ServiceStep] is fed the SALON's
//     aggregate catalogue via its Phase 250 additive `servicesOverride`
//     param (NOT `servicesListProvider` — see that param's own doc for why
//     "my own services" is the wrong question for a `SALON_ADMIN` caller,
//     who has no master profile at all). [ConfirmStep] is fed a master
//     identity card via its Phase 250 additive `masterCard` param.
//   * `dateTime` / `masters` — Phase 250's OWN two new widgets
//     ([SalonDateStep] / [SalonMastersStep]), NOT the promoted [DateTimeStep]
//     — see `salon_booking_wizard_steps.dart`'s header for why that promoted
//     widget cannot be reused here (it needs a KNOWN master up front; this
//     wizard doesn't have one until the `masters` step itself).
//   * `done` — reuses [BookingSuccessScaffold] / [SuccessSecondaryButton] /
//     [BookingSummaryCards], exactly like the master wizard's own private
//     `_DoneStep` (not promoted — each wizard root owns its own terminal
//     payoff, mirrors `master_create_booking_screen.dart`'s own file header).
//
// ## Masters-provider choice (staff caller, not a public client)
//
// [salonStaffMastersRosterProvider] (`salon/application/
// salon_staff_masters_roster.dart`, 2026-10-05): the management `/staff`
// roster projected onto its masters — NOT the public `/masters` rail, which
// lists only BOOKABLE masters, and NOT `publicSalonProfileProvider` (tuned
// for the CLIENT-facing profile screen's lifecycle). Coverage
// (`salonMasterServiceCoverageProvider`) and slots
// (`salonMasterDaySlotsProvider`) are the SAME families the CLIENT-facing
// salon booking flow already uses — see `salon_booking_wizard_steps.dart`.
//
// ## `salonId` is NEVER sent in the create call
//
// `CreateMasterBookingRequest` (Phase 246) has no `salonId` field at all —
// the endpoint is `POST /api/v1/masters/{masterId}/bookings`; the backend
// derives the salon from the master server-side (backend `phase-171`
// amendment A2). `widget.salonId` is used ONLY to list this salon's masters
// (`SalonMastersStep`) — it never reaches the request body, structurally
// (there is no field to put it in).
//
// ## Deviations from the design file
//
//   1. Header uses [BookingTopBar] (as the master wizard already deviates,
//      see its own doc) rather than a literal port of the design's
//      `_CreateHeader`. Consistency with every other booking-flow screen's
//      chrome.
//   2. `confirm` shows THE shared [MasterStrip] feeding
//      [BookingSummaryCards.masterCard] (already a supported slot on that
//      shared widget) rather than the design's bespoke
//      `NeumorphicCard(color: 0xFFEDE4D5)` block — the SAME "who you're
//      booking with" visual grammar the rest of this app's booking flow
//      already uses, not a second bespoke card shape. Until 2026-09-19 this
//      was a private `_SalonConfirmMasterCard` that hand-rebuilt the strip's
//      row from [MasterStripShell]'s own text tokens; that fork is gone
//      (REUSE-FIRST, reversing phase-339 D3) and `_buildMasterCard` now
//      returns the strip itself, which also brings the design's shadow and
//      the shared avatar badge back.
//   3. `masters`-step status pill is not the design's eager three-state
//      N-slots/Зайнятий/Не-виконує pill: a covering, bookable master carries
//      NO pill at all, and a non-covering master is hidden outright rather
//      than shown dimmed. Slots ARE fetched eagerly for every COVERING
//      master on mount (2026-09-18 real-device fix, reversing this
//      deviation's earlier "lazily on tile expand" text) so a master with
//      genuinely zero free time on the picked day renders disabled with
//      «Немає вільного часу» without requiring a tap — see
//      `salon_booking_wizard_steps.dart`'s header for the full rationale and
//      fan-out bound.
//   4. No «Коментар для майстра» field on `confirm` — mirrors the master
//      wizard's OWN deviation #5: `CreateMasterBookingRequest` carries no
//      `clientComment` field to transmit it through.
//   5. No «Додати в календар» link on `done` — mirrors the master wizard's
//      deviation #6 (would need a guest-identity `buildCalendarDescription`
//      parameter that does not exist; a fake button is worse than none).
//   6. Done-step copy does not claim an SMS/notification was sent — the
//      backend's confirmation SMS is gated off by default (backend Phase
//      22.7); see [AppLocalizations.salonCreateBookingDoneSubline].
//   7. «Далі» CTA labels on `client`/`service` reuse the app's generic
//      wording (via the promoted steps themselves), matching the master
//      wizard; the `dateTime` step's own advance CTA (`salonCreateBooking
//      DateNextCta`) used to be transcribed literally ("Далі — Майстри")
//      since no existing generic convention covered it — 2026-09-18:
//      reverted to the generic «Далі» wording after all, matching
//      `registerNextStep`/`registerContinue`/`step2CtaContinue`/
//      `bookingNextCta`'s existing convention of duplicate-by-value keys.
//      The `dateTime` CTA also moved from embedded-in-scroll to a pinned
//      [BookingCtaFooter], matching every other step.
//
// ## Walk-in only / no existing-client toggle
//
// See [ClientStep]'s own doc — unchanged, reused verbatim. Backend Phase
// 22.3 (linking a walk-in to an existing app client) is deferred; there is
// no field for it.
//
// ## PHASE 253 — `service` becomes multi-select, sharing [ServiceStep]'s
// widened path with the master wizard
//
// `service` used to auto-navigate straight to `dateTime` on a single tap
// (`onSelect` immediately called `_goTo`). That is exactly the "selection
// navigates" defect the master wizard already fixed for its own steps
// (2026-08-20 UX note above `_NextCtaFooter`) — and multi-select makes it
// outright wrong here too: a tap that jumps away gives no chance to pick a
// second service. `service` now gets its own pinned [BookingSummaryBar]
// footer (the SAME reused widget the master wizard's `_buildBottomBar` now
// pins for this step), and selection is SELECT ONLY — see
// `master_create_booking_screen.dart`'s widened header for the shared
// `CatalogueSelectionController` / ordered-list / cap-toggle mechanics,
// which this screen owns its own instance of (never a shared instance
// across the two wizards — each wizard is an independent widget subtree).
// `SalonMastersStep`'s per-master coverage check, `confirm`, and `_submit`
// used to still key off exactly one service via a TEMPORARY `_primaryService`
// shim (same as the pre-multi-service master wizard's own) — phases 335–340
// closed that gap:
//
//   * Phase 335 — `SalonMastersStep` covers EVERY selected service: a master
//     is bookable only if they cover the whole visit (`every`, not `any`),
//     mirroring `project_salon_scheduling_is_per_master` (one master
//     performs the whole visit).
//   * Phase 336 — the `masters` step's slot fetch chains every selected
//     service's assignment id, so the times it offers are times the whole
//     visit actually fits (never sized to service #1 alone).
//   * Phase 337 — `SalonMastersStep.onPick` returns every assignment id,
//     ordered index-for-index with `_selectedServices`, and this screen holds
//     them as `_assignmentIds` (a changed selection after a pick clears
//     `_master`/`_assignmentIds`/`_startAt` — `_onToggleService`).
//   * Phase 338 — `_submit` sends `masterServiceIds: _assignmentIds`
//     (every selected service), and `_primaryService` is deleted.
//   * Phase 339 — `confirm` renders `services: _selectedServices` (every
//     service + one «Разом» total), reaching `ConfirmStep`'s already-built
//     multi path (`booking_wizard_steps.dart`).
//
// Ordering was deliberate: 338 shipped BEFORE 339 so the wizard was never
// caught mid-track displaying an N-service recap against a request that
// still only booked service #1 (see phase 338/339's own "D0 — ORDERING"
// decisions).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/features/salon/application/salon_service_catalog_notifier.dart';
import 'package:beautica_mobile/features/salon/domain/salon_master_summary.dart';
import 'package:beautica_mobile/features/salon/domain/salon_service_catalog.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/feedback/show_velvet_snack.dart';
import 'package:beautica_mobile/shared/formatters/booking_date_labels.dart';
import 'package:beautica_mobile/shared/formatters/duration_minutes.dart';
import 'package:beautica_mobile/shared/formatters/service_price_display.dart';

import '../application/master_create_booking_notifier.dart'
    show masterCreateBookingProvider;
import '../application/salon_booking_schedule_notifier.dart'
    show salonMasterDaySlotsProvider;
import '../data/slot_repository.dart' show maxServicesPerVisit;
import '../domain/appointment.dart';
import '../domain/booking_slot.dart';
import '../domain/create_master_booking_request.dart';
import 'widgets/booking_cta_footer.dart';
import 'widgets/booking_recap.dart';
import 'widgets/booking_success_scaffold.dart';
import 'widgets/booking_summary_bar.dart';
import 'widgets/booking_summary_cards.dart';
import 'widgets/booking_top_bar.dart';
import 'widgets/booking_wizard_steps.dart';
import 'widgets/master_strip.dart' show MasterStrip;
import 'widgets/salon_avatar_gradients.dart';
import 'widgets/salon_booking_wizard_steps.dart';
import 'widgets/service_catalogue_accordion.dart'
    show CatalogueSelectionController;
import 'widgets/selected_services_shelf.dart' show salonServiceForShelf;

export '../application/master_create_booking_notifier.dart'
    show masterCreateBookingProvider;

// ---------------------------------------------------------------------------
// Step enum — SIX values, `masters` restored (this is the variant the
// design was drawn for — see file header).
// ---------------------------------------------------------------------------

enum _BookingStep { client, service, dateTime, masters, confirm, done }

// ---------------------------------------------------------------------------
// Root screen
// ---------------------------------------------------------------------------

/// The salon «Новий запис» wizard — see file header for the full reuse map.
class SalonCreateBookingScreen extends ConsumerStatefulWidget {
  const SalonCreateBookingScreen({super.key, required this.salonId});

  /// Used ONLY to list this salon's masters (`SalonMastersStep`) — never
  /// sent in the create call, see this file's header.
  final String salonId;

  @override
  ConsumerState<SalonCreateBookingScreen> createState() =>
      _SalonCreateBookingScreenState();
}

class _SalonCreateBookingScreenState
    extends ConsumerState<SalonCreateBookingScreen> {
  _BookingStep _step = _BookingStep.client;

  final TextEditingController _firstNameCtrl = TextEditingController();
  final TextEditingController _lastNameCtrl = TextEditingController();
  final TextEditingController _phoneCtrl = TextEditingController();

  // PHASE 253 — multi-select service state, the SAME shape the master
  // wizard now owns (its own, separate instance — see this file's header).
  final CatalogueSelectionController _selectionController =
      CatalogueSelectionController();
  final List<MasterService> _selectedServices = <MasterService>[];
  DateTime? _date;
  SalonMasterSummary? _master;

  /// PHASE 337 — one assignment id per [_selectedServices] entry, index-
  /// aligned (asserted where set). `SalonMastersStep.onPick`'s ordered
  /// return value, stored verbatim.
  List<String> _assignmentIds = <String>[];
  DateTime? _startAt;

  /// PHASE 256 — mirrors `master_create_booking_screen.dart`'s identical
  /// field (own doc there) — the screen-owned reentrancy guard covering the
  /// gap the notifier's own `isLoading` guard cannot: the turn between the
  /// submit future resolving and this screen's own `setState` to `done`.
  ///
  /// Audit-fix cycle 1 (mobile-perf MEDIUM, 2026-08-21) — a [ValueNotifier],
  /// NOT a plain field mutated through `setState`, mirroring the master
  /// wizard's identical fix (own doc there): the flag is read by exactly one
  /// widget (`_SalonConfirmCtaFooter`, only reachable on `confirm`), so a
  /// `setState` here reconstructed the whole six-step wizard subtree for a
  /// change only one leaf cares about. `.value` writes are exactly as
  /// synchronous as the plain-field write they replace — the guard is set
  /// `true` at the top of [_submit] BEFORE any `await` and only ever cleared
  /// on the error path.
  final ValueNotifier<bool> _submitting = ValueNotifier<bool>(false);

  /// PHASE 256 — mirrors `master_create_booking_screen.dart`'s identical
  /// field — the server's created visit, set the instant [_submit] succeeds.
  Appointment? _createdAppointment;

  late final ScreenProtectionManager _screenProtection;

  @override
  void initState() {
    super.initState();
    // SEC — this screen collects a WALK-IN GUEST's name/phone, a third party
    // who never installed the app and never consented in it. Mirrors
    // `master_create_booking_screen.dart`'s identical guard.
    _screenProtection = ref.read(screenProtectionProvider)..acquire();
  }

  @override
  void dispose() {
    _screenProtection.release();
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _phoneCtrl.dispose();
    _submitting.dispose();
    _selectionController.dispose();
    super.dispose();
  }

  /// Toggles [service] in/out of the visit selection, capped at
  /// [maxServicesPerVisit] — see `master_create_booking_screen.dart`'s
  /// identical method doc (same pattern, same cap, own instance).
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
        _selectedServices.add(service);
      } else {
        _selectedServices.removeWhere((MasterService s) => s.id == service.id);
      }
      // PHASE 337 D3 — a changed selection invalidates any pick already
      // made on `masters`: a stale `_assignmentIds` sized to the previous
      // selection is the 409 of phase 336 by another route, and a stale
      // `_master`/`_startAt` would submit a time chosen for a different
      // visit. `service` is the only step this selection can change from
      // after a pick, so it is the only step that needs the clear.
      _master = null;
      _assignmentIds = <String>[];
      _startAt = null;
    });
    _selectionController.toggleService(service.id);
  }

  void _goTo(_BookingStep s) => setState(() => _step = s);

  /// Header back-chevron handler. On `client`, pops the whole wizard route;
  /// every other step steps back one index. Unlike the master wizard, there
  /// is no embedded date/time sub-phase to special-case here — `dateTime`
  /// and `masters` are two ordinary steps, not one combined widget with an
  /// internal phase.
  void _handleBack() {
    if (_step == _BookingStep.client) {
      context.pop();
      return;
    }
    setState(() => _step = _BookingStep.values[_step.index - 1]);
  }

  Future<void> _submit() async {
    // PHASE 256 — mirrors `master_create_booking_screen.dart`'s identical
    // guard (own doc there). Checked/flipped SYNCHRONOUSLY, before any
    // `await` — a `ValueNotifier.value` read/write is exactly as synchronous
    // as the plain-field version it replaced (audit-fix cycle 1).
    if (_submitting.value) return;
    final DateTime? startAt = _startAt;
    final SalonMasterSummary? master = _master;
    final List<String> assignmentIds = _assignmentIds;
    final String? phone = toE164UaPhone(_phoneCtrl.text);
    // Defensive — unreachable via the normal flow: `confirm` is only reached
    // once every field above is set (see `_buildStep`'s `masters` case), and
    // `client`'s Next is disabled until the phone normalizes.
    if (_selectedServices.isEmpty ||
        startAt == null ||
        master == null ||
        assignmentIds.isEmpty ||
        phone == null) {
      return;
    }
    // No `setState` — only the [ValueListenableBuilder] scoped around
    // [_SalonConfirmCtaFooter] depends on this flag (see [_submitting]'s
    // doc).
    _submitting.value = true;

    final CreateMasterBookingRequest request = CreateMasterBookingRequest(
      // PHASE 338 — every selected service's assignment id, in tap order.
      // The chosen master's OWN per-master assignment ids — NEVER
      // `service.id`/`service.serviceDefId` (the salon-catalog id). See
      // `SalonMastersStep.onPick`'s own doc. Passed verbatim, no
      // re-derivation, no re-sorting (phase 337 D2 already guarantees
      // `_assignmentIds` is index-aligned with `_selectedServices`).
      masterServiceIds: assignmentIds,
      startsAt: startAt,
      guest: WalkInGuest(
        name: _firstNameCtrl.text.trim(),
        surname: _lastNameCtrl.text.trim(),
        phone: phone,
      ),
    );
    // PHASE 256 — the notifier now returns the SERVER's created [Appointment]
    // — see `master_create_booking_notifier.dart`'s doc.
    final Appointment? created = await ref
        .read(masterCreateBookingProvider.notifier)
        // `salonId` is NOT part of `request` (see this file's header — the
        // salon is never sent to the backend). It rides alongside it purely
        // so the success fan-out can drop THIS board's day-rail dot set
        // (`salonBookedDaysProvider(salonId)`) as well as the master-scoped
        // one — without it the newly-booked day stayed undotted for up to the
        // provider's thirty-minute `keepAlive` TTL.
        .submit(
          masterId: master.masterId,
          request: request,
          salonId: widget.salonId,
        );
    if (!mounted) return;
    final AsyncValue<void> result = ref.read(masterCreateBookingProvider);
    if (result.hasError) {
      // No `setState` here either — see the analogous note in the master
      // wizard's `_submit`.
      _submitting.value = false;
      _maybeShowDuplicateSnack(result.error);
      return;
    }
    if (created == null) return; // defensive — unreachable when !hasError
    setState(() {
      _createdAppointment = created;
      _step = _BookingStep.done;
    });
  }

  /// Mirrors `master_create_booking_screen.dart`'s identical method (own
  /// doc there) — the ONE deliberate deviation is the recovery step: THIS
  /// wizard picks its slot on `masters` (via [SalonMastersStep]), not
  /// `dateTime` (date-only here), so «Оновити» returns there instead.
  void _maybeShowDuplicateSnack(Object? error) {
    if (error is! MasterBookingDuplicateFailure) return;
    final l10n = AppLocalizations.of(context);
    showErrorSnack(
      context,
      l10n.errMasterBookingDuplicate,
      actionLabel: l10n.masterCreateBookingDuplicateRefreshAction,
      onAction: _handleDuplicateRefresh,
    );
  }

  /// «Оновити» on the duplicate-409 snack — returns to `masters` (where THIS
  /// wizard's slot picker lives — see [_maybeShowDuplicateSnack]) and drops
  /// every cached slot fetch so re-picking genuinely re-fetches.
  void _handleDuplicateRefresh() {
    // Mirrors `master_create_booking_screen.dart`'s identical guard (own
    // doc there) — this screen has NO `PopScope` at all (file header: "No
    // `PopScope` needed here"), so the system back gesture pops `confirm`
    // even more readily than the master wizard's. The 6s-dwelling snack
    // outlives that pop (root overlay, independent subtree), so a tap on
    // its action must not touch `ref`/`setState` on a disposed State.
    if (!mounted) return;
    ref.invalidate(salonMasterDaySlotsProvider);
    setState(() => _step = _BookingStep.masters);
  }

  String _titleFor(AppLocalizations l10n, _BookingStep step) => switch (step) {
    _BookingStep.client => l10n.masterCreateBookingTitle,
    _BookingStep.service => l10n.masterCreateBookingServiceTitle,
    _BookingStep.dateTime => l10n.salonCreateBookingDateTitle,
    _BookingStep.masters => l10n.salonCreateBookingMastersStepTitle,
    _BookingStep.confirm => l10n.bookingConfirmScreenTitle,
    _BookingStep.done => '',
  };

  /// The salon's aggregate catalogue, mapped to [MasterService] for
  /// [ServiceStep]'s `servicesOverride` — see that param's own doc.
  AsyncValue<List<MasterService>> _salonServicesAsync(WidgetRef ref) {
    return ref
        .watch(salonServiceCatalogProvider(widget.salonId))
        .whenData(
          (List<SalonServiceCategoryEntry> catalog) => <MasterService>[
            for (final SalonServiceCategoryEntry c in catalog)
              for (final SalonCatalogService s in c.services)
                salonServiceForShelf(s),
          ],
        );
  }

  Widget _buildStep(AppLocalizations l10n) {
    switch (_step) {
      case _BookingStep.client:
        return ClientStep(
          key: const ValueKey<_BookingStep>(_BookingStep.client),
          firstNameCtrl: _firstNameCtrl,
          lastNameCtrl: _lastNameCtrl,
          phoneCtrl: _phoneCtrl,
          onNext: () => _goTo(_BookingStep.service),
        );
      case _BookingStep.service:
        return ServiceStep(
          key: const ValueKey<_BookingStep>(_BookingStep.service),
          // PHASE 253 — multi-select path, SELECT ONLY (see this file's
          // header). Advancing is the pinned [BookingSummaryBar] CTA's job
          // (`_buildBottomBar`), same as the master wizard.
          selectedServiceIds: _selectionController,
          onToggleService: _onToggleService,
          servicesOverride: _salonServicesAsync(ref),
          onRetryOverride: () =>
              ref.invalidate(salonServiceCatalogProvider(widget.salonId)),
          emptyTitleOverride: l10n.salonCreateBookingServiceEmptyTitle,
          emptyBodyOverride: l10n.salonCreateBookingServiceEmptyBody,
        );
      case _BookingStep.dateTime:
        return SalonDateStep(
          key: const ValueKey<_BookingStep>(_BookingStep.dateTime),
          salonId: widget.salonId,
          services: _selectedServices,
          selected: _date,
          onSelect: (DateTime d) => setState(() => _date = d),
        );
      case _BookingStep.masters:
        return SalonMastersStep(
          key: const ValueKey<_BookingStep>(_BookingStep.masters),
          salonId: widget.salonId,
          services: _selectedServices,
          date: _date!,
          onPick:
              (
                SalonMasterSummary master,
                List<String> assignmentIds,
                BookingSlot slot,
              ) {
                setState(() {
                  _master = master;
                  _assignmentIds = assignmentIds;
                  _startAt = slot.startAt;
                });
                _goTo(_BookingStep.confirm);
              },
        );
      case _BookingStep.confirm:
        return ConfirmStep(
          key: const ValueKey<_BookingStep>(_BookingStep.confirm),
          services: _selectedServices,
          startAt: _startAt!,
          firstName: _firstNameCtrl.text.trim(),
          lastName: _lastNameCtrl.text.trim(),
          phone: _phoneCtrl.text.trim(),
          masterCard: _buildMasterCard(_master!),
        );
      case _BookingStep.done:
        // Unreachable — `done` is rendered directly from `build()` below,
        // never through `AnimatedSwitcher`/`_buildStep` (mirrors the master
        // wizard's own `_buildStep` doc).
        return const SizedBox.shrink();
    }
  }

  /// The confirm step's «Запис до майстра» identity card.
  ///
  /// THE shared [MasterStrip] — the same widget the salon master picker, the
  /// slot picker, «Деталі запису» and both success screens render. This used
  /// to be a private `_SalonConfirmMasterCard` that hand-rebuilt the strip's
  /// row out of [MasterStripShell]'s own `masterStripLabel`/`masterStripName`
  /// tokens; reusing the strip itself is the REUSE-FIRST rule (CLAUDE.md) and
  /// reverses phase-339 decision D3. No parameter had to be added: the strip
  /// already takes every field as a primitive.
  Widget _buildMasterCard(SalonMasterSummary master) {
    final int gradientIndex = master.masterId.hashCode.abs() % 6;
    return MasterStrip(
      key: const Key('salon-create-booking-master-card'),
      name: '${master.firstName} ${master.lastName}'.trim(),
      type: master.type,
      professionalTitle: master.professionalTitle,
      // Same "unrated reads «—», never «0.0»" fold the removed fork applied
      // (and `MasterStrip.fromSchedule`'s own) — verbatim, not widened.
      avgRating: master.reviewCount > 0 ? master.avgRating : null,
      reviewCount: master.reviewCount,
      showLabel: true,
      showRole: true,
      showRating: master.reviewCount > 0,
      avatarGradient: salonAvatarGradient(gradientIndex),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    if (_step == _BookingStep.done) {
      final Appointment? appointment = _createdAppointment;
      if (appointment == null) {
        // Defensive — unreachable via the normal flow (see `_buildStep`).
        return const Scaffold(body: SizedBox.shrink());
      }
      return _SalonDoneStep(
        appointment: appointment,
        onClose: () => context.pop(),
      );
    }

    // No `PopScope` needed here (unlike the master wizard, which guards an
    // embedded date/time sub-phase) — `dateTime` and `masters` are two
    // ordinary steps, and `done` renders as an entirely separate subtree
    // (via `BookingSuccessScaffold`'s own `PopScope(canPop: false)`) above,
    // never reaching this branch at all.
    return Scaffold(
      backgroundColor: BrandColors.base,
      bottomNavigationBar: switch (_step) {
        // PHASE 253 — [BookingSummaryBar] REUSED as the `service` step's
        // pinned footer (same widget, same wiring as the master wizard's
        // `_buildBottomBar` — see this file's header). Previously this step
        // had no footer at all: `onSelect` navigated straight through.
        _BookingStep.service => BookingSummaryBar(
          services: _selectedServices,
          ctaLabel: l10n.bookingNextCta,
          ctaIcon: Icons.arrow_forward_rounded,
          enabled: _selectedServices.isNotEmpty,
          onAction: () => _goTo(_BookingStep.dateTime),
          onRemove: _onToggleService,
        ),
        // 2026-09-18 real-device fix — was embedded inside [SalonDateStep]'s
        // own `SingleChildScrollView` (a deliberate deviation from the
        // approved design at the time, see this file's deviation #7); the
        // user asked for it pinned like every other step's footer instead.
        // [BookingCtaFooter] REUSED verbatim (same widget the `confirm`
        // footer below and the master wizard's confirm step already use),
        // not a hand-rolled bar.
        _BookingStep.dateTime => BookingCtaFooter(
          label: l10n.salonCreateBookingDateNextCta,
          enabled: _date != null,
          loading: false,
          onPressed: () => _goTo(_BookingStep.masters),
          buttonKey: const Key('salon-create-booking-date-next'),
          icon: Icons.arrow_forward_rounded,
        ),
        // Only this footer depends on `_submitting` — same scoping primitive
        // as the master wizard's confirm-step footer (audit-fix cycle 1,
        // mobile-perf MEDIUM: see [_submitting]'s own doc).
        _BookingStep.confirm => ValueListenableBuilder<bool>(
          valueListenable: _submitting,
          builder: (BuildContext context, bool submitting, Widget? child) =>
              _SalonConfirmCtaFooter(onSubmit: _submit, submitting: submitting),
        ),
        _ => null,
      },
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            BookingTopBar(
              title: _titleFor(l10n, _step),
              backSemantics: l10n.registerBackStep,
              backKey: const Key('salon-create-booking-back'),
              onBack: _handleBack,
            ),
            StepIndicator(currentStep: _step.index, totalSteps: 5),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                transitionBuilder: (Widget child, Animation<double> a) =>
                    // dim-decorative: step cross-fade (AnimatedSwitcher); 1 at rest
                    FadeTransition(opacity: a, child: child),
                child: _buildStep(l10n),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Confirm CTA footer — thin wrapper over the shared BookingCtaFooter, byte-
// identical shape to the master wizard's own private `_ConfirmCtaFooter`.
// ---------------------------------------------------------------------------

class _SalonConfirmCtaFooter extends ConsumerWidget {
  const _SalonConfirmCtaFooter({
    required this.onSubmit,
    required this.submitting,
  });

  final VoidCallback onSubmit;

  /// PHASE 256 — mirrors `master_create_booking_screen.dart`'s
  /// `_ConfirmCtaFooter.submitting` (own doc there).
  final bool submitting;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final bool inFlight = ref.watch(
      masterCreateBookingProvider.select((AsyncValue<void> s) => s.isLoading),
    );
    final bool busy = submitting || inFlight;
    return BookingCtaFooter(
      key: const Key('salon-create-booking-cta-footer'),
      buttonKey: const Key('salon-create-booking-submit-cta'),
      label: busy ? l10n.bookingSubmitCtaLoading : l10n.bookingSubmitCta,
      enabled: !busy,
      loading: busy,
      onPressed: onSubmit,
    );
  }
}

// ---------------------------------------------------------------------------
// Done — success payoff, reuses BookingSuccessScaffold (see file header).
// ---------------------------------------------------------------------------

/// PHASE 338 (D5) — mirrors `master_create_booking_screen.dart`'s `_DoneStep`
/// (own doc there): renders the SERVER's [appointment] — every ordered
/// `items[]` entry, not the wizard's local selection. Before this phase the
/// wizard only ever sent one service, so `items` always had exactly one
/// entry; now the request carries every selected service's assignment id
/// (phase 338 D1), and the done step must be able to show all of them —
/// matching what `ConfirmStep` already shows one step earlier for the SAME
/// visit (phase 339's `services:` swap).
class _SalonDoneStep extends StatelessWidget {
  const _SalonDoneStep({required this.appointment, required this.onClose});

  final Appointment appointment;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    // REUSE — the same per-item -> [BookingSelection] mapping `ConfirmStep`
    // uses for its local selection (`booking_wizard_steps.dart:751-761`),
    // just fed from the SERVER's `items[]` instead of the wizard's
    // `MasterService` list. The «Разом» total is never summed here: passing
    // `selections:` reaches `BookingRecap`'s existing `_BookingTotals.from`
    // (via `formatBookingTotalsFromTerms`), the one place that knows how
    // FIXED and RANGE prices combine (D1/D2).
    final List<BookingSelection> selections = <BookingSelection>[
      for (final AppointmentItem item in appointment.items)
        BookingSelection(
          name: item.serviceName,
          price: ServicePriceDisplay.formatRange(item.price, item.priceMax),
          duration: DurationMinutes.format(item.durationMinutes),
          durationMinutes: item.durationMinutes,
          priceMin: item.price,
          priceMax: item.priceMax,
        ),
    ];

    return BookingSuccessScaffold(
      title: l10n.bookingSuccessTitle,
      // Deviation #6 (file header) — no SMS/notification claim.
      subline: l10n.salonCreateBookingDoneSubline,
      actions: <Widget>[
        SuccessSecondaryButton(
          buttonKey: const Key('salon-create-booking-done-cta'),
          label: l10n.masterCreateBookingDoneCta,
          icon: Icons.check_rounded,
          onPressed: onClose,
        ),
      ],
      recapCards: <Widget>[
        BookingSummaryCards(
          key: const Key('salon-create-booking-done-card'),
          showBorder: true,
          compactText: true,
          dense: true,
          showAddress: false,
          // D3 — the SERVER's window (`formatSlotTimeRange`, a real
          // persisted `endAt` — see `_DoneStep`'s identical note in the
          // master wizard for the derived-vs-persisted split).
          dateLabel: formatFullDate(appointment.startAt),
          timeLabel: formatSlotTimeRange(
            appointment.startAt,
            appointment.endAt,
          ),
          selections: selections,
        ),
      ],
    );
  }
}
