// Phase 247 (part 2 of 2) — MasterCreateBookingScreen: the INDEPENDENT_MASTER
// «Новий запис» wizard — a walk-in / phone booking the master creates on
// their OWN calendar for a guest with no app account.
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
//     is new (`_toE164UaPhone` below) — it mirrors, but does not call,
//     `shared/validators/phone_validator.dart`'s `validatePhone`, which
//     answers a different question (validity, not the normalized string —
//     see `_toE164UaPhone`'s own doc for why the two coexist).
//
// The header (back-chevron + centred title) reuses [BookingTopBar] — every
// other booking-flow screen in this app already uses it. Only the 4-dot
// connected-line step indicator ([_StepIndicator] below) is a literal port of
// the design file's own `_StepIndicator` (adapted to 4 steps): no existing
// shared widget renders that exact visual grammar (`SubStepIndicator` is a
// 2-pill auth-flow widget with a different shape; the salon flow's own
// `_StepIndicator` in `salon_time_screen.dart` is a numeric "1/4" pill +
// growing bar, not connected dots).
//
// ## Deviations from the design file (see also each private widget's doc)
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
// See [_toE164UaPhone]'s own doc.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_notifier.dart';
import 'package:beautica_mobile/features/salon/domain/salon_service_catalog.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/features/services/presentation/services_list_notifier.dart'
    show servicesListProvider;
import 'package:beautica_mobile/features/services/presentation/widgets/service_category_list.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/formatters/booking_date_labels.dart';
import 'package:beautica_mobile/shared/formatters/duration_minutes.dart';
import 'package:beautica_mobile/shared/formatters/service_price_display.dart';
import 'package:beautica_mobile/shared/formatters/ua_phone_input_formatter.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';

import '../application/master_create_booking_notifier.dart'
    show masterCreateBookingProvider;
import '../application/salon_booking_schedule_notifier.dart';
import '../domain/create_master_booking_request.dart';
import '../domain/salon_master_schedule.dart';
import 'widgets/booking_cta_footer.dart';
import 'widgets/booking_recap.dart';
import 'widgets/booking_success_scaffold.dart';
import 'widgets/booking_summary_cards.dart';
import 'widgets/booking_top_bar.dart';
import 'widgets/labelled_row.dart';
import 'widgets/master_schedule_page.dart';
import 'widgets/salon_avatar_gradients.dart';

export '../application/master_create_booking_notifier.dart'
    show masterCreateBookingProvider;

// ---------------------------------------------------------------------------
// Phone normalization
// ---------------------------------------------------------------------------

