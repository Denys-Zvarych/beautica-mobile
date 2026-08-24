// Phase 249 — Promoted booking-wizard chrome + step widgets.
//
// PURE MOVE — no behaviour change. These widgets were private to
// `master_create_booking_screen.dart` (Phase 247 part 2) and are promoted
// here, verbatim, per the REUSE-FIRST rule: Phase 250's SALON 6-step wizard
// needs the EXACT SAME step bodies this master wizard already uses (same
// client form, same service picker, same date/time embed, same confirm
// recap), differing only by an inserted `masters` step and a different
// master source. A `_`-prefixed class cannot be imported from another file,
// so copying was the only alternative — forbidden by this repo's locked
// REUSE-FIRST rule (see `CLAUDE.md`). This is the same move Phase 247 part 1
// already made one layer down for the service-picker widgets themselves
// (`service_category_list.dart`).
//
// Promoted (dropped the leading underscore, otherwise byte-identical):
//   [StepIndicator]   — the dot indicator, connected by lines.
//   [ClientStep]      — Ім'я / Прізвище / Телефон + E.164 gate.
//   [ServiceStep]      — the picker over the promoted
//                        `service_category_list.dart` widgets.
//   [ServiceStepEmpty] — the required empty state.
//   [ConfirmStep]      — the summary + submit-error banner.
//
// Phase 265 D2 — `DateTimeStep` (which used to be promoted here, wrapping
// `MasterSchedulePage`) is DELETED. It was the only ORPHANED step widget
// once Phase 264 swapped `/master/bookings/new` onto the routed walk-in
// chain (which uses the client's own `SlotDateScreen`/`SlotTimeScreen`
// instead) and the salon wizard NEVER called it (see
// `salon_create_booking_screen.dart`'s own file header). Verified by an
// exact-count grep before deletion, not by eye — see this phase's own
// hand-off notes.
//
// Also promoted — a private helper [ClientStep]/[ConfirmStep]'s own
// `_submit` boundary depend on, which would otherwise fail to compile from a
// separate file (mirrors Phase 247 part 1's `_CardEntry` →
// [CategoryGroupEntry] promotion):
//   [toE164UaPhone] — the screen-boundary UA phone normalizer. Still NOT
//   added to `shared/validators/phone_validator.dart` — see its own doc for
//   why the two coexist; moving it into this widgets file keeps it at the
//   same conceptual boundary (the wizard's own client-collection step), just
//   promoted alongside the widget that is its only real caller.
//
// Kept private (implementation detail of [ConfirmStep], no external consumer
// needs it standalone — mirrors the byte-identical `_SubmitErrorBanner`
// already duplicated across FOUR other files in this codebase, see its own
// doc below):
//   [_SubmitErrorBanner]
//
// ONE additive change, and only one (per the phase brief): [StepIndicator]
// used to hard-code both the dot COUNT (4) and its own step-index lookup via
// the master wizard's private `_BookingStep` enum — a type that cannot cross
// files. Promoting it therefore ALSO required retyping `step: _BookingStep`
// to `currentStep: int` (an unavoidable consequence of the enum being
// file-private, not a behaviour change — `_BookingStep.index` for every
// pre-`done` step is numerically identical to the old `_steps.indexOf(step)`
// lookup, see `master_create_booking_screen.dart`'s call site). The COUNT
// itself is the one genuinely additive parameter: `totalSteps` defaults to
// `4`, the master variant's value, so the master screen's call site does not
// need to pass it. Phase 250's salon wizard (5 steps) passes `totalSteps: 5`.
//
// `master_create_booking_screen.dart` was the ORIGINAL sole caller; Phase 250
// added the salon wizard as an ADDITIVE second consumer of these same public
// types. Phase 265 deleted the master wizard outright (its route now renders
// the routed walk-in chain instead — [WalkInGuestStepScreen] /
// [WalkInServiceStepScreen], `presentation/walk_in_*_step_screen.dart`, which
// reuse [ClientStep] / [ServiceStep] / [ServiceStepEmpty] verbatim), so
// `salon_create_booking_screen.dart` is now this file's only [StepIndicator]/
// [ConfirmStep] caller — [ClientStep]/[ServiceStep]/[ServiceStepEmpty] gained
// the two new walk-in-chain callers alongside it.
//
// PHASE 250 — two more additive params, both defaulting to `null` so
// `master_create_booking_screen.dart`'s existing call sites take the exact
// same branch as before (golden-verified — see
// `test/golden/master_create_booking_wizard_golden_test.dart`):
//
//   * [ServiceStep.servicesOverride] / [ServiceStep.onRetryOverride] — the
//     master wizard's service picker is fed from `servicesListProvider`
//     ("MY OWN services" — the authenticated master's own catalogue). The
//     salon wizard cannot use that provider at all: its caller is
//     `SALON_OWNER` (who may also be a performing master, i.e. own SOME
//     services) or `SALON_ADMIN` (who owns NONE — an admin has no master
//     profile, so `listMyServices()` is the wrong question for them). The
//     salon wizard's service picker must show the SALON's aggregate
//     catalogue (every service any of its masters perform), not "my own".
//     Rather than reaching into [ServiceStep] and rewiring which provider it
//     watches (which would touch the master wizard's own path too), the step
//     accepts an already-resolved [AsyncValue] to render instead — the salon
//     screen computes it from `salonServiceCatalogProvider(salonId)` and
//     hands it down. `null` (both params) preserves the ORIGINAL
//     `ref.watch(servicesListProvider)` / `ref.invalidate(servicesListProvider)`
//     pair unchanged.
//   * [ConfirmStep.masterCard] — the design's confirm step shows a master
//     identity card (`_ConfirmStep`'s "Запис до майстра" block) because a
//     SALON booker picks among several masters. The master wizard
//     deliberately omits it (deviation #4, `master_create_booking_screen
//     .dart`'s file header — a master booking themselves would see a card
//     naming themselves). [BookingSummaryCards] already exposes a
//     `masterCard: Widget?` slot for exactly this; this promotion only
//     threads it through from [ConfirmStep]'s own constructor. `null` (the
//     master wizard's call site) renders no card, exactly as before.
//
// PHASE 253 — [ServiceStep] widened ADDITIVELY from single- to multi-select,
// so both wizards can build a real N-service visit (`masterServiceIds`,
// Phase 252's data layer) instead of the temporary one-element shim.
//
//   * [ServiceStep.selectedServiceIds] / [ServiceStep.onToggleService] — the
//     new pair. `selectedServiceIds` is a `ValueListenable<Set<String>>`
//     (the caller's own [CatalogueSelectionController] — REUSED verbatim from
//     `service_catalogue_accordion.dart`, the same primitive
//     `ServiceSelectorSheet`/`SalonServiceSelectionScreen` already use for
//     this exact job; not forked, not rebuilt). `onToggleService` fires with
//     the tapped [MasterService] on every tap, add or remove — the CALLER
//     decides whether to allow the add (the `maxServicesPerVisit` cap lives
//     in the wizard screen's own toggle handler, mirroring
//     `service_selector_sheet.dart:277-288`'s `_onToggleService`, NOT inside
//     this widget) and how to track selection ORDER (the wizard screen
//     appends/removes from its own ordered `List<MasterService>` as each
//     callback fires — a `Set` cannot carry tap order, so this widget never
//     tries to derive one).
//   * `null` (both) is the ORIGINAL single-select path, preserved byte-for-
//     byte: the mark predicate falls back to `entry.service.id ==
//     widget.selectedServiceId` and each tap calls `widget.onSelect` — the
//     constructor asserts the two pairs are never mixed. No existing caller
//     passes the new pair, so nothing renders differently until a caller
//     opts in.
//   * The picker's underlying accordion ([CategorySection] / [ServiceCard]
//     from `service_category_list.dart`) is UNCHANGED — [ServiceCard]
//     already exposed additive `selectable`/`selected` booleans generic to
//     single- vs. multi-select (Phase 247 part 2), so widening the SELECTION
//     SOURCE the mark predicate reads from is the only change this phase
//     makes here. The client flow's OTHER accordion family
//     (`CatalogueCategorySection`/`CatalogueRow` in
//     `service_catalogue_accordion.dart`) renders a domain-agnostic
//     projection for a differently-shaped screen (full-page, favourite
//     hearts, category hoisting) and is NOT swapped in here — doing so would
//     duplicate rendering logic this widget already has working, which is
//     exactly what REUSE-FIRST forbids. [BookingSummaryBar] (the pinned
//     "Разом" shelf + CTA) IS reused, at the wizard-screen level, as this
//     step's new bottom bar — see `master_create_booking_screen.dart` /
//     `salon_create_booking_screen.dart`.

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart'
    show approvedCategoriesProvider;
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

