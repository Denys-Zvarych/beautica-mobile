// SALON_MASTER own-profile screen — the role's landing screen (`roleHomePath`,
// `RouteNames.salonMasterProfile`, `/staff/profile`).
//
// Fixes the "blank home" bug: an invited SALON_MASTER previously logged in and
// landed on the bare `_Placeholder('home')` (`roleHomePath`'s old `_` wildcard
// arm) — see `routing/role_home.dart` and `routing/auth_redirect.dart`.
//
// Scope (product decision, 2026-09-01 — "for now the salon master will not see
// the salon profile at all, only his personal profile"): a read-only
// first-person self-view ONLY. No salon profile, no «Команда»/team surface, no
// bottom-nav shell, no services/bookings/schedule tabs — those are a later
// increment.
//
// Identity card also carries the EMPLOYING salon's name + address, read-only
// (user requirement, 2026-09-01: "location for salon master should [be the]
// salon location", "in salon master we need somewhere to show the salon
// name"). Unlike `SettingsHubScreen`'s «Локація» row (an EDIT affordance
// pushing `RouteNames.masterEditLocation` — the MASTER's own location), this
// is a display-only row: a SALON_MASTER cannot edit the salon's address
// (`salon_settings_screen.dart`'s locked decision — "Owner-only: admins
// cannot edit salon info" — applies a fortiori to a master, who has even less
// standing than an admin), and the approved design's `master_own_profile
// _screen.dart` never wires this identity card to any location-edit
// destination in the first place. Placed on THIS screen rather than the
// settings hub because `MasterAddressBlock` — the shared widget every other
// master identity card already uses to render an address next to the
// [RoleChip] — is an identity-card composition primitive, not a settings
// row; the settings hub's own design (`master_personal_settings_screen.dart`)
// deliberately has no «Локація» row to add one to. See
// [salonMasterOwnProfileProvider]'s header for how the salon is fetched.
//
// ── REUSE-FIRST ──────────────────────────────────────────────────────────
// Composed entirely from shared building blocks already shipped for the two
// structurally adjacent screens — [MasterProfileScreen] (INDEPENDENT_MASTER's
// own profile) and `SalonStaffProfileScreen` (the owner/admin's THIRD-PERSON
// view of a staff member): [ProfileScaffold], [ProfileAvatar], [RoleChip],
// [StatTile], [ServicesStatTile], [RatingStar], [ContactTile],
// [ServiceCategoryCardList] and [SkeletonShimmerScope]/[SkeletonBlock]. None of
// those private-widget bodies were forked — this is a new COMPOSITION of
// already-shared atoms, the same way every other profile screen in this
// feature is built (see each shared widget's own file for its own reuse list).
//
// Data comes from [salonMasterOwnProfileProvider] — `masterProfileProvider`
// (`GET /masters/me`, already admits SALON_MASTER) paired with the public
// `GET /masters/{masterId}/services` read; see that file's header for the full
// rationale (in particular why `servicesListProvider` would 403).
//
// Design source: `docs/signup-designs/SalonManagementDesign/lib/screens/
// master_own_profile_screen.dart` — ported within VelvetTouch, swapping the
// preview's `StaffIdentityCard`/`StaffStatTile`/`StaffProfileCategories`
// widget names for this codebase's already-shipped equivalents ([ProfileAvatar]
// + [RoleChip], [StatTile], [ServiceCategoryCardList]).
//
// Not portable as-is: the design's own [StaffProfileCategories] renders an
// «Усі послуги» → `MasterServicesScreen` link; that destination is
// INDEPENDENT_MASTER-only (`RouteNames.services`) and out of this scope's
// services-management surface, so the section here omits the link entirely
// and renders `ServiceCategoryCardList(interactive: false)` — the SAME
// treatment `SalonStaffProfileScreen` already gives a THIRD-PERSON viewer,
// since `/services` has no meaning for either viewer of this role's catalogue.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/icons/app_icon.dart';
import 'package:beautica_mobile/core/icons/beautica_asset_icons.dart';
import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/master/application/salon_master_own_profile_notifier.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/formatters/address_lines.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:beautica_mobile/shared/widgets/rating_star.dart';
import 'package:beautica_mobile/shared/widgets/salon_affiliation_line.dart';
import 'package:beautica_mobile/shared/widgets/skeleton_shimmer.dart';

import 'widgets/master_address_block.dart';
import 'widgets/profile_avatar.dart';
import 'widgets/profile_scaffold.dart';
import 'widgets/service_category_cards.dart';
import 'widgets/services_stat_tile.dart';

export 'package:beautica_mobile/features/master/application/salon_master_own_profile_notifier.dart'
    show salonMasterOwnProfileProvider;