/// Normalizes a Ukrainian phone number typed in ANY shape the client accepts
/// (`+380 XX XXX XX XX`, `380XXXXXXXXX`, `0XXXXXXXXX`, or a bare 9-digit
/// subscriber number) to the bare E.164 shape `WalkInGuest.phone`'s wire
/// CHECK ([kWalkInGuestPhonePattern]) requires — `+380XXXXXXXXX`, no
/// separators. Returns `null` when [raw] does not resolve to exactly 9
/// Ukrainian subscriber digits.
///
/// Deliberately NOT added to `shared/validators/phone_validator.dart`: this
/// phase's domain rule (`create_master_booking_request.dart`'s doc) is that
/// phone normalization happens AT THE SCREEN BOUNDARY, not in a shared
/// validator or the repository. This mirrors `validatePhone`'s own branch
/// structure (the exact same accepted/rejected shapes) but returns the
/// normalized string instead of a validity verdict — a different output
/// contract that validator was never built to carry, so the two coexist
/// rather than one wrapping the other.
String? _toE164UaPhone(String raw) {
  final String stripped = raw.trim().replaceAll(RegExp(r'[\s\-]'), '');
  final String subscriber;
  if (stripped.startsWith('+380')) {
    subscriber = stripped.substring(4);
  } else if (stripped.startsWith('380')) {
    subscriber = stripped.substring(3);
  } else if (stripped.startsWith('0') && stripped.length == 10) {
    subscriber = stripped.substring(1);
  } else if (stripped.startsWith('38') && !stripped.startsWith('380')) {
    // Paste-guard, mirrors validatePhone: "38" without the "0" is rejected
    // rather than silently becoming "338...".
    return null;
  } else {
    subscriber = stripped;
  }
  if (!RegExp(r'^\d{9}$').hasMatch(subscriber)) return null;
  return '+380$subscriber';
}

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
    final String? phone = _toE164UaPhone(_phoneCtrl.text);
    // Defensive — unreachable via the normal flow: `confirm` is only reached
    // once `_service`/`_startAt` are set, and `client`'s Next is disabled
    // until the phone normalizes (see `_ClientStep._canAdvance`).
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
        return _ClientStep(
          key: const ValueKey<_BookingStep>(_BookingStep.client),
          firstNameCtrl: _firstNameCtrl,
          lastNameCtrl: _lastNameCtrl,
          phoneCtrl: _phoneCtrl,
          onNext: () => _goTo(_BookingStep.service),
        );
      case _BookingStep.service:
        return _ServiceStep(
          key: const ValueKey<_BookingStep>(_BookingStep.service),
          selectedServiceId: _service?.id,
          onSelect: (MasterService s) {
            setState(() => _service = s);
            _goTo(_BookingStep.dateTime);
          },
        );
      case _BookingStep.dateTime:
        return _DateTimeStep(
          key: const ValueKey<_BookingStep>(_BookingStep.dateTime),
          master: master,
          service: _service!,
          onSlotChosen: (DateTime startAt) {
            setState(() => _startAt = startAt);
            _goTo(_BookingStep.confirm);
          },
        );
      case _BookingStep.confirm:
        return _ConfirmStep(
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

    return PopScope(
      canPop: !inTimeSubPhase,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;
        ref.read(salonBookingScheduleProvider.notifier).clearDate();
      },
      child: Scaffold(
        backgroundColor: BrandColors.base,
        bottomNavigationBar: (_step == _BookingStep.confirm)
            ? masterAsync.maybeWhen(
                data: (Master master) =>
                    _ConfirmCtaFooter(onSubmit: () => _submit(master.id)),
                orElse: () => null,
              )
            : null,
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
              _StepIndicator(step: _step),
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
// Step indicator — 4 dots connected by lines. Literal port of the design
// file's own `_StepIndicator`, adapted to this wizard's 4 non-`done` steps
// (the design's version had 5 — it still included `masters`). See file
// header for why no existing shared widget covers this exact visual.
// ---------------------------------------------------------------------------

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.step});

  final _BookingStep step;

  static const List<_BookingStep> _steps = <_BookingStep>[
    _BookingStep.client,
    _BookingStep.service,
    _BookingStep.dateTime,
    _BookingStep.confirm,
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final int current = _steps.indexOf(step);
    return Semantics(
      label: l10n.salonBookingStepLabel(current + 1, _steps.length),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: VelvetSpacing.xl,
          vertical: VelvetSpacing.sm,
        ),
        child: Row(
          children: List<Widget>.generate(_steps.length * 2 - 1, (int i) {
            if (i.isOdd) {
              return Expanded(
                child: Container(
                  height: 1,
                  color: i ~/ 2 < current
                      ? BrandColors.accent
                      : BrandColors.faint,
                ),
              );
            }
            final int idx = i ~/ 2;
            final bool done = idx < current;
            final bool active = idx == current;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: active ? 10 : 8,
              width: active ? 10 : 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done || active ? BrandColors.accent : BrandColors.faint,
              ),
            );
          }),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 1 — Client
// ---------------------------------------------------------------------------

class _ClientStep extends StatefulWidget {
  const _ClientStep({
    super.key,
    required this.firstNameCtrl,
    required this.lastNameCtrl,
    required this.phoneCtrl,
    required this.onNext,
  });

  final TextEditingController firstNameCtrl;
  final TextEditingController lastNameCtrl;
  final TextEditingController phoneCtrl;
  final VoidCallback onNext;

  @override
  State<_ClientStep> createState() => _ClientStepState();
}

class _ClientStepState extends State<_ClientStep> {
  bool get _canAdvance =>
      widget.firstNameCtrl.text.trim().isNotEmpty &&
      widget.lastNameCtrl.text.trim().isNotEmpty &&
      _toE164UaPhone(widget.phoneCtrl.text) != null;

