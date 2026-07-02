// Phase 13.6 — Public Salon Profile (CLIENT-facing, read-only).
//
// The client's view of a salon, reached by tapping a search-result card. The
// salon sibling of the Public Master Profile (Phase 13.5): same depth
// language and widget vocabulary, but a distinct layout — a full-bleed cover
// photo with an overlapping hero card, a 4-tab switcher (Про салон / Майстри
// / Послуги / Відгуки), and a pinned "Записатись на послугу" CTA — ported
// verbatim from the approved preview at
// `docs/signup-designs/PublicSalonProfile/lib/screens/public_salon_profile_screen.dart`.
//
// Data sources (each its own AsyncValue so one tab's failure never blanks the
// others):
//   • [publicSalonProfileProvider] — salon detail + masters rail (hero card +
//     "Майстри" tab), loaded in parallel.
//   • [salonServiceCatalogProvider] — "Послуги" tab.
//   • [salonReviewSummaryProvider] + [salonReviewsProvider] — "Відгуки" tab
//     (each independent so changing the sort never re-fetches the summary).
//
// The cover + favourite heart render even while the hero data is still
// loading (the favourite toggle only needs [salonId], not the resolved
// salon), mirroring the master profile's "top-bar action available before
// data resolves" pattern.

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
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/utils/instagram_url.dart';
import 'package:beautica_mobile/shared/widgets/contact_tile.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:beautica_mobile/shared/widgets/skeleton_shimmer.dart';

import '../application/public_salon_profile_notifier.dart';
import '../application/salon_portfolio_notifier.dart';
import '../application/salon_service_catalog_notifier.dart';
import '../domain/salon.dart';
import '../domain/salon_master_summary.dart';
import '../domain/salon_portfolio_photo.dart';
import '../domain/salon_service_catalog.dart';
import 'widgets/salon_cover_widgets.dart';
import 'widgets/salon_master_card.dart';
import 'widgets/salon_reviews_section.dart';
import 'widgets/salon_services_accordion.dart';

/// CLIENT-facing read-only profile of the salon identified by [salonId].
class PublicSalonProfileScreen extends ConsumerStatefulWidget {
  const PublicSalonProfileScreen({super.key, required this.salonId});

  /// Backend Salon-row UUID of the profile being viewed.
  final String salonId;

  @override
  ConsumerState<PublicSalonProfileScreen> createState() =>
      _PublicSalonProfileScreenState();
}

