// Phase 247 (part 2 of 2) — MasterCreateBookingScreen: the INDEPENDENT_MASTER
// «Новий запис» wizard — a walk-in / phone booking the master creates on
// their OWN calendar for a guest with no app account.
//
// Phase 249 — PURE MOVE, no behaviour change: the six step widgets
// (`StepIndicator`, `ClientStep`, `ServiceStep`, `ServiceStepEmpty`,
// `DateTimeStep`, `ConfirmStep`) that used to be private to this file are now
// promoted to `widgets/booking_wizard_steps.dart` (dropped the leading
// underscore) so Phase 250's salon wizard can reuse them without forking.
// This file now only owns the wizard's ROOT scaffold (step routing, header,
// PopScope, submit orchestration) plus the `done`-step payoff and its CTA
// footer, which were NOT promoted (see that phase doc's table).
//
// DESIGN SOURCE (locked 2026-08-19): transcribed from
// `docs/signup-designs/SalonManagementDesign/lib/screens/
// create_booking_screen.dart` (2026-07-09) — NOT the superseded
// `docs/signup-designs/MasterCreateBookingWizard/` preview (see that
// directory's own `SUPERSEDED.md` and phase-245's RESOLVED block). The design
// file's `masters` step is dropped: an INDEPENDENT_MASTER is the only
// possible master, so a one-row picker would be pointless — see phase-245/247
// for the full rationale. The remaining FIVE steps
// (`client → service → dateTime → confirm → done`) are transcribed, with the
// deviations below.
//
// ## REUSE-FIRST — what this screen is actually built from
//
// Per the phase docs and this repo's locked REUSE-FIRST rule, almost nothing
// here is new UI:
//   • `dateTime` — reuses [MasterSchedulePage] (the salon flow's inline
//     date→time picker body) UNMODIFIED, fed a [SalonMasterSchedule] built
//     from this master's own profile + the ONE picked service. This is
//     exactly the "date+time as one wizard step, backed by the same slot
//     semantics" shape the phase doc asks for — no new slot math, no new
//     calendar, no new time-chip widget written here.
//   • `service` — reuses the Phase 247 part 1 PROMOTED widgets
//     ([CategorySection], [ServiceCard], [groupServicesByCategory], …) from
//     `services/presentation/widgets/service_category_list.dart` in picker
//     mode (additive `selectable`/`selected` params on [ServiceCard] — see
//     that file). The services page itself is untouched behaviourally.
//   • `confirm` / `done` — reuse [BookingSummaryCards] (core constructor,
//     `masterCard: null`, `showAddress: false`), [LabelledRow],
//     [BookingCtaFooter], [BookingSuccessScaffold] + [SuccessSecondaryButton]
//     — the SAME shared recap/footer/celebration widgets the client-facing
//     `booking_confirm_screen.dart` / `booking_success_screen.dart` already
//     use. No bespoke recap card, no bespoke success scaffold.
//   • The phone field's live input MASK reuses
//     `shared/formatters/ua_phone_input_formatter.dart`
//     (`UaPhoneInputFormatter`). Normalization to the wire's bare E.164 shape
//     is new (`toE164UaPhone`, promoted in Phase 249 to
//     `widgets/booking_wizard_steps.dart`) — it mirrors, but does not call,
//     `shared/validators/phone_validator.dart`'s `validatePhone`, which
//     answers a different question (validity, not the normalized string —
//     see `toE164UaPhone`'s own doc for why the two coexist).
//
// The header (back-chevron + centred title) reuses [BookingTopBar] — every
// other booking-flow screen in this app already uses it. Only the 4-dot
// connected-line step indicator ([StepIndicator], promoted in Phase 249) is a
// literal port of the design file's own `_StepIndicator` (adapted to 4
// steps): no existing shared widget renders that exact visual grammar
// (`SubStepIndicator` is a 2-pill auth-flow widget with a different shape;
// the salon flow's own `_StepIndicator` in `salon_time_screen.dart` is a
// numeric "1/4" pill + growing bar, not connected dots).
//
// ## Deviations from the design file (see also each step widget's own doc in
// `widgets/booking_wizard_steps.dart`)
//
//   1. No `masters` step (see above — phase-245/247 rationale).
//   2. Header uses [BookingTopBar], not a literal port of the design's
//      `_CreateHeader` (border-bottom decoration, larger title). Chosen for
//      consistency with every other booking-flow screen's chrome — see the
//      REUSE-FIRST note above.
//   3. `dateTime` is DATE + TIME in one step (design split them into
//      `_DateTimeStep` (date only) + `_MastersStep` (time, nested inside a
//      master tile)). See the file-header note on [MasterSchedulePage] reuse.
//   4. `confirm` shows NO master-identity card. The design's card exists
//      because a SALON booker picks among several masters; an
//      INDEPENDENT_MASTER booking themselves would show a card naming
//      themselves, which is meaningless. A guest identity row
//      ([LabelledRow] + [AppLocalizations.masterCreateBookingGuestLabel])
//      takes its place instead.
//   5. No «Коментар для майстра» field. `CreateMasterBookingRequest` (Phase
//      246) carries no `clientComment` — the ACTUAL shipped
//      `CreateStaffBookingRequest` wire schema has exactly three properties
//      (`masterServiceId`, `startsAt`, `guest`) — see that file's own doc for
//      the ground-truth OpenAPI note. A field this repository cannot
//      transmit has no business on this screen.
//   6. No «Додати в календар» link on `done`. The design's own version is
//      already a no-op (`onTap: () {}`) — wiring it for real would need a
//      GUEST-identity parameter on `shared/calendar/add_to_calendar.dart`'s
//      `buildCalendarDescription`, which currently models a PROVIDER
//      identity, not a client one. Shipping a fake button that looks
//      functional but isn't would be worse than omitting it; out of scope
//      for this phase.
//   7. Done-step copy does NOT say "Нагадування надійде автоматично" (the
//      design's claim) — the backend's confirmation SMS is gated OFF by
//      default (backend Phase 22.7), so promising an automatic notification
//      would be false. See [AppLocalizations.masterCreateBookingDoneSubline].
//   8. «Далі» CTA label on the client step is the app's generic
//      [AppLocalizations.bookingNextCta] ("Далі"), not the design's
//      step-labelled "Далі — Послуга" — consistent with every other booking
//      step's CTA in this app.
//
// ## Phone normalization (locked to the screen boundary, not the repository)
//
// See `toE164UaPhone`'s own doc in `widgets/booking_wizard_steps.dart`.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_notifier.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/formatters/booking_date_labels.dart';
import 'package:beautica_mobile/shared/formatters/duration_minutes.dart';
import 'package:beautica_mobile/shared/formatters/service_price_display.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';

