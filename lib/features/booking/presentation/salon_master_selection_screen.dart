// MO-4 (single-master single-visit rework) — SalonMasterSelectionScreen: salon
// booking flow step 2 of 4.
//
// After multi-selecting services (step 1, `SalonServiceSelectionScreen`), the
// CLIENT sees only the masters who perform ALL of the selected services (the
// coverage INTERSECTION) and picks exactly ONE. This REPLACES the pre-MO-4
// per-service master-assignment + contested-service resolver: a salon booking
// is now ONE visit against ONE master who covers the whole selection, mirroring
// the independent-master flow. If NO single master covers every selected
// service, a clear empty state guides the client to adjust their selection
// (the single-master constraint — there is no multi-master fallback).
//
// «Далі» resolves the chosen master's ordered per-master `MasterServiceAssignment`
// ids (from `salonMasterServiceCoverageProvider`) into a [SalonMasterSchedule]
// visit and pushes the step-3 "Час" screen (`RouteNames.salonBookingTime`).
//
// DATA — [salonMasterServiceCoverageProvider] (`salon_master_coverage_notifier
// .dart`) resolves `masterId -> {serviceDefId: assignmentId}` via one
// `GET /salons/{salonId}/services/{serviceDefId}/masters` per selected service
// (8-concurrent, per-service graceful degradation). A master covers the whole
// selection iff its coverage map contains EVERY selected service id. Master
// DISPLAY data (name/avatar/rating) comes from `publicSalonProfileProvider`'s
// roster.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:beautica_mobile/shared/widgets/skeleton_shimmer.dart';

import '../../salon/application/public_salon_profile_notifier.dart';
import '../../salon/application/salon_service_catalog_notifier.dart';
import '../../salon/domain/salon_master_summary.dart';
import '../../salon/domain/salon_service_catalog.dart';
import '../application/salon_master_coverage_notifier.dart';
import '../domain/salon_booking_args.dart';
import '../domain/salon_master_schedule.dart';
import 'widgets/booking_summary_bar.dart';
import 'widgets/master_strip.dart';
import 'widgets/selected_services_shelf.dart';

/// Avatar gradients cycled by roster position — the exact palette
/// `SalonMasterCard` uses; kept in sync here since only camel/mocha gradient
/// placeholders exist for master avatars anywhere in the app.
const List<List<Color>> _kAvatarGradients = <List<Color>>[
  <Color>[Color(0xFFD4B896), Color(0xFF8A6840)],
  <Color>[Color(0xFFB89A7A), Color(0xFF6A4A28)],
  <Color>[Color(0xFFDFC6A8), Color(0xFFB89A7A)],
  <Color>[Color(0xFFC8A878), Color(0xFF6A4A28)],
  <Color>[Color(0xFFCFB090), Color(0xFF8A6840)],
  <Color>[Color(0xFFE0CAAC), Color(0xFFB89A7A)],
];

List<Color> _avatarGradient(int index) =>
    _kAvatarGradients[index % _kAvatarGradients.length];

/// Salon booking flow step 2 — single covering-master picker.
class SalonMasterSelectionScreen extends ConsumerStatefulWidget {
  const SalonMasterSelectionScreen({super.key, required this.args});

  final SalonBookingMasterSelectionArgs args;

  @override
  ConsumerState<SalonMasterSelectionScreen> createState() =>
      _SalonMasterSelectionScreenState();
}