class _PublicSalonProfileScreenState
    extends ConsumerState<PublicSalonProfileScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  // Pre-built staggered-entrance animations so build() never allocates a
  // CurvedAnimation/Tween per frame (mobile-perf pattern, mirrors
  // PublicMasterProfileScreen). Three sections: cover+hero / tab bar / tab body.
  late final CurvedAnimation _anim0;
  late final CurvedAnimation _anim1;
  late final CurvedAnimation _anim2;
  late final Animation<Offset> _slide0;
  late final Animation<Offset> _slide1;
  late final Animation<Offset> _slide2;

  // Captured in initState so dispose() never touches `ref`.
  late final ScreenProtectionManager _screenProtection;

  /// Active section tab (0 = Про салон).
  int _tab = 0;

  static const double _coverHeight = 232;
  static const double _heroProtrusion = 116;

  @override
  void initState() {
    super.initState();
    // SEC: this screen renders the salon's address (PII) — guard against
    // screenshots / app-switcher snapshots while it is mounted. Mirrors the
    // INTENTIONAL PRODUCT DECISION on PublicMasterProfileScreen — do not
    // remove in a future audit pass.
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
      curve: const Interval(0.18, 0.64, curve: Curves.easeOutCubic),
    );
    _anim2 = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.30, 1.0, curve: Curves.easeOutCubic),
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
  }

  @override
  void dispose() {
    _screenProtection.release();
    _anim0.dispose();
    _anim1.dispose();
    _anim2.dispose();
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
    final AsyncValue<PublicSalonProfileData> async = ref.watch(
      publicSalonProfileProvider(widget.salonId),
    );
    final double topInset = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: BrandColors.base,
      bottomNavigationBar: async.maybeWhen(
        data: (PublicSalonProfileData data) => _BookingShelf(salon: data.$1),
        orElse: () => null,
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.only(bottom: VelvetSpacing.xxl),
        child: async.when(
          loading: () => _LoadingBody(
            salonId: widget.salonId,
            topInset: topInset,
            coverHeight: _coverHeight,
            heroProtrusion: _heroProtrusion,
          ),
          error: (Object e, _) => _ErrorBody(
            salonId: widget.salonId,
            topInset: topInset,
            failure: e is Failure ? e : UnknownFailure(cause: e),
            onRetry: () =>
                ref.invalidate(publicSalonProfileProvider(widget.salonId)),
          ),
          data: (PublicSalonProfileData data) {
            _startReveal();
            return _LoadedBody(
              salonId: widget.salonId,
              salon: data.$1,
              masters: data.$2,
              topInset: topInset,
              coverHeight: _coverHeight,
              heroProtrusion: _heroProtrusion,
              tab: _tab,
              onTabSelected: (int i) => setState(() => _tab = i),
              anim0: _anim0,
              anim1: _anim1,
              anim2: _anim2,
              slide0: _slide0,
              slide1: _slide1,
              slide2: _slide2,
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _LoadingBody — cover skeleton + favourite/back controls (already usable)
// ---------------------------------------------------------------------------

class _LoadingBody extends StatelessWidget {
  const _LoadingBody({
    required this.salonId,
    required this.topInset,
    required this.coverHeight,
    required this.heroProtrusion,
  });

  final String salonId;
  final double topInset;
  final double coverHeight;
  final double heroProtrusion;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Stack(
          children: <Widget>[
            Padding(
              padding: EdgeInsets.only(bottom: heroProtrusion),
              child: SalonCover(height: coverHeight, topInset: topInset),
            ),
            Positioned(
              top: topInset + VelvetSpacing.sm,
              left: VelvetSpacing.lg,
              child: const _BackButton(),
            ),
            Positioned(
              top: topInset + VelvetSpacing.sm,
              right: VelvetSpacing.lg,
              child: _FavoriteToggleButton(salonId: salonId),
            ),
            Positioned(
              left: VelvetSpacing.lg,
              right: VelvetSpacing.lg,
              bottom: 0,
              child: SkeletonShimmerScope(
                child: SkeletonBlock(
                  width: double.infinity,
                  height: heroProtrusion,
                  radius: VelvetRadii.card,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: VelvetSpacing.lg),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: VelvetSpacing.lg),
          child: SkeletonShimmerScope(
            child: SkeletonBlock(width: double.infinity, height: 44),
          ),
        ),
        const SizedBox(height: VelvetSpacing.lg),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: VelvetSpacing.lg),
          child: SkeletonShimmerScope(
            child: SkeletonBlock(
              width: double.infinity,
              height: 220,
              radius: VelvetRadii.card,
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// _ErrorBody — back control + centred ErrorState
// ---------------------------------------------------------------------------

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({
    required this.salonId,
    required this.topInset,
    required this.failure,
    required this.onRetry,
  });

  final String salonId;
  final double topInset;
  final Failure failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: EdgeInsets.only(
            top: topInset + VelvetSpacing.sm,
            left: VelvetSpacing.lg,
          ),
          child: const Align(
            alignment: Alignment.topLeft,
            child: _BackButton(),
          ),
        ),
        const SizedBox(height: VelvetSpacing.xl),
        ErrorState(failure: failure, onRetry: onRetry),
      ],
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton();

  @override
  Widget build(BuildContext context) {
    return CoverIconButton(
      key: const Key('salon-profile-back'),
      icon: Icons.arrow_back_ios_new_rounded,
      semanticLabel: AppLocalizations.of(context).salonProfileBackLabel,
      onTap: () => context.pop(),
    );
  }
}

// ---------------------------------------------------------------------------
// _LoadedBody — cover + hero + tab bar + tab body
// ---------------------------------------------------------------------------

class _LoadedBody extends StatelessWidget {
  const _LoadedBody({
    required this.salonId,
    required this.salon,
    required this.masters,
    required this.topInset,
    required this.coverHeight,
    required this.heroProtrusion,
    required this.tab,
    required this.onTabSelected,
    required this.anim0,
    required this.anim1,
    required this.anim2,
    required this.slide0,
    required this.slide1,
    required this.slide2,
  });

  final String salonId;
  final Salon salon;
  final List<SalonMasterSummary> masters;
  final double topInset;
  final double coverHeight;
  final double heroProtrusion;
  final int tab;
  final ValueChanged<int> onTabSelected;

  final Animation<double> anim0;
  final Animation<double> anim1;
  final Animation<double> anim2;
  final Animation<Offset> slide0;
  final Animation<Offset> slide1;
  final Animation<Offset> slide2;

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
    final l10n = AppLocalizations.of(context);
    final List<String> tabs = <String>[
      l10n.salonTabAbout,
      l10n.salonTabMasters,
      l10n.salonTabServices,
      l10n.salonTabReviews,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _CoverAndHero(
          coverHeight: coverHeight,
          heroProtrusion: heroProtrusion,
          topInset: topInset,
          salon: salon,
          reveal: _reveal,
          anim0: anim0,
          slide0: slide0,
        ),
        const SizedBox(height: VelvetSpacing.lg),
        _reveal(
          anim1,
          slide1,
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: VelvetSpacing.lg),
            child: SalonTabBar(
              tabs: tabs,
              selected: tab,
              onSelect: onTabSelected,
            ),
          ),
        ),
        const SizedBox(height: VelvetSpacing.lg),
        _reveal(
          anim2,
          slide2,
          KeyedSubtree(
            key: ValueKey<String>('salon-tab-body-${_tabKeys[tab]}'),
            child: switch (tab) {
              0 => _AboutTab(salon: salon),
              1 => _MastersTab(masters: masters),
              2 => _ServicesTab(salonId: salonId),
              _ => SalonReviewsSection(salonId: salonId),
            },
          ),
        ),
      ],
    );
  }

  static const List<String> _tabKeys = <String>[
    'about',
    'masters',
    'services',
    'reviews',
  ];
}

/// The cover photo + overlapping hero card region.
class _CoverAndHero extends StatelessWidget {
  const _CoverAndHero({
    required this.coverHeight,
    required this.heroProtrusion,
    required this.topInset,
    required this.salon,
    required this.reveal,
    required this.anim0,
    required this.slide0,
  });

  final double coverHeight;
  final double heroProtrusion;
  final double topInset;
  final Salon salon;
  final Widget Function(Animation<double>, Animation<Offset>, Widget) reveal;
  final Animation<double> anim0;
  final Animation<Offset> slide0;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        Padding(
          padding: EdgeInsets.only(bottom: heroProtrusion),
          child: SalonCover(
            height: coverHeight,
            topInset: topInset,
            imageUrl: salon.coverImageUrl,
          ),
        ),
        Positioned(
          top: topInset + VelvetSpacing.sm,
          left: VelvetSpacing.lg,
          child: const _BackButton(),
        ),
        Positioned(
          top: topInset + VelvetSpacing.sm,
          right: VelvetSpacing.lg,
          child: _FavoriteToggleButton(salonId: salon.id),
        ),
        Positioned(
          left: VelvetSpacing.lg,
          right: VelvetSpacing.lg,
          bottom: 0,
          child: reveal(anim0, slide0, _SalonHeroCard(salon: salon)),
        ),
      ],
    );
  }
}

