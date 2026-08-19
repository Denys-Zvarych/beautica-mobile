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
// See `application/salon_masters_roster_notifier.dart`'s header for the full
// reasoning: [salonMastersRosterProvider] (new, thin), NOT
// `publicSalonProfileProvider` (over-fetches the full salon detail and is
// tuned for the CLIENT-facing profile screen's lifecycle). Coverage
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
//   2. `confirm` shows a master identity card built from [MasterStrip]'s
//      leaf pieces feeding [BookingSummaryCards.masterCard] (already a
//      supported slot on that shared widget) rather than the design's
//      bespoke `NeumorphicCard(color: 0xFFEDE4D5)` block — the SAME
//      "who you're booking with" visual grammar the rest of this app's
//      booking flow already uses, not a second bespoke card shape.
//   3. `masters`-step status pill is two-state ("Виконує"/"Не виконує"), not
//      the design's eager three-state N-slots/Зайнятий/Не-виконує pill, and
//      slots are fetched lazily on tile expand, not eagerly for every master
//      on mount — see `salon_booking_wizard_steps.dart`'s header for the
//      full fan-out rationale.
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
//      wizard; the `dateTime` step's own advance CTA IS transcribed
//      literally ("Далі — Майстри") since — unlike the client step — no
//      existing generic convention covers it.
//
// ## Walk-in only / no existing-client toggle
//
// See [ClientStep]'s own doc — unchanged, reused verbatim. Backend Phase
// 22.3 (linking a walk-in to an existing app client) is deferred; there is
// no field for it.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/features/salon/application/salon_service_catalog_notifier.dart';
import 'package:beautica_mobile/features/salon/domain/salon_master_summary.dart';
import 'package:beautica_mobile/features/salon/domain/salon_service_catalog.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/formatters/booking_date_labels.dart';
import 'package:beautica_mobile/shared/formatters/duration_minutes.dart';
import 'package:beautica_mobile/shared/formatters/service_price_display.dart';

import '../application/master_create_booking_notifier.dart'
    show masterCreateBookingProvider;
