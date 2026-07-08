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
//   • bookingsThisMonth   → shows '—' in the Bookings stat tile
//   • contactPhone        → populated from [Master.phoneNumber]
//   • instagram           → populated from [Master.instagram]; shows '—' when null
//
// Services section and stat tile use live [servicesListProvider] data (Phase 5).
//
// Navigation: this is the INDEPENDENT_MASTER's tab-root/home screen, reached
// only via `context.go(...)` (redirect landing target + all 6 nav call sites)
// — it is always first in its stack, so it renders no back affordance
// (`showBack: false` below). The top-right menu button
// (Key('btn-menu-master')) pushes RouteNames.masterMenu — the settings hub that
// lists the per-section edit pages (personal / contacts / location / account).

import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/core/icons/app_icon.dart';
import 'package:beautica_mobile/core/icons/beautica_asset_icons.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/category_slug.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/features/services/presentation/services_list_notifier.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/utils/instagram_url.dart';
import 'package:beautica_mobile/shared/utils/phone_uri.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:beautica_mobile/shared/widgets/rating_star.dart';
import 'package:beautica_mobile/shared/widgets/skeleton_shimmer.dart';

import 'package:beautica_mobile/core/theme/beautica_icons.dart';
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

  // Captured in initState so dispose() never touches `ref` — under Riverpod 3.x
  // using `ref` in dispose() throws ("widget is about to or has been
  // unmounted"). Hold the keepAlive manager reference instead.
  late final ScreenProtectionManager _screenProtection;

  @override
  void initState() {
    super.initState();
    // SEC MEDIUM-1/-2/-3: ref-counted screenshot guard + iOS app-switcher-
    // snapshot blur for this PII-bearing screen. The manager is idempotent and
    // `!kDebugMode`-guarded internally, and keeps protection alive while any
    // PII route is mounted.
    _screenProtection = ref.read(screenProtectionProvider)..acquire();
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
    // SEC MEDIUM-1: release the ref-counted guard; protection only lifts once
    // the last PII route unmounts.
    _screenProtection.release();
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
      // Tab-root screen — always first in its Navigator stack (see the
      // header comment above), so there is no route to pop back to. Without
      // this, ProfileScaffold's `showBack` default of `true` would render a
      // back chevron whose `onBack` calls `context.pop()` and throws
      // `GoError('There is nothing to pop')`.
      showBack: false,
      trailing: NeumorphicIconButton(
        key: const Key('btn-menu-master'),
        icon: BeauticaIcons.menuBurger,
        semanticLabel: l10n.settingsHubMenuButton,
        onTap: () => context.push(RouteNames.masterMenu),
      ),
      bottomNavBar: const VelvetBottomNavBar(activeIndex: 3),
      // Pull-to-refresh: invalidate the master profile and the services list
      // (the profile screen displays live service counts and category cards).
      // Riverpod 3.x note: invalidate + await .future — never gate on value==null.
      onRefresh: () async {
        ref.invalidate(masterProfileProvider);
        ref.invalidate(servicesListProvider);
        await Future.wait([
          ref.read(masterProfileProvider.future),
          ref.read(servicesListProvider.future),
        ]);
      },
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

  // Hoisted to avoid per-frame TextStyle allocation during the 1100ms entrance
  // animation (~66 builds). Same pattern as _cardStyle / _ratingInlineStyle.
  static final TextStyle _professionalTitleStyle = VelvetText.feedbackMutedSm
      .copyWith(color: BrandColors.accent, fontStyle: FontStyle.italic);

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
    // PERF: RepaintBoundary isolates each reveal section's per-frame fade/slide
    // repaint so the entrance animation does not invalidate sibling sections.
    return RepaintBoundary(
      child: FadeTransition(
        opacity: fadeAnim,
        child: SlideTransition(position: slideAnim, child: child),
      ),
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
                        maxLines: 2,
                        softWrap: true,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (master.professionalTitle != null &&
                          master.professionalTitle!.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 2),
                        Text(
                          master.professionalTitle!,
                          key: const Key('master-profile-professional-title'),
                          style: _professionalTitleStyle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (master.professionalTitle == null ||
                          master.professionalTitle!.isEmpty) ...<Widget>[
                        const SizedBox(height: VelvetSpacing.xs + 2),
                        RoleChip(
                          label: roleLabel,
                          icon: Icons.auto_awesome_rounded,
                        ),
                      ],
                      if (locationLine != null) ...[
                        const SizedBox(height: VelvetSpacing.xs),
                        // Location row: icon + combined address string.
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            const AppIcon(
                              BeauticaAssetIcons.locationMarker,
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
                    iconWidget: RatingStar(
                      rating: master.reviewCount == 0 ? null : master.avgRating,
                      size: 18,
                      showLabel: false,
                    ),
                    value: master.reviewCount == 0
                        ? '—'
                        : master.avgRating.toStringAsFixed(1),
                    caption: l10n.masterRatingLabel,
                    valueKey: const Key('master-profile-rating-value'),
                  ),
                ),
                const SizedBox(width: VelvetSpacing.sm),
                Expanded(
                  child: Consumer(
                    builder: (context, ref, _) {
                      final servicesAsync = ref.watch(servicesListProvider);
                      final String countValue = servicesAsync.when(
                        data: (list) => list.length.toString(),
                        loading: () => '—',
                        error: (_, _) => '—',
                      );
                      return StatTile(
                        icon: Icons.design_services_outlined,
                        value: countValue,
                        caption: l10n.masterServicesLabel,
                        valueKey: const Key('master-profile-services-value'),
                      );
                    },
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
                          Text(l10n.masterAllPhotos, style: VelvetText.link()),
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

        // 5 — Service categories section: live category cards built from the
        // master's real services grouped by category. Non-empty categories only.
        // Tapping a card pushes /services?expandCategory=<slug> so the services
        // list opens with that category pre-expanded and all others collapsed.
        //
        // P-H2 fix: extracted into [_ProfileCategoriesSection] which memoizes
        // the grouping + card list with identity-equality cache fields so the
        // heavy computation is skipped on every provider tick that does not
        // actually change the data.
        _revealWith(anim4, slide4, const _ProfileCategoriesSection()),
        const SizedBox(height: VelvetSpacing.xl),

        // 6 — Contacts section: phone and Instagram from domain model;
        // both fall back to '—' when the field is not set by the master.
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
                semanticLabel: l10n.masterPhoneSemantics,
                onTap: () {
                  // Sanitize verbatim stored input through canonicalTelUri
                  // (STRICT tel: allow-list — rejects empty / '—' / non-
                  // dialable). An unvalidated string is never handed to
                  // launchUrl; no-op on null. Validation is wired in front of
                  // the deferred launch so the contract is correct when it
                  // lands.
                  final Uri? telUri = canonicalTelUri(master.phoneNumber);
                  if (telUri == null) return;
                  // TODO(Phase-4.x): launchUrl(telUri);
                },
              ),
              const SizedBox(height: VelvetSpacing.sm),
              ContactTile(
                key: const Key('master-contact-instagram'),
                icon: Icons.alternate_email,
                label: l10n.masterInstagramLabel,
                // Value is stored verbatim from user input — may be a bare
                // handle, "@"-prefixed, or a full https://instagram.com/...
                // URL depending on what the user entered.
                value: master.instagram ?? '—',
                semanticLabel: l10n.masterInstagramLabel,
                onTap: () => _openInstagram(context, master.instagram),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Opens the master's Instagram profile in the Instagram app or a browser.
  ///
  /// [rawValue] is the verbatim stored contact string (bare handle,
  /// "@"-prefixed, or full URL). It is sanitized through
  /// [canonicalInstagramUri] (STRICT https + host/charset allow-list) before
  /// launch — an unvalidated string is never handed to [launchUrl]. On a null
  /// result (no safe URL) or a launch failure, a localized SnackBar is shown.
  ///
  /// Invoked fire-and-forget from the tile's synchronous [ContactTile.onTap];
  /// [context.mounted] is re-checked after the await before touching the tree.
  /// No PII (handle/URL) is logged.
  static Future<void> _openInstagram(
    BuildContext context,
    String? rawValue,
  ) async {
    final Uri? uri = canonicalInstagramUri(rawValue);
    if (uri == null) {
      _showInstagramError(context);
      return;
    }

    bool launched = false;
    try {
      launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on Object catch (error) {
      if (kDebugMode) {
        log(
          'Instagram launch threw',
          name: 'feature.master',
          level: 900,
          error: error,
        );
      }
    }

    if (!context.mounted) return;
    if (!launched) _showInstagramError(context);
  }

  /// Shows the localized "couldn't open Instagram" SnackBar.
  static void _showInstagramError(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context).masterInstagramOpenError),
      ),
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
// _ProfileCategoriesSection — P-H2 memoized category grouping
// ---------------------------------------------------------------------------

/// Watches [servicesListProvider] and [approvedCategoriesProvider] and renders
/// the section header + one [_ProfileCategoryCard] per non-empty category
/// bucket.
///
/// Memoizes the bucket grouping and card list with identity-equality cache
/// fields ([_cachedServices], [_cachedCategories], [_cachedGroups],
/// [_cachedCards]). The heavy computation inside [_rebuild] is only triggered
/// when at least one of the two watched lists changes by identity — matching
/// the pattern used by [_LoadedBodyState._resolveGroups] in
/// [services_list_screen.dart].
class _ProfileCategoriesSection extends ConsumerStatefulWidget {
  const _ProfileCategoriesSection();

  @override
  ConsumerState<_ProfileCategoriesSection> createState() =>
      _ProfileCategoriesSectionState();
}

class _ProfileCategoriesSectionState
    extends ConsumerState<_ProfileCategoriesSection> {
  // Identity-equality cache fields — recompute only when references change.
  List<MasterService>? _cachedServices;
  List<ServiceCategoryOption>? _cachedCategories;

  // Derived outputs — rebuilt only on cache miss.
  Map<String, List<MasterService>>? _cachedGroups;
  List<Widget>? _cachedCards;

  void _rebuild(
    List<MasterService> services,
    List<ServiceCategoryOption>? categories,
    AppLocalizations l10n,
  ) {
    if (_cachedGroups != null &&
        identical(_cachedServices, services) &&
        identical(_cachedCategories, categories)) {
      // Cache hit — no recompute needed.
      return;
    }

    // --- bucket grouping ---
    final Map<String, List<MasterService>> buckets =
        <String, List<MasterService>>{};
    for (final MasterService s in services) {
      final String key = (s.category ?? '').trim().toUpperCase();
      (buckets[key] ??= <MasterService>[]).add(s);
    }

    // --- label resolver ---
    String resolveLabel(String slug) {
      if (slug.isEmpty) return l10n.serviceCategoryUncategorized;
      if (categories != null) {
        for (final ServiceCategoryOption opt in categories) {
          if (categorySlugMatches(slug, opt.name)) return opt.displayName;
        }
      }
      return humanizeCategorySlug(slug);
    }

    // --- card list ---
    final List<Widget> cards = <Widget>[];
    var first = true;
    for (final MapEntry<String, List<MasterService>> entry in buckets.entries) {
      if (!first) cards.add(const SizedBox(height: VelvetSpacing.sm));
      first = false;
      final String resolvedLabel = resolveLabel(entry.key);
      cards.add(
        _ProfileCategoryCard(
          key: Key(
            'profile-category-${entry.key.isEmpty ? '_none' : entry.key}',
          ),
          label: resolvedLabel,
          count: entry.value.length,
          // Pass the raw slug so the card's own live BuildContext drives
          // navigation — never bake a BuildContext into a cached closure.
          slug: entry.key.isEmpty ? null : entry.key,
          semanticLabel: l10n.masterProfileCategorySemantics(
            resolvedLabel,
            entry.value.length,
          ),
        ),
      );
    }

    // --- store results ---
    _cachedServices = services;
    _cachedCategories = categories;
    _cachedGroups = buckets;
    _cachedCards = cards;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final servicesAsync = ref.watch(servicesListProvider);
    final categoriesAsync = ref.watch(approvedCategoriesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: VelvetSpacing.xs),
          child: Row(
            children: <Widget>[
              // Flexible so the section label ellipsizes instead of overflowing
              // the header Row at 320 dp / textScale 1.3 (was a 12 px right
              // overflow when both labels rendered at their natural width).
              Flexible(
                child: Text(
                  l10n.masterProfileCategoriesLabel,
                  style: VelvetText.sectionLabel(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => context.push(RouteNames.services),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(l10n.masterAllServices, style: VelvetText.link()),
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
        servicesAsync.when(
          loading: () => const SkeletonShimmerScope(
            child: Column(
              children: <Widget>[
                SkeletonBlock(
                  width: double.infinity,
                  height: 56,
                  radius: VelvetRadii.card,
                ),
                SizedBox(height: VelvetSpacing.sm),
                SkeletonBlock(
                  width: double.infinity,
                  height: 56,
                  radius: VelvetRadii.card,
                ),
              ],
            ),
          ),
          error: (_, _) => Padding(
            padding: const EdgeInsets.only(top: VelvetSpacing.xs),
            child: Text(l10n.errUnknown, style: VelvetText.feedbackMutedXs),
          ),
          data: (List<MasterService> services) {
            if (services.isEmpty) {
              return Padding(
                padding: const EdgeInsets.only(top: VelvetSpacing.xs),
                child: Text(
                  l10n.servicesEmpty,
                  style: VelvetText.feedbackMutedXs,
                ),
              );
            }
            _rebuild(services, categoriesAsync.value, l10n);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _cachedCards!,
            );
          },
        ),
      ],
    );
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
    <Color>[Color(0xFFC8A878), Color(0xFF6A4A28)],
    <Color>[Color(0xFFCFB090), Color(0xFF8A6840)],
    <Color>[Color(0xFFE0CAAC), Color(0xFFB89A7A)],
  ];

  static final Color _glyphColor = BrandColors.white.withValues(alpha: 0.65);

  @override
  Widget build(BuildContext context) {
    final List<Color> fill = _fills[widget.index % _fills.length];
    return Semantics(
      label: AppLocalizations.of(
        context,
      ).masterPortfolioTileSemantics(widget.index + 1),
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
            child: Icon(Icons.photo_outlined, color: _glyphColor, size: 22),
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

// ---------------------------------------------------------------------------
// Profile category cards
// ---------------------------------------------------------------------------

/// A non-expandable raised neumorphic card representing a category under which
/// the master has created services. Visually identical to [_CategorySection]'s
/// header pillow on the services list screen: same tokens, same typography,
/// same count badge — but without a disclosure chevron or collapsible body.
///
/// Tapping navigates to the services list with the matching category
/// pre-expanded (`expandCategory` query parameter).
class _ProfileCategoryCard extends StatefulWidget {
  const _ProfileCategoryCard({
    super.key,
    required this.label,
    required this.count,
    required this.semanticLabel,
    // Null means "uncategorized" — navigates to /services with no query param.
    this.slug,
  });

  final String label;
  final int count;
  final String semanticLabel;

  /// The raw category slug (upper-cased, e.g. `"MANICURE"`), or `null` for the
  /// uncategorized bucket. Navigation is performed inside [_ProfileCategoryCardState]
  /// using the card's own live [BuildContext] so cached widget instances never
  /// hold a stale context closure from an earlier frame.
  final String? slug;

  @override
  State<_ProfileCategoryCard> createState() => _ProfileCategoryCardState();
}

class _ProfileCategoryCardState extends State<_ProfileCategoryCard> {
  bool _pressed = false;

  // P-M4 fix: hoisted to avoid per-build TextStyle allocation.
  static final TextStyle _cardStyle = VelvetText.subheading().copyWith(
    fontSize: 16,
  );

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) {
          setState(() => _pressed = false);
          // Navigation is built here — inside the card's own live BuildContext —
          // so that cached widget instances never call context.push on a stale
          // context from the frame _rebuild() last executed.
          final String? slug = widget.slug;
          context.push(
            Uri(
              path: RouteNames.services,
              queryParameters: slug == null
                  ? null
                  : <String, String>{'expandCategory': slug},
            ).toString(),
          );
        },
        child: AnimatedScale(
          scale: _pressed ? 0.99 : 1.0,
          duration: const Duration(milliseconds: 110),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(
              horizontal: VelvetSpacing.md,
              vertical: VelvetSpacing.sm + 2,
            ),
            decoration: BoxDecoration(
              color: BrandColors.base,
              borderRadius: BorderRadius.circular(VelvetRadii.card),
              boxShadow: _pressed ? null : VelvetShadows.extrudedCard,
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    widget.label,
                    style: _cardStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: VelvetSpacing.sm),
                _ProfileCategoryCountBadge(count: widget.count),
                const SizedBox(width: VelvetSpacing.sm),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: BrandColors.accent,
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A small recessed count badge — local copy of [_CategoryCountBadge] from
/// the services list screen, using identical tokens so both surfaces are
/// pixel-identical without a cross-feature import.
class _ProfileCategoryCountBadge extends StatelessWidget {
  const _ProfileCategoryCountBadge({required this.count});

  final int count;

  // Hoisted to avoid per-build allocation — identical style to the services
  // list screen's _CategoryCountBadge.
  static final TextStyle _style = VelvetText.pill().copyWith(fontSize: 12.5);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: VelvetSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: BrandColors.base,
        borderRadius: BorderRadius.circular(VelvetRadii.pill),
        boxShadow: VelvetShadows.extrudedSmall,
      ),
      child: Text('$count', style: _style),
    );
  }
}