/// The overlapping identity card: logo monogram + name + a ★ rating ·
/// review count row, with the locality/address sub-line tightly stacked
/// beneath it on its own row.
class _SalonHeroCard extends StatelessWidget {
  const _SalonHeroCard({required this.salon});

  final Salon salon;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final String? monogram = salon.name.trim().isEmpty
        ? null
        : salon.name.trim()[0].toUpperCase();
    final String ratingLabel = salon.avgRating?.toStringAsFixed(1) ?? '—';
    final String? locationLine = _buildLocationLine(salon);

    return NeumorphicCard(
      key: const Key('salon-profile-hero-card'),
      color: const Color(0xFFEDE4D5),
      padding: const EdgeInsets.all(VelvetSpacing.md + 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              SalonLogo(diameter: 68, monogram: monogram),
              const SizedBox(width: VelvetSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      salon.name,
                      key: const Key('salon-profile-name'),
                      style: VelvetText.displayName().copyWith(fontSize: 20),
                      maxLines: 2,
                      softWrap: true,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 5),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const Icon(
                          Icons.star_rounded,
                          size: 16,
                          color: BrandColors.accentDeep,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          ratingLabel,
                          key: const Key('salon-profile-rating'),
                          style: _ratingInlineStyle,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            '·  ${l10n.salonReviewCountLabel(salon.reviewCount)}',
                            style: VelvetText.feedback(
                              BrandColors.muted,
                            ).copyWith(fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (locationLine != null) ...<Widget>[
            // Tight gap (matches the name→rating spacing above) rather than
            // the old VelvetSpacing.md (16px): the location line is a
            // tightly-coupled continuation of the rating row, not a loosely
            // separated address section (mobile-debugger fix — restores the
            // hero card's natural height past `_heroProtrusion`'s 116px
            // budget so it protrudes into the cover again).
            const SizedBox(height: 5),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Padding(
                  padding: EdgeInsets.only(top: 1),
                  child: Icon(
                    Icons.location_on_outlined,
                    size: 15,
                    color: BrandColors.accentDeep,
                  ),
                ),
                const SizedBox(width: VelvetSpacing.xs + 1),
                Expanded(
                  child: Text(
                    locationLine,
                    key: const Key('salon-profile-address-text'),
                    style: VelvetText.feedback(
                      BrandColors.textSecondary,
                    ).copyWith(fontSize: 13),
                    // Defensive cap (mobile-debugger fix): a pathologically
                    // long street/buildingNo/locationNote combination must
                    // not be allowed to keep growing the hero card's height
                    // unbounded — that's what let it blow past
                    // `_heroProtrusion`'s budget and overlap the cover's
                    // controls in the first place.
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static final TextStyle _ratingInlineStyle = VelvetText.bodyStrong().copyWith(
    fontSize: 14,
  );

  /// Composes the hero card's locality/address line, or `null` when nothing
  /// is available so the caller hides the row.
  ///
  /// Prefers the structured taxonomy fields (`street` / `buildingNo` /
  /// `locationNote`, Phase 10.6+) over the legacy free-text `city`/`address`
  /// pair — the backend stopped writing the legacy fields once a salon
  /// re-saves its location under the taxonomy, so relying on them alone would
  /// blank the row for every salon created/edited since then (mobile-side fix
  /// for `PublicSalonResponse` commit `ef96845`).
  ///
  /// Unlike [Master]'s identity card, this never resolves `cityId` to a
  /// human-readable name: [Salon] carries no `oblastId`, and
  /// `LocationRepository.fetchCities` requires one to list cities — so a raw
  /// `cityId` alone cannot be looked up client-side. The taxonomy branch
  /// below therefore renders only the parts that already arrive as plain
  /// text (`street`/`buildingNo`/`locationNote`).
  ///
  /// Falls back to the legacy `city`/`address` pair only when none of the
  /// taxonomy fields are set (a salon that predates Phase 10.6, or has never
  /// been re-saved since).
  static String? _buildLocationLine(Salon salon) {
    final String? street = (salon.street?.isNotEmpty ?? false)
        ? salon.street
        : null;
    final String? buildingNo = (salon.buildingNo?.isNotEmpty ?? false)
        ? salon.buildingNo
        : null;
    final String? locationNote = (salon.locationNote?.isNotEmpty ?? false)
        ? salon.locationNote
        : null;

    if (street != null) {
      final StringBuffer buf = StringBuffer(street);
      if (buildingNo != null) {
        buf
          ..write(', ')
          ..write(buildingNo);
      }
      if (locationNote != null) {
        buf
          ..write(', ')
          ..write(locationNote);
      }
      return buf.toString();
    }

    final String? city = (salon.city?.isNotEmpty ?? false) ? salon.city : null;
    final String? address = (salon.address?.isNotEmpty ?? false)
        ? salon.address
        : null;
    if (city == null && address == null) return null;
    if (address != null && city != null) return '$city, $address';
    return address ?? city;
  }
}

// ---------------------------------------------------------------------------
// _AboutTab — "Про салон": blurb + optional Instagram contact
// ---------------------------------------------------------------------------

class _AboutTab extends StatelessWidget {
  const _AboutTab({required this.salon});

  final Salon salon;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final String? description = (salon.description?.trim().isNotEmpty ?? false)
        ? salon.description!.trim()
        : null;
    final String? instagram = (salon.instagramUrl?.isNotEmpty ?? false)
        ? salon.instagramUrl
        : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: VelvetSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            description ?? l10n.salonAboutEmpty,
            key: const Key('salon-about-text'),
            style: description == null
                ? VelvetText.feedback(BrandColors.muted)
                : VelvetText.bodyStrong(),
          ),
          _SalonPortfolioRail(salonId: salon.id),
          if (instagram != null) ...<Widget>[
            const SizedBox(height: VelvetSpacing.xl),
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: VelvetSpacing.xs),
              child: Text(
                l10n.masterContactsLabel,
                style: VelvetText.sectionLabel(),
              ),
            ),
            ContactTile(
              key: const Key('salon-contact-instagram'),
              icon: Icons.alternate_email,
              label: l10n.masterInstagramLabel,
              value: instagram,
              semanticLabel: l10n.masterInstagramLabel,
              onTap: () => _openInstagram(context, instagram),
            ),
          ],
        ],
      ),
    );
  }

