// Phase 21.5 — Salon staff member (master OR admin) management profile.
//
// The owner/admin's view of ONE of their salon's staff — reached from the
// «Персонал» grid's `SalonMasterCard` tap. A literal structural mirror of the
// shipped CLIENT-facing `PublicMasterProfileScreen`
// (`features/master/presentation/public_master_profile_screen.dart`, see
// that file's own header for its own precedent), reworked for the owner/
// admin viewing a colleague:
//
//   • identity card: avatar, name, a management [RoleChip] (Майстер's own
//     professional title, or a generic salon-master label; Адміністратор for
//     an admin). The specialty/title SUB-LINE under the name is removed for
//     BOTH roles — redundant with the RoleChip;
//   • stats row (rating / reviews / services / experience) — MASTER ONLY,
//     admins have no service metrics;
//   • «Про майстра» / «Послуги» / «Відгуки» tabs (Phase 354) — MASTER ONLY,
//     the same [ProfileTabBar]/[ProfileTabSelection] mechanism
//     `PublicMasterProfileScreen`/`MasterProfileScreen`/
//     `SalonMasterProfileScreen` already share (Phase 351, D15):
//       - «Про майстра» — bio (or the empty-about copy, Phase 351's own
//         "always show one of two variants" rule) + the phone contact;
//       - «Послуги» — services grouped by category via the shared
//         [ServiceCategoryCardList]. Tappable (`interactive: true`) whenever
//         the master has a resolved `masterId` — same condition that gates
//         the management pair below — via the widget's `onCategoryTap`
//         override, which redirects to `RouteNames.salonManageStaffServices`
//         (the SAME destination the management pair's «Послуги» card opens)
//         instead of [ServiceCategoryCard]'s own built-in
//         `RouteNames.services` default, which is scoped to the AUTHENTICATED
//         viewer, not [member] (2026-09-26, user request — see
//         `docs/mobile-phases/phase-357-staff-profile-services-tappable.md`).
//         Falls back to non-interactive, static tiles when `masterId` is
//         unresolved (the Phase 318 data-anomaly case). Omitted entirely when
//         the master has no active services, mirroring
//         `PublicMasterProfileScreen`'s own services tab (no dedicated
//         empty-state — [ServiceCategoryCardList] itself renders nothing for
//         an empty list);
//       - «Відгуки» — [MasterReviewsBody]. When the resolved entry carries no
//         `masterId` (the Phase 318 data-anomaly case — the same condition
//         that disables the management pair below), [MasterReviewsBody]'s
//         own null-`masterId` arm renders its zero-reviews empty state with
//         NO fetch;
//   • «Графік роботи» / «Послуги» management-action card pair — MASTER ONLY.
//     User decision 2026-09-26 ("also add the tabs to this profile too", then
//     "at the bottom of the page" when offered the placement choice) —
//     placed at the BOTTOM of the page, AFTER the tab content, so it reads
//     the same regardless of which tab is active (it sits outside
//     [ProfileTabSection] entirely — a tab switch never touches it). See
//     `docs/mobile-phases/phase-354-salon-staff-profile-tabs.md`'s Decisions
//     for the full record (this overrides that phase doc's own D2, which
//     recommended keeping the pair ABOVE the tabs);
//   • contacts = PHONE ONLY (Instagram is intentionally not shown here — see
//     [SalonStaffMemberProfileData]'s own header doc for the rationale). For
//     a MASTER entry this now lives inside the «Про майстра» tab; for an
//     ADMIN entry (no tabs at all) it stays a top-level section, omitted when
//     unset;
//   • the `tune_rounded` settings action — an ADMIN entry always gets it;
//     a MASTER entry gets it only for a SALON_OWNER viewer who is not
//     looking at their own row (Phase 307, D3/D4) — and no pinned booking
//     shelf (client-only affordance), simply absent, not a disabled
//     placeholder.
//
// Data comes from [salonStaffMemberProfileProvider] (a family keyed on
// `(salonId, memberId)`), which resolves the roster entry from the
// already-cached [salonManagementProfileProvider] and, for a master entry
// only, additionally loads the master's active services.
//
// Design source: `docs/signup-designs/SalonManagementDesign/lib/screens/
// master_management_profile_screen.dart` — ported within the locked
// VelvetTouch palette, reusing the shipped ProfileScaffold / ProfileAvatar /
// RoleChip / StatTile / ServicesStatTile / RatingStar / ContactTile /
// ServiceCategoryCardList / SkeletonShimmerScope widgets verbatim. Phase 354
// additionally reuses [ProfileTabBar] / [ProfileTabSelection] /
// [ProfileTabSection] / [masterProfileTabLabels] / [MasterReviewsBody] —
// every one already shared by the other three master profile screens, none
// forked for this one.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/time/clock_provider.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/core/widgets/reveal_transition.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_selectors.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/presentation/master_role_label.dart';
import 'package:beautica_mobile/features/salon/application/salon_staff_member_notifier.dart';
import 'package:beautica_mobile/features/salon/domain/salon_staff_member.dart';
import 'package:beautica_mobile/features/schedule/domain/schedule_scope.dart';
import 'package:beautica_mobile/features/schedule/domain/weekly_schedule.dart';
import 'package:beautica_mobile/features/schedule/presentation/weekly_schedule_notifier.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/presentation/service_catalogue_revision.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/formatters/weekly_schedule_summary.dart';
import 'package:beautica_mobile/shared/time/kyiv_day.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:beautica_mobile/shared/widgets/profile_tab_bar.dart';
import 'package:beautica_mobile/shared/widgets/profile_tab_selection.dart';
import 'package:beautica_mobile/shared/widgets/rating_star.dart';
import 'package:beautica_mobile/shared/widgets/skeleton_shimmer.dart';