class _SalonMasterSelectionScreenState
    extends ConsumerState<SalonMasterSelectionScreen> {
  /// The single chosen master id, or `null` before any pick. A `ValueNotifier`
  /// (not a `setState` field) so tapping a row rebuilds only the affected rows
  /// + the pinned bar, not the whole master list.
  final ValueNotifier<String?> _pickedMasterId = ValueNotifier<String?>(null);

  // Captured in initState so dispose() never touches `ref` (Riverpod 3.x
  // throws on a post-dispose `ref` read).
  late final ScreenProtectionManager _screenProtection;

  @override
  void initState() {
    super.initState();
    // SEC: renders selected service names + prices via `SelectedServicesShelf`
    // — guard against screenshots / app-switcher snapshots while mounted.
    _screenProtection = ref.read(screenProtectionProvider)..acquire();
  }

  @override
  void dispose() {
    _screenProtection.release();
    _pickedMasterId.dispose();
    super.dispose();
  }

  void _pick(String masterId) {
    _pickedMasterId.value = _pickedMasterId.value == masterId ? null : masterId;
  }

  /// Builds the chosen master's [SalonMasterSchedule] visit (ordered services +
  /// their per-master assignment ids) and pushes the step-3 "Час" screen.
  void _confirm(
    SalonMasterSummary master,
    List<SalonCatalogService> selected,
    Map<String, String> coverageForMaster,
  ) {
    // Every selected service is covered by this master (only covering masters
    // are pickable), so each assignment id resolves — guarded anyway to avoid
    // a `!` on a nullable map read.
    final List<String> orderedIds = <String>[];
    for (final SalonCatalogService s in selected) {
      final String? assignmentId = coverageForMaster[s.id];
      if (assignmentId == null) return;
      orderedIds.add(assignmentId);
    }

    final SalonMasterSchedule visit = SalonMasterSchedule(
      masterId: master.masterId,
      firstName: master.firstName,
      lastName: master.lastName,
      type: master.type,
      professionalTitle: master.professionalTitle,
      avgRating: master.reviewCount > 0 ? master.avgRating : null,
      reviewCount: master.reviewCount,
      services: selected,
      orderedMasterServiceIds: orderedIds,
    );

    context.push(
      RouteNames.salonBookingTime,
      extra: SalonBookingTimeArgs(salonId: widget.args.salonId, visit: visit),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final String salonId = widget.args.salonId;

    final salonAsync = ref.watch(publicSalonProfileProvider(salonId));
    final catalogAsync = ref.watch(salonServiceCatalogProvider(salonId));
    final coverageAsync = ref.watch(
      salonMasterServiceCoverageProvider(widget.args),
    );

    final Object? error =
        salonAsync.error ?? catalogAsync.error ?? coverageAsync.error;
    final PublicSalonProfileData? salonData = salonAsync.value;
    final List<SalonServiceCategoryEntry>? catalog = catalogAsync.value;
    final Map<String, Map<String, String>>? coverage = coverageAsync.value;

    Widget body;
    Widget? bottomBar;

    if (error != null) {
      final Failure failure = error is Failure
          ? error
          : UnknownFailure(cause: error);
      body = SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: SizedBox(
          height: 400,
          child: ErrorState(
            key: const Key('salon-master-selection-error-state'),
            failure: failure,
            onRetry: () {
              ref.invalidate(publicSalonProfileProvider(salonId));
              ref.invalidate(salonServiceCatalogProvider(salonId));
              ref.invalidate(salonMasterServiceCoverageProvider(widget.args));
            },
          ),
        ),
      );
    } else if (salonData == null || catalog == null || coverage == null) {
      body = const _LoadingBody();
    } else {
      final (_, List<SalonMasterSummary> masters) = salonData;
      final List<SalonCatalogService> allServices = <SalonCatalogService>[
        for (final SalonServiceCategoryEntry c in catalog) ...c.services,
      ];
      // Index services by id once (first occurrence wins, matching the prior
      // `firstWhere`), so selection resolution is a single lookup per id
      // instead of two linear scans.
      final Map<String, SalonCatalogService> servicesById =
          <String, SalonCatalogService>{};
      for (final SalonCatalogService s in allServices) {
        servicesById.putIfAbsent(s.id, () => s);
      }
      final List<SalonCatalogService> selected = <SalonCatalogService>[
        for (final String id in widget.args.selectedServiceIds)
          if (servicesById[id] case final SalonCatalogService s) s,
      ];

      // The coverage INTERSECTION: masters whose coverage map contains EVERY
      // selected service id — i.e. they perform the whole visit. Roster order
      // is preserved.
      final List<SalonMasterSummary> covering = <SalonMasterSummary>[
        for (final SalonMasterSummary m in masters)
          if (_coversAll(coverage[m.masterId], widget.args.selectedServiceIds))
            m,
      ];

      final List<MasterService> shelfServices = <MasterService>[
        for (final SalonCatalogService s in selected) salonServiceForShelf(s),
      ];

      body = _Body(
        covering: covering,
        pickListenable: _pickedMasterId,
        onPick: _pick,
      );

      // Pinned shelf + total + «Далі». Enabled once ONE master is picked.
      // Only shown when at least one master covers the whole selection — the
      // empty state (in `_Body`) needs no confirm bar.
      bottomBar = covering.isEmpty
          ? null
          : ValueListenableBuilder<String?>(
              valueListenable: _pickedMasterId,
              builder: (BuildContext context, String? picked, Widget? _) {
                return BookingSummaryBar(
                  services: shelfServices,
                  ctaLabel: l10n.bookingNextCta,
                  ctaIcon: Icons.arrow_forward_rounded,
                  enabled: picked != null,
                  onAction: () {
                    if (picked == null) return;
                    final SalonMasterSummary master = covering.firstWhere(
                      (SalonMasterSummary m) => m.masterId == picked,
                    );
                    _confirm(
                      master,
                      selected,
                      coverage[picked] ?? const <String, String>{},
                    );
                  },
                );
              },
            );
    }

    return Scaffold(
      backgroundColor: BrandColors.base,
      bottomNavigationBar: bottomBar,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            _TopBar(
              title: l10n.salonBookingMastersTitle,
              onBack: () => context.pop(),
            ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }

  /// Whether [coverageForMaster] (a master's `serviceDefId -> assignmentId`
  /// map, or `null` if the master covers nothing) contains EVERY id in
  /// [selectedServiceIds] — i.e. this master performs the whole visit.
  static bool _coversAll(
    Map<String, String>? coverageForMaster,
    List<String> selectedServiceIds,
  ) {
    if (coverageForMaster == null || selectedServiceIds.isEmpty) return false;
    for (final String id in selectedServiceIds) {
      if (!coverageForMaster.containsKey(id)) return false;
    }
    return true;
  }
}

// ---------------------------------------------------------------------------
// Top bar + step indicator
// ---------------------------------------------------------------------------

class _TopBar extends StatelessWidget {
  const _TopBar({required this.title, required this.onBack});

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
                key: const Key('salon-master-selection-back'),
                icon: Icons.arrow_back_ios_new_rounded,
                semanticLabel: l10n.registerBackStep,
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
              child: _StepIndicator(current: 2, total: 4),
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
              style: VelvetText.bookChipSecW800,
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

// ---------------------------------------------------------------------------
// Loading state
// ---------------------------------------------------------------------------

class _LoadingBody extends StatelessWidget {
  const _LoadingBody();

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmerScope(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          VelvetSpacing.lg,
          VelvetSpacing.md,
          VelvetSpacing.lg,
          VelvetSpacing.lg,
        ),
        children: const <Widget>[
          SkeletonBlock(
            width: double.infinity,
            height: 96,
            radius: VelvetRadii.card,
          ),
          SizedBox(height: VelvetSpacing.md),
          SkeletonBlock(
            width: double.infinity,
            height: 96,
            radius: VelvetRadii.card,
          ),
          SizedBox(height: VelvetSpacing.md),
          SkeletonBlock(
            width: double.infinity,
            height: 96,
            radius: VelvetRadii.card,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Body — covering-master list OR the no-covering-master empty state
// ---------------------------------------------------------------------------

class _Body extends StatelessWidget {
  const _Body({
    required this.covering,
    required this.pickListenable,
    required this.onPick,
  });

  final List<SalonMasterSummary> covering;
  final ValueListenable<String?> pickListenable;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    if (covering.isEmpty) {
      // The single-master constraint: no ONE master performs every selected
      // service. Guide the client to adjust their selection — there is no
      // multi-master fallback.
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(VelvetSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SizedBox(
                height: 88,
                width: 88,
                child: NeumorphicInset(
                  radius: 44,
                  child: Center(
                    child: Icon(
                      Icons.person_search_outlined,
                      size: 36,
                      color: BrandColors.accent.withValues(alpha: 0.9),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: VelvetSpacing.lg),
              Text(
                l10n.salonBookingNoCoveringMasterTitle,
                key: const Key('salon-master-selection-no-covering-master'),
                style: VelvetText.heading20,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: VelvetSpacing.sm),
              Text(
                l10n.salonBookingNoCoveringMasterHint,
                style: VelvetText.feedbackMutedSm,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: <Widget>[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            VelvetSpacing.lg,
            VelvetSpacing.md,
            VelvetSpacing.lg,
            0,
          ),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  l10n.salonBookingPickMasterIntro,
                  style: VelvetText.body14,
                ),
                const SizedBox(height: VelvetSpacing.lg),
                Row(
                  children: <Widget>[
                    const Icon(
                      Icons.groups_2_rounded,
                      size: 16,
                      color: BrandColors.accent,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      l10n.salonBookingMastersSectionLabel,
                      style: VelvetText.sectionLabel(),
                    ),
                    const Spacer(),
                    Text(
                      l10n.salonBookingMastersSectionHint,
                      style: VelvetText.feedbackMutedSm,
                    ),
                  ],
                ),
                const SizedBox(height: VelvetSpacing.sm + 4),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            VelvetSpacing.lg,
            0,
            VelvetSpacing.lg,
            VelvetSpacing.xxl,
          ),
          sliver: SliverList.separated(
            itemCount: covering.length,
            separatorBuilder: (BuildContext context, int i) =>
                const SizedBox(height: VelvetSpacing.sm + 4),
            itemBuilder: (BuildContext context, int i) {
              final SalonMasterSummary m = covering[i];
              return _MasterPickRowListener(
                key: Key('salon_booking_master_row_${m.masterId}'),
                master: m,
                avatarGradient: _avatarGradient(i),
                pickListenable: pickListenable,
                onTap: () => onPick(m.masterId),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Listens to the shared pick `ValueNotifier` directly so tapping one master
/// only rebuilds the rows whose selected flag actually flipped.
class _MasterPickRowListener extends StatefulWidget {
  const _MasterPickRowListener({
    super.key,
    required this.master,
    required this.avatarGradient,
    required this.pickListenable,
    required this.onTap,
  });

  final SalonMasterSummary master;
  final List<Color> avatarGradient;
  final ValueListenable<String?> pickListenable;
  final VoidCallback onTap;

  @override
  State<_MasterPickRowListener> createState() => _MasterPickRowListenerState();
}

class _MasterPickRowListenerState extends State<_MasterPickRowListener> {
  late bool _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.pickListenable.value == widget.master.masterId;
    widget.pickListenable.addListener(_handleChanged);
  }

  @override
  void dispose() {
    widget.pickListenable.removeListener(_handleChanged);
    super.dispose();
  }

  void _handleChanged() {
    final bool next = widget.pickListenable.value == widget.master.masterId;
    if (next == _selected) return;
    setState(() => _selected = next);
  }

  @override
  Widget build(BuildContext context) {
    return _MasterPickRow(
      master: widget.master,
      avatarGradient: widget.avatarGradient,
      selected: _selected,
      onTap: widget.onTap,
    );
  }
}

/// One selectable master row: the shared [MasterStrip] identity card + a radio
/// select token.
///
/// ## Why there is no row-wide press scale (mobile-perf MEDIUM)
///
/// This row used to add its own `AnimatedScale(0.99)` press affordance. It was
/// driven by a `Listener`, because a second `GestureDetector` here would enter
/// the gesture arena against [MasterStrip]'s own — deeper, therefore winning —
/// `InkWell` and lose, leaving the scale stuck mid-press.
///
/// But `Listener` is not an arena member either, and that is exactly the
/// problem: when the enclosing `Scrollable` claims the drag, the row is never
/// told. `onPointerDown` set the flag and only `onPointerUp`/`onPointerCancel`
/// cleared it, neither of which fires until the finger lifts — so EVERY scroll
/// begun on a row pinned that row at 0.99 for the whole drag and fling, while
/// the `InkWell` (a proper arena member) correctly dropped its highlight. The
/// two press affordances visibly disagreed. `master_booking_card.dart:1715`
/// documents this same failure mode from an earlier audit.
///
/// The fix is to delete the row scale rather than to patch its reset, because
/// since M2 the strip owns its own tap and therefore its own press feedback:
/// the row was showing TWO stacked press signals for one gesture. Deleting it
/// leaves the `InkWell` as the sole affordance — and, crucially, adds no new
/// gesture recognizer, so the arena conflict that forced the `Listener` in the
/// first place cannot come back. The row is stateless again as a result.
class _MasterPickRow extends StatelessWidget {
  const _MasterPickRow({
    required this.master,
    required this.avatarGradient,
    required this.selected,
    required this.onTap,
  });

  final SalonMasterSummary master;
  final List<Color> avatarGradient;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final SalonMasterSummary m = master;
    final String name = '${m.firstName} ${m.lastName}'.trim();
    final String? ownTitle = m.professionalTitle?.trim();
    final String role = (ownTitle != null && ownTitle.isNotEmpty)
        ? ownTitle
        : masterRoleLabel(m.type, l10n);
    final double? avgRating = m.reviewCount > 0 ? m.avgRating : null;
    final String ratingLabel =
        avgRating?.toStringAsFixed(1) ?? MasterStrip.noRatingLabel;

    return Semantics(
      button: true,
      checked: selected,
      label: l10n.salonMasterCardSemanticLabel(name, role, ratingLabel),
      // REQUIRED, not decorative. `ExcludeSemantics` strips the `InkWell`'s
      // and the row detector's tap actions out of the subtree, so without an
      // action of its own this node announced to TalkBack as a checkable
      // button that could not be activated — a screen-reader user could not
      // pick a master at all, which makes the whole salon booking flow
      // unfinishable. Same defect class as `master_strip_shell.dart:214`.
      onTap: onTap,
      child: ExcludeSemantics(
        // Restores the dead hit zone the deleted row-wide detector used to
        // cover: the `SizedBox` gutter between the strip and the token (a
        // ~40dp column) toggled nothing once the row went stateless.
        //
        // Safe against the F1 scroll-pin regression this row was rewritten to
        // cure: a `TapGestureRecognizer` is a proper arena member, so when the
        // enclosing `Scrollable` claims the drag this loses the arena and is
        // cancelled — unlike the `Listener` that pinned the old press scale.
        // It also adds NO press state: the row stays stateless and the strip's
        // `InkWell` remains the sole press affordance. Being shallower than
        // that `InkWell`, it never steals the strip region (arena sweep
        // resolves to the first-added member, which is the deepest).
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Row(
            children: <Widget>[
              Expanded(
                child: MasterStrip(
                  name: name,
                  type: m.type,
                  professionalTitle: m.professionalTitle,
                  avgRating: avgRating,
                  reviewCount: m.reviewCount,
                  showLabel: false,
                  showRole: true,
                  showRating: true,
                  avatarGradient: avatarGradient,
                  avatarBordered: true,
                  // The strip owns its tap (M2), and since the row-wide press
                  // SCALE was deleted its `InkWell` is also the row's only
                  // press affordance — the row detector above is hit-target
                  // coverage only and paints nothing. Here the tap SELECTS
                  // this master rather than navigating to their reviews, so
                  // this row is exempt from the leave/stay policy documented
                  // on `MasterStrip.onTap`.
                  onTap: onTap,
                ),
              ),
              const SizedBox(width: VelvetSpacing.sm + 2),
              // The select token no longer needs a detector of its own: the
              // row-wide opaque one above covers it (and the gutter) against
              // the identical callback.
              _SelectToken(selected: selected),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectToken extends StatelessWidget {
  const _SelectToken({required this.selected});

  final bool selected;

  static const double _size = 30;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _size,
      width: _size,
      child: selected
          ? AnimatedScale(
              scale: 1,
              duration: const Duration(milliseconds: 260),
              curve: Curves.elasticOut,
              child: Container(
                key: const ValueKey<bool>(true),
                decoration: const BoxDecoration(
                  // RRect (radius = half the 30dp side) reads as a circle but
                  // avoids Impeller-GLES's broken circle box-shadow blur path.
                  borderRadius: BorderRadius.all(Radius.circular(15)),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[
                      BrandColors.accentLatte,
                      BrandColors.accentDeep,
                    ],
                  ),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: Color(0xFF8C6A44),
                      offset: Offset(2, 2),
                      blurRadius: 5,
                      spreadRadius: -1,
                    ),
                    BoxShadow(
                      color: BrandColors.shadowLightStrong,
                      offset: Offset(-2, -2),
                      blurRadius: 5,
                      spreadRadius: -1,
                    ),
                  ],
                ),
                child: const Center(
                  child: Icon(
                    Icons.check_rounded,
                    size: 18,
                    color: BrandColors.white,
                  ),
                ),
              ),
            )
          : const NeumorphicInset(
              radius: 999,
              child: SizedBox(height: _size, width: _size),
            ),
    );
  }
}