  /// Opens the salon's Instagram, sanitising [rawValue] through
  /// [canonicalInstagramUri] (STRICT https + host/charset allow-list) before
  /// launch — mirrors [PublicMasterProfileScreen]'s identical guard.
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
          name: 'feature.salon.public',
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
}

// ---------------------------------------------------------------------------
// _SalonPortfolioRail — "Про салон" tab: real photo rail (Phase 13.6
// follow-up — GET /salons/{salonId}/portfolio, previously unwired).
// ---------------------------------------------------------------------------

/// Loads and renders the salon's real portfolio photo rail. Own independent
/// [AsyncValue] (mirrors [_ServicesTab]/[SalonReviewsSection]) so a broken
/// gallery read never blanks the description/Instagram sections around it.
///
/// Renders NOTHING — no heading, no empty rail, no error chrome — whenever
/// the salon has zero photos, the read is still loading, or the read fails:
/// this is fully optional chrome on top of the description, the same way the
/// hero card's location line hides entirely when absent (see
/// [_SalonHeroCard._buildLocationLine]).
/// How many portfolio photos render up front before the "show all"
/// affordance is needed (mobile-perf MEDIUM fix, mirrors
/// [kSalonMastersInitialCount]'s "show all" precedent exactly). The rail
/// sits in a plain `Row` inside a `SingleChildScrollView` (not lazy — no
/// viewport culling), and `getSalonPortfolio` carries no `page`/`size`
/// contract to bound the fetch itself the way `getSalonMasters`/
/// `getSalonReviews` do — so every returned photo would otherwise fire its
/// `Image.network` request simultaneously on first paint regardless of how
/// large the salon's full gallery is. Capping the initial render bounds that
/// burst; the rest builds only once the user explicitly asks for them.
const int kSalonPortfolioInitialCount = 8;