import '../../application/master_create_booking_notifier.dart'
    show masterCreateBookingProvider;
import '../../domain/create_master_booking_request.dart'
    show kWalkInGuestNameMaxLength;
import 'booking_recap.dart';
import 'booking_summary_cards.dart';
import 'labelled_row.dart';

// ---------------------------------------------------------------------------
// Phone normalization
// ---------------------------------------------------------------------------

/// Normalizes a Ukrainian phone number typed in ANY shape the client accepts
/// (`+380 XX XXX XX XX`, `380XXXXXXXXX`, `0XXXXXXXXX`, or a bare 9-digit
/// subscriber number) to the bare E.164 shape `WalkInGuest.phone`'s wire
/// CHECK (`kWalkInGuestPhonePattern`) requires — `+380XXXXXXXXX`, no
/// separators. Returns `null` when [raw] does not resolve to exactly 9
/// Ukrainian subscriber digits.
///
/// Deliberately NOT added to `shared/validators/phone_validator.dart`: this
/// wizard's domain rule (`create_master_booking_request.dart`'s doc) is that
/// phone normalization happens AT THE SCREEN BOUNDARY, not in a shared
/// validator or the repository. This mirrors `validatePhone`'s own branch
/// structure (the exact same accepted/rejected shapes) but returns the
/// normalized string instead of a validity verdict — a different output
/// contract that validator was never built to carry, so the two coexist
/// rather than one wrapping the other.
String? toE164UaPhone(String raw) {
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
// Step indicator — dots connected by lines. Literal port of the design
// file's own `_StepIndicator`. See file header for the one additive param
// this promotion adds ([totalSteps]).
// ---------------------------------------------------------------------------

class StepIndicator extends StatelessWidget {
  const StepIndicator({
    super.key,
    required this.currentStep,
    this.totalSteps = 4,
  });

  /// 0-based index of the active step among the wizard's non-`done` steps.
  final int currentStep;

  /// Total number of non-`done` steps to render dots for. Defaults to `4` —
  /// the master wizard's value — so the master screen's call site does not
  /// need to pass it. Phase 250's salon wizard passes `5`.
  final int totalSteps;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      label: l10n.salonBookingStepLabel(currentStep + 1, totalSteps),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: VelvetSpacing.xl,
          vertical: VelvetSpacing.sm,
        ),
        child: Row(
          children: List<Widget>.generate(totalSteps * 2 - 1, (int i) {
            if (i.isOdd) {
              return Expanded(
                child: Container(
                  height: 1,
                  color: i ~/ 2 < currentStep
                      ? BrandColors.accent
                      : BrandColors.faint,
                ),
              );
            }
            final int idx = i ~/ 2;
            final bool done = idx < currentStep;
            final bool active = idx == currentStep;
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
// Step — Client
// ---------------------------------------------------------------------------

class ClientStep extends StatefulWidget {
  const ClientStep({
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
  State<ClientStep> createState() => _ClientStepState();
}

class _ClientStepState extends State<ClientStep> {
  bool get _canAdvance =>
      widget.firstNameCtrl.text.trim().isNotEmpty &&
      widget.lastNameCtrl.text.trim().isNotEmpty &&
      toE164UaPhone(widget.phoneCtrl.text) != null;

  String? _phoneError(AppLocalizations l10n) {
    final String raw = widget.phoneCtrl.text.trim();
    if (raw.isEmpty) return null;
    return toE164UaPhone(raw) == null ? l10n.errPhoneInvalid : null;
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
            // Mirrors the backend column EXACTLY —
            // `StaffClientRef.Guest.MAX_NAME_LENGTH` = 100, itself mirroring
            // `bookings.guest_name VARCHAR(100)`. Anything longer is a clean
            // 400 from the server, so refusing the 101st character here turns
            // a round-trip rejection into a keystroke that simply does not
            // land — and bounds what the confirm/done recap cards have to
            // render (audit-fix cycle 1, FINDING 4). `NeumorphicTextField`
            // pins `counterText: ''`, so no counter appears and no layout
            // moves.
            maxLength: kWalkInGuestNameMaxLength,
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
            // Same backend ceiling as the first-name field above.
            maxLength: kWalkInGuestNameMaxLength,
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
// Step — Service (picker mode over the Phase 247 part 1 promoted widgets)
// ---------------------------------------------------------------------------

class ServiceStep extends ConsumerStatefulWidget {
  const ServiceStep({
    super.key,
    this.selectedServiceId,
    this.onSelect,
    this.selectedServiceIds,
    this.onToggleService,
    this.servicesOverride,
    this.onRetryOverride,
    this.emptyTitleOverride,
    this.emptyBodyOverride,
  }) : assert(
         (selectedServiceIds == null) == (onToggleService == null),
         'selectedServiceIds and onToggleService must be provided together '
         '(the multi-select path) — never one without the other.',
       ),
       assert(
         selectedServiceIds != null || onSelect != null,
         'ServiceStep needs either the multi-select pair '
         '(selectedServiceIds + onToggleService) or the legacy onSelect '
         'callback.',
       );

  /// Legacy single-select path. `null` when [selectedServiceIds] is provided
  /// instead (the multi-select path) — see this file's header.
  final String? selectedServiceId;

  /// Legacy single-select path. `null` when [onToggleService] is provided
  /// instead.
  final ValueChanged<MasterService>? onSelect;

  /// PHASE 253 — multi-select path. A [CatalogueSelectionController] (or any
  /// `ValueListenable<Set<String>>`) the caller owns and disposes. `null`
  /// preserves the original single-select rendering exactly — see this
  /// file's header.
  final ValueListenable<Set<String>>? selectedServiceIds;

  /// PHASE 253 — fires with the tapped [MasterService] on every tap (add OR
  /// remove); the caller decides whether to allow the add (cap) and how to
  /// track selection order. Paired 1:1 with [selectedServiceIds] — see this
  /// file's header.
  final ValueChanged<MasterService>? onToggleService;

  /// Phase 250 (salon wizard) — overrides the internal
  /// `ref.watch(servicesListProvider)` read with an already-resolved
  /// [AsyncValue]. `null` (the master wizard's only call site) preserves the
  /// original behaviour exactly — see this file's header.
  final AsyncValue<List<MasterService>>? servicesOverride;

  /// Paired with [servicesOverride]: the retry action for that override's
  /// error state. `null` preserves the original
  /// `ref.invalidate(servicesListProvider)` retry.
  final VoidCallback? onRetryOverride;

  /// Forwarded to [ServiceStepEmpty] — see that widget's own doc.
  final String? emptyTitleOverride;
  final String? emptyBodyOverride;

  @override
  ConsumerState<ServiceStep> createState() => _ServiceStepState();
}

class _ServiceStepState extends ConsumerState<ServiceStep> {
  // PERF A1 (HIGH) fix — mirrors services_list_screen.dart:337. Driving a
  // `ListView.builder` off the resolved groups (instead of a plain
  // `ListView` over an eagerly-built `children:` list) means `ServiceStep`
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
  // sections' worth of children on every `ServiceStep` rebuild) plus the
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

  // Named (not inlined as `() => ref.invalidate(servicesListProvider)`) so
  // `dart format` can never re-wrap the call onto a line without `onRetry`
  // on it. `test/features/services/presentation/services_catalogue_invalidation_test.dart`
  // greps `lib/**.dart` LINE BY LINE for `invalidate(servicesListProvider)`
  // and only exempts lines that also contain `onRetry` — a retry of this
  // step's own failed read is not a catalogue mutation, but the guard is
  // line-based, so a wrapped `onRetry: widget.onRetryOverride ?? () => ...`
  // closure (line break landing between `onRetry:` and the invalidate call)
  // false-positives. Do not "simplify" this back into an inline closure.
  void _onRetry() => ref.invalidate(servicesListProvider);

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
    final AsyncValue<List<MasterService>> asyncServices =
        widget.servicesOverride ?? ref.watch(servicesListProvider);
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
        onRetry: widget.onRetryOverride ?? _onRetry,
      ),
      data: (List<MasterService> list) {
        if (list.isEmpty) {
          return ServiceStepEmpty(
            key: const Key('master-create-booking-service-empty'),
            titleOverride: widget.emptyTitleOverride,
            bodyOverride: widget.emptyBodyOverride,
          );
        }
        final List<CategoryGroup> groups = _resolveGroups(
          list,
          categoriesAsync,
          l10n.serviceCategoryUncategorized,
        );
        final ValueListenable<Set<String>>? selectedIds =
            widget.selectedServiceIds;
        // Legacy single-select path (`selectedIds == null`) renders the
        // EXACT SAME tree as before this phase — no `ValueListenableBuilder`
        // wrap, so byte-identical for every pre-existing caller.
        if (selectedIds == null) {
          return _buildGroupList(groups, selectedServiceIds: null);
        }
        // Multi-select path — re-marks the affected cards whenever the
        // caller's selection set changes. Scoped to just this list (not the
        // whole `ServiceStep`), mirroring the narrow-`ValueListenableBuilder`
        // pattern `ServiceSelectorSheet`/`BookingSummaryBar` already use.
        return ValueListenableBuilder<Set<String>>(
          valueListenable: selectedIds,
          builder: (BuildContext context, Set<String> ids, _) =>
              _buildGroupList(groups, selectedServiceIds: ids),
        );
      },
    );
  }

  Widget _buildGroupList(
    List<CategoryGroup> groups, {
    required Set<String>? selectedServiceIds,
  }) {
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
                    selected: selectedServiceIds != null
                        ? selectedServiceIds.contains(entry.service.id)
                        : entry.service.id == widget.selectedServiceId,
                    onEdit: selectedServiceIds != null
                        ? () => widget.onToggleService!(entry.service)
                        : () => widget.onSelect!(entry.service),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class ServiceStepEmpty extends StatelessWidget {
  const ServiceStepEmpty({super.key, this.titleOverride, this.bodyOverride});

  /// Phase 250 (salon wizard) — the master wizard's default copy
  /// ("Додайте послугу в розділі «Мої послуги»…") tells the reader to go add
  /// a service THEMSELVES, which is simply wrong for a `SALON_ADMIN` caller
  /// — that role has no master profile and no «Мої послуги» screen at all.
  /// `null` (the master wizard's only call site) preserves the original
  /// copy unchanged.
  final String? titleOverride;
  final String? bodyOverride;

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
              titleOverride ?? l10n.masterCreateBookingServiceEmptyTitle,
              style: VelvetText.headingSm,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: VelvetSpacing.sm),
            Text(
              bodyOverride ?? l10n.masterCreateBookingServiceEmptyBody,
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
// Step — Confirm
// ---------------------------------------------------------------------------

class ConfirmStep extends ConsumerWidget {
  const ConfirmStep({
    super.key,
    this.service,
    this.services,
    required this.startAt,
    required this.firstName,
    required this.lastName,
    required this.phone,
    this.masterCard,
  }) : assert(
         (service == null) != (services == null),
         'ConfirmStep needs exactly one of service (legacy single) or '
         'services (Phase 255 ordered multi) — never both, never neither.',
       );

  /// Legacy single-service path. `null` when [services] is provided instead
  /// — see this constructor's assert and [services]' own doc.
  final MasterService? service;

  /// PHASE 255 — the visit's full ordered service selection (1..n). `null`
  /// preserves the pre-255 single-service rendering exactly (every call site
  /// until this phase passed [service] alone). When non-null, this wins and
  /// [service] is ignored.
  final List<MasterService>? services;

  final DateTime startAt;
  final String firstName;
  final String lastName;
  final String phone;

  /// Phase 250 (salon wizard) — an optional prebuilt master-identity card,
  /// forwarded verbatim into [BookingSummaryCards.masterCard]. `null` (the
  /// master wizard's only call site) renders no card — see this file's
  /// header for why a master booking themselves has no business naming
  /// themselves here.
  final Widget? masterCard;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final AsyncValue<void> submitState = ref.watch(masterCreateBookingProvider);

    // Single normalisation point (mirrors [DateTimeStep]'s D2) — every use
    // below reads `ordered`, never `service`/`services` directly.
    final List<MasterService> ordered = services ?? <MasterService>[service!];

    // PHASE 255 — REUSE, not a hand-rolled sum: [BookingSelection] per
    // service (feeds [BookingSummaryCards]' already-existing MULTI path,
    // `selections:`) and the visit's window is `startAt` → `startAt +
    // Σdurations`. Summing raw `durationMinutes` ints for the WINDOW LABEL
    // is not the price-total arithmetic D1/D2 ban — it is the exact same
    // plain fold `SalonMasterSchedule.summedDurationMinutes` already uses for
    // the identical purpose (the salon flow's own multi-service confirm/
    // success window). The MONEY total is never summed here — that is
    // `BookingRecap`'s job via `formatBookingTotalsFromTerms`, reached
    // through `BookingSummaryCards(selections: ...)` below.
    final List<BookingSelection> selections = <BookingSelection>[
      for (final MasterService s in ordered)
        BookingSelection(
          name: s.name,
          price: ServicePriceDisplay.format(s),
          duration: DurationMinutes.format(s.durationMinutes),
          durationMinutes: s.durationMinutes,
          priceMin: s.priceMin,
          priceMax: s.priceMax,
        ),
    ];
    final int totalDurationMinutes = ordered.fold<int>(
      0,
      (int sum, MasterService s) => sum + s.durationMinutes,
    );

    // Legacy `service:` callers keep the EXACT pre-255 rendering
    // (`BookingRecap.single` — no "N послуг" header, no dividers, no
    // "Разом" row) — the additive-widening guarantee D4 requires. Only the
    // new `services:` path (both wizards, post-255) renders through
    // [BookingSummaryCards]' existing multi-selection `selections:` mode —
    // the SAME mode `.fromSchedule` already uses for the salon flow's own
    // multi-service visit.
    final bool isMultiPath = services != null;

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
          // WHO — the walk-in guest. No master-identity card here: the
          // caller of this step IS the one creating this booking on their
          // own calendar, so a card naming them would be self-referential
          // (see `master_create_booking_screen.dart`'s file-header deviation
          // list, item 4).
          NeumorphicCard(
            key: const Key('master-create-booking-guest-card'),
            padding: const EdgeInsets.all(VelvetSpacing.md),
            child: LabelledRow(
              label: l10n.masterCreateBookingGuestLabel,
              value: '$firstName $lastName'.trim(),
              detail: phone.isEmpty ? null : phone,
              // THIRD-PARTY FREE TEXT (audit-fix cycle 1, FINDING 4 —
              // mobile-security LOW, 2026-08-20). The guest's name is typed
              // in by the master, not formatted by the backend, and the
              // backend's own ceiling is 100 characters PER field
              // (`StaffClientRef.Guest.MAX_NAME_LENGTH`) — 200 across the two.
              // Unbounded, a pasted 200-character name flooded this recap card
              // and pushed the booking details it exists to confirm off the
              // step. `labelled_row.dart:37-47` prescribes exactly this pair
              // for the case; two lines keeps a genuinely long-but-real
              // Ukrainian double-barrelled name readable.
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: VelvetSpacing.md),
          // WHERE / WHEN / WHAT — the shared booking-details card, the SAME
          // one the client-facing confirm/success screens use.
          BookingSummaryCards(
            key: const Key('master-create-booking-confirm-card'),
            masterCard: masterCard,
            showAddress: false,
            dateLabel: formatFullDate(startAt),
            timeLabel: formatTimeRange(startAt, totalDurationMinutes),
            // See `isMultiPath`'s doc just above `build`'s return: legacy
            // `service:` renders via `singleSelection:` (byte-identical to
            // pre-255), the new `services:` path via the multi `selections:`
            // list — the SAME reused mode `.fromSchedule` already carries
            // for the salon flow's own multi-service visit.
            singleSelection: isMultiPath ? null : selections.single,
            selections: isMultiPath ? selections : const <BookingSelection>[],
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
/// promotion refactor across all five. Kept private here — [ConfirmStep] is
/// its only caller, same as before the move.
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
