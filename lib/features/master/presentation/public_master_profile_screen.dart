// Phase 13.5 — Public master profile (CLIENT-facing, read-only).
//
// The client's view of an INDEPENDENT_MASTER, reached by tapping a search /
// favourites result card. Same depth language as the master's own profile
// (`MasterProfileScreen`) but:
//   • NO edit button — the top-right action is a favourite (heart) toggle;
//   • NO read-only body services-list — the services count feeds the stats row;
//   • contacts = Instagram only (no phone/dialer tile);
//   • a pinned camel-wash booking shelf («Послуги та ціни») rendering the empty
//     state — the «Записатись до майстра» CTA opens the Phase 14.1 booking
//     flow (placeholder route until 14.1 ships).
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
import 'package:beautica_mobile/features/favorites/application/favorite_toggle_notifier.dart';
import 'package:beautica_mobile/features/favorites/domain/favorite_target.dart';
import 'package:beautica_mobile/features/master/application/public_master_profile_notifier.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/utils/instagram_url.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:beautica_mobile/shared/widgets/rating_star.dart';
import 'package:beautica_mobile/shared/widgets/skeleton_shimmer.dart';

import 'widgets/profile_avatar.dart';
import 'widgets/profile_scaffold.dart';

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
  // mirrors MasterProfileScreen). Five sections: identity / stats / bio /
  // portfolio / contacts.
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

  // Captured in initState so dispose() never touches `ref` (Riverpod 3.x throws
  // when `ref` is used after the widget is unmounted).
  late final ScreenProtectionManager _screenProtection;

  @override
  void initState() {
    super.initState();
    // SEC: this screen renders another master's address (PII) — guard against
    // screenshots / app-switcher snapshots while it is mounted. The manager is
    // ref-counted and !kDebugMode-guarded internally.
    //
    // INTENTIONAL PRODUCT DECISION (keep): the FLAG_SECURE screenshot guard on
    // the public profile is deliberate — do NOT remove it in a future audit pass.
    // The owner reviewed it and chose to retain the protection on this screen.
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
            serviceCount: data.$2.length,
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
// _PublicProfileBody — loaded state
// ---------------------------------------------------------------------------

class _PublicProfileBody extends StatelessWidget {
  const _PublicProfileBody({
    required this.masterId,
    required this.master,
    required this.serviceCount,
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

  /// Trusted route param (`widget.masterId`) — used for navigation instead of
  /// [master].id, which is a value round-tripped through the profile
  /// response and mapped by `MasterMapper`. See the reviews tile's `onTap`
  /// below.
  final String masterId;
  final Master master;
  final int serviceCount;

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
    final String roleLabel = _roleLabel(master.type, l10n);
    final String? locationLine = _buildLocationLine(master);
    final String? noteText = (master.locationNote?.isNotEmpty ?? false)
        ? master.locationNote
        : null;
    final bool hasReviews = master.reviewCount > 0;
    // Instagram + portfolio are an INDEPENDENT_MASTER-only affordance — a
    // salon-affiliated master's public profile hides both, mirroring the
    // backend's `MasterDetailResponse.fromPublic` address-masking rule for the
    // same `MasterType` distinction. Purely a display decision: the payload
    // still carries the raw fields for every type.
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
                      if (locationLine != null) ...<Widget>[
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
                                locationLine,
                                key: const Key(
                                  'public-master-profile-address-text',
                                ),
                                style: VelvetText.feedbackMutedXs,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        if (noteText != null) ...<Widget>[
                          const SizedBox(height: 2),
                          Padding(
                            padding: const EdgeInsets.only(left: 16),
                            child: Text(
                              noteText,
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
                      rating: hasReviews ? master.avgRating : null,
                      size: 18,
                      showLabel: false,
                    ),
                    value: hasReviews
                        ? master.avgRating.toStringAsFixed(1)
                        : '—',
                    caption: l10n.masterRatingLabel,
                    valueKey: const Key('public-master-profile-rating-value'),
                  ),
                ),
                const SizedBox(width: VelvetSpacing.sm),
                Expanded(
                  child: StatTile(
                    icon: Icons.design_services_outlined,
                    value: serviceCount.toString(),
                    caption: l10n.masterServicesLabel,
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
          _reveal(
            anim2,
            slide2,
            Column(
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
        // INDEPENDENT_MASTER only — hidden entirely for salon-affiliated masters.
        if (isIndependent)
          _reveal(
            anim3,
            slide3,
            Column(
              key: const Key('public-master-profile-portfolio'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(
                    left: 4,
                    bottom: VelvetSpacing.xs,
                  ),
                  child: Text(
                    l10n.masterPortfolioLabel,
                    style: VelvetText.sectionLabel(),
                  ),
                ),
                SizedBox(
                  height: 72,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    padding: EdgeInsets.zero,
                    child: Row(
                      children: <Widget>[
                        for (int i = 0; i < 6; i++) ...<Widget>[
                          _PortfolioTile(index: i),
                          if (i < 5) const SizedBox(width: VelvetSpacing.md),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

        // 5 — Contacts (Instagram only; omitted when not set).
        if (instagram != null) ...<Widget>[
          const SizedBox(height: VelvetSpacing.xl),
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
  /// [launchUrl]. On a null result / launch failure a localized SnackBar shows.
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

  static void _showInstagramError(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context).masterInstagramOpenError),
      ),
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

  /// Composes the identity-card address line (street + buildingNo + city), or
  /// `null` when nothing is available so the caller hides the row.
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
        buf
          ..write(', ')
          ..write(building);
      }
      if (city != null) {
        buf
          ..write(', ')
          ..write(city);
      }
    } else {
      buf.write(city);
    }
    return buf.toString();
  }
}

// ---------------------------------------------------------------------------
// _FavoriteToggleButton — top-right heart bound to the favorite toggle notifier
// ---------------------------------------------------------------------------

/// A 48×48 raised neumorphic heart that flips the favourite flag for this
/// master via [favoriteToggleProvider] (targetType = MASTER). The icon pops on
/// toggle; the button depresses on press. On a failed toggle the notifier
/// reverts the optimistic flag and a localized SnackBar is shown.
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
    if (failure != null && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failure.userMessage(context))));
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
// _BookingShelf — pinned camel-wash «Послуги та ціни» booking shelf (empty state)
// ---------------------------------------------------------------------------

/// The pinned bottom booking shelf. On the profile it renders the EMPTY state:
/// a section label above a camel «Записатись до майстра» CTA. Tapping the CTA
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
              Padding(
                padding: const EdgeInsets.only(bottom: VelvetSpacing.sm),
                child: Text(
                  l10n.publicMasterBookingSectionLabel,
                  style: VelvetText.sectionLabel(),
                ),
              ),
              const SizedBox(height: VelvetSpacing.md),
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
// _PortfolioTile — raised gradient placeholder thumbnail (real photos: later)
// ---------------------------------------------------------------------------

class _PortfolioTile extends StatefulWidget {
  const _PortfolioTile({required this.index});

  final int index;

  @override
  State<_PortfolioTile> createState() => _PortfolioTileState();
}

class _PortfolioTileState extends State<_PortfolioTile> {
  bool _pressed = false;

  // Hoisted so the glyph tint is allocated once for the class, not per build()
  // (this State rebuilds on every press) — mobile-perf MP pattern.
  static final Color _photoGlyph = BrandColors.white.withValues(alpha: 0.65);

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
            child: Icon(Icons.photo_outlined, color: _photoGlyph, size: 22),
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