class _SalonPortfolioRail extends ConsumerStatefulWidget {
  const _SalonPortfolioRail({required this.salonId});

  final String salonId;

  @override
  ConsumerState<_SalonPortfolioRail> createState() =>
      _SalonPortfolioRailState();
}

class _SalonPortfolioRailState extends ConsumerState<_SalonPortfolioRail> {
  // Flips true once the user explicitly taps "show all" — mirrors
  // [_MastersTabState._showAll] exactly: a one-time, user-triggered build of
  // the remainder is an acceptable cost; only the unconditional first-paint
  // build is guarded against.
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<SalonPortfolioPhoto>> async = ref.watch(
      salonPortfolioProvider(widget.salonId),
    );
    return async.when(
      data: (List<SalonPortfolioPhoto> photos) =>
          photos.isEmpty ? const SizedBox.shrink() : _rail(context, photos),
      loading: () => const SizedBox.shrink(),
      error: (Object e, StackTrace st) {
        if (kDebugMode) {
          log(
            'salon portfolio load failed — hiding the optional rail',
            name: 'feature.salon.public',
            level: 900,
            error: e,
            stackTrace: st,
          );
        }
        return const SizedBox.shrink();
      },
    );
  }

  Widget _rail(BuildContext context, List<SalonPortfolioPhoto> photos) {
    final l10n = AppLocalizations.of(context);
    final bool hasMore = photos.length > kSalonPortfolioInitialCount;
    final List<SalonPortfolioPhoto> visible = hasMore && !_showAll
        ? photos.sublist(0, kSalonPortfolioInitialCount)
        : photos;

    return Column(
      key: const Key('salon-about-portfolio'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: VelvetSpacing.xl),
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: VelvetSpacing.xs),
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
                for (int i = 0; i < visible.length; i++) ...<Widget>[
                  _SalonPortfolioTile(photo: visible[i], index: i),
                  if (i < visible.length - 1 || (hasMore && !_showAll))
                    const SizedBox(width: VelvetSpacing.md),
                ],
                if (hasMore && !_showAll)
                  _ShowAllPortfolioTile(
                    remaining: photos.length - kSalonPortfolioInitialCount,
                    onTap: () => setState(() => _showAll = true),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A trailing 72dp tile appended to the portfolio rail whenever the gallery
/// exceeds [kSalonPortfolioInitialCount], showing the remaining count.
/// Tapping it reveals the rest of the gallery in place — the horizontal-rail
/// equivalent of [_ShowAllMastersButton] below (same reveal-on-tap contract,
/// different shell: an inline tile rather than a full-width button, to match
/// this rail's tile-row vocabulary).
class _ShowAllPortfolioTile extends StatelessWidget {
  const _ShowAllPortfolioTile({required this.remaining, required this.onTap});

  final int remaining;
  final VoidCallback onTap;

  static const double _size = 72;
  static const BorderRadius _radius = BorderRadius.all(
    Radius.circular(VelvetRadii.field),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      button: true,
      label: l10n.salonPortfolioShowAll,
      child: GestureDetector(
        key: const Key('salon-portfolio-show-all'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          height: _size,
          width: _size,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              color: BrandColors.faint,
              borderRadius: _radius,
              boxShadow: VelvetShadows.extrudedSmall,
            ),
            child: Center(
              child: Text('+$remaining', style: VelvetText.bodyStrong()),
            ),
          ),
        ),
      ),
    );
  }
}

