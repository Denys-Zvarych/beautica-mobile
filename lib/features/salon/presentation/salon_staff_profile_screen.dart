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
//   • bio ("Про майстра") — MASTER ONLY, omitted when empty;
//   • services grouped by category ("Послуги") — MASTER ONLY, via the
//     shared [ServiceCategoryCardList] (`interactive: false` — `true` would
//     deep-link into the AUTHENTICATED viewer's own `/services` screen, not
//     [member]'s);
//   • contacts = PHONE ONLY (Instagram is intentionally not shown here — see
//     [SalonStaffMemberProfileData]'s own header doc for the rationale),
//     omitted when unset;
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
// ServiceCategoryCardList / SkeletonShimmerScope widgets verbatim.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_selectors.dart';
import 'package:beautica_mobile/features/salon/application/salon_staff_member_notifier.dart';
import 'package:beautica_mobile/features/salon/domain/salon_staff_member.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:beautica_mobile/shared/widgets/rating_star.dart';
import 'package:beautica_mobile/shared/widgets/skeleton_shimmer.dart';

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
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  // Pre-built staggered-entrance animations (mobile-perf pattern, mirrors
  // `PublicMasterProfileScreen`) so build() never allocates a
  // CurvedAnimation/Tween per frame. Five sections: identity / stats / bio /
  // service categories / contacts.
  late final CurvedAnimation _anim0;
  late final CurvedAnimation _anim1;
  late final CurvedAnimation _anim2;
  late final CurvedAnimation _anim3;
  late final CurvedAnimation _anim4;
  late final Animation<Offset> _slide0;
  late final Animation<Offset> _slide1;
  late final Animation<Offset> _slide2;
  late final Animation<Offset> _slide3;
  late final Animation<Offset> _slide4;

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
    _anim2 = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.28, 0.80, curve: Curves.easeOutCubic),
    );
    _anim3 = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.40, 0.90, curve: Curves.easeOutCubic),
    );
    _anim4 = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.50, 1.0, curve: Curves.easeOutCubic),
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
  }

  @override
  void dispose() {
    _anim0.dispose();
    _anim1.dispose();
    _anim2.dispose();
    _anim3.dispose();
    _anim4.dispose();
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
            member: data.$1,
            services: data.$2,
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
// _StaffProfileBody — loaded state
// ---------------------------------------------------------------------------

class _StaffProfileBody extends StatelessWidget {
  const _StaffProfileBody({
    required this.member,
    required this.services,
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

  final SalonStaffMember member;

  /// The master's active services (empty for an admin entry — see
  /// [SalonStaffMemberProfileData]'s own header doc). Drives both the
  /// services stat tile and the read-only service-categories section.
  final List<MasterService> services;

  final Animation<double> anim0;
  final Animation<double> anim1;
  final Animation<double> anim2;
  final Animation<double> anim3;
  final Animation<double> anim4;
  final Animation<Offset> slide0;
  final Animation<Offset> slide1;
  final Animation<Offset> slide2;
  final Animation<Offset> slide3;
  final Animation<Offset> slide4;

  static Widget _reveal(
    Animation<double> fade,
    Animation<Offset> slide,
    Widget child,
  ) => RepaintBoundary(
    child: FadeTransition(
      opacity: fade,
      child: SlideTransition(position: slide, child: child),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool isAdmin = member.role == SalonStaffRole.admin;
    final String displayName = '${member.firstName} ${member.lastName}'.trim();
    // Admins are administrative staff, not service-providing masters — no
    // service rating, reviews, service count, bio, or category list.
    final bool hasReviews = !isAdmin && member.reviewCount > 0;
    final String? bio = (!isAdmin && (member.bio?.isNotEmpty ?? false))
        ? member.bio
        : null;
    final String? phone = (member.phoneNumber?.trim().isNotEmpty ?? false)
        ? member.phoneNumber!.trim()
        : null;
    final String? ownTitle = member.professionalTitle?.trim();
    final String roleLabel = isAdmin
        ? l10n.salonStaffRoleAdmin
        : (ownTitle != null && ownTitle.isNotEmpty)
        ? ownTitle
        : l10n.masterRoleSalonMaster;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // 1 — identity card.
        _reveal(
          anim0,
          slide0,
          NeumorphicCard(
            color: const Color(0xFFEDE4D5),
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
          _reveal(
            anim1,
            slide1,
            IntrinsicHeight(
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
        ],

        // 3 — bio (master only, omitted entirely when empty).
        if (bio != null) ...<Widget>[
          _reveal(
            anim2,
            slide2,
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
                    child: Text(bio, style: VelvetText.bodyStrong()),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: VelvetSpacing.xl),
        ],

        // 4 — services grouped by category (master only). `interactive:
        // false` — the owner/admin viewer's own `/services` route has no
        // meaning for [member]'s catalogue. Omitted when the master has no
        // active services, matching how bio/contacts are omitted when empty.
        if (!isAdmin && services.isNotEmpty) ...<Widget>[
          _reveal(
            anim3,
            slide3,
            Column(
              key: const Key('salon-staff-profile-service-categories'),
              crossAxisAlignment: CrossAxisAlignment.start,
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
                  interactive: false,
                ),
              ],
            ),
          ),
          const SizedBox(height: VelvetSpacing.xl),
        ],

        // 5 — contacts (phone only; Instagram intentionally NOT shown here —
        // see this file's header doc). Omitted when unset.
        if (phone != null)
          _reveal(
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
          // Bio block.
          Padding(
            padding: EdgeInsets.only(left: 4, bottom: VelvetSpacing.xs),
            child: SkeletonBlock(width: 110, height: 13),
          ),
          SkeletonBlock(
            width: double.infinity,
            height: 92,
            radius: VelvetRadii.card,
          ),
        ],
      ),
    );
  }
}