  String? _phoneError(AppLocalizations l10n) {
    final String raw = widget.phoneCtrl.text.trim();
    if (raw.isEmpty) return null;
    return _toE164UaPhone(raw) == null ? l10n.errPhoneInvalid : null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(VelvetSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SizedBox(height: VelvetSpacing.xs),
          Text(
            l10n.masterCreateBookingClientHeading,
            style: VelvetText.subheadingWizard15,
          ),
          const SizedBox(height: VelvetSpacing.xs),
          Text(l10n.masterCreateBookingClientIntro, style: VelvetText.body()),
          const SizedBox(height: VelvetSpacing.lg),
          NeumorphicTextField(
            key: const Key('master-create-booking-first-name'),
            label: l10n.masterCreateBookingFirstNameLabel,
            controller: widget.firstNameCtrl,
            hintText: l10n.masterCreateBookingFirstNameHint,
            prefixIcon: const Icon(
              Icons.person_outline_rounded,
              size: 18,
              color: BrandColors.accent,
            ),
            textInputAction: TextInputAction.next,
            // SEC MEDIUM fix — this collects a WALK-IN GUEST's name, a third
            // party who never installed the app and never consented in it.
            // Mirrors register_step_1_screen.dart:209,236 /
            // otp_code_field.dart:76: keep this PII out of the device IME's
            // personalized-learning corpus (which can cloud-sync and outlive
            // logout/uninstall).
            enableIMEPersonalizedLearning: false,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: VelvetSpacing.md),
          NeumorphicTextField(
            key: const Key('master-create-booking-last-name'),
            label: l10n.masterCreateBookingLastNameLabel,
            controller: widget.lastNameCtrl,
            hintText: l10n.masterCreateBookingLastNameHint,
            prefixIcon: const Icon(
              Icons.person_outline_rounded,
              size: 18,
              color: BrandColors.accent,
            ),
            textInputAction: TextInputAction.next,
            // SEC MEDIUM fix — see the first-name field above.
            enableIMEPersonalizedLearning: false,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: VelvetSpacing.md),
          NeumorphicTextField(
            key: const Key('master-create-booking-phone'),
            label: l10n.masterCreateBookingPhoneLabel,
            controller: widget.phoneCtrl,
            hintText: l10n.masterCreateBookingPhoneHint,
            prefixIcon: const Icon(
              Icons.phone_outlined,
              size: 18,
              color: BrandColors.accent,
            ),
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.done,
            inputFormatters: const <TextInputFormatter>[
              UaPhoneInputFormatter(),
            ],
            errorText: _phoneError(l10n),
            // SEC MEDIUM fix — see the first-name field above.
            enableIMEPersonalizedLearning: false,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: VelvetSpacing.xl),
          NeumorphicButton(
            key: const Key('master-create-booking-client-next'),
            label: l10n.bookingNextCta,
            icon: Icons.arrow_forward_rounded,
            onPressed: _canAdvance ? widget.onNext : null,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 2 — Service (picker mode over the Phase 247 part 1 promoted widgets)
// ---------------------------------------------------------------------------

class _ServiceStep extends ConsumerStatefulWidget {
  const _ServiceStep({
    super.key,
    required this.selectedServiceId,
    required this.onSelect,
  });

  final String? selectedServiceId;
  final ValueChanged<MasterService> onSelect;

  @override
  ConsumerState<_ServiceStep> createState() => _ServiceStepState();
}

class _ServiceStepState extends ConsumerState<_ServiceStep> {
  // PERF A1 (HIGH) fix — mirrors services_list_screen.dart:337. Driving a
  // `ListView.builder` off the resolved groups (instead of a plain
  // `ListView` over an eagerly-built `children:` list) means `_ServiceStep`
  // no longer constructs a `CategorySection`/`ServiceCard` widget object for
  // every section on every build — only the sections that reach
  // `itemBuilder` do.
  //
  // MEASURED CAVEAT (falsified during the fix, see the audit trail): with
  // either implementation, `RenderSliverList`'s own viewport-based child
  // management already deferred *Element* mounting (and therefore
  // `ServiceCard.initState()` / `AnimationController` allocation) for
  // off-screen sections — a widget test with 48 services across 8
  // categories mounted exactly 1 section / 6 cards under BOTH the old
  // `ListView(children:)` and this `ListView.builder`. So this fix's real
  // saving is the eager `List<Widget>` CONSTRUCTION pass (calling
  // `CategorySection(...)`/`ServiceCard(...)` constructors for all N
  // sections' worth of children on every `_ServiceStep` rebuild) plus the
  // identity-based grouping cache below (P-M2 pattern) — not eliminating
  // eager `AnimationController` allocation, which was never actually
  // happening for off-screen sections in the first place.
  //
  // `initiallyExpanded: true` is unchanged and intentional (one-shot picker,
  // not a maintained catalogue view).
  //
  // Identity-based cache (P-M2 pattern): only recompute the grouping when
  // the underlying services list or category options change by identity.
  List<MasterService>? _cachedServices;
  List<ServiceCategoryOption>? _cachedCategories;
  List<CategoryGroup>? _cachedGroups;

  List<CategoryGroup> _resolveGroups(
    List<MasterService> services,
    AsyncValue<List<ServiceCategoryOption>> categoriesAsync,
    String uncategorizedLabel,
  ) {
    final List<ServiceCategoryOption>? categoriesValue = categoriesAsync.value;
    final bool hit =
        _cachedGroups != null &&
        identical(_cachedServices, services) &&
        identical(_cachedCategories, categoriesValue);
    if (hit) return _cachedGroups!;

    final List<CategoryGroup> groups = groupServicesByCategory(
      services: services,
      categoriesAsync: categoriesAsync,
      uncategorizedLabel: uncategorizedLabel,
    );
    _cachedServices = services;
    _cachedCategories = categoriesValue;
    _cachedGroups = groups;
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final AsyncValue<List<MasterService>> asyncServices = ref.watch(
      servicesListProvider,
    );
    final AsyncValue<List<ServiceCategoryOption>> categoriesAsync = ref.watch(
      approvedCategoriesProvider,
    );

    return asyncServices.when(
      loading: () => const Center(
        key: ValueKey<String>('master-create-booking-service-loading'),
        child: CircularProgressIndicator(color: BrandColors.accent),
      ),
      error: (Object e, StackTrace _) => ErrorState(
        key: const Key('master-create-booking-service-error'),
        failure: e is Failure ? e : UnknownFailure(cause: e),
        onRetry: () => ref.invalidate(servicesListProvider),
      ),
      data: (List<MasterService> list) {
        if (list.isEmpty) {
          return const _ServiceStepEmpty(
            key: Key('master-create-booking-service-empty'),
          );
        }
        final List<CategoryGroup> groups = _resolveGroups(
          list,
          categoriesAsync,
          l10n.serviceCategoryUncategorized,
        );
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(
            VelvetSpacing.lg,
            VelvetSpacing.md,
            VelvetSpacing.lg,
            VelvetSpacing.xl,
          ),
          itemCount: groups.length,
          itemBuilder: (BuildContext context, int index) {
            final CategoryGroup group = groups[index];
            final String sectionSlug = group.key.isEmpty ? '_none' : group.key;
            return Padding(
              padding: const EdgeInsets.only(bottom: VelvetSpacing.md),
              child: CategorySection(
                key: Key('mcb_category_section_$sectionSlug'),
                title: group.label,
                count: group.cards.length,
                // Every section starts expanded: this is a one-shot picker,
                // not a maintained catalogue view, so showing everything
                // open reduces taps to find a service — unlike the services
                // page, which starts every section collapsed by default.
                initiallyExpanded: true,
                children: <Widget>[
                  for (final CategoryGroupEntry entry in group.cards)
                    Padding(
                      padding: const EdgeInsets.only(top: VelvetSpacing.md),
                      child: ServiceCard(
                        key: Key('mcb_service_card_${entry.service.id}'),
                        service: entry.service,
                        selectable: true,
                        selected: entry.service.id == widget.selectedServiceId,
                        onEdit: () => widget.onSelect(entry.service),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _ServiceStepEmpty extends StatelessWidget {
  const _ServiceStepEmpty({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(VelvetSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.spa_rounded, size: 44, color: BrandColors.accent),
            const SizedBox(height: VelvetSpacing.md),
            Text(
              l10n.masterCreateBookingServiceEmptyTitle,
              style: VelvetText.headingSm,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: VelvetSpacing.sm),
            Text(
              l10n.masterCreateBookingServiceEmptyBody,
              style: VelvetText.body(),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 3 — Date & Time (reuses MasterSchedulePage unmodified)
// ---------------------------------------------------------------------------

class _DateTimeStep extends ConsumerWidget {
  const _DateTimeStep({
    super.key,
    required this.master,
    required this.service,
    required this.onSlotChosen,
  });

  final Master master;
  final MasterService service;
  final ValueChanged<DateTime> onSlotChosen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Auto-advance the wizard the instant a slot is picked inside
    // [MasterSchedulePage] — that widget has no "on slot chosen" callback of
    // its own (it is a self-contained salon-flow step body), so this listens
    // to the SAME [salonBookingScheduleProvider] state it writes to instead
    // of adding one. Fires once per date→slot transition (never on a bare
    // date pick, which only sets `date`).
    ref.listen(salonBookingScheduleProvider, (
      SalonBookingScheduleState? previous,
      SalonBookingScheduleState next,
    ) {
      if (previous?.slot == null && next.slot != null) {
        onSlotChosen(next.slot!.startAt);
      }
    });

    final SalonMasterSchedule schedule = SalonMasterSchedule(
      masterId: master.id,
      firstName: master.firstName,
      lastName: master.lastName,
      type: master.type,
      professionalTitle: master.professionalTitle,
      avgRating: master.displayRating,
      reviewCount: master.reviewCount,
      services: <SalonCatalogService>[
        SalonCatalogService(
          id: service.id,
          name: service.name,
          durationLabel: DurationMinutes.format(service.durationMinutes),
          priceDisplay: service.priceDisplay,
          category: service.category,
          serviceTypeSlug: service.serviceTypeSlug,
          serviceTypeNameUk: service.serviceTypeNameUk,
          durationMinutes: service.durationMinutes,
          priceType: service.priceType,
          priceMin: service.priceMin,
          priceMax: service.priceMax,
        ),
      ],
      // The master's own per-master assignment id — the SAME id space
      // `MasterService.id` already represents (see that field's doc).
      orderedMasterServiceIds: <String>[service.id],
    );

    return MasterSchedulePage(
      schedule: schedule,
      avatarGradient: salonAvatarGradient(0),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 4 — Confirm
// ---------------------------------------------------------------------------

class _ConfirmStep extends ConsumerWidget {
  const _ConfirmStep({
    super.key,
    required this.service,
    required this.startAt,
    required this.firstName,
    required this.lastName,
    required this.phone,
  });

  final MasterService service;
  final DateTime startAt;
  final String firstName;
  final String lastName;
  final String phone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final AsyncValue<void> submitState = ref.watch(masterCreateBookingProvider);

    final BookingSelection selection = BookingSelection(
      name: service.name,
      price: ServicePriceDisplay.format(service),
      duration: DurationMinutes.format(service.durationMinutes),
      durationMinutes: service.durationMinutes,
      priceMin: service.priceMin,
      priceMax: service.priceMax,
    );

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        VelvetSpacing.lg,
        VelvetSpacing.md,
        VelvetSpacing.lg,
        VelvetSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // WHO — the walk-in guest. No master-identity card here (see file
          // header deviation #4): the master IS the one creating this
          // booking, so a card naming them would be self-referential.
          NeumorphicCard(
            key: const Key('master-create-booking-guest-card'),
            padding: const EdgeInsets.all(VelvetSpacing.md),
            child: LabelledRow(
              label: l10n.masterCreateBookingGuestLabel,
              value: '$firstName $lastName'.trim(),
              detail: phone.isEmpty ? null : phone,
            ),
          ),
          const SizedBox(height: VelvetSpacing.md),
          // WHERE / WHEN / WHAT — the shared booking-details card, the SAME
          // one the client-facing confirm/success screens use.
          BookingSummaryCards(
            key: const Key('master-create-booking-confirm-card'),
            showAddress: false,
            dateLabel: formatFullDate(startAt),
            timeLabel: formatTimeRange(startAt, service.durationMinutes),
            singleSelection: selection,
          ),
          if (submitState.hasError) ...<Widget>[
            const SizedBox(height: VelvetSpacing.md),
            _SubmitErrorBanner(
              failure: submitState.error is Failure
                  ? submitState.error as Failure
                  : UnknownFailure(cause: submitState.error),
            ),
          ],
        ],
      ),
    );
  }
}

/// The single inline error banner shown when a submit fails — mirrors the
/// byte-identical `_SubmitErrorBanner` already duplicated across FOUR
/// existing files in this codebase (`booking_confirm_screen.dart`,
/// `salon_booking_confirm_screen.dart`, `apply_schedule_sheet.dart`,
/// `verification_screen.dart`). Following that PRE-EXISTING convention for a
/// fifth minimal private copy rather than taking on an out-of-scope
/// promotion refactor across all five.
class _SubmitErrorBanner extends StatelessWidget {
  const _SubmitErrorBanner({required this.failure});

  final Failure failure;

  @override
  Widget build(BuildContext context) {
    return NeumorphicCard(
      key: const Key('master-create-booking-submit-error'),
      showBorder: true,
      padding: const EdgeInsets.all(VelvetSpacing.sm + 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(
              Icons.error_outline_rounded,
              size: 18,
              color: BrandColors.error,
            ),
          ),
          const SizedBox(width: VelvetSpacing.sm),
          Expanded(
            child: Text(
              failure.userMessage(context),
              style: VelvetText.feedback(BrandColors.error),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pinned bottom footer carrying the «Записатись» CTA — thin wrapper over the
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
      label: inFlight ? l10n.bookingSubmitCtaLoading : l10n.bookingSubmitCta,
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