/// One 72dp real-photo thumbnail in the salon's portfolio rail. Reuses the
/// sibling [PublicMasterProfileScreen]'s `_PortfolioTile` visual shell (72dp
/// square, [VelvetRadii.field] corner, [VelvetShadows.extrudedSmall] raised
/// shadow) but backs it with a real [Image.network] instead of a gradient
/// placeholder — mirroring [ResultThumbnail]'s exact network-image
/// convention (`discovery/presentation/widgets/result_thumbnail.dart`):
/// https-only scheme guard, decode-resolution-capped `cacheWidth`, and an
/// [errorBuilder] fallback tile on load failure. Deliberately no
/// `loadingBuilder`/shimmer — [SkeletonShimmerScope]'s [AnimationController]
/// repeats forever once mounted (it has no "stop when idle" state), so
/// wrapping this ALWAYS-VISIBLE rail in one would leave a perpetual ticker
/// running for the rail's entire lifetime, not just while an image is
/// actually loading — the same reason [ResultThumbnail] never uses a shimmer
/// either.
class _SalonPortfolioTile extends StatelessWidget {
  const _SalonPortfolioTile({required this.photo, required this.index});

  final SalonPortfolioPhoto photo;
  final int index;

  static const double _size = 72;
  static const BorderRadius _radius = BorderRadius.all(
    Radius.circular(VelvetRadii.field),
  );

