// Phase 4.2 — Master Profile Screen (read-only).
//
// Layout: ProfileScaffold chrome (fixed top bar + scrollable body + bottom nav).
//
// Four [AsyncValue] states are handled explicitly:
//   • loading  → [_ProfileSkeleton] (neumorphic shimmer blocks via
//                 SkeletonShimmerScope / SkeletonBlock)
//   • data     → [_ProfileBody] (staggered fade-up reveal via
//                 AnimationController 1100 ms, 4 sections)
//   • error    → [ErrorState] with retry [ref.invalidate]
//
// Phase 351 (U4′/U5-U7) — restructured around the SAME card→tab mechanism as
// the public master profile and the salon master's own profile: the 4 stat
// cards (bookings / rating / services / reviews) STAY under the identity
// card, then «Про майстра» / «Послуги» / «Відгуки» tabs follow. Tapping
// «Рейтинг»/«Відгуки» switches to the «Відгуки» tab (the exact list the
// deleted standalone «Мої відгуки» screen used to show, unchanged, D11);
// tapping «Послуги» switches to the «Послуги» tab (D16) — a
// category tap INSIDE that tab still pushes `/services?expandCategory=`, the
// full editor. The bookings card stays non-interactive (no tab of its own).
// Uses the shared `ProfileTabSelection` mixin (D15) — no
// `IndexedStack`/`TabController`, no hand-rolled second `int _tab` field.
//
// Design source: `docs/signup-designs/MasterProfileScreen/` — transcribed 1:1.
//
// Domain-model gaps (fields absent from [Master]):
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
import 'package:beautica_mobile/features/location/presentation/saved_settlement_label.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/presentation/services_list_notifier.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/formatters/address_lines.dart';
import 'package:beautica_mobile/shared/utils/instagram_url.dart';
import 'package:beautica_mobile/shared/utils/phone_uri.dart';
import 'package:beautica_mobile/shared/feedback/show_velvet_snack.dart';
import 'package:beautica_mobile/shared/widgets/add_link.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:beautica_mobile/shared/widgets/expandable_note.dart';
import 'package:beautica_mobile/shared/widgets/notification_bell_button.dart';
import 'package:beautica_mobile/shared/widgets/portfolio_rail.dart';
import 'package:beautica_mobile/shared/widgets/profile_tab_bar.dart';
import 'package:beautica_mobile/shared/widgets/profile_tab_selection.dart';
import 'package:beautica_mobile/shared/widgets/rating_star.dart';
import 'package:beautica_mobile/shared/widgets/skeleton_shimmer.dart';

import 'package:beautica_mobile/core/theme/beautica_icons.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/features/services/presentation/service_catalogue_invalidation.dart';

