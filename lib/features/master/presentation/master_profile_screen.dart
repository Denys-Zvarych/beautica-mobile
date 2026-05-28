// Phase 4.2 — Master Profile Screen (read-only).
//
// Layout: ProfileScaffold chrome (fixed top bar + scrollable body).
//
// Four [AsyncValue] states are handled explicitly:
//   • loading  → [_ProfileSkeleton] (neumorphic shimmer blocks via
//                 SkeletonShimmerScope / SkeletonBlock)
//   • data     → [_ProfileBody] (staggered fade-up reveal via
//                 AnimationController 1100 ms, 5 sections)
//   • error    → [ErrorState] with retry [ref.invalidate]
//
// Design source: `docs/signup-designs/MasterProfileScreen/` — transcribed 1:1.
//
// Domain-model gaps (fields absent from [Master]):
//   • serviceCount        → shows '—' in the Services stat tile
//   • bookingsThisMonth   → shows '—' in the Bookings stat tile
//   • contactPhone /
//     instagram           → Contacts section omitted entirely
//
// Navigation: back uses `context.pop()`; edit button is Key('btn-edit-master')
// placeholder (Phase 4.3 will wire it to RouteNames.masterEdit).

import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:screen_protector/screen_protector.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:beautica_mobile/shared/widgets/skeleton_shimmer.dart';

import 'master_profile_notifier.dart';
import 'widgets/profile_avatar.dart';
import 'widgets/profile_scaffold.dart';

export 'master_profile_notifier.dart' show masterProfileProvider;

/// Read-only view of the authenticated INDEPENDENT_MASTER's profile.
///
/// Handles all four [AsyncValue] states. Staggered entrance animation
/// assembled on a single 1100 ms [AnimationController].
class MasterProfileScreen extends ConsumerStatefulWidget {
  const MasterProfileScreen({super.key});

  @override
  ConsumerState<MasterProfileScreen> createState() =>
      _MasterProfileScreenState();
}