import '../../master/presentation/widgets/management_action_card.dart';
import '../../master/presentation/widgets/master_profile_tabs.dart';
import '../../master/presentation/widgets/master_reviews_body.dart';
import '../../master/presentation/widgets/profile_avatar.dart';
import '../../master/presentation/widgets/profile_scaffold.dart';
import '../../master/presentation/widgets/service_category_cards.dart';
import '../../master/presentation/widgets/services_stat_tile.dart';

/// Owner/admin-facing management profile of the salon staff member
/// identified by [memberId] (the roster row's `userId`) within [salonId].
class SalonStaffProfileScreen extends ConsumerStatefulWidget {
  const SalonStaffProfileScreen({
    super.key,
    required this.salonId,
    required this.memberId,
  });

  final String salonId;
  final String memberId;

  @override
  ConsumerState<SalonStaffProfileScreen> createState() =>
      _SalonStaffProfileScreenState();
}

class _SalonStaffProfileScreenState
    extends ConsumerState<SalonStaffProfileScreen>
    with
        SingleTickerProviderStateMixin,
        ProfileTabSelection<SalonStaffProfileScreen> {
  late final AnimationController _controller;

  // Pre-built staggered-entrance animations (mobile-perf pattern, mirrors
  // `PublicMasterProfileScreen`/`SalonMasterProfileScreen`) so build() never
  // allocates a CurvedAnimation/Tween per frame. Phase 354 — six sections now:
  // identity / stats / tab bar / tab body / management pair, PLUS the
  // ADMIN-only contacts section, which shares `_anim4`/`_slide4` with the
  // (mutually exclusive) admin branch — see the doc on `_anim4` below.
  late final CurvedAnimation _anim0;
  late final CurvedAnimation _anim1;
  late final CurvedAnimation _anim2;
  late final CurvedAnimation _anim3;
  late final CurvedAnimation _anim4;
  late final CurvedAnimation _anim5;
  late final Animation<Offset> _slide0;
  late final Animation<Offset> _slide1;
  late final Animation<Offset> _slide2;
  late final Animation<Offset> _slide3;
  late final Animation<Offset> _slide4;
  late final Animation<Offset> _slide5;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    );
    _anim0 = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.00, 0.55, curve: Curves.easeOutCubic),
    );
    _anim1 = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.15, 0.68, curve: Curves.easeOutCubic),
    );
    // Phase 354 — tab bar. Was the bio section's interval pre-354; bio no
    // longer has a section of its own (it lives inside the «Про майстра» tab
    // body instead), so this interval is now spent on the tab bar, which sits
    // in the SAME visual slot (directly under the stats row).
    _anim2 = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.28, 0.80, curve: Curves.easeOutCubic),
    );
    // Phase 354 — tab body. Was the service-categories section's interval
    // pre-354, for the same reason as `_anim2` above.
    _anim3 = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.40, 0.90, curve: Curves.easeOutCubic),
    );
    // ADMIN-only contacts section (a MASTER entry's phone now lives inside
    // the tab body, under `_anim3`). Interval UNCHANGED from pre-354 — this
    // was already the last-declared section for the admin branch (the
    // master-only stats/bio/categories/pair sections it used to follow are
    // all gated off for an admin, so it effectively ran right after identity
    // both before and after this phase).
    _anim4 = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.50, 1.00, curve: Curves.easeOutCubic),
    );
    // The management pair (schedule + services). User decision 2026-09-26 —
    // moved to the BOTTOM of the page, after the tab content, so it is now
    // the LAST section on the master branch (pre-354 it sat second-from-top,
    // directly under the stats row, with the early 0.22-0.74 interval that
    // position called for — see git history for that rationale). The
    // interval is widened to the tail of the cascade to match its new
    // position.
    _anim5 = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.58, 1.00, curve: Curves.easeOutCubic),
    );
    const Offset slideBegin = Offset(0, 0.04);
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
    disposeProfileTabSelection();
    _anim0.dispose();
    _anim1.dispose();
    _anim2.dispose();
    _anim3.dispose();
    _anim4.dispose();
    _anim5.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _startReveal() {
    if (!_controller.isAnimating && _controller.value == 0) {
      _controller.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<SalonStaffMemberProfileData> async = ref.watch(
      salonStaffMemberProfileProvider(widget.salonId, widget.memberId),
    );

    // Phase 21.6 — the trailing management control. ADMIN entries: it opens
    // [StaffSettingsScreen], whose two actions
    // (`DELETE|PATCH /salons/{salonId}/admins/{userId}`) are admin-specific.
    //
    // Read off the SAME `maybeWhen` shape the title uses: unknown role
    // (loading/error) renders no trailing action, so the control never
    // appears before it is known to be correct.
    final bool isAdmin = async.maybeWhen(
      data: (SalonStaffMemberProfileData data) =>
          data.$1.role == SalonStaffRole.admin,
      orElse: () => false,
    );

    // Phase 307 — the MASTER counterpart. `DELETE /salons/{salonId}/masters
    // /{masterId}` is SALON_OWNER-only (unlike remove-admin, which an admin
    // may also perform) and never against the owner's own master row (D3/
    // D4 — see `StaffSettingsScreen`'s own header for the full rationale).
    // Gating the GEAR here is a UI-correctness convenience, not the real
    // gate — `StaffSettingsScreen`'s own body re-checks both conditions
    // itself, since the route is reachable without this control (back
    // stack, in-app `go`, cold deep link).
    final SalonStaffMember? member = async.maybeWhen(
      data: (SalonStaffMemberProfileData data) => data.$1,
      orElse: () => null,
    );
    final bool isOwner = ref.watch(isSalonOwnerProvider);
    final String? currentUserId = ref.watch(currentUserProvider)?.id;
    final bool showMasterGear =
        member != null &&
        member.role == SalonStaffRole.master &&
        isOwner &&
        member.userId != currentUserId;

    return ProfileScaffold(
      title: async.maybeWhen(
        data: (SalonStaffMemberProfileData data) =>
            data.$1.role == SalonStaffRole.admin
            ? l10n.salonStaffProfileAdminTitle
            : l10n.salonStaffProfileMasterTitle,
        // Role is unknown before the data resolves — default to the master
        // title (the common case) for the loading/error frame.
        orElse: () => l10n.salonStaffProfileMasterTitle,
      ),
      trailing: isAdmin
          ? NeumorphicIconButton(
              key: const Key('btn-admin-settings'),
              icon: Icons.tune_rounded,
              semanticLabel: l10n.adminSettingsManageSemanticLabel,
              onTap: () => context.push(
                RouteNames.salonManageStaffSettings(
                  widget.salonId,
                  widget.memberId,
                ),
              ),
            )
          : showMasterGear
          ? NeumorphicIconButton(
              key: const Key('btn-master-settings'),
              icon: Icons.tune_rounded,
              semanticLabel: l10n.staffSettingsManageMasterSemanticLabel,
              onTap: () => context.push(
                RouteNames.salonManageStaffSettings(
                  widget.salonId,
                  widget.memberId,
                ),
              ),
            )
          : null,
      child: async.when(
        loading: () => const _StaffProfileSkeleton(),
        error: (Object e, _) => ErrorState(
          failure: e is Failure ? e : UnknownFailure(cause: e),
          onRetry: () => ref.invalidate(
            salonStaffMemberProfileProvider(widget.salonId, widget.memberId),
          ),
        ),
        data: (SalonStaffMemberProfileData data) {
          _startReveal();
          return _StaffProfileBody(
            salonId: widget.salonId,
            memberId: widget.memberId,
            member: data.$1,
            services: data.$2,
            tabNotifier: profileTabNotifier,
            onSelectTab: selectProfileTab,
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
// _StaffProfileBody — loaded state
// ---------------------------------------------------------------------------

class _StaffProfileBody extends StatelessWidget {
  const _StaffProfileBody({
    required this.salonId,
    required this.memberId,
    required this.member,
    required this.services,
    required this.tabNotifier,
    required this.onSelectTab,
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

  /// Phase 312 (D3) — needed for the schedule row's provider watch
  /// (`weeklyScheduleProvider(ScheduleScope.salonMaster(...))`) and its
  /// `onTap` navigation target.
  final String salonId;
  final String memberId;

  final SalonStaffMember member;

  /// The master's active services (empty for an admin entry — see
  /// [SalonStaffMemberProfileData]'s own header doc). Drives both the
  /// services stat tile and the «Послуги» tab body.
  final List<MasterService> services;

  /// [ProfileTabSelection.profileTabNotifier] — the active tab index (0 =
  /// Про майстра, 1 = Послуги, 2 = Відгуки), as a [ValueNotifier] so only the
  /// [ProfileTabSection] below rebuilds on a tab switch (mobile-perf
  /// pattern, mirrors the other three master profile screens). The identity
  /// card / stat row / management pair never watch it.
  final ValueNotifier<int> tabNotifier;

  /// [ProfileTabSelection.selectProfileTab] — passed to [ProfileTabBar]'s
  /// `onSelect`, the only way to switch tabs (the stat cards are
  /// display-only, matching the other three master profile screens).
  final ValueChanged<int> onSelectTab;

  final Animation<double> anim0;
  final Animation<double> anim1;
  final Animation<double> anim2;
  final Animation<double> anim3;
  final Animation<double> anim4;
  final Animation<double> anim5;
  final Animation<Offset> slide0;
  final Animation<Offset> slide1;
  final Animation<Offset> slide2;
  final Animation<Offset> slide3;
  final Animation<Offset> slide4;
  final Animation<Offset> slide5;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool isAdmin = member.role == SalonStaffRole.admin;
    final String displayName = '${member.firstName} ${member.lastName}'.trim();
    // Admins are administrative staff, not service-providing masters — no
    // service rating, reviews, service count, bio, tabs, or management pair.
    final bool hasReviews = !isAdmin && member.reviewCount > 0;
    final String? bio = (!isAdmin && (member.bio?.isNotEmpty ?? false))
        ? member.bio
        : null;
    final String? phone = (member.phoneNumber?.trim().isNotEmpty ?? false)
        ? member.phoneNumber!.trim()
        : null;
    final String? ownTitle = member.professionalTitle?.trim();
    // The non-admin fallback is keyed on `masterType` (identity), NOT on
    // `role` (capability): an admin tapping the OWNER's roster row lands
    // here, and the owner is auto-enrolled as a master of their own salon,
    // so `role` is `master` while the chip must read «Власник салону». A
    // null `masterType` (an unrecognised wire role) keeps the old
    // salon-master wording. The master's own [professionalTitle] still wins
    // over both.
    final String roleLabel = isAdmin
        ? l10n.salonStaffRoleAdmin
        : (ownTitle != null && ownTitle.isNotEmpty)
        ? ownTitle
        : masterRoleLabel(member.masterType ?? MasterType.salonMaster, l10n);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // 1 — identity card.
        RevealTransition(
          key: const Key('salon-staff-profile-reveal-0'),
          fade: anim0,
          slide: slide0,
          child: NeumorphicCard(
            color: BrandColors.baseEmphasis,
            padding: const EdgeInsets.all(VelvetSpacing.md),
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
                        key: const Key('salon-staff-profile-name'),
                        style: VelvetText.displayName(),
                        maxLines: 2,
                        softWrap: true,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: VelvetSpacing.xs + 2),
                      RoleChip(
                        key: const Key('salon-staff-profile-role-chip'),
                        label: roleLabel,
                        icon: Icons.auto_awesome_rounded,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: VelvetSpacing.xl),

        // 2 — stats row: rating / reviews / services / experience. Suppressed
        // for admins — they have no service metrics.
        if (!isAdmin) ...<Widget>[
          RevealTransition(
            key: const Key('salon-staff-profile-reveal-1'),
            fade: anim1,
            slide: slide1,
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Expanded(
                    child: StatTile(
                      icon: Icons.star_rounded,
                      iconWidget: RatingStar(
                        rating: hasReviews ? member.avgRating : null,
                        size: 18,
                        showLabel: false,
                      ),
                      value: hasReviews
                          ? (member.avgRating?.toStringAsFixed(1) ?? '—')
                          : '—',
                      caption: l10n.masterRatingLabel,
                      valueKey: const Key('salon-staff-profile-rating-value'),
                    ),
                  ),
                  const SizedBox(width: VelvetSpacing.sm),
                  Expanded(
                    child: StatTile(
                      icon: Icons.reviews_outlined,
                      value: hasReviews ? member.reviewCount.toString() : '—',
                      caption: l10n.masterStatsReviewsLabel,
                      valueKey: const Key('salon-staff-profile-reviews-value'),
                    ),
                  ),
                  const SizedBox(width: VelvetSpacing.sm),
                  Expanded(
                    child: ServicesStatTile(
                      count: services.length,
                      valueKey: const Key('salon-staff-profile-services-value'),
                    ),
                  ),
                  const SizedBox(width: VelvetSpacing.sm),
                  Expanded(
                    child: StatTile(
                      icon: Icons.workspace_premium_outlined,
                      // No tenure field on the domain model yet — show a dash,
                      // mirrors every other experience tile in the app.
                      value: '—',
                      caption: l10n.publicMasterExperienceLabel,
                      iconColor: BrandColors.accentDeep,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: VelvetSpacing.xl),

          // 3+4 — Tab bar + tab body, isolated behind ONE `ProfileTabSection`
          // (mobile-perf pattern, mirrors the other three master profile
          // screens) — a tab switch here only rebuilds this region, never the
          // identity card / stat row above it, and never the management pair
          // below it.
          ProfileTabSection(
            notifier: tabNotifier,
            builder: (BuildContext context, int tab) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                // 3 — Tab bar. The only way to switch tabs — the stat cards
                // above are display-only.
                RevealTransition(
                  key: const Key('salon-staff-profile-reveal-2'),
                  fade: anim2,
                  slide: slide2,
                  child: ProfileTabBar(
                    tabs: masterProfileTabLabels(l10n),
                    selected: tab,
                    onSelect: onSelectTab,
                    keyPrefix: 'salon-staff-profile',
                  ),
                ),
                const SizedBox(height: VelvetSpacing.lg),

                // 4 — Tab body: «Про майстра» (bio + phone contact) /
                // «Послуги» (read-only category grid, omitted entirely when
                // the master has no services — mirrors
                // `PublicMasterProfileScreen`'s own services tab, which has
                // no dedicated empty state either) / «Відгуки» (this
                // master's reviews; a null `masterId` — the Phase 318
                // data-anomaly case — renders [MasterReviewsBody]'s own
                // zero-reviews empty state with no fetch).
                RevealTransition(
                  key: const Key('salon-staff-profile-reveal-3'),
                  fade: anim3,
                  slide: slide3,
                  child: KeyedSubtree(
                    key: ValueKey<int>(tab),
                    child: switch (tab) {
                      0 => _StaffAboutTab(bio: bio, phone: phone),
                      1 =>
                        services.isEmpty
                            ? const SizedBox.shrink()
                            // 2026-09-26 (user request) — make the category
                            // cards tappable for the owner/admin viewer too,
                            // same as `MasterProfileScreen`'s own «Послуги»
                            // tab (`interactive: true`), but redirected to
                            // the SAME destination the management pair's
                            // «Послуги» card below already opens
                            // (`RouteNames.salonManageStaffServices`) rather
                            // than [ServiceCategoryCard]'s own default
                            // `RouteNames.services` (that route is scoped to
                            // the AUTHENTICATED viewer, not [member]).
                            // `Consumer`-wrapped so the tap handler can reuse
                            // the exact await-then-invalidate pattern the
                            // management row below already established (D4)
                            // — one round trip, only when something actually
                            // changed. Non-interactive whenever the
                            // management row itself would be disabled (no
                            // resolved `masterId` — the Phase 318
                            // data-anomaly case), so the two affordances
                            // never disagree.
                            : Consumer(
                                builder: (BuildContext context, WidgetRef ref, _) {
                                  final String staffMasterId =
                                      member.masterId ?? '';
                                  final bool staffHasMasterId =
                                      staffMasterId.isNotEmpty;
                                  return Column(
                                    key: const Key(
                                      'salon-staff-profile-service-categories',
                                    ),
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          left: 4,
                                          bottom: VelvetSpacing.xs,
                                        ),
                                        child: Text(
                                          l10n.masterServicesLabel,
                                          style: VelvetText.sectionLabel(),
                                        ),
                                      ),
                                      ServiceCategoryCardList(
                                        services: services,
                                        keyPrefix: 'staff-profile-category',
                                        interactive: staffHasMasterId,
                                        // `context` here is the ancestor
                                        // `Consumer`'s builder context (the
                                        // one that owns `ref`), NOT the
                                        // tapped card's own context — see
                                        // `_openStaffServices`'s doc.
                                        onCategoryTap: !staffHasMasterId
                                            ? null
                                            : (BuildContext _, String? _) =>
                                                  _openStaffServices(
                                                    context,
                                                    ref,
                                                  ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                      _ => MasterReviewsBody(masterId: member.masterId),
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: VelvetSpacing.xl),

          // 5 — the management pair: schedule card (Phase 312, D3) + services
          // card (Phase 325, D1) — MASTER ONLY; an admin has no master row and
          // therefore no schedule or services block. Both share the SAME
          // reveal animation — they are siblings inside one block, not two
          // sections.
          //
          // Phase 354 (user decision 2026-09-26) — this block sits at the
          // BOTTOM of the page, after the tab content, so it renders
          // identically regardless of which tab is active: it is a sibling of
          // [ProfileTabSection], not a child of it, so a tab switch never
          // rebuilds it and it never rebuilds on one either. See this file's
          // header doc for the full placement rationale.
          //
          // Phase 325 replaced the former `SettingsRow` pair with the
          // `ManagementActionCard` pair (design source:
          // `docs/signup-designs/SalonServicesEntryPath/lib/screens/
          // staff_profile_screen.dart:174-211`, variant B · «пара дій») — the
          // SAME `IntrinsicHeight` > `Row(stretch)` > `Expanded` idiom the
          // stats row above already uses. Destination/gating for BOTH cards
          // are unchanged.
          RevealTransition(
            key: const Key('salon-staff-profile-reveal-5'),
            fade: anim5,
            slide: slide5,
            child: Consumer(
              builder: (BuildContext context, WidgetRef ref, _) {
                final String masterId = member.masterId ?? '';
                final bool hasMasterId = masterId.isNotEmpty;
                final ScheduleScope scope = ScheduleScope.salonMaster(
                  salonId: salonId,
                  masterId: masterId,
                );
                final AsyncValue<List<WeeklySchedule>> asyncWeekly = ref.watch(
                  weeklyScheduleProvider(scope),
                );

                // D11 — switch on the CONCRETE AsyncValue SUBTYPE, never
                // `.hasError` (an `AsyncLoading(retrying: true)` mid-retry
                // satisfies `hasError` without meaning failure — see
                // `project_asyncvalue_haserror_retrying_trap`) and never
                // `value == null` (would read a genuinely-empty schedule the
                // same as "still loading").
                final String value;
                final bool rowLoading;
                if (asyncWeekly is AsyncData<List<WeeklySchedule>>) {
                  value = weeklyScheduleSummary(
                    asyncWeekly.value,
                    kyivToday(ref.watch(clockProvider)),
                    l10n.staffProfileScheduleNotSet,
                    // Qase defect #36 — without this the row reduces a week of
                    // DIFFERING hours to one min-max span, reading as hours the
                    // owner never set. See `weeklyScheduleSummary`'s doc.
                    variedHoursLabel: l10n.staffProfileScheduleVariedHours,
                  );
                  rowLoading = false;
                } else if (asyncWeekly is AsyncError<List<WeeklySchedule>>) {
                  // AsyncError → '—', NOT «Не задано» — that would assert a
                  // fact ("no schedule set") the app does not actually have.
                  value = '—';
                  rowLoading = false;
                } else {
                  value = '';
                  rowLoading = true;
                }

                // D3 — a genuinely-resolved empty catalogue («Ще немає») is
                // distinct from a failed load. A failed load of THIS data
                // never reaches here: `services` comes from the SAME
                // `salonStaffMemberProfileProvider` future that gates the
                // whole screen (see `_SalonStaffProfileScreenState.build`'s
                // `async.when`) — if fetching the master's services throws,
                // the WHOLE provider throws (`salonStaffMemberProfile`'s
                // single `await ... getMasterServices(masterId)`), so the
                // screen renders `ErrorState` instead of `_StaffProfileBody`
                // and this card is never built with a stale/wrong count.
                // `services.isEmpty` here can therefore only ever mean a
                // real empty catalogue, never a failure.
                final String servicesValue = services.isEmpty
                    ? l10n.staffProfileServicesEmpty
                    : l10n.staffProfileServicesCount(services.length);

                // 2026-09-26 (owner/admin master-card polish) — flag the two
                // genuinely-empty values («Не задано» / «Ще немає») in
                // [BrandColors.error] so an operator spots an unconfigured
                // master at a glance. `value` equals `notSetLabel`
                // byte-for-byte ONLY via `weeklyScheduleSummary`'s two
                // `return notSetLabel;` paths (never for a resolved
                // schedule, and never for the '—'/'' AsyncError/loading
                // sentinels — see the comments above), so the string
                // comparison is exact, not a heuristic.
                final Color? scheduleValueColor =
                    value == l10n.staffProfileScheduleNotSet
                    ? BrandColors.error
                    : null;
                final Color? servicesValueColor = services.isEmpty
                    ? BrandColors.error
                    : null;

                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Expanded(
                        child: ManagementActionCard(
                          key: const Key('salon-staff-profile-schedule-row'),
                          icon: Icons.calendar_month_rounded,
                          label: l10n.scheduleTitle,
                          value: value,
                          valueColor: scheduleValueColor,
                          loading: rowLoading,
                          // D2-mirrored data-anomaly guard
                          // (`staff_settings_screen.dart`'s identical
                          // `enabled: member.masterId != null`) — a resolved
                          // master entry with no `masterId` never sends a
                          // guessed id.
                          enabled: hasMasterId,
                          onTap: !hasMasterId
                              ? () {}
                              : () => context.push(
                                  RouteNames.salonManageStaffSchedule(
                                    salonId,
                                    memberId,
                                  ),
                                  extra: scope,
                                ),
                        ),
                      ),
                      const SizedBox(width: VelvetSpacing.md),
                      // Phase 325 (D1) — «Послуги» sibling card, same
                      // guard as the schedule card above. `emphasis: true`
                      // is the ONE camel-washed card in the pair (approved
                      // design's own "spend the boldness in one place"
                      // rule). The value is the active-service count
                      // ALREADY loaded for the services stat tile (D2) — no
                      // second fetch, no new provider.
                      Expanded(
                        child: ManagementActionCard(
                          key: const Key('salon-staff-profile-services-row'),
                          icon: Icons.design_services_rounded,
                          label: l10n.masterServicesLabel,
                          value: servicesValue,
                          valueColor: servicesValueColor,
                          emphasis: true,
                          enabled: hasMasterId,
                          // Shares `_openStaffServices` with the «Послуги»
                          // tab's category cards above — see that method's
                          // doc for the push→await→revision-gated-invalidate
                          // rationale.
                          onTap: !hasMasterId
                              ? () {}
                              : () => _openStaffServices(context, ref),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],

        // 6 — contacts (phone only; Instagram intentionally NOT shown here —
        // see this file's header doc). ADMIN ONLY: a MASTER entry's phone now
        // lives inside the «Про майстра» tab body (see `_StaffAboutTab`
        // above) — an admin has no tabs at all (D4), so it keeps its own
        // top-level section, omitted when unset.
        if (isAdmin && phone != null) ...<Widget>[
          RevealTransition(
            key: const Key('salon-staff-profile-reveal-4'),
            fade: anim4,
            slide: slide4,
            child: Column(
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
                  key: const Key('salon-staff-profile-contact-phone'),
                  icon: Icons.phone_outlined,
                  value: phone,
                  semanticLabel: l10n.phoneLabel,
                  // Dialing out is not in this phase's scope — mirrors
                  // `_AboutReadView`'s identical phone tile on the salon's own
                  // management profile.
                  onTap: () {},
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // 2026-09-26 (REUSE-FIRST audit fix) — the «Послуги» tab's category cards
  // (`ServiceCategoryCardList.onCategoryTap` above) and the management
  // pair's «Послуги» card (`ManagementActionCard.onTap` above) both open the
  // SAME destination (`RouteNames.salonManageStaffServices`) and must
  // invalidate the SAME provider on return. This used to be two verbatim
  // copies of the push→await→revision-gated-invalidate sequence; extracted
  // to one method so a fix here reaches both call sites.
  //
  // D4 — await the push, then invalidate the profile provider so the stat
  // tile and the category grid pick up services added/removed in the
  // subtree. Pattern: `services_list_screen.dart`'s `_openAndRefresh`.
  //
  // 2026-09-13 audit (M7) — the invalidate is GATED on an actual mutation.
  // `salonStaffMemberProfileProvider.build` re-runs
  // `getMasterServices(masterId)` (`salon_staff_member_notifier.dart:75-79`),
  // so doing it unconditionally charged a full round trip to an operator
  // who only LOOKED. [serviceCatalogueRevisionProvider] is bumped by the
  // one fan-out point every create/edit/delete in that subtree calls; an
  // unchanged counter means nothing could have changed. See
  // `service_catalogue_revision.dart` for why this is a counter and not a
  // pop result.
  //
  // `context` here MUST be the one that owns `ref` (the ancestor
  // `Consumer`'s builder context) — never a descendant card's tapped
  // context, whose `mounted` can read differently from the context the
  // `ref` calls are actually scoped to.
  Future<void> _openStaffServices(BuildContext context, WidgetRef ref) async {
    final int before = ref.read(serviceCatalogueRevisionProvider);
    await context.push<void>(
      RouteNames.salonManageStaffServices(salonId, memberId),
    );
    if (!context.mounted) return;
    final int after = ref.read(serviceCatalogueRevisionProvider);
    if (after == before) return;
    ref.invalidate(salonStaffMemberProfileProvider(salonId, memberId));
  }
}

// ---------------------------------------------------------------------------
// _StaffAboutTab — «Про майстра»: bio (or the empty-about copy) + the phone
// contact. MASTER role only — see [_StaffProfileBody.build]'s tab switch.
// ---------------------------------------------------------------------------

/// Phase 354 — the «Про майстра» tab body. Mirrors
/// `PublicMasterProfileScreen`'s own `_AboutTab` (a client's READ-ONLY view
/// of a master — the closer analog than `SalonMasterProfileScreen`'s
/// first-person, editable `_SalonMasterAboutTab`, per this phase's D3): bio
/// ALWAYS renders one of two variants (real bio, or the muted empty-about
/// copy) rather than omitting the whole section when empty — this screen's
/// pre-354 behaviour omitted the bio section entirely for an empty bio; the
/// tab now shows something on every open, matching the other three master
/// profiles. No portfolio rail here (INDEPENDENT_MASTER-only elsewhere, and
/// out of this screen's scope) and the contact is phone, not Instagram — an
/// owner/admin management view, not the public client one.
class _StaffAboutTab extends StatelessWidget {
  const _StaffAboutTab({required this.bio, required this.phone});

  final String? bio;
  final String? phone;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (bio != null)
          Column(
            key: const Key('salon-staff-profile-bio'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(
                  left: 4,
                  bottom: VelvetSpacing.xs,
                ),
                child: Text(
                  l10n.publicMasterBioLabel,
                  style: VelvetText.sectionLabel(),
                ),
              ),
              NeumorphicInset(
                radius: VelvetRadii.card,
                child: Padding(
                  padding: const EdgeInsets.all(VelvetSpacing.md + 2),
                  child: Text(bio!, style: VelvetText.bodyStrong()),
                ),
              ),
            ],
          )
        else
          // D3 — reuses `PublicMasterProfileScreen`'s own empty-about copy
          // (`l10n.publicMasterAboutEmpty`) verbatim; this screen is a
          // read-only THIRD-PERSON view of the master too, so the same
          // wording applies unchanged.
          Text(
            l10n.publicMasterAboutEmpty,
            key: const Key('salon-staff-profile-about-empty'),
            style: VelvetText.feedback(BrandColors.muted),
          ),

        // Contacts (phone only; omitted when unset).
        if (phone != null) ...<Widget>[
          const SizedBox(height: VelvetSpacing.xl),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: VelvetSpacing.xs),
            child: Text(
              l10n.masterContactsLabel,
              style: VelvetText.sectionLabel(),
            ),
          ),
          ContactTile(
            key: const Key('salon-staff-profile-contact-phone'),
            icon: Icons.phone_outlined,
            value: phone!,
            semanticLabel: l10n.phoneLabel,
            // Dialing out is not in this phase's scope — mirrors this
            // screen's pre-354 top-level phone tile and the admin branch's
            // identical one below.
            onTap: () {},
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// _StaffProfileSkeleton — loading state
// ---------------------------------------------------------------------------

class _StaffProfileSkeleton extends StatelessWidget {
  const _StaffProfileSkeleton();

  @override
  Widget build(BuildContext context) {
    return const SkeletonShimmerScope(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Identity card.
          NeumorphicCard(
            color: BrandColors.baseEmphasis,
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
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: VelvetSpacing.xl),
          // Stats row.
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
          // Tab bar placeholder (D7 — parity with `SalonMasterProfileScreen`'s
          // own skeleton).
          SkeletonBlock(width: double.infinity, height: 44),
          SizedBox(height: VelvetSpacing.lg),
          // Tab body placeholder.
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