import 'master_profile_notifier.dart';
import 'widgets/master_address_block.dart';
import 'widgets/master_profile_tabs.dart';
import 'widgets/master_reviews_body.dart';
import 'widgets/profile_avatar.dart';
import 'widgets/profile_scaffold.dart';
import 'widgets/service_category_cards.dart';
import 'widgets/services_stat_tile.dart';

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
    with
        SingleTickerProviderStateMixin,
        ProfileTabSelection<MasterProfileScreen> {
  late final AnimationController _controller;

  // Fix 1 (PERF HIGH-1): Pre-built CurvedAnimation instances so build() never
  // allocates a new CurvedAnimation on each frame. Typed as CurvedAnimation
  // (not Animation<double>) so dispose() is accessible. Phase 351 (D14) —
  // FOUR sections now (identity card / stat-card row / tab bar / tab body),
  // down from six (the old stats/bio/portfolio/categories/contacts stack).
  late final CurvedAnimation _anim0;
  late final CurvedAnimation _anim1;
  late final CurvedAnimation _anim2;
  late final CurvedAnimation _anim3;

  // Fix 2 (PERF MEDIUM): Pre-built Tween<Offset>.animate() instances so
  // _revealWith() never allocates a new Tween+_AnimatedEvaluation on each
  // build frame. Animation<Offset> instances derived from a CurvedAnimation
  // do not own resources and do not need to be disposed.
  late final Animation<Offset> _slide0;
  late final Animation<Offset> _slide1;
  late final Animation<Offset> _slide2;
  late final Animation<Offset> _slide3;

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
    // Fix 1: initialise the four CurvedAnimation instances once here rather
    // than recreating them on every build() frame. Same intervals as the
    // public master profile's identical 4-section reveal, for consistency.
    _anim0 = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.00, 0.55, curve: Curves.easeOutCubic),
    );
    _anim1 = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.15, 0.65, curve: Curves.easeOutCubic),
    );
    _anim2 = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.30, 0.80, curve: Curves.easeOutCubic),
    );
    _anim3 = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.45, 1.00, curve: Curves.easeOutCubic),
    );
    // Fix 2: derive the four slide animations once from their parent
    // CurvedAnimation. The same begin/end Offset is shared across all four —
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
  }

  @override
  void dispose() {
    // SEC MEDIUM-1: release the ref-counted guard; protection only lifts once
    // the last PII route unmounts.
    _screenProtection.release();
    disposeProfileTabSelection();
    // Fix 1: dispose each CurvedAnimation before the controller.
    _anim0.dispose();
    _anim1.dispose();
    _anim2.dispose();
    _anim3.dispose();
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
      // Phase 363 — the global notification bell sits LEFT of the burger, the
      // same `bell · burger` order and gap as the client top bar. «Мій профіль»
      // is this role's landing tab, so it is the one header that carries it.
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const ConnectedNotificationBell(
            buttonKey: Key('master_profile_bell_button'),
          ),
          const SizedBox(width: VelvetSpacing.sm + 4),
          NeumorphicIconButton(
            key: const Key('btn-menu-master'),
            icon: BeauticaIcons.menuBurger,
            semanticLabel: l10n.settingsHubMenuButton,
            onTap: () => context.push(RouteNames.masterMenu),
          ),
        ],
      ),
      bottomNavBar: const VelvetBottomNavBar(activeIndex: 3),
      // Pull-to-refresh: invalidate the master profile and the services list
      // (the profile screen displays live service counts and category cards).
      // Riverpod 3.x note: invalidate + await .future — never gate on value==null.
      onRefresh: () async {
        ref.invalidate(masterProfileProvider);
        invalidateMasterServiceCatalogues(ref);
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
            tabNotifier: profileTabNotifier,
            onSelectTab: selectProfileTab,
            anim0: _anim0,
            anim1: _anim1,
            anim2: _anim2,
            anim3: _anim3,
            slide0: _slide0,
            slide1: _slide1,
            slide2: _slide2,
            slide3: _slide3,
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
    required this.tabNotifier,
    required this.onSelectTab,
    required this.anim0,
    required this.anim1,
    required this.anim2,
    required this.anim3,
    required this.slide0,
    required this.slide1,
    required this.slide2,
    required this.slide3,
  });

  final Master master;

  /// [ProfileTabSelection.profileTabNotifier] — the active tab index (0 =
  /// Про майстра, 1 = Послуги, 2 = Відгуки), as a [ValueNotifier] so only the
  /// [ProfileTabSection] below rebuilds on a tab switch (mobile-perf LOW,
  /// Phase 351 audit-fix cycle 1) — the identity card / stat-card row above
  /// it never watches it.
  final ValueNotifier<int> tabNotifier;

  /// [ProfileTabSelection.selectProfileTab] — passed to [ProfileTabBar]'s
  /// `onSelect`, the only way to switch tabs (the stat cards are
  /// display-only, user decision 2026-09-26).
  final ValueChanged<int> onSelectTab;

  // Fix 1 (PERF HIGH-1): pre-built CurvedAnimation instances passed from the
  // owning StatefulWidget. Using FadeTransition + SlideTransition avoids a
  // separate GPU raster layer per section (vs. Opacity + Transform.translate).
  // Phase 351 (D14) — FOUR instances match the four reveal sections (identity
  // card / stat-card row / tab bar / tab body).
  final Animation<double> anim0;
  final Animation<double> anim1;
  final Animation<double> anim2;
  final Animation<double> anim3;

  // Fix 2 (PERF MEDIUM): pre-built Animation<Offset> instances passed from the
  // owning StatefulWidget. Eliminates Tween+_AnimatedEvaluation allocations on
  // every _revealWith() call during the 1100 ms entrance animation.
  final Animation<Offset> slide0;
  final Animation<Offset> slide1;
  final Animation<Offset> slide2;
  final Animation<Offset> slide3;

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

    // Phase 220 (C) — pre-compute the SPLIT address lines once per build so
    // the identity card's Text widgets never contain inline ternary chains.
    // Each line gets its own independent budget instead of one combined
    // string crammed into the ~150px right-hand column.
    //
    // Phase 224 — also pre-compose the COLLAPSED one-line form. Which of the
    // two renderings actually ships is decided by `MasterAddressBlock`, which
    // measures the collapsed string against the real available width; both
    // forms are composed here so the widget stays a pure layout decision.
    // «м. Львів, Львівська обл.» — the picker's label, not the bare name;
    // the bare name when the read carries no settlement type.
    final String? settlementLabel =
        savedSettlementLabel(l10n, master.savedSettlement) ?? master.city;
    final String? localityLine = buildLocalityLine(settlementLabel);
    final String? streetLine = buildStreetLine(
      master.street,
      master.buildingNo,
    );
    final String? combinedAddressLine = buildCombinedAddressLine(
      settlementLabel,
      master.street,
      master.buildingNo,
    );
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
                      const SizedBox(height: VelvetSpacing.xs + 2),
                      RoleChip(
                        key: (master.professionalTitle?.isNotEmpty == true)
                            ? const Key('master-profile-professional-title')
                            : null,
                        label: (master.professionalTitle?.isNotEmpty == true)
                            ? master.professionalTitle!
                            : roleLabel,
                        icon: Icons.auto_awesome_rounded,
                      ),
                      // `combinedAddressLine != null` is EXACTLY equivalent to
                      // the old `localityLine != null || streetLine != null`
                      // gate — all three builders treat the same fields as
                      // blank — and it promotes the local to non-nullable for
                      // the widget below.
                      if (combinedAddressLine != null) ...[
                        const SizedBox(height: VelvetSpacing.xs),
                        // Phase 220 (C) + Phase 224 — semantic hierarchy:
                        // locality (city) first — matching the convention in
                        // `result_address_block.dart` — then street +
                        // building, then the note. `MasterAddressBlock`
                        // collapses the first two onto ONE row when the whole
                        // string fits at the real available width, and keeps
                        // the 220 split when it does not; the pin rides beside
                        // whichever line renders first either way.
                        MasterAddressBlock(
                          keyPrefix: 'master-profile',
                          icon: const AppIcon(
                            BeauticaAssetIcons.locationMarker,
                            size: MasterAddressBlock.iconSize,
                            color: BrandColors.muted,
                          ),
                          localityLine: localityLine,
                          streetLine: streetLine,
                          combinedLine: combinedAddressLine,
                        ),
                        // Note row: shown only when locationNote is set.
                        // Phase 221 (B) — tap-to-expand: clamped at
                        // maxLines: 3 (Phase 219 A) with a «більше»/
                        // «згорнути» toggle that appears only when the note
                        // actually overflows that budget.
                        if (noteText != null) ...[
                          const SizedBox(height: 2),
                          Padding(
                            padding: const EdgeInsets.only(left: 16),
                            child: ExpandableNote(
                              key: const Key('master-profile-location-note'),
                              text: noteText,
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

        // 2 — 4-up stat cards: bookings / rating / services / reviews (U5 —
        // the cards STAY). Display-only (user decision 2026-09-26) — no tap,
        // no ripple, no button semantics, on any of the four. The «Про
        // майстра» / «Послуги» / «Відгуки» tabs below are the only way to
        // switch tabs. IntrinsicHeight + CrossAxisAlignment.stretch ensures
        // equal heights even when caption text wraps (e.g. "Записів\nмісяця").
        _revealWith(
          anim1,
          slide1,
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(
                  child: StatTile(
                    key: const Key('master-profile-bookings-tile'),
                    icon: Icons.calendar_month_outlined,
                    // Qase defect #25 — this tile rendered a hardcoded '—'
                    // because the field did not exist. `GET /masters/me` now
                    // supplies it. Still '—' when NULL, which means "this
                    // endpoint did not supply it" (the public master endpoint
                    // withholds it) — never coalesce to 0, which would tell a
                    // master with a full calendar they have none. A real zero
                    // is an int and renders as "0".
                    value: master.bookingsThisMonth?.toString() ?? '—',
                    caption: l10n.masterStatsBookingsLabel,
                    iconColor: BrandColors.accentDeep,
                  ),
                ),
                const SizedBox(width: VelvetSpacing.sm),
                Expanded(
                  child: StatTile(
                    key: const Key('master-profile-rating-tile'),
                    icon: Icons.star_rounded,
                    // `displayRating` folds all three "no rating yet" shapes
                    // (null average, a stale 0.0, zero reviews) onto null, so
                    // the star and the readout cannot disagree. See its doc.
                    iconWidget: RatingStar(
                      rating: master.displayRating,
                      size: 18,
                      showLabel: false,
                    ),
                    value: master.displayRating?.toStringAsFixed(1) ?? '—',
                    caption: l10n.masterRatingLabel,
                    valueKey: const Key('master-profile-rating-value'),
                  ),
                ),
                const SizedBox(width: VelvetSpacing.sm),
                Expanded(
                  child: Consumer(
                    builder: (context, ref, _) {
                      final servicesAsync = ref.watch(servicesListProvider);
                      // null = unresolved; ServicesStatTile collapses that AND
                      // an empty catalogue onto '—', mirroring the
                      // rating/reviews tiles' zero-state on this row. A FAILED
                      // load is kept distinguishable (hasError → '?') so a
                      // suppressed /services response never reads as "this
                      // master has no services".
                      final (int? count, bool hasError) = servicesAsync.when(
                        data: (list) => (list.length, false),
                        loading: () => (null, false),
                        error: (_, _) => (null, true),
                      );
                      return ServicesStatTile(
                        key: const Key('master-profile-services-tile'),
                        count: count,
                        hasError: hasError,
                        valueKey: const Key('master-profile-services-value'),
                      );
                    },
                  ),
                ),
                const SizedBox(width: VelvetSpacing.sm),
                Expanded(
                  child: StatTile(
                    key: const Key('master-profile-reviews-tile'),
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

        // 3+4 — Tab bar + tab body, isolated behind ONE `ProfileTabSection`
        // (mobile-perf LOW, Phase 351 audit-fix cycle 1) — a tab switch now
        // only rebuilds this region, never sections 1-2 above.
        ProfileTabSection(
          notifier: tabNotifier,
          builder: (BuildContext context, int tab) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // 3 — Tab bar. The only way to switch tabs — the stat cards
              // above are display-only (user decision 2026-09-26).
              _revealWith(
                anim2,
                slide2,
                ProfileTabBar(
                  tabs: masterProfileTabLabels(l10n),
                  selected: tab,
                  onSelect: onSelectTab,
                  keyPrefix: 'master-profile',
                ),
              ),
              const SizedBox(height: VelvetSpacing.lg),

              // 4 — Tab body: «Про майстра» (bio + portfolio + contacts) /
              // «Послуги» (D16 — interactive category cards, unchanged) /
              // «Відгуки» (the SAME `MasterReviewsBody` the deleted
              // standalone «Мої відгуки» screen rendered — D11).
              _revealWith(
                anim3,
                slide3,
                KeyedSubtree(
                  key: ValueKey<int>(tab),
                  child: switch (tab) {
                    0 => _AboutTab(master: master),
                    1 => const _ProfileCategoriesSection(),
                    _ => MasterReviewsBody(masterId: master.id),
                  },
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
// _AboutTab — «Про майстра»: bio (or the AddLink empty-state) + portfolio +
// contacts (phone/Instagram).
// ---------------------------------------------------------------------------

class _AboutTab extends StatelessWidget {
  const _AboutTab({required this.master});

  final Master master;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // Bio section. Phase 351 (U-locked "Both rows" empty-state
        // decision) — this is the master's OWN profile, so an empty bio no
        // longer omits the section outright: it shows the promoted
        // [AddLink] «Додати опис» (REUSE-FIRST, promoted from the salon
        // management screen's `_AddLink`/`_AboutReadView`'s
        // `canEdit`-branch — `salon_management_profile_screen.dart:949-957`)
        // opening this master's own bio editor
        // ([RouteNames.masterEditPersonal] → `PersonalInfoEditScreen`).
        Column(
          key: const Key('master-profile-bio'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: VelvetSpacing.xs),
              child: Text(
                l10n.masterBioLabel,
                style: VelvetText.sectionLabel(),
              ),
            ),
            if (master.bio != null && master.bio!.isNotEmpty)
              NeumorphicInset(
                radius: VelvetRadii.card,
                child: Padding(
                  padding: const EdgeInsets.all(VelvetSpacing.md + 2),
                  child: Text(master.bio!, style: VelvetText.bodyStrong()),
                ),
              )
            else
              AddLink(
                key: const Key('master-profile-add-bio'),
                label: l10n.salonManageAddDescriptionLink,
                onTap: () => context.push(RouteNames.masterEditPersonal),
              ),
          ],
        ),
        const SizedBox(height: VelvetSpacing.xl),

        // Portfolio section: placeholder tiles (Phase 4.4 ships real ones).
        // REUSE-FIRST — [PortfolioRail] promoted to
        // shared/widgets/portfolio_rail.dart; also used by
        // public_master_profile_screen.dart and the salon owner/admin
        // «Про салон» tab.
        PortfolioRail(
          onSeeAll: () {
            // Phase 4.4 — portfolio gallery route.
          },
        ),
        const SizedBox(height: VelvetSpacing.xl),

        // Contacts section: phone and Instagram from domain model; both
        // fall back to '—' when the field is not set by the master.
        Text(l10n.masterContactsLabel, style: VelvetText.sectionLabel()),
        const SizedBox(height: VelvetSpacing.xs),
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
    );
  }

  /// Opens the master's Instagram profile in the Instagram app or a browser.
  ///
  /// [rawValue] is the verbatim stored contact string (bare handle,
  /// "@"-prefixed, or full URL). It is sanitized through
  /// [canonicalInstagramUri] (STRICT https + host/charset allow-list) before
  /// launch — an unvalidated string is never handed to [launchUrl]. On a null
  /// result (no safe URL) or a launch failure, a localized VelvetSnack is shown.
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

  /// Shows the localized "couldn't open Instagram" error VelvetSnack.
  ///
  /// This is the master's OWN tab-root screen — its `bottomNavBar` always
  /// renders the shared `VelvetBottomNavBar` (never suppressed), so the
  /// bottom-anchored snack needs `bottomInset` to clear it; see
  /// `VelvetSizes.bottomNavClearanceMaster`'s doc.
  static void _showInstagramError(BuildContext context) {
    showErrorSnack(
      context,
      AppLocalizations.of(context).masterInstagramOpenError,
      bottomInset: VelvetSizes.bottomNavClearanceMaster,
    );
  }
}

// ---------------------------------------------------------------------------
// _ProfileCategoriesSection — P-H2 memoized category grouping
// ---------------------------------------------------------------------------

/// Watches [servicesListProvider] and renders the section header + the
/// shared [ServiceCategoryCardList] (interactive: true — tapping a card
/// navigates to `/services?expandCategory=<slug>`, the owner's own service-
/// management screen). Category-label resolution lives in
/// [ServiceCategoryCardList] itself, via [approvedCategoriesProvider].
class _ProfileCategoriesSection extends ConsumerWidget {
  const _ProfileCategoriesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final servicesAsync = ref.watch(servicesListProvider);

    // Section header — a single right-aligned "all services" link. The
    // "Послуги" section title was removed per product decision; the link now
    // sits flush to the right margin. Built on demand so it can be omitted
    // entirely in the zero-services empty state, where the single
    // "Додати послуги" CTA is the only call to action.
    Widget buildHeader() => Padding(
      padding: const EdgeInsets.only(left: 4, bottom: VelvetSpacing.xs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: <Widget>[
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
    );

    return servicesAsync.when(
      loading: () => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          buildHeader(),
          const SkeletonShimmerScope(
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
        ],
      ),
      error: (_, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          buildHeader(),
          Padding(
            padding: const EdgeInsets.only(top: VelvetSpacing.xs),
            child: Text(l10n.errUnknown, style: VelvetText.feedbackMutedXs),
          ),
        ],
      ),
      data: (List<MasterService> services) {
        // Zero-services empty state: a single primary CTA that opens the
        // first-time bulk service-setup flow — the SAME entry point the
        // services-list empty state uses (RouteNames.serviceSetup). The
        // section header and "all services" link are intentionally dropped
        // here so the CTA stands alone.
        if (services.isEmpty) {
          return Padding(
            padding: const EdgeInsets.only(top: VelvetSpacing.xs),
            child: SizedBox(
              width: double.infinity,
              child: NeumorphicButton(
                key: const Key('btn-master-add-services'),
                label: l10n.masterAddServices,
                icon: Icons.add_rounded,
                onPressed: () => context.push(RouteNames.serviceSetup),
              ),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            buildHeader(),
            ServiceCategoryCardList(
              services: services,
              keyPrefix: 'profile-category',
              interactive: true,
            ),
          ],
        );
      },
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

          // 3 — Tab bar placeholder.
          SkeletonBlock(width: double.infinity, height: 44),
          SizedBox(height: VelvetSpacing.lg),

          // 4 — Tab body placeholder.
          SkeletonBlock(
            width: double.infinity,
            height: 160,
            radius: VelvetRadii.card,
          ),
        ],
      ),
    );
  }
}