/// Read-only first-person self-view of the authenticated SALON_MASTER's own
/// profile. See this file's header for full scope + reuse rationale.
class SalonMasterProfileScreen extends ConsumerStatefulWidget {
  const SalonMasterProfileScreen({super.key});

  @override
  ConsumerState<SalonMasterProfileScreen> createState() =>
      _SalonMasterProfileScreenState();
}

class _SalonMasterProfileScreenState
    extends ConsumerState<SalonMasterProfileScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  // Pre-built staggered-entrance animations (mobile-perf pattern, mirrors
  // `SalonStaffProfileScreen`/`MasterProfileScreen`) so build() never
  // allocates a CurvedAnimation/Tween per frame. Five sections: identity /
  // stats / bio / service categories / contacts.
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

  // Captured in initState so dispose() never touches `ref` (Riverpod 3.x
  // throws if `ref` is used post-unmount). PII-bearing self-view screen —
  // mirrors `MasterProfileScreen`/`OwnerOwnProfileScreen`'s identical guard.
  late final ScreenProtectionManager _screenProtection;

  @override
  void initState() {
    super.initState();
    _screenProtection = ref.read(screenProtectionProvider)..acquire();
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
    _screenProtection.release();
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
    final AsyncValue<SalonMasterOwnProfileData> async = ref.watch(
      salonMasterOwnProfileProvider,
    );

    return ProfileScaffold(
      // Reuses the SAME title copy as the INDEPENDENT_MASTER's own profile —
      // both are first-person "my profile" landings.
      title: l10n.masterProfileTitle,
      // Tab-root/landing screen — always first in its Navigator stack (the
      // `roleHomePath` target, reached only via `context.go`), so there is
      // no route to pop back to. Mirrors `MasterProfileScreen`'s identical
      // `showBack: false`.
      showBack: false,
      trailing: NeumorphicIconButton(
        key: const Key('btn-menu-salon-master'),
        icon: Icons.tune_rounded,
        semanticLabel: l10n.settingsHubMenuButton,
        onTap: () => context.push(RouteNames.salonMasterSettings),
      ),
      onRefresh: () async {
        ref.invalidate(salonMasterOwnProfileProvider);
        await ref.read(salonMasterOwnProfileProvider.future);
      },
      child: async.when(
        loading: () => const _SalonMasterProfileSkeleton(),
        error: (Object e, _) => ErrorState(
          failure: e is Failure ? e : UnknownFailure(cause: e),
          onRetry: () => ref.invalidate(salonMasterOwnProfileProvider),
        ),
        data: (SalonMasterOwnProfileData data) {
          _startReveal();
          return _SalonMasterProfileBody(
            master: data.$1,
            services: data.$2,
            salon: data.$3,
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
// _SalonMasterProfileBody — loaded state
// ---------------------------------------------------------------------------

class _SalonMasterProfileBody extends StatelessWidget {
  const _SalonMasterProfileBody({
    required this.master,
    required this.services,
    required this.salon,
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

  /// The master's own active services — drives the services stat tile and
  /// the read-only «Мої категорії» section.
  final List<MasterService> services;

  /// The employing salon, for the read-only salon-name + salon-address rows
  /// on the identity card. `null` omits both rows entirely — never a `—`
  /// placeholder — see [salonMasterOwnProfileProvider]'s header for when
  /// this is null (no `salonId`, or the salon read failed).
  final Salon? salon;

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
    final String displayName = '${master.firstName} ${master.lastName}'.trim();
    final bool hasReviews = master.reviewCount > 0;
    final String? bio = (master.bio?.isNotEmpty ?? false) ? master.bio : null;
    final String? phone = (master.phoneNumber?.trim().isNotEmpty ?? false)
        ? master.phoneNumber!.trim()
        : null;
    final String? ownTitle = master.professionalTitle?.trim();
    final String roleLabel = (ownTitle != null && ownTitle.isNotEmpty)
        ? ownTitle
        : l10n.masterRoleSalonMaster;

    // The employing salon's name + address — read-only (see this file's
    // header). `salonName` gates on non-empty since [Salon.name] is
    // non-nullable but the backend can serve `""`; the address builders
    // already collapse blank/whitespace-only fields to `null` on their own
    // (`shared/formatters/address_lines.dart`).
    final Salon? affiliatedSalon = salon;
    final String? salonName =
        (affiliatedSalon != null && affiliatedSalon.name.trim().isNotEmpty)
        ? affiliatedSalon.name.trim()
        : null;
    final String? salonLocalityLine = buildLocalityLine(affiliatedSalon?.city);
    final String? salonStreetLine = buildStreetLine(
      affiliatedSalon?.street,
      affiliatedSalon?.buildingNo,
    );
    final String? salonCombinedAddressLine = buildCombinedAddressLine(
      affiliatedSalon?.city,
      affiliatedSalon?.street,
      affiliatedSalon?.buildingNo,
    );

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
                        key: const Key('salon-master-profile-name'),
                        style: VelvetText.displayName(),
                        maxLines: 2,
                        softWrap: true,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: VelvetSpacing.xs + 2),
                      RoleChip(
                        key: const Key('salon-master-profile-role-chip'),
                        label: roleLabel,
                        icon: Icons.auto_awesome_rounded,
                      ),
                      // Employing salon's name — «I work at X» (item 3). Omitted
                      // when there is no salon to name, never rendered empty.
                      if (salonName != null) ...<Widget>[
                        const SizedBox(height: VelvetSpacing.xs),
                        SalonAffiliationLine(
                          key: const Key('salon-master-profile-salon-name'),
                          salonName: salonName,
                        ),
                      ],
                      // Employing salon's address — READ-ONLY (item 2): this
                      // role has no personal location to edit and cannot edit
                      // the salon's, so — unlike `master_profile_screen.dart`'s
                      // identical-looking block — this renders with no tap
                      // target at all. Same gate as every other
                      // `MasterAddressBlock` call site: non-null exactly when
                      // at least one of locality/street is visible.
                      if (salonCombinedAddressLine != null) ...<Widget>[
                        const SizedBox(height: VelvetSpacing.xs),
                        MasterAddressBlock(
                          keyPrefix: 'salon-master-profile-salon',
                          icon: const AppIcon(
                            BeauticaAssetIcons.locationMarker,
                            size: MasterAddressBlock.iconSize,
                            color: BrandColors.muted,
                          ),
                          localityLine: salonLocalityLine,
                          streetLine: salonStreetLine,
                          combinedLine: salonCombinedAddressLine,
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

        // 2 — stats row: rating / reviews / services / experience.
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
                      rating: hasReviews ? master.displayRating : null,
                      size: 18,
                      showLabel: false,
                    ),
                    value: hasReviews
                        ? (master.displayRating?.toStringAsFixed(1) ?? '—')
                        : '—',
                    caption: l10n.masterRatingLabel,
                    valueKey: const Key('salon-master-profile-rating-value'),
                  ),
                ),
                const SizedBox(width: VelvetSpacing.sm),
                Expanded(
                  child: StatTile(
                    icon: Icons.reviews_outlined,
                    value: hasReviews ? master.reviewCount.toString() : '—',
                    caption: l10n.masterStatsReviewsLabel,
                    valueKey: const Key('salon-master-profile-reviews-value'),
                  ),
                ),
                const SizedBox(width: VelvetSpacing.sm),
                Expanded(
                  child: ServicesStatTile(
                    count: services.length,
                    valueKey: const Key('salon-master-profile-services-value'),
                  ),
                ),
                const SizedBox(width: VelvetSpacing.sm),
                Expanded(
                  child: StatTile(
                    icon: Icons.workspace_premium_outlined,
                    // No tenure field on the domain model yet — mirrors
                    // every other experience tile in the app.
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

        // 3 — bio («Про себе», first-person; omitted entirely when empty).
        if (bio != null) ...<Widget>[
          _reveal(
            anim2,
            slide2,
            Column(
              key: const Key('salon-master-profile-bio'),
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
                    child: Text(bio, style: VelvetText.bodyStrong()),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: VelvetSpacing.xl),
        ],

        // 4 — «Мої категорії»: services grouped by category, read-only
        // (`interactive: false` — `/services` is INDEPENDENT_MASTER-only and
        // has no meaning here; see this file's header). Omitted when the
        // master has no active services, matching how bio/contacts are
        // omitted when empty.
        if (services.isNotEmpty) ...<Widget>[
          _reveal(
            anim3,
            slide3,
            Column(
              key: const Key('salon-master-profile-service-categories'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(
                    left: 4,
                    bottom: VelvetSpacing.xs,
                  ),
                  child: Text(
                    l10n.masterOwnCategoriesLabel,
                    style: VelvetText.sectionLabel(),
                  ),
                ),
                ServiceCategoryCardList(
                  services: services,
                  keyPrefix: 'salon-master-profile-category',
                  interactive: false,
                ),
              ],
            ),
          ),
          const SizedBox(height: VelvetSpacing.xl),
        ],

        // 5 — contacts (phone only; the design omits any other contact
        // method here). Omitted when unset.
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
                  key: const Key('salon-master-profile-contact-phone'),
                  icon: Icons.phone_outlined,
                  value: phone,
                  semanticLabel: l10n.phoneLabel,
                  // Dialing out is not in this phase's scope — mirrors
                  // `SalonStaffProfileScreen`'s identical phone tile.
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
// _SalonMasterProfileSkeleton — loading state
// ---------------------------------------------------------------------------

class _SalonMasterProfileSkeleton extends StatelessWidget {
  const _SalonMasterProfileSkeleton();

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
