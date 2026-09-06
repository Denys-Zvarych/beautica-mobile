// Phase 13.5 — Public master profile (CLIENT-facing, read-only).
//
// The client's view of an INDEPENDENT_MASTER, reached by tapping a search /
// favourites result card. Same depth language as the master's own profile
// (`MasterProfileScreen`) but:
//   • NO edit button — the top-right action is a favourite (heart) toggle;
//   • a read-only «Послуги» section mirrors the master's own profile: the
//     active services are grouped by category and rendered as one summary
//     card per non-empty bucket via the shared [ServiceCategoryCardList]
//     (`interactive: false`) — label + count only, no forward chevron, no
//     tap. The owner's version navigates a tapped card to
//     `/services?expandCategory=<slug>`, but that route is scoped to the
//     AUTHENTICATED master, not [widget.masterId], so it has no meaning for a
//     client browsing someone else's profile and is stripped here;
//   • contacts = Instagram only (no phone/dialer tile);
//   • a pinned camel-wash booking shelf holding a single «Записатись до
//     майстра» CTA (no section label) — it opens the Phase 14.1 booking flow
//     (placeholder route until 14.1 ships).
//
// Data comes from [publicMasterProfileProvider] (a family keyed on masterId)
// which loads the master + active services in parallel. All three AsyncValue
// states are handled explicitly (loading skeleton / error / data).
//
// Design source: `docs/signup-designs/PublicMasterProfile/` — ported within the
// locked Warm Mocha (VelvetTouch) palette, reusing the production
// ProfileScaffold / ProfileAvatar / RoleChip / StatTile / ContactTile widgets.

import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/core/widgets/reveal_transition.dart';
import 'package:beautica_mobile/features/favorites/application/favorite_toggle_notifier.dart';
import 'package:beautica_mobile/features/favorites/domain/favorite_target.dart';
import 'package:beautica_mobile/features/master/application/public_master_profile_notifier.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/feedback/show_velvet_snack.dart';
import 'package:beautica_mobile/shared/formatters/address_lines.dart';
import 'package:beautica_mobile/shared/utils/instagram_url.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:beautica_mobile/shared/widgets/expandable_note.dart';
import 'package:beautica_mobile/shared/widgets/portfolio_rail.dart';
import 'package:beautica_mobile/shared/widgets/rating_star.dart';
import 'package:beautica_mobile/shared/widgets/skeleton_shimmer.dart';

import 'widgets/master_address_block.dart';
import 'widgets/profile_avatar.dart';
import 'widgets/profile_scaffold.dart';
import 'widgets/service_category_cards.dart';
import 'widgets/services_stat_tile.dart';

/// CLIENT-facing read-only profile of the master identified by [masterId].
class PublicMasterProfileScreen extends ConsumerStatefulWidget {
  const PublicMasterProfileScreen({super.key, required this.masterId});

  /// Backend Master-row UUID of the profile being viewed.
  final String masterId;

  @override
  ConsumerState<PublicMasterProfileScreen> createState() =>
      _PublicMasterProfileScreenState();
}