  @override
  Widget build(BuildContext context) {
    // Image.network uses its own HttpClient (not the pinned Dio), so guard the
    // scheme here: only https is allowed — mirrors [ResultThumbnail]'s SEC
    // guard against a malicious/compromised `http://` photo URL leaking the
    // client IP if ATS/NSC is ever relaxed.
    final bool isHttps = Uri.tryParse(photo.url)?.scheme == 'https';
    final Widget tile = !isHttps
        ? _errorTile()
        : ClipRRect(
            borderRadius: _radius,
            child: Image.network(
              photo.url,
              fit: BoxFit.cover,
              cacheWidth: (_size * MediaQuery.devicePixelRatioOf(context))
                  .round(),
              errorBuilder: (_, _, _) => _errorTile(),
            ),
          );

    return Semantics(
      label: AppLocalizations.of(
        context,
      ).masterPortfolioTileSemantics(index + 1),
      image: true,
      child: SizedBox(
        key: Key('salon-portfolio-photo-${photo.id}'),
        height: _size,
        width: _size,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            borderRadius: _radius,
            boxShadow: VelvetShadows.extrudedSmall,
          ),
          child: tile,
        ),
      ),
    );
  }

  Widget _errorTile() {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: BrandColors.faint,
        borderRadius: _radius,
      ),
      child: Center(
        child: Icon(
          Icons.broken_image_outlined,
          color: BrandColors.white.withValues(alpha: 0.85),
          size: 26,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _MastersTab — "Майстри": 2-column grid
// ---------------------------------------------------------------------------

/// How many masters render up front before the "show all" affordance is
/// needed (mobile-perf LOW fix, Phase 13.6 audit follow-up). 3 full rows of
/// the 2-column grid — small enough to bound the eager-build cost described
/// below regardless of how close a roster gets to [kSalonMastersPageSize].
const int kSalonMastersInitialCount = 6;

class _MastersTab extends StatefulWidget {
  const _MastersTab({required this.masters});

  final List<SalonMasterSummary> masters;

  @override
  State<_MastersTab> createState() => _MastersTabState();
}

class _MastersTabState extends State<_MastersTab> {
  // Flips true once the user explicitly taps "show all" — a one-time,
  // user-triggered build of the remainder is an acceptable cost; it is
  // ONLY the unconditional first-paint build this guards against.
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final List<SalonMasterSummary> masters = widget.masters;

    if (masters.isEmpty) {
      return Padding(
        key: const Key('salon-masters-empty'),
        padding: const EdgeInsets.symmetric(horizontal: VelvetSpacing.lg),
        child: Text(
          l10n.salonMastersEmpty,
          style: VelvetText.feedback(BrandColors.muted),
        ),
      );
    }

    final bool hasMore = masters.length > kSalonMastersInitialCount;
    final List<SalonMasterSummary> visible = hasMore && !_showAll
        ? masters.sublist(0, kSalonMastersInitialCount)
        : masters;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            VelvetSpacing.lg,
            0,
            VelvetSpacing.lg,
            VelvetSpacing.sm,
          ),
          // Vertical 2-column grid, not a lazy viewport-backed sliver: the
          // masters tab sits inside the screen's single outer
          // [SingleChildScrollView] (see `PublicSalonProfileScreen.build`),
          // not a [CustomScrollView], so `shrinkWrap: true` +
          // `NeverScrollableScrollPhysics` is the standard way to embed a
          // grid without a nested scrollable (double-scroll jank / gesture
          // conflicts). Because shrink-wrapping forces Flutter to eagerly
          // build every child up front to measure the wrapped height (no
          // lazy viewport culling), [visible] is capped to
          // [kSalonMastersInitialCount] on first paint rather than the full
          // roster (capped at [kSalonMastersPageSize], 50) — see the "show
          // all" affordance below (mobile-perf LOW fix, Phase 13.6 audit
          // follow-up). `mainAxisExtent` (not `childAspectRatio`) pins each
          // row to the exact [kSalonMasterCardHeight] regardless of column
          // width, so [SalonMasterCard]'s long-name/wrapped-role overflow
          // budget stays valid at any screen width.
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: VelvetSpacing.md,
              crossAxisSpacing: VelvetSpacing.md,
              mainAxisExtent: kSalonMasterCardHeight,
            ),
            itemCount: visible.length,
            itemBuilder: (context, i) {
              final SalonMasterSummary master = visible[i];
              return SalonMasterCard(
                key: Key('salon-master-card-${master.masterId}'),
                name: '${master.firstName} ${master.lastName}'.trim(),
                role: _roleLabel(master.type, l10n),
                ratingLabel: master.reviewCount > 0
                    ? (master.avgRating?.toStringAsFixed(1) ?? '—')
                    : '—',
                avatarIndex: i,
                onTap: () => context.push(
                  RouteNames.masterPublicProfile(master.masterId),
                ),
              );
            },
          ),
        ),
        if (hasMore && !_showAll)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              VelvetSpacing.lg,
              0,
              VelvetSpacing.lg,
              VelvetSpacing.sm,
            ),
            child: _ShowAllMastersButton(
              onTap: () => setState(() => _showAll = true),
            ),
          ),
      ],
    );
  }

  static String _roleLabel(MasterType type, AppLocalizations l10n) {
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

/// A full-width, lightweight "show all" affordance rendered below the
/// masters grid whenever the roster exceeds [kSalonMastersInitialCount].
/// Reuses the same extruded-tile vocabulary as [_SortIconButton] in the
/// reviews tab (`BrandColors.base` fill + `VelvetShadows.extrudedSmall`)
/// rather than the heavy gradient CTA reserved for the pinned "Записатись на
/// послугу" button — this is a secondary, in-page reveal, not a primary
/// action.
class _ShowAllMastersButton extends StatelessWidget {
  const _ShowAllMastersButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      button: true,
      label: l10n.salonMastersShowAll,
      child: GestureDetector(
        key: const Key('salon-masters-show-all'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 44,
          decoration: BoxDecoration(
            color: BrandColors.base,
            borderRadius: BorderRadius.circular(VelvetRadii.field),
            boxShadow: VelvetShadows.extrudedSmall,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(l10n.salonMastersShowAll, style: VelvetText.link()),
              const SizedBox(width: VelvetSpacing.xs),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 20,
                color: BrandColors.accentDeep,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _ServicesTab — "Послуги": own AsyncValue (independent of the hero load)
// ---------------------------------------------------------------------------

class _ServicesTab extends ConsumerWidget {
  const _ServicesTab({required this.salonId});

  final String salonId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final AsyncValue<List<SalonServiceCategoryEntry>> async = ref.watch(
      salonServiceCatalogProvider(salonId),
    );

    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(horizontal: VelvetSpacing.lg),
        child: SkeletonShimmerScope(
          child: SkeletonBlock(
            width: double.infinity,
            height: 160,
            radius: VelvetRadii.card,
          ),
        ),
      ),
      error: (Object e, _) => ErrorState(
        failure: e is Failure ? e : UnknownFailure(cause: e),
        onRetry: () => ref.invalidate(salonServiceCatalogProvider(salonId)),
      ),
      data: (List<SalonServiceCategoryEntry> categories) => categories.isEmpty
          ? Padding(
              key: const Key('salon-services-empty'),
              padding: const EdgeInsets.symmetric(horizontal: VelvetSpacing.lg),
              child: Text(
                l10n.salonServicesEmpty,
                style: VelvetText.feedback(BrandColors.muted),
              ),
            )
          : SalonServicesAccordion(categories: categories),
    );
  }
}

// ---------------------------------------------------------------------------
// _FavoriteToggleButton — top-right heart bound to the favorite toggle notifier
// ---------------------------------------------------------------------------

class _FavoriteToggleButton extends ConsumerStatefulWidget {
  const _FavoriteToggleButton({required this.salonId});

  final String salonId;

  @override
  ConsumerState<_FavoriteToggleButton> createState() =>
      _FavoriteToggleButtonState();
}

class _FavoriteToggleButtonState extends ConsumerState<_FavoriteToggleButton> {
  FavoriteTarget get _target =>
      FavoriteTarget(type: FavoriteTargetType.salon, id: widget.salonId);

  Future<void> _onTap() async {
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
    final l10n = AppLocalizations.of(context);
    final FavoriteTarget target = _target;
    final bool isFavorite = ref.watch(
      favoriteToggleProvider.select(
        (Map<FavoriteTarget, FavoriteEntry> m) =>
            m[target]?.isFavorite ?? false,
      ),
    );

    return CoverIconButton(
      key: const Key('salon-favorite-toggle'),
      icon: isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
      iconColor: isFavorite ? BrandColors.accentDeep : BrandColors.text,
      toggled: isFavorite,
      semanticLabel: isFavorite
          ? l10n.favoriteRemoveLabel
          : l10n.favoriteAddLabel,
      onTap: _onTap,
    );
  }
}

// ---------------------------------------------------------------------------
// _BookingShelf — pinned camel-wash «Записатись на послугу» booking shelf
// ---------------------------------------------------------------------------

/// The pinned bottom booking shelf. Booking always happens through a specific
/// master, but this salon-level CTA is the entry point into the (future)
/// combined service/master picker; until that ships it opens the same
/// booking placeholder route the public master profile uses.
class _BookingShelf extends StatelessWidget {
  const _BookingShelf({required this.salon});

  final Salon salon;

  static const Color _shelfSurface = Color(0xFFEDE4D5);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
            VelvetSpacing.md,
            VelvetSpacing.lg,
            VelvetSpacing.md,
          ),
          child: NeumorphicButton(
            key: const Key('salon-book-cta'),
            label: l10n.salonBookingCta,
            icon: Icons.event_available_rounded,
            onPressed: () =>
                context.push(RouteNames.bookingNew, extra: salon.id),
          ),
        ),
      ),
    );
  }
}