class _MasterProfileScreenState extends ConsumerState<MasterProfileScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  // Fix 1 (PERF HIGH-1): Pre-built CurvedAnimation instances so build() never
  // allocates a new CurvedAnimation on each frame. Typed as CurvedAnimation
  // (not Animation<double>) so dispose() is accessible. Five instances match
  // the five _revealWith() call sites in _ProfileBody.
  late final CurvedAnimation _anim0;
  late final CurvedAnimation _anim1;
  late final CurvedAnimation _anim2;
  late final CurvedAnimation _anim3;
  late final CurvedAnimation _anim4;

  // Fix 2 (PERF MEDIUM): Pre-built Tween<Offset>.animate() instances so
  // _revealWith() never allocates a new Tween+_AnimatedEvaluation on each
  // build frame. Animation<Offset> instances derived from a CurvedAnimation
  // do not own resources and do not need to be disposed.
  late final Animation<Offset> _slide0;
  late final Animation<Offset> _slide1;
  late final Animation<Offset> _slide2;
  late final Animation<Offset> _slide3;
  late final Animation<Offset> _slide4;

  @override
  void initState() {
    super.initState();
    // Fix 8 (SEC MEDIUM-3): protect PII-bearing screen from screenshots in
    // release builds. The !kDebugMode guard matches the project-wide pattern
    // (all other PII screens use the same guard).
    if (!kDebugMode) ScreenProtector.preventScreenshotOn();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    // Fix 1: initialise the six CurvedAnimation instances once here rather
    // than recreating them on every build() frame.
    _anim0 = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.00, 0.55, curve: Curves.easeOutCubic),
    );
    _anim1 = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.18, 0.65, curve: Curves.easeOutCubic),
    );
    _anim2 = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.30, 0.78, curve: Curves.easeOutCubic),
    );
    _anim3 = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.38, 0.88, curve: Curves.easeOutCubic),
    );
    _anim4 = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.44, 0.94, curve: Curves.easeOutCubic),
    );
    // Fix 2: derive the five slide animations once from their parent
    // CurvedAnimation. The same begin/end Offset is shared across all five —
    // only the parent (timing curve) differs, matching the stagger intent.
    const slideBegin = Offset(0, 0.04);
    _slide0 = Tween<Offset>(
      begin: slideBegin,
      end: Offset.zero,
    ).animate(_anim0);
    _slide1 = Tween<Offset>(
      begin: slideBegin,
      end: Offset.zero,
    ).animate(_anim1);
    _slide2 = Tween<Offset>(
      begin: slideBegin,
      end: Offset.zero,
    ).animate(_anim2);
    _slide3 = Tween<Offset>(
      begin: slideBegin,
      end: Offset.zero,
    ).animate(_anim3);
    _slide4 = Tween<Offset>(
      begin: slideBegin,
      end: Offset.zero,
    ).animate(_anim4);
  }

  @override
  void dispose() {
    // Fix 8: lift screenshot protection when leaving the screen.
    if (!kDebugMode) ScreenProtector.preventScreenshotOff();
    // Fix 1: dispose each CurvedAnimation before the controller.
    _anim0.dispose();
    _anim1.dispose();
    _anim2.dispose();
    _anim3.dispose();
    _anim4.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// Forward the controller when the data state first arrives so the entrance
  /// animation runs only when content is ready.
  void _startReveal() {
    if (!_controller.isAnimating && _controller.value == 0) {
      _controller.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final masterAsync = ref.watch(masterProfileProvider);

    return ProfileScaffold(
      title: l10n.masterProfileTitle,
      trailing: NeumorphicIconButton(
        key: const Key('btn-edit-master'),
        icon: Icons.edit_outlined,
        semanticLabel: l10n.masterEditButton,
        onTap: () {
          // Phase 4.3 will wire this to RouteNames.masterEdit.
          if (kDebugMode) {
            log(
              'Edit profile tapped — Phase 4.3 not yet implemented',
              name: 'feature.master',
              level: 800,
            );
          }
        },
      ),
      child: masterAsync.when(
        loading: () => const _ProfileSkeleton(),
        error: (e, _) => ErrorState(
          failure: e is Failure ? e : UnknownFailure(cause: e),
          onRetry: () => ref.invalidate(masterProfileProvider),
        ),
        data: (master) {
          _startReveal();
          return _ProfileBody(
            master: master,
            anim0: _anim0,
            anim1: _anim1,
            anim2: _anim2,
            anim3: _anim3,
            anim4: _anim4,
            slide0: _slide0,
            slide1: _slide1,
            slide2: _slide2,
            slide3: _slide3,
            slide4: _slide4,
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _ProfileBody — loaded state
// ---------------------------------------------------------------------------

class _ProfileBody extends StatelessWidget {
  const _ProfileBody({
    required this.master,
    required this.anim0,
    required this.anim1,
    required this.anim2,
    required this.anim3,
    required this.anim4,
    required this.slide0,
    required this.slide1,
    required this.slide2,
    required this.slide3,
    required this.slide4,
  });

  final Master master;

  // Fix 1 (PERF HIGH-1): pre-built CurvedAnimation instances passed from the
  // owning StatefulWidget. Using FadeTransition + SlideTransition avoids a
  // separate GPU raster layer per section (vs. Opacity + Transform.translate).
  // Five instances match the five reveal sections.
  final Animation<double> anim0;
  final Animation<double> anim1;
  final Animation<double> anim2;
  final Animation<double> anim3;
  final Animation<double> anim4;

  // Fix 2 (PERF MEDIUM): pre-built Animation<Offset> instances passed from the
  // owning StatefulWidget. Eliminates Tween+_AnimatedEvaluation allocations on
  // every _revealWith() call during the 1100 ms entrance animation.
  final Animation<Offset> slide0;
  final Animation<Offset> slide1;
  final Animation<Offset> slide2;
  final Animation<Offset> slide3;
  final Animation<Offset> slide4;

  /// Wraps [child] in a staggered fade-up animation.
  ///
  /// [fadeAnim] drives opacity; [slideAnim] drives the vertical offset.
  /// Both are pre-built in [_MasterProfileScreenState.initState] — no heap
  /// allocations occur during build.
  ///
  /// [FadeTransition] and [SlideTransition] are compositing-friendly — they do
  /// not create extra raster layers unlike [Opacity] + [Transform.translate].
  Widget _revealWith(
    Animation<double> fadeAnim,
    Animation<Offset> slideAnim,
    Widget child,
  ) {
    return FadeTransition(
      opacity: fadeAnim,
      child: SlideTransition(position: slideAnim, child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final String displayName = '${master.firstName} ${master.lastName}';
    final String roleLabel = _roleLabel(master.type, l10n);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // 1 — Identity card: avatar left + name / role chip / city right.
        // Warm-wash card color (#EDE4D5) reads as a distinct raised surface.
        _revealWith(
          anim0,
          slide0,
          NeumorphicCard(
            color: const Color(0xFFEDE4D5),
            padding: const EdgeInsets.all(VelvetSpacing.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                const ProfileAvatar(),
                const SizedBox(width: VelvetSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        displayName,
                        key: const Key('master-profile-name'),
                        style: VelvetText.displayName(),
                      ),
                      const SizedBox(height: VelvetSpacing.xs + 2),
                      RoleChip(
                        label: roleLabel,
                        icon: Icons.auto_awesome_rounded,
                      ),
                      if (master.city != null && master.city!.isNotEmpty) ...[
                        const SizedBox(height: VelvetSpacing.xs),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            const Icon(
                              Icons.location_on_outlined,
                              size: 13,
                              color: BrandColors.muted,
                            ),
                            const SizedBox(width: 3),
                            Flexible(
                              child: Text(
                                master.city!,
                                // Fix 3 (PERF MEDIUM-1): use pre-cached static
                                // instead of calling feedback().copyWith() per
                                // build frame.
                                style: VelvetText.feedbackMutedSm,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: VelvetSpacing.xl),

        // 2 — 4-up stats row: bookings / rating / services / reviews.
        // IntrinsicHeight + CrossAxisAlignment.stretch ensures equal heights
        // even when caption text wraps (e.g. "Записів\nмісяця").
        _revealWith(
          anim1,
          slide1,
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(
                  child: StatTile(
                    icon: Icons.calendar_month_outlined,
                    // bookingsThisMonth absent from domain model — show dash.
                    value: '—',
                    caption: l10n.masterStatsBookingsLabel,
                    iconColor: BrandColors.accentDeep,
                  ),
                ),
                const SizedBox(width: VelvetSpacing.xs),
                Expanded(
                  child: StatTile(
                    icon: Icons.star_rounded,
                    value: master.avgRating.toStringAsFixed(1),
                    caption: l10n.masterRatingLabel,
                    valueKey: const Key('master-profile-rating-value'),
                  ),
                ),
                const SizedBox(width: VelvetSpacing.xs),
                Expanded(
                  child: StatTile(
                    icon: Icons.design_services_outlined,
                    // serviceCount absent from domain model — show dash.
                    value: '—',
                    caption: l10n.masterServicesLabel,
                  ),
                ),
                const SizedBox(width: VelvetSpacing.xs),
                Expanded(
                  child: StatTile(
                    icon: Icons.reviews_outlined,
                    value: master.reviewCount.toString(),
                    caption: l10n.masterStatsReviewsLabel,
                    valueKey: const Key('master-profile-reviews-value'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: VelvetSpacing.xl),

        // 3 — Bio section (omitted entirely if bio is null or empty).
        if (master.bio != null && master.bio!.isNotEmpty)
          _revealWith(
            anim2,
            slide2,
            Column(
              key: const Key('master-profile-bio'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(
                    left: 4,
                    bottom: VelvetSpacing.xs,
                  ),
                  child: Text(
                    l10n.masterBioLabel,
                    style: VelvetText.sectionLabel(),
                  ),
                ),
                NeumorphicInset(
                  radius: VelvetRadii.card,
                  child: Padding(
                    padding: const EdgeInsets.all(VelvetSpacing.md + 2),
                    child: Text(master.bio!, style: VelvetText.bodyStrong()),
                  ),
                ),
              ],
            ),
          ),
        if (master.bio != null && master.bio!.isNotEmpty)
          const SizedBox(height: VelvetSpacing.xl),

        // 4 — Portfolio section: placeholder tiles (Phase 4.4 ships real ones).
        _revealWith(
          anim3,
          slide3,
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(
                  left: 4,
                  bottom: VelvetSpacing.xs,
                ),
                child: Row(
                  children: <Widget>[
                    Text(
                      l10n.masterPortfolioLabel,
                      style: VelvetText.sectionLabel(),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () {
                        // Phase 4.4 — portfolio gallery route.
                      },
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text('Усі фото', style: VelvetText.link()),
                          const SizedBox(width: 2),
                          const Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 12,
                            color: BrandColors.accentDeep,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Placeholder tiles — replaced by real Image.network tiles in
              // Phase 4.4.
              Row(
                children: <Widget>[
                  for (int i = 0; i < 3; i++) ...<Widget>[
                    _PortfolioPlaceholderTile(index: i),
                    if (i < 2) const SizedBox(width: VelvetSpacing.md),
                  ],
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: VelvetSpacing.xl),

        // 5 — Services section header + "Усі послуги" link (no tiles in Phase 4.2).
        _revealWith(
          anim4,
          slide4,
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(
                  left: 4,
                  bottom: VelvetSpacing.xs,
                ),
                child: Row(
                  children: <Widget>[
                    Text(
                      l10n.masterServicesLabel,
                      style: VelvetText.sectionLabel(),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () {
                        // Phase 5 — services catalog route.
                      },
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text('Усі послуги', style: VelvetText.link()),
                          const SizedBox(width: 2),
                          const Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 12,
                            color: BrandColors.accentDeep,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Service tiles ship in Phase 5. For now, an inset placeholder
              // hint so the section doesn't look empty.
              NeumorphicInset(
                radius: VelvetRadii.field,
                child: Padding(
                  padding: const EdgeInsets.all(VelvetSpacing.md),
                  child: Text(
                    'Послуги з\'являться в Phase 5',
                    style: VelvetText.feedback(BrandColors.muted),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Maps [MasterType] to a localized role label string.
  String _roleLabel(MasterType type, AppLocalizations l10n) {
    switch (type) {
      case MasterType.independentMaster:
        return l10n.masterRoleIndependent;
      case MasterType.salonMaster:
        return l10n.masterRoleSalonMaster;
      case MasterType.salonOwner:
        return l10n.masterRoleSalonOwner;
    }
  }
}

// ---------------------------------------------------------------------------
// _PortfolioPlaceholderTile
// ---------------------------------------------------------------------------

/// Raised 72×72 tile with a camel-mocha gradient fill — simulates a photo.
/// Replaced by real [Image.network] tiles in Phase 4.4.
class _PortfolioPlaceholderTile extends StatefulWidget {
  const _PortfolioPlaceholderTile({required this.index});

  final int index;

  @override
  State<_PortfolioPlaceholderTile> createState() =>
      _PortfolioPlaceholderTileState();
}

class _PortfolioPlaceholderTileState extends State<_PortfolioPlaceholderTile> {
  bool _pressed = false;

  static const List<List<Color>> _fills = <List<Color>>[
    <Color>[Color(0xFFD4B896), Color(0xFF8A6840)],
    <Color>[Color(0xFFB89A7A), Color(0xFF6A4A28)],
    <Color>[Color(0xFFDFC6A8), Color(0xFFB89A7A)],
  ];

  @override
  Widget build(BuildContext context) {
    final List<Color> fill = _fills[widget.index % _fills.length];
    return Semantics(
      label: 'Фото портфоліо ${widget.index + 1}',
      button: true,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          height: 72,
          width: 72,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(VelvetRadii.field),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: fill,
            ),
            boxShadow: _pressed
                ? null
                : const <BoxShadow>[
                    BoxShadow(
                      color: BrandColors.shadowDarkButton,
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
          child: Center(
            child: Icon(
              Icons.photo_outlined,
              color: BrandColors.white.withValues(alpha: 0.65),
              size: 22,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _ProfileSkeleton — loading state
// ---------------------------------------------------------------------------

/// Neumorphic shimmer skeleton matching the layout of [_ProfileBody].
///
/// Ported verbatim from
/// `docs/signup-designs/MasterProfileScreen/lib/screens/master_profile_loading_screen.dart`.
class _ProfileSkeleton extends StatelessWidget {
  const _ProfileSkeleton();

  @override
  Widget build(BuildContext context) {
    return const SkeletonShimmerScope(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // 1 — Identity card skeleton.
          NeumorphicCard(
            color: Color(0xFFEDE4D5),
            padding: EdgeInsets.all(VelvetSpacing.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                SkeletonBlock(width: 80, height: 80, circle: true),
                SizedBox(width: VelvetSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      SkeletonBlock(width: 140, height: 16),
                      SizedBox(height: VelvetSpacing.xs + 2),
                      SkeletonBlock(width: 100, height: 24, radius: 999),
                      SizedBox(height: VelvetSpacing.xs),
                      SkeletonBlock(width: 160, height: 10),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: VelvetSpacing.xl),

          // 2 — Stats row — 4 equal skeleton tiles.
          Row(
            children: <Widget>[
              Expanded(
                child: SkeletonBlock(
                  width: double.infinity,
                  height: 96,
                  radius: VelvetRadii.field + 2,
                ),
              ),
              SizedBox(width: VelvetSpacing.xs),
              Expanded(
                child: SkeletonBlock(
                  width: double.infinity,
                  height: 96,
                  radius: VelvetRadii.field + 2,
                ),
              ),
              SizedBox(width: VelvetSpacing.xs),
              Expanded(
                child: SkeletonBlock(
                  width: double.infinity,
                  height: 96,
                  radius: VelvetRadii.field + 2,
                ),
              ),
              SizedBox(width: VelvetSpacing.xs),
              Expanded(
                child: SkeletonBlock(
                  width: double.infinity,
                  height: 96,
                  radius: VelvetRadii.field + 2,
                ),
              ),
            ],
          ),
          SizedBox(height: VelvetSpacing.xl),

          // 3 — Bio section label + block.
          Padding(
            padding: EdgeInsets.only(left: 4, bottom: VelvetSpacing.xs),
            child: SkeletonBlock(width: 90, height: 13),
          ),
          SkeletonBlock(
            width: double.infinity,
            height: 92,
            radius: VelvetRadii.card,
          ),
          SizedBox(height: VelvetSpacing.xl),

          // 4 — Portfolio section label + 3 thumbnail blocks.
          Padding(
            padding: EdgeInsets.only(left: 4, bottom: VelvetSpacing.xs),
            child: SkeletonBlock(width: 90, height: 13),
          ),
          Row(
            children: <Widget>[
              SkeletonBlock(width: 72, height: 72, radius: VelvetRadii.field),
              SizedBox(width: VelvetSpacing.md),
              SkeletonBlock(width: 72, height: 72, radius: VelvetRadii.field),
              SizedBox(width: VelvetSpacing.md),
              SkeletonBlock(width: 72, height: 72, radius: VelvetRadii.field),
            ],
          ),
          SizedBox(height: VelvetSpacing.xl),

          // 5 — Services section label + 2 row blocks.
          Padding(
            padding: EdgeInsets.only(left: 4, bottom: VelvetSpacing.xs),
            child: SkeletonBlock(width: 110, height: 13),
          ),
          SkeletonBlock(
            width: double.infinity,
            height: 60,
            radius: VelvetRadii.field,
          ),
          SizedBox(height: VelvetSpacing.xs + 4),
          SkeletonBlock(
            width: double.infinity,
            height: 60,
            radius: VelvetRadii.field,
          ),
        ],
      ),
    );
  }
}