import '../domain/booking_slot.dart';
import '../domain/create_master_booking_request.dart';
import 'widgets/booking_cta_footer.dart';
import 'widgets/booking_recap.dart';
import 'widgets/booking_success_scaffold.dart';
import 'widgets/booking_summary_cards.dart';
import 'widgets/booking_top_bar.dart';
import 'widgets/booking_wizard_steps.dart';
import 'widgets/master_strip.dart' show MasterRatingReadout, masterRoleLabel;
import 'widgets/salon_avatar_gradients.dart';
import 'widgets/salon_booking_wizard_steps.dart';
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

  MasterService? _service;
  DateTime? _date;
  SalonMasterSummary? _master;
  String? _assignmentId;
  DateTime? _startAt;

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
    super.dispose();
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
    final MasterService? service = _service;
    final DateTime? startAt = _startAt;
    final SalonMasterSummary? master = _master;
    final String? assignmentId = _assignmentId;
    final String? phone = toE164UaPhone(_phoneCtrl.text);
    // Defensive — unreachable via the normal flow: `confirm` is only reached
    // once every field above is set (see `_buildStep`'s `masters` case), and
    // `client`'s Next is disabled until the phone normalizes.
    if (service == null ||
        startAt == null ||
        master == null ||
        assignmentId == null ||
        phone == null) {
      return;
    }

    final CreateMasterBookingRequest request = CreateMasterBookingRequest(
      // The chosen master's OWN per-master assignment id — NEVER
      // `service.id`/`service.serviceDefId` (the salon-catalog id). See
      // `SalonMastersStep.onPick`'s own doc.
      masterServiceId: assignmentId,
      startsAt: startAt,
      guest: WalkInGuest(
        name: _firstNameCtrl.text.trim(),
        surname: _lastNameCtrl.text.trim(),
        phone: phone,
      ),
    );
    await ref
        .read(masterCreateBookingProvider.notifier)
        .submit(masterId: master.masterId, request: request);
    if (!mounted) return;
    if (ref.read(masterCreateBookingProvider).hasError) return;
    setState(() => _step = _BookingStep.done);
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
          selectedServiceId: _service?.id,
          servicesOverride: _salonServicesAsync(ref),
          onRetryOverride: () =>
              ref.invalidate(salonServiceCatalogProvider(widget.salonId)),
          emptyTitleOverride: l10n.salonCreateBookingServiceEmptyTitle,
          emptyBodyOverride: l10n.salonCreateBookingServiceEmptyBody,
          onSelect: (MasterService s) {
            setState(() => _service = s);
            _goTo(_BookingStep.dateTime);
          },
        );
      case _BookingStep.dateTime:
        return SalonDateStep(
          key: const ValueKey<_BookingStep>(_BookingStep.dateTime),
          selected: _date,
          onSelect: (DateTime d) => setState(() => _date = d),
          onNext: _date == null ? null : () => _goTo(_BookingStep.masters),
        );
      case _BookingStep.masters:
        return SalonMastersStep(
          key: const ValueKey<_BookingStep>(_BookingStep.masters),
          salonId: widget.salonId,
          service: _service!,
          date: _date!,
          onPick:
              (
                SalonMasterSummary master,
                String assignmentId,
                BookingSlot slot,
              ) {
                setState(() {
                  _master = master;
                  _assignmentId = assignmentId;
                  _startAt = slot.startAt;
                });
                _goTo(_BookingStep.confirm);
              },
        );
      case _BookingStep.confirm:
        return ConfirmStep(
          key: const ValueKey<_BookingStep>(_BookingStep.confirm),
          service: _service!,
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

  Widget _buildMasterCard(SalonMasterSummary master) {
    final int gradientIndex = master.masterId.hashCode.abs() % 6;
    return _SalonConfirmMasterCard(
      master: master,
      avatarGradient: salonAvatarGradient(gradientIndex),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    if (_step == _BookingStep.done) {
      final MasterService? service = _service;
      final DateTime? startAt = _startAt;
      if (service == null || startAt == null) {
        // Defensive — unreachable via the normal flow (see `_buildStep`).
        return const Scaffold(body: SizedBox.shrink());
      }
      return _SalonDoneStep(
        service: service,
        startAt: startAt,
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
      bottomNavigationBar: (_step == _BookingStep.confirm)
          ? _SalonConfirmCtaFooter(onSubmit: _submit)
          : null,
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
// Confirm-step master identity card — leaf pieces reused (see file header
// deviation #2), the row composition is new (no existing "chrome-less
// identity row" widget fits inside another card without doubling chrome).
// ---------------------------------------------------------------------------

class _SalonConfirmMasterCard extends StatelessWidget {
  const _SalonConfirmMasterCard({
    required this.master,
    required this.avatarGradient,
  });

  final SalonMasterSummary master;
  final List<Color> avatarGradient;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final String name = '${master.firstName} ${master.lastName}'.trim();
    final String? ownTitle = master.professionalTitle?.trim();
    final String role = (ownTitle != null && ownTitle.isNotEmpty)
        ? ownTitle
        : masterRoleLabel(master.type, l10n);
    final double? rating = master.reviewCount > 0 ? master.avgRating : null;

    return DecoratedBox(
      key: const Key('salon-create-booking-master-card'),
      decoration: const BoxDecoration(
        color: Color(0xFFEDE4D5),
        borderRadius: BorderRadius.all(Radius.circular(VelvetRadii.card)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(VelvetSpacing.md),
        child: Row(
          children: <Widget>[
            Container(
              height: 48,
              width: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: avatarGradient,
                ),
              ),
              child: Center(
                child: Icon(
                  Icons.person_rounded,
                  color: BrandColors.white.withValues(alpha: 0.85),
                  size: 24,
                ),
              ),
            ),
            const SizedBox(width: VelvetSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  // The SAME caption `MasterStripShell` renders for the
                  // identical string elsewhere in this booking flow — token
                  // reuse, not a coincidence (see file header deviation #2).
                  Text(
                    l10n.bookingMasterStripLabel,
                    style: VelvetText.masterStripLabel,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: VelvetText.masterStripName,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          role,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: VelvetText.feedbackMutedSm,
                        ),
                      ),
                      if (master.reviewCount > 0)
                        MasterRatingReadout(
                          avgRating: rating,
                          reviewCount: master.reviewCount,
                        ),
                    ],
                  ),
                ],
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
  const _SalonConfirmCtaFooter({required this.onSubmit});

  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final bool inFlight = ref.watch(
      masterCreateBookingProvider.select((AsyncValue<void> s) => s.isLoading),
    );
    return BookingCtaFooter(
      key: const Key('salon-create-booking-cta-footer'),
      buttonKey: const Key('salon-create-booking-submit-cta'),
      label: inFlight ? l10n.bookingSubmitCtaLoading : l10n.bookingSubmitCta,
      enabled: true,
      loading: inFlight,
      onPressed: onSubmit,
    );
  }
}

// ---------------------------------------------------------------------------
// Done — success payoff, reuses BookingSuccessScaffold (see file header).
// ---------------------------------------------------------------------------

class _SalonDoneStep extends StatelessWidget {
  const _SalonDoneStep({
    required this.service,
    required this.startAt,
    required this.onClose,
  });

  final MasterService service;
  final DateTime startAt;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    final BookingSelection selection = BookingSelection(
      name: service.name,
      price: ServicePriceDisplay.format(service),
      duration: DurationMinutes.format(service.durationMinutes),
      durationMinutes: service.durationMinutes,
      priceMin: service.priceMin,
      priceMax: service.priceMax,
    );

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
          dateLabel: formatFullDate(startAt),
          timeLabel: formatTimeRange(startAt, service.durationMinutes),
          singleSelection: selection,
        ),
      ],
    );
  }
}
