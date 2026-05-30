// Phase 4.2 — Master Profile Screen (read-only).
//
// Layout: ProfileScaffold chrome (fixed top bar + scrollable body + bottom nav).
//
// Four [AsyncValue] states are handled explicitly:
//   • loading  → [_ProfileSkeleton] (neumorphic shimmer blocks via
//                 SkeletonShimmerScope / SkeletonBlock)
//   • data     → [_ProfileBody] (staggered fade-up reveal via
//                 AnimationController 1100 ms, 6 sections)
//   • error    → [ErrorState] with retry [ref.invalidate]
//
// Design source: `docs/signup-designs/MasterProfileScreen/` — transcribed 1:1.
//
// Domain-model gaps (fields absent from [Master]):
//   • serviceCount        → shows '—' in the Services stat tile and header
//   • bookingsThisMonth   → shows '—' in the Bookings stat tile
//   • contactPhone /
//     instagram           → Contacts section shows '—' placeholder rows
//                           (Phase 13 populates real data)
//
// Navigation: back uses `context.pop()`; edit button (Key('btn-edit-master'))
// navigates to RouteNames.masterEdit (Phase 4.3).

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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

import 'package:beautica_mobile/routing/route_names.dart';

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
  // (not Animation<double>) so dispose() is accessible. Six instances match
  // the six _revealWith() call sites in _ProfileBody.
  late final CurvedAnimation _anim0;
  late final CurvedAnimation _anim1;
  late final CurvedAnimation _anim2;
  late final CurvedAnimation _anim3;
  late final CurvedAnimation _anim4;
  late final CurvedAnimation _anim5;

  // Fix 2 (PERF MEDIUM): Pre-built Tween<Offset>.animate() instances so
  // _revealWith() never allocates a new Tween+_AnimatedEvaluation on each
  // build frame. Animation<Offset> instances derived from a CurvedAnimation
  // do not own resources and do not need to be disposed.
  late final Animation<Offset> _slide0;
  late final Animation<Offset> _slide1;
  late final Animation<Offset> _slide2;
  late final Animation<Offset> _slide3;
  late final Animation<Offset> _slide4;
  late final Animation<Offset> _slide5;

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
    // Contacts section — last reveal, matching the design's 0.55–1.0 stagger.
    _anim5 = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.55, 1.0, curve: Curves.easeOutCubic),
    );
    // Fix 2: derive the six slide animations once from their parent
    // CurvedAnimation. The same begin/end Offset is shared across all six —
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
    _slide5 = Tween<Offset>(
      begin: slideBegin,
      end: Offset.zero,
    ).animate(_anim5);
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
    _anim5.dispose();
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
        onTap: () => context.go(RouteNames.masterEdit),
      ),
      bottomNavBar: const VelvetBottomNavBar(activeIndex: 3),
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
            anim5: _anim5,
            slide0: _slide0,
            slide1: _slide1,
            slide2: _slide2,
            slide3: _slide3,
            slide4: _slide4,
            slide5: _slide5,
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
    required this.anim5,
    required this.slide0,
    required this.slide1,
    required this.slide2,
    required this.slide3,
    required this.slide4,
    required this.slide5,
  });

  final Master master;

  // Fix 1 (PERF HIGH-1): pre-built CurvedAnimation instances passed from the
  // owning StatefulWidget. Using FadeTransition + SlideTransition avoids a
  // separate GPU raster layer per section (vs. Opacity + Transform.translate).
  // Six instances match the six reveal sections.
  final Animation<double> anim0;
  final Animation<double> anim1;
  final Animation<double> anim2;
  final Animation<double> anim3;
  final Animation<double> anim4;
  final Animation<double> anim5;

  // Fix 2 (PERF MEDIUM): pre-built Animation<Offset> instances passed from the
  // owning StatefulWidget. Eliminates Tween+_AnimatedEvaluation allocations on
  // every _revealWith() call during the 1100 ms entrance animation.
  final Animation<Offset> slide0;
  final Animation<Offset> slide1;
  final Animation<Offset> slide2;
  final Animation<Offset> slide3;
  final Animation<Offset> slide4;
  final Animation<Offset> slide5;

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

    // Pre-compute the combined address string once per build so the identity
    // card Row's child Text widget never contains inline ternary chains.
    // Compose: street + buildingNo (if present) + city (if present).
    final String? locationLine = _buildLocationLine(master);
    final String? noteText = (master.locationNote?.isNotEmpty ?? false)
        ? master.locationNote
        : null;

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
            // P1-1 + P1-2 fix: RoleChip uses NeumorphicInset which wraps a
            // RepaintBoundary that can paint near the card's rounded corners.
            // clipContent: true opts this card into ClipRRect; all other
            // NeumorphicCard usages on this screen keep the default (false).
            clipContent: true,
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
                      if (locationLine != null) ...[
                        const SizedBox(height: VelvetSpacing.xs),
                        // Location row: icon + combined address string.
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
                                locationLine,
                                key: const Key('master-profile-address-text'),
                                // 11 sp variant allows wrapping so longer
                                // address strings are never clipped.
                                style: VelvetText.feedbackMutedXs,
                              ),
                            ),
                          ],
                        ),
                        // Note row: shown only when locationNote is set.
                        if (noteText != null) ...[
                          const SizedBox(height: 2),
                          Padding(
                            padding: const EdgeInsets.only(left: 16),
                            child: Text(
                              noteText,
                              // Pre-cached static (11 sp variant) avoids
                              // per-frame copyWith call.
                              style: VelvetText.feedbackMutedNote,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
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
                const SizedBox(width: VelvetSpacing.sm),
                Expanded(
                  child: StatTile(
                    icon: Icons.star_rounded,
                    value: master.reviewCount == 0
                        ? '—'
                        : master.avgRating.toStringAsFixed(1),
                    caption: l10n.masterRatingLabel,
                    valueKey: const Key('master-profile-rating-value'),
                  ),
                ),
                const SizedBox(width: VelvetSpacing.sm),
                Expanded(
                  child: StatTile(
                    icon: Icons.design_services_outlined,
                    // serviceCount absent from domain model — show dash.
                    value: '—',
                    caption: l10n.masterServicesLabel,
                  ),
                ),
                const SizedBox(width: VelvetSpacing.sm),
                Expanded(
                  child: StatTile(
                    icon: Icons.reviews_outlined,
                    value: master.reviewCount == 0
                        ? '—'
                        : master.reviewCount.toString(),
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
              // Placeholder tiles — horizontal scroll of 6 tiles matching
              // the design's portfolio row. Replaced by real Image.network
              // tiles in Phase 4.4.
              SizedBox(
                height: 72,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  // M-3 fix: match the BouncingScrollPhysics convention used
                  // by the outer vertical scroll in profile_scaffold.dart.
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.zero,
                  child: Row(
                    children: <Widget>[
                      for (int i = 0; i < 6; i++) ...<Widget>[
                        _PortfolioPlaceholderTile(index: i),
                        if (i < 5) const SizedBox(width: VelvetSpacing.md),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: VelvetSpacing.xl),

        // 5 — Services section: label (with '—' count) + placeholder ServiceTile
        // rows. Real tiles arrive in Phase 5; the placeholders match the approved
        // design's visual structure so the screen looks complete now.
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
                    // '—' count shows unknown total; real count arrives in Phase 5.
                    Text(
                      '${l10n.masterServicesLabel} · —',
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
              // Static placeholder rows — replaced by live data in Phase 5.
              for (
                int i = 0;
                i < _ProfileBody._kServicePlaceholders.length;
                i++
              ) ...<Widget>[
                ServiceTile(
                  name: _ProfileBody._kServicePlaceholders[i].name,
                  duration: _ProfileBody._kServicePlaceholders[i].duration,
                  price: _ProfileBody._kServicePlaceholders[i].price,
                  photoGradient: _ProfileBody._kServicePlaceholders[i].gradient,
                ),
                if (i < _ProfileBody._kServicePlaceholders.length - 1)
                  const SizedBox(height: VelvetSpacing.md - 4),
              ],
            ],
          ),
        ),
        const SizedBox(height: VelvetSpacing.xl),

        // 6 — Contacts section: phone from domain model; Instagram placeholder
        // until that field is wired (future phase).
        _revealWith(
          anim5,
          slide5,
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(
                  left: 4,
                  bottom: VelvetSpacing.xs,
                ),
                child: Text(
                  l10n.masterContactsLabel,
                  style: VelvetText.sectionLabel(),
                ),
              ),
              ContactTile(
                key: const Key('master-contact-phone'),
                icon: Icons.phone_outlined,
                value: master.phoneNumber ?? '—',
                semanticLabel: 'Телефон',
                // When wiring tel: URL launching, validate phoneNumber against
                // RegExp(r'^[+\d\s\-()]*$') before constructing the URI to
                // prevent USSD injection (e.g. *21*+...# codes on Android tel: intent).
                onTap: () {},
              ),
              const SizedBox(height: VelvetSpacing.sm),
              ContactTile(
                key: const Key('master-contact-instagram'),
                icon: Icons.alternate_email,
                label: 'Instagram',
                value: '—',
                semanticLabel: 'Instagram',
                onTap: () {},
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Static service placeholder entries — displayed until Phase 5 wires the
  /// real service list from the server.
  static const List<_ServicePlaceholder> _kServicePlaceholders =
      <_ServicePlaceholder>[
        _ServicePlaceholder(
          name: 'Манікюр',
          duration: '60 хв',
          price: '500 грн',
          gradient: <Color>[Color(0xFFD4B896), Color(0xFF8A6840)],
        ),
        _ServicePlaceholder(
          name: 'Педикюр',
          duration: '90 хв',
          price: '700 грн',
          gradient: <Color>[Color(0xFFB89A7A), Color(0xFF6A4A28)],
        ),
      ];

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

  /// Builds the combined address line for the identity card location row.
  ///
  /// Composition rules (matching the approved design mockup):
  /// - street + buildingNo + city  → "вул. Хрещатик, 22, Київ"
  /// - street only + city          → "вул. Хрещатик, Київ"
  /// - city only                   → "Київ"
  /// - nothing available           → `null` (caller must hide the row)
  ///
  /// Called once per build from [build()] and stored in a local `final` to
  /// avoid repeated computation during the frame.
  static String? _buildLocationLine(Master master) {
    final String? street = (master.street?.isNotEmpty ?? false)
        ? master.street
        : null;
    final String? building = (master.buildingNo?.isNotEmpty ?? false)
        ? master.buildingNo
        : null;
    final String? city = (master.city?.isNotEmpty ?? false)
        ? master.city
        : null;

    if (street == null && city == null) return null;

    final StringBuffer buf = StringBuffer();
    if (street != null) {
      buf.write(street);
      if (building != null) {
        buf.write(', ');
        buf.write(building);
      }
      if (city != null) {
        buf.write(', ');
        buf.write(city);
      }
    } else {
      // Only city is present.
      buf.write(city);
    }
    return buf.toString();
  }
}

// ---------------------------------------------------------------------------
// _ServicePlaceholder
// ---------------------------------------------------------------------------

/// Immutable data holder for a static service row displayed before Phase 5
/// wires the real service list from the server.
class _ServicePlaceholder {
  const _ServicePlaceholder({
    required this.name,
    required this.duration,
    required this.price,
    required this.gradient,
  });

  final String name;
  final String duration;
  final String price;
  final List<Color> gradient;
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
    <Color>[Color(0xFFC8A878), Color(0xFF6A4A28)],
    <Color>[Color(0xFFCFB090), Color(0xFF8A6840)],
    <Color>[Color(0xFFE0CAAC), Color(0xFFB89A7A)],
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