import '../application/master_create_booking_notifier.dart'
    show masterCreateBookingProvider;
import '../application/salon_booking_schedule_notifier.dart';
import '../domain/booking_slot.dart';
import '../domain/create_master_booking_request.dart';
import 'widgets/booking_cta_footer.dart';
import 'widgets/booking_recap.dart';
import 'widgets/booking_success_scaffold.dart';
import 'widgets/booking_summary_cards.dart';
import 'widgets/booking_top_bar.dart';
import 'widgets/labelled_row.dart';
import 'widgets/booking_wizard_steps.dart';

export '../application/master_create_booking_notifier.dart'
    show masterCreateBookingProvider;

// ---------------------------------------------------------------------------
// Step enum — FIVE values, no `masters` step.
// ---------------------------------------------------------------------------

enum _BookingStep { client, service, dateTime, confirm, done }

// ---------------------------------------------------------------------------
// Root screen
// ---------------------------------------------------------------------------

/// The master «Новий запис» wizard — see file header for the full reuse map.
class MasterCreateBookingScreen extends ConsumerStatefulWidget {
  const MasterCreateBookingScreen({super.key});

  @override
  ConsumerState<MasterCreateBookingScreen> createState() =>
      _MasterCreateBookingScreenState();
}

class _MasterCreateBookingScreenState
    extends ConsumerState<MasterCreateBookingScreen> {
  _BookingStep _step = _BookingStep.client;

  final TextEditingController _firstNameCtrl = TextEditingController();
  final TextEditingController _lastNameCtrl = TextEditingController();
  final TextEditingController _phoneCtrl = TextEditingController();

  MasterService? _service;
  DateTime? _startAt;

  /// The calendar day tapped on the `dateTime` step but NOT yet committed.
  ///
  /// Selection no longer navigates anywhere on this wizard (user-reported UX
  /// defect, 2026-08-20): the embedded [MasterSchedulePage] runs in staging
  /// mode, so tapping a day parks it here instead of writing
  /// `salonBookingScheduleProvider.date` — the write that flips that page into
  /// its time sub-phase. The «Далі» footer performs that commit
  /// ([_commitStagedDate]).
  ///
  /// A [ValueNotifier], NOT a plain field mutated through `setState`
  /// (mobile-perf MEDIUM, 2026-08-20). Only TWO things in the tree depend on
  /// the staged day — the month grid's selection ring and this step's «Далі»
  /// footer — but a `setState` here reconstructed the whole wizard: 683 of the
  /// tree's 921 elements per day tap, 146 of them chrome ABOVE
  /// [MasterSchedulePage] (`BookingTopBar`, `StepIndicator` + its
  /// `AnimatedContainer`s, the step `AnimatedSwitcher`, the `Scaffold`) that
  /// cannot depend on it — and the user can browse days indefinitely. Handed
  /// to both dependents as a listenable, a day tap rebuilds exactly those two
  /// subtrees and nothing else. (Same rebuild-scoping primitive this codebase
  /// already uses in ~58 places, e.g. `service_form.dart`'s `_dirtyNotifier`.)
  final ValueNotifier<DateTime?> _stagedDate = ValueNotifier<DateTime?>(null);

  late final ScreenProtectionManager _screenProtection;

  @override
  void initState() {
    super.initState();
    _screenProtection = ref.read(screenProtectionProvider)..acquire();
  }

  @override
  void dispose() {
    _screenProtection.release();
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _phoneCtrl.dispose();
    _stagedDate.dispose();
    super.dispose();
  }

  void _goTo(_BookingStep s) => setState(() => _step = s);

  /// Header back-chevron handler. On `client`, pops the whole wizard route.
  /// On `dateTime` WHILE the embedded [MasterSchedulePage] is in its TIME
  /// sub-phase, steps back to the calendar sub-phase instead of leaving the
  /// step (mirrors `SalonTimeScreen._handleTopBarBack`, the same reuse this
  /// step is built on). Otherwise steps back one wizard step.
  void _handleBack(bool inTimeSubPhase) {
    if (_step == _BookingStep.client) {
      context.pop();
      return;
    }
    if (_step == _BookingStep.dateTime && inTimeSubPhase) {
      ref.read(salonBookingScheduleProvider.notifier).clearDate();
      return;
    }
    setState(() => _step = _BookingStep.values[_step.index - 1]);
  }

  Future<void> _submit(String masterId) async {
    final MasterService? service = _service;
    final DateTime? startAt = _startAt;
    final String? phone = toE164UaPhone(_phoneCtrl.text);
    // Defensive — unreachable via the normal flow: `confirm` is only reached
    // once `_service`/`_startAt` are set, and `client`'s Next is disabled
    // until the phone normalizes (see `ClientStep._canAdvance`).
    if (service == null || startAt == null || phone == null) return;

    final CreateMasterBookingRequest request = CreateMasterBookingRequest(
      masterServiceId: service.id,
      startsAt: startAt,
      guest: WalkInGuest(
        name: _firstNameCtrl.text.trim(),
        surname: _lastNameCtrl.text.trim(),
        phone: phone,
      ),
    );
    await ref
        .read(masterCreateBookingProvider.notifier)
        .submit(masterId: masterId, request: request);
    if (!mounted) return;
    // A submit failure keeps the notifier's AsyncError state, which the
    // confirm step's own `ref.watch` renders as an inline banner — do NOT
    // advance past it.
    if (ref.read(masterCreateBookingProvider).hasError) return;
    setState(() => _step = _BookingStep.done);
  }

  String _titleFor(AppLocalizations l10n, _BookingStep step) => switch (step) {
    _BookingStep.client => l10n.masterCreateBookingTitle,
    _BookingStep.service => l10n.masterCreateBookingServiceTitle,
    _BookingStep.dateTime => l10n.masterCreateBookingDateTimeTitle,
    _BookingStep.confirm => l10n.bookingConfirmScreenTitle,
    _BookingStep.done => '',
  };

  Widget _buildStep(Master master, AppLocalizations l10n) {
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
          // SELECT ONLY — no navigation. Advancing is the pinned «Далі»
          // footer's job (see [_NextCtaFooter]); a tap that jumped straight to
          // the next step gave the user no chance to see, or change, what they
          // had picked.
          onSelect: (MasterService s) => setState(() => _service = s),
        );
      case _BookingStep.dateTime:
        return DateTimeStep(
          key: const ValueKey<_BookingStep>(_BookingStep.dateTime),
          master: master,
          service: _service!,
          stagedDate: _stagedDate,
          // SELECT ONLY — same reasoning as the service step above. No
          // `setState`: see [_stagedDate]'s doc for why the staged day is
          // published through the notifier instead.
          onDateStaged: (DateTime day) => _stagedDate.value = day,
        );
      case _BookingStep.confirm:
        return ConfirmStep(
          key: const ValueKey<_BookingStep>(_BookingStep.confirm),
          service: _service!,
          startAt: _startAt!,
          firstName: _firstNameCtrl.text.trim(),
          lastName: _lastNameCtrl.text.trim(),
          phone: _phoneCtrl.text.trim(),
        );
      case _BookingStep.done:
        // Unreachable — `done` is rendered directly from `build()` below,
        // never through `AnimatedSwitcher`/`_buildStep` (see that method's
        // doc for why).
        return const SizedBox.shrink();
    }
  }

  /// Commits the staged calendar day to `salonBookingScheduleProvider`, which
  /// IS the move to the time sub-phase — the embedded [MasterSchedulePage]
  /// renders its chips off `date != null`. See that widget's `onDateStaged`
  /// doc.
  ///
  /// Reads [_stagedDate] at PRESS time rather than closing over a value
  /// captured when the footer was built: the notifier is the single source of
  /// truth for the staged day, so there is nothing here that can go stale
  /// (same reasoning as [_commitSlotAndAdvance] below, one step later in the
  /// flow). The `null` branch is defensive only — the CTA is disabled without
  /// a staged day — and replaces the unreachable `() {}` this used to hand
  /// [BookingCtaFooter] for the disabled case (mobile-perf LOW, 2026-08-20:
  /// that footer already collapses `enabled ? onPressed : null` itself, so the
  /// empty closure was allocated on every root build and never called).
  void _commitStagedDate() {
    final DateTime? staged = _stagedDate.value;
    if (staged == null) return;
    ref.read(salonBookingScheduleProvider.notifier).selectDate(staged);
  }

  /// Snapshots the slot the master has settled on and advances to `confirm`.
  ///
  /// THE ONLY place `_startAt` is ever written (audit-fix cycle 1, FINDING 1 —
  /// CRITICAL). It used to be mirrored out of a `ref.listen` inside
  /// [DateTimeStep] whose guard was edge-triggered on `null → non-null`;
  /// because `SalonBookingSchedule.selectSlot` writes slot A → slot B
  /// directly, a RE-PICK never re-fired and the wizard confirmed and submitted
  /// the FIRST slot tapped. Reading `salonBookingScheduleProvider` at the
  /// instant «Далі» is pressed removes the mirror — and with it the whole
  /// class of desync — rather than patching the guard. See [DateTimeStep]'s
  /// own note.
  ///
  /// `ref.read`, not `ref.watch`: a one-shot read inside an action handler.
  /// The `null` branch is defensive — the CTA is gated on the SAME provider
  /// field (`slotPicked` in [build]), so it cannot be pressed without one.
  void _commitSlotAndAdvance() {
    final BookingSlot? slot = ref.read(salonBookingScheduleProvider).slot;
    if (slot == null) return;
    setState(() {
      _startAt = slot.startAt;
      _step = _BookingStep.confirm;
    });
  }

  /// The pinned footer for the current step, or `null` where the step carries
  /// its own inline CTA (`client`) or none at all.
  ///
  /// Every mid-flow footer here exists because SELECTION MUST NOT NAVIGATE
  /// (user-reported UX defect, 2026-08-20): tapping a service used to jump
  /// straight to `dateTime`, tapping a day used to flip to the time chips, and
  /// tapping a slot used to jump to `confirm` — three moves the user never
  /// asked for, with no chance to review or revise the pick. Each now only
  /// records the choice; «Далі» is what advances.
  Widget? _buildBottomBar(
    AppLocalizations l10n,
    AsyncValue<Master> masterAsync, {
    required bool inTimeSubPhase,
    required bool slotPicked,
  }) {
    switch (_step) {
      case _BookingStep.service:
        return _NextCtaFooter(
          buttonKey: const Key('master-create-booking-service-next'),
          label: l10n.bookingNextCta,
          enabled: _service != null,
          onPressed: () => _goTo(_BookingStep.dateTime),
        );
      case _BookingStep.dateTime:
        if (inTimeSubPhase) {
          return _NextCtaFooter(
            buttonKey: const Key('master-create-booking-time-next'),
            label: l10n.bookingNextCta,
            enabled: slotPicked,
            onPressed: _commitSlotAndAdvance,
          );
        }
        // Only this footer depends on the staged day — see [_stagedDate].
        return ValueListenableBuilder<DateTime?>(
          valueListenable: _stagedDate,
          builder: (BuildContext context, DateTime? staged, Widget? child) =>
              _NextCtaFooter(
                buttonKey: const Key('master-create-booking-date-next'),
                label: l10n.bookingNextCta,
                enabled: staged != null,
                onPressed: _commitStagedDate,
              ),
        );
      case _BookingStep.confirm:
        return masterAsync.maybeWhen(
          data: (Master master) =>
              _ConfirmCtaFooter(onSubmit: () => _submit(master.id)),
          orElse: () => null,
        );
      case _BookingStep.client:
      case _BookingStep.done:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final AsyncValue<Master> masterAsync = ref.watch(masterProfileProvider);

    if (_step == _BookingStep.done) {
      final MasterService? service = _service;
      final DateTime? startAt = _startAt;
      if (service == null || startAt == null) {
        // Defensive — unreachable via the normal flow (see `_buildStep`).
        return const Scaffold(body: SizedBox.shrink());
      }
      // [BookingSuccessScaffold] is a FULL Scaffold + its own
      // `PopScope(canPop: false)` — rendered standalone here (not nested
      // inside this screen's own Scaffold below) so the wizard chrome
      // (header, step indicator, outer Scaffold) is fully replaced, not
      // double-wrapped, on the terminal step.
      return _DoneStep(
        service: service,
        startAt: startAt,
        firstName: _firstNameCtrl.text.trim(),
        lastName: _lastNameCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
        onClose: () => context.pop(),
      );
    }

    // Only relevant while on `dateTime` — see `_handleBack`'s doc. Watched
    // here (not just read) so both the `PopScope.canPop` gate and the header
    // back-chevron agree, frame-for-frame, with the embedded
    // `MasterSchedulePage`'s own phase.
    final bool inTimeSubPhase =
        _step == _BookingStep.dateTime &&
        ref.watch(salonBookingScheduleProvider.select((s) => s.date != null));

    // Gated on the PROVIDER's slot, never on `_startAt` alone: every route
    // back to the calendar (`clearDate` from the header chevron, the system
    // back gesture, the time phase's edge-swipe, the «Змінити дату» empty
    // state) clears the provider's slot, and `selectDate` clears it too. A
    // footer keyed off the wizard's own `_startAt` would stay enabled over a
    // slot the user has already dropped.
    final bool slotPicked =
        _step == _BookingStep.dateTime &&
        ref.watch(salonBookingScheduleProvider.select((s) => s.slot != null));

    return PopScope(
      canPop: !inTimeSubPhase,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;
        ref.read(salonBookingScheduleProvider.notifier).clearDate();
      },
      child: Scaffold(
        backgroundColor: BrandColors.base,
        bottomNavigationBar: _buildBottomBar(
          l10n,
          masterAsync,
          inTimeSubPhase: inTimeSubPhase,
          slotPicked: slotPicked,
        ),
        body: SafeArea(
          bottom: false,
          child: Column(
            children: <Widget>[
              BookingTopBar(
                title: _titleFor(l10n, _step),
                backSemantics: l10n.registerBackStep,
                backKey: const Key('master-create-booking-back'),
                onBack: () => _handleBack(inTimeSubPhase),
              ),
              StepIndicator(currentStep: _step.index),
              Expanded(
                child: masterAsync.when(
                  data: (Master master) => AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    transitionBuilder: (Widget child, Animation<double> a) =>
                        FadeTransition(opacity: a, child: child),
                    child: _buildStep(master, l10n),
                  ),
                  loading: () => const Center(
                    key: ValueKey<String>('master-create-booking-loading'),
                    child: CircularProgressIndicator(color: BrandColors.accent),
                  ),
                  error: (Object e, StackTrace _) => ErrorState(
                    key: const Key('master-create-booking-master-error'),
                    failure: e is Failure ? e : UnknownFailure(cause: e),
                    onRetry: () => ref.invalidate(masterProfileProvider),
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

// ---------------------------------------------------------------------------
// Step widgets — StepIndicator, ClientStep, ServiceStep, ServiceStepEmpty,
// DateTimeStep, ConfirmStep. Promoted to `widgets/booking_wizard_steps.dart`
// in Phase 249 (dropped the leading underscore) so Phase 250's salon wizard
// can reuse them without forking — see that file's own header for the full
// promotion rationale and the one additive parameter it introduced.
// ---------------------------------------------------------------------------

/// Pinned bottom footer carrying a mid-flow «Далі» CTA — the same shared
/// [BookingCtaFooter] chrome as the submit footer below, so the wizard's
/// bottom edge does not change shape between steps. Never in flight (nothing
/// is submitted mid-flow), and carries the forward arrow rather than the
/// footer's default check: a check would read as "booked".
class _NextCtaFooter extends StatelessWidget {
  const _NextCtaFooter({
    required this.buttonKey,
    required this.label,
    required this.enabled,
    required this.onPressed,
  });

  final Key buttonKey;
  final String label;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return BookingCtaFooter(
      key: const Key('master-create-booking-next-footer'),
      buttonKey: buttonKey,
      label: label,
      icon: Icons.arrow_forward_rounded,
      enabled: enabled,
      loading: false,
      onPressed: onPressed,
    );
  }
}

/// Pinned bottom footer carrying the «Записати» CTA — thin wrapper over the
/// shared [BookingCtaFooter] so this step gets the exact same pinned-footer
/// chrome the client-facing confirm screens use.
class _ConfirmCtaFooter extends ConsumerWidget {
  const _ConfirmCtaFooter({required this.onSubmit});

  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final bool inFlight = ref.watch(
      masterCreateBookingProvider.select((AsyncValue<void> s) => s.isLoading),
    );
    return BookingCtaFooter(
      key: const Key('master-create-booking-cta-footer'),
      buttonKey: const Key('master-create-booking-submit-cta'),
      // NOT the shared `bookingSubmitCta` («Записатись»): that label is the
      // CLIENT's reflexive "book myself in", and four other screens depend on
      // it reading exactly that way. Here the actor is the master booking
      // SOMEONE ELSE in, so the wizard carries its own transitive label. The
      // in-flight caption («Надсилаємо…») is actor-neutral and stays shared.
      label: inFlight
          ? l10n.bookingSubmitCtaLoading
          : l10n.masterCreateBookingSubmitCta,
      enabled: true,
      loading: inFlight,
      onPressed: onSubmit,
    );
  }
}

// ---------------------------------------------------------------------------
// Step 5 — Done (success payoff)
// ---------------------------------------------------------------------------

/// The success payoff — reuses [BookingSuccessScaffold] (the SAME celebration
/// scaffold the client-facing `BookingSuccessScreen` uses) rather than a
/// bespoke port of the design's `_DoneStep`. Rendered standalone by
/// [MasterCreateBookingScreen.build] (not through the wizard's own
/// Scaffold/AnimatedSwitcher) — see that method's doc for why.
class _DoneStep extends StatelessWidget {
  const _DoneStep({
    required this.service,
    required this.startAt,
    required this.firstName,
    required this.lastName,
    required this.phone,
    required this.onClose,
  });

  final MasterService service;
  final DateTime startAt;
  final String firstName;
  final String lastName;
  final String phone;
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
      // Deviation #7 (file header) — no SMS/notification claim.
      subline: l10n.masterCreateBookingDoneSubline,
      actions: <Widget>[
        SuccessSecondaryButton(
          buttonKey: const Key('master-create-booking-done-cta'),
          label: l10n.masterCreateBookingDoneCta,
          icon: Icons.check_rounded,
          onPressed: onClose,
        ),
      ],
      recapCards: <Widget>[
        // WHO — the same guest card [ConfirmStep] renders, in the same
        // position (guest first, booking details second). The step the master
        // just confirmed showed them who they were booking; dropping that on
        // the payoff screen left the one fact they most need to double-check
        // (did I type the right client?) visible only on the screen they had
        // already left.
        NeumorphicCard(
          key: const Key('master-create-booking-done-guest-card'),
          showBorder: true,
          padding: const EdgeInsets.all(VelvetSpacing.md),
          child: LabelledRow(
            label: l10n.masterCreateBookingGuestLabel,
            value: '$firstName $lastName'.trim(),
            detail: phone.isEmpty ? null : phone,
            // Bounded for the same reason, and to the same pair of values, as
            // [ConfirmStep]'s copy of this card — see that call site in
            // `widgets/booking_wizard_steps.dart` (audit-fix cycle 1,
            // FINDING 4). The two must stay in step: they render the same
            // third-party free text either side of the submit.
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        // No manual spacer — [BookingSuccessScaffold] already separates every
        // `recapCards` entry with an `md` gap (see its file header).
        // WHEN / WHAT.
        BookingSummaryCards(
          key: const Key('master-create-booking-done-card'),
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