class _PublicMasterProfileScreenState
    extends ConsumerState<PublicMasterProfileScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  // Pre-built staggered-entrance animations (one per reveal section) so build()
  // never allocates a CurvedAnimation/Tween per frame (mobile-perf pattern,
  // mirrors MasterProfileScreen). Six sections: identity / stats / bio /
  // portfolio / service categories / contacts.
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

  // Captured in initState so dispose() never touches `ref` (Riverpod 3.x throws
  // when `ref` is used after the widget is unmounted).
  late final ScreenProtectionManager _screenProtection;

  @override
  void initState() {
    super.initState();
    // SEC: this screen renders another master's address (PII) — guard against
    // app-switcher snapshots while it is mounted. The manager is ref-counted
    // and !kDebugMode-guarded internally. It does NOT block screenshots:
    // capture is allowed app-wide by product decision 2026-08-20, see the
    // header of `lib/core/security/screen_protection.dart`.
    //
    // INTENTIONAL PRODUCT DECISION (keep): retaining the acquire on the public
    // profile is deliberate — do NOT remove it in a future audit pass. The
    // owner reviewed it and chose to keep this screen inside the guard. (The
    // review predates the 2026-08-20 reversal, which narrowed WHAT the guard
    // does but did not touch any acquire/release call site.)
    _screenProtection = ref.read(screenProtectionProvider)..acquire();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
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
      curve: const Interval(0.40, 0.90, curve: Curves.easeOutCubic),
    );
    // Service categories — inserted between portfolio and contacts.
    _anim4 = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.45, 0.95, curve: Curves.easeOutCubic),
    );
    _anim5 = CurvedAnimation(
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
    _slide5 = Tween<Offset>(
      begin: slideBegin,
      end: Offset.zero,
    ).animate(_anim5);
  }

  @override
  void dispose() {
    _screenProtection.release();
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
    final AsyncValue<PublicMasterProfileData> async = ref.watch(
      publicMasterProfileProvider(widget.masterId),
    );

    return ProfileScaffold(
      title: l10n.publicMasterProfileTitle,
      trailing: _FavoriteToggleButton(masterId: widget.masterId),
      // The booking shelf is only meaningful once the master has resolved.
      bottomNavBar: async.maybeWhen(
        data: (_) => _BookingShelf(masterId: widget.masterId),
        orElse: () => null,
      ),
      child: async.when(
        loading: () => const _PublicProfileSkeleton(),
        error: (Object e, _) => ErrorState(
          failure: e is Failure ? e : UnknownFailure(cause: e),
          onRetry: () =>
              ref.invalidate(publicMasterProfileProvider(widget.masterId)),
        ),
        data: (PublicMasterProfileData data) {
          _startReveal();
          return _PublicProfileBody(
            masterId: widget.masterId,
            master: data.$1,
            services: data.$2,
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
// _PublicProfileBody — loaded state
// ---------------------------------------------------------------------------

class _PublicProfileBody extends StatelessWidget {
  const _PublicProfileBody({
    required this.masterId,
    required this.master,
    required this.services,
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

  /// Trusted route param (`widget.masterId`) — used for navigation instead of
  /// [master].id, which is a value round-tripped through the profile
  /// response and mapped by `MasterMapper`. See the reviews tile's `onTap`
  /// below.
  final String masterId;
  final Master master;

  /// The master's active services, loaded in parallel with [master] by
  /// [publicMasterProfileProvider]. Drives both the services stat tile
  /// (`.length`) and the read-only service-categories section below.
  final List<MasterService> services;

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
    final String displayName = '${master.firstName} ${master.lastName}'.trim();
    final String roleLabel = _roleLabel(master.type, l10n);
    final String? localityLine = buildLocalityLine(master.city);
    final String? streetLine = buildStreetLine(
      master.street,
      master.buildingNo,
    );
    // Phase 224 — the COLLAPSED one-line form of the same address. Which of
    // the two renderings ships is `MasterAddressBlock`'s measured decision.
    final String? combinedAddressLine = buildCombinedAddressLine(
      master.city,
      master.street,
      master.buildingNo,
    );
    // Phase 222 — sanitization now happens INSIDE `ExpandableNote` (it
    // must run on the exact same string the widget measures for overflow AND
    // renders — see that widget's class doc). Pre-sanitizing here too would
    // be a redundant no-op pass (sanitize is idempotent) that only obscures
    // which layer owns the invariant; kept single-sourced in the widget.
    final String? noteText = (master.locationNote?.isNotEmpty ?? false)
        ? master.locationNote
        : null;
    final bool hasReviews = master.reviewCount > 0;
    // Instagram + portfolio are an INDEPENDENT_MASTER-only affordance — a
    // salon-affiliated master's public profile hides both. This is a
    // client-side-only decision for THIS pair specifically: the backend's
    // `MasterDetailResponse.fromPublic` never masks `instagram` (it — like
    // `bio` — is returned unmasked for every `MasterType`). The backend DOES
    // null out `street` / `buildingNo` / `locationNote` / `cityId` /
    // `oblastId` / `districtId` for `SALON_MASTER` / `SALON_OWNER` — only
    // `INDEPENDENT_MASTER` receives those on this public path — so for the
    // ADDRESS fields (not instagram/bio) this screen's `isIndependent` gate
    // is redundant with, not a substitute for, an already-enforced backend
    // rule.
    final bool isIndependent = master.type == MasterType.independentMaster;
    final String? instagram =
        (isIndependent && (master.instagram?.isNotEmpty ?? false))
        ? master.instagram
        : null;
    final bool hasBio = master.bio != null && master.bio!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // 1 — Identity card.
        RevealTransition(
          key: const Key('public-master-profile-reveal-0'),
          fade: anim0,
          slide: slide0,
          child: NeumorphicCard(
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
                        key: const Key('public-master-profile-name'),
                        style: VelvetText.displayName(),
                        maxLines: 2,
                        softWrap: true,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: VelvetSpacing.xs + 2),
                      RoleChip(
                        key: (master.professionalTitle?.isNotEmpty == true)
                            ? const Key(
                                'public-master-profile-professional-title',
                              )
                            : null,
                        label: (master.professionalTitle?.isNotEmpty == true)
                            ? master.professionalTitle!
                            : roleLabel,
                        icon: Icons.auto_awesome_rounded,
                      ),
                      // Equivalent to the old `localityLine != null ||
                      // streetLine != null` gate (see the own-profile screen
                      // for why), and it promotes the local to non-nullable.
                      if (combinedAddressLine != null) ...<Widget>[
                        const SizedBox(height: VelvetSpacing.xs),
                        // Phase 220 (C) + Phase 224 — same address block as
                        // the own-profile screen: locality (city) first, then
                        // street + building, collapsed onto ONE row when the
                        // whole string fits, then the note. Composition lives
                        // in `shared/formatters/address_lines.dart`, the
                        // measure-and-choose in
                        // `widgets/master_address_block.dart`.
                        MasterAddressBlock(
                          keyPrefix: 'public-master-profile',
                          icon: const Icon(
                            Icons.location_on_outlined,
                            size: MasterAddressBlock.iconSize,
                            color: BrandColors.muted,
                          ),
                          localityLine: localityLine,
                          streetLine: streetLine,
                          combinedLine: combinedAddressLine,
                        ),
                        if (noteText != null) ...<Widget>[
                          const SizedBox(height: 2),
                          Padding(
                            padding: const EdgeInsets.only(left: 16),
                            child: ExpandableNote(
                              key: const Key(
                                'public-master-profile-location-note',
                              ),
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

        // 2 — Stats row: rating / services / reviews / experience.
        // Order of the three tiles shared with the personal MasterProfileScreen
        // (rating / services / reviews) mirrors that screen's stats row exactly
        // (Bookings / Rating / Services / Reviews there — Bookings has no public
        // equivalent so it is omitted, not reshuffled in). `experience` has no
        // personal-profile equivalent either; it is kept in its original
        // trailing slot rather than invented a position for it.
        // IntrinsicHeight equalises the four StatTiles to the tallest tile —
        // intentional and laid out ONCE per data render (not per frame). It
        // matches the sibling MasterProfileScreen and the approved design;
        // removing it would diverge from that locked pattern.
        RevealTransition(
          key: const Key('public-master-profile-reveal-1'),
          fade: anim1,
          slide: slide1,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(
                  // Tappable — mirrors the reviews tile below: pushes the
                  // same public reviews list for this master regardless of
                  // review count. Uses the trusted route param [masterId],
                  // not `master.id` from the network response.
                  child: GestureDetector(
                    key: const Key('public-master-profile-rating-tile'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () =>
                        context.push(RouteNames.masterPublicReviews(masterId)),
                    child: StatTile(
                      icon: Icons.star_rounded,
                      // `displayRating` folds all three "no rating yet" shapes
                      // (null average, a stale 0.0, zero reviews) onto null, so
                      // the star and the readout cannot disagree. [hasReviews]
                      // still governs the count tile below, where 0 is a true,
                      // renderable fact. See `MasterRatingX.displayRating`.
                      iconWidget: RatingStar(
                        rating: master.displayRating,
                        size: 18,
                        showLabel: false,
                      ),
                      value: master.displayRating?.toStringAsFixed(1) ?? '—',
                      caption: l10n.masterRatingLabel,
                      valueKey: const Key('public-master-profile-rating-value'),
                    ),
                  ),
                ),
                const SizedBox(width: VelvetSpacing.sm),
                Expanded(
                  child: ServicesStatTile(
                    count: services.length,
                    valueKey: const Key('public-master-profile-services-value'),
                  ),
                ),
                const SizedBox(width: VelvetSpacing.sm),
                Expanded(
                  // Tappable — pushes the public reviews list for this master
                  // ([RouteNames.masterPublicReviews]), mirroring the reviews
                  // tile on the master's own profile (`master-profile-reviews-tile`
                  // in `master_profile_screen.dart`).
                  child: GestureDetector(
                    key: const Key('public-master-profile-reviews-tile'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () =>
                        context.push(RouteNames.masterPublicReviews(masterId)),
                    child: StatTile(
                      icon: Icons.reviews_outlined,
                      value: hasReviews ? master.reviewCount.toString() : '—',
                      caption: l10n.masterStatsReviewsLabel,
                      valueKey: const Key(
                        'public-master-profile-reviews-value',
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: VelvetSpacing.sm),
                Expanded(
                  child: StatTile(
                    icon: Icons.workspace_premium_outlined,
                    // No tenure field on the domain model yet — show a dash.
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

        // 3 — Bio (omitted entirely when empty).
        if (hasBio) ...<Widget>[
          RevealTransition(
            key: const Key('public-master-profile-reveal-2'),
            fade: anim2,
            slide: slide2,
            child: Column(
              key: const Key('public-master-profile-bio'),
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
                    child: Text(master.bio!, style: VelvetText.bodyStrong()),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: VelvetSpacing.xl),
        ],

        // 4 — Portfolio rail (placeholder tiles until the gallery phase).
        // INDEPENDENT_MASTER only — hidden entirely for salon-affiliated
        // masters. REUSE-FIRST — [PortfolioRail] promoted to
        // shared/widgets/portfolio_rail.dart; no `onSeeAll` here (this
        // read-only view has no gallery route), matching prior behaviour.
        if (isIndependent)
          RevealTransition(
            key: const Key('public-master-profile-reveal-3'),
            fade: anim3,
            slide: slide3,
            child: const PortfolioRail(
              railKey: Key('public-master-profile-portfolio'),
            ),
          ),

        // 5 — Service categories: read-only for a client — mirrors the
        // master's own profile section, minus the owner-only navigation (see
        // the file header comment). Omitted entirely when the master has zero
        // active services, matching how Bio/Contacts are omitted when empty.
        if (services.isNotEmpty) ...<Widget>[
          const SizedBox(height: VelvetSpacing.xl),
          RevealTransition(
            key: const Key('public-master-profile-reveal-4'),
            fade: anim4,
            slide: slide4,
            child: Column(
              key: const Key('public-master-profile-service-categories'),
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
                  keyPrefix: 'public-master-profile-category',
                  interactive: false,
                ),
              ],
            ),
          ),
        ],

        // 6 — Contacts (Instagram only; omitted when not set).
        if (instagram != null) ...<Widget>[
          const SizedBox(height: VelvetSpacing.xl),
          RevealTransition(
            key: const Key('public-master-profile-reveal-5'),
            fade: anim5,
            slide: slide5,
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
                  key: const Key('public-master-contact-instagram'),
                  icon: Icons.alternate_email,
                  label: l10n.masterInstagramLabel,
                  value: instagram,
                  semanticLabel: l10n.masterInstagramLabel,
                  onTap: () => _openInstagram(context, instagram),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// Opens the master's Instagram in the Instagram app or a browser, sanitising
  /// [rawValue] through [canonicalInstagramUri] (STRICT https + host/charset
  /// allow-list) before launch — an unvalidated string is never handed to
  /// [launchUrl]. On a null result / launch failure a localized VelvetSnack shows.
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
          name: 'feature.master.public',
          level: 900,
          error: error,
        );
      }
    }
    if (!context.mounted) return;
    if (!launched) _showInstagramError(context);
  }

  /// This route is registered TOP-LEVEL, outside the CLIENT `StatefulShellRoute`
  /// (app_router.dart) — pushed full-screen OVER `ClientShell`, which replaces
  /// it entirely (the shared `ClientBottomNav` is not part of this route's
  /// tree at all). The screen's own bottom slot is `_BookingShelf`, a local
  /// per-screen CTA, not the shared nav bar the `bottomNavClearance*` constants
  /// exist to clear — so no `bottomInset` is needed here.
  static void _showInstagramError(BuildContext context) {
    showErrorSnack(
      context,
      AppLocalizations.of(context).masterInstagramOpenError,
    );
  }

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
// _FavoriteToggleButton — top-right heart bound to the favorite toggle notifier
// ---------------------------------------------------------------------------

/// A 48×48 raised neumorphic heart that flips the favourite flag for this
/// master via [favoriteToggleProvider] (targetType = MASTER). The icon pops on
/// toggle; the button depresses on press. On a failed toggle the notifier
/// reverts the optimistic flag and a localized VelvetSnack is shown.
class _FavoriteToggleButton extends ConsumerStatefulWidget {
  const _FavoriteToggleButton({required this.masterId});

  final String masterId;

  @override
  ConsumerState<_FavoriteToggleButton> createState() =>
      _FavoriteToggleButtonState();
}

class _FavoriteToggleButtonState extends ConsumerState<_FavoriteToggleButton> {
  bool _pressed = false;

  FavoriteTarget get _target =>
      FavoriteTarget(type: FavoriteTargetType.master, id: widget.masterId);

  Future<void> _onTap() async {
    setState(() => _pressed = false);
    final Failure? failure = await ref
        .read(favoriteToggleProvider.notifier)
        .toggle(_target);
    // See `_showInstagramError`'s doc above — this top-level route sits over
    // `ClientShell`, not inside it, so no `bottomInset` is needed here either.
    if (failure != null && mounted) {
      showErrorSnack(context, failure.userMessage(context));
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final FavoriteTarget target = _target;
    final bool isFavorite = ref.watch(
      favoriteToggleProvider.select(
        (Map<FavoriteTarget, FavoriteEntry> m) =>
            m[target]?.isFavorite ?? false,
      ),
    );

    return Semantics(
      button: true,
      toggled: isFavorite,
      label: isFavorite ? l10n.favoriteRemoveLabel : l10n.favoriteAddLabel,
      child: GestureDetector(
        key: const Key('public-master-favorite-toggle'),
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => _onTap(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 48,
          width: 48,
          decoration: BoxDecoration(
            color: BrandColors.base,
            borderRadius: _heartRadius,
            boxShadow: _pressed ? null : VelvetShadows.extrudedSmall,
          ),
          child: Center(
            child: AnimatedScale(
              scale: isFavorite ? 1.12 : 1,
              duration: const Duration(milliseconds: 220),
              curve: Curves.elasticOut,
              child: Icon(
                isFavorite
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                size: 22,
                color: isFavorite ? BrandColors.accent : BrandColors.muted,
              ),
            ),
          ),
        ),
      ),
    );
  }

  static const BorderRadius _heartRadius = BorderRadius.all(
    Radius.circular(VelvetRadii.field),
  );
}

// ---------------------------------------------------------------------------
// _BookingShelf — pinned camel-wash booking shelf (CTA only)
// ---------------------------------------------------------------------------

/// The pinned bottom booking shelf. On the profile it holds a single child: the
/// camel «Записатись до майстра» CTA — no section label. Tapping the CTA
/// opens the Phase 14.1 booking flow ([RouteNames.bookingNew]) carrying the
/// target master id in `extra`. Actual service selection lives in 14.1.
class _BookingShelf extends StatelessWidget {
  const _BookingShelf({required this.masterId});

  final String masterId;

  /// Camel-wash surface (a few steps off the page base) so the shelf reads as
  /// its own elevated sheet rising from the bottom.
  static const Color _shelfSurface = Color(0xFFEDE4D5);

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: _shelfSurface,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(VelvetRadii.card),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: BrandColors.shadowDarkCard,
            offset: Offset(0, -9),
            blurRadius: 24,
          ),
          BoxShadow(
            color: BrandColors.shadowLightStrong,
            offset: Offset(0, -1),
            blurRadius: 3,
            spreadRadius: -1,
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            VelvetSpacing.lg,
            VelvetSpacing.lg,
            VelvetSpacing.lg,
            VelvetSpacing.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              NeumorphicButton(
                key: const Key('public-master-book-cta'),
                label: l10n.publicMasterBookingCta,
                icon: Icons.add_rounded,
                onPressed: () =>
                    context.push(RouteNames.bookingNew, extra: masterId),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _PublicProfileSkeleton — loading state
// ---------------------------------------------------------------------------

class _PublicProfileSkeleton extends StatelessWidget {
  const _PublicProfileSkeleton();

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
                      SizedBox(height: VelvetSpacing.xs),
                      SkeletonBlock(width: 160, height: 10),
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
