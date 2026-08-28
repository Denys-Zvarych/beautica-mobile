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
import 'package:beautica_mobile/core/media/beautica_image.dart';
import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
// Cross-feature application import (not presentation/data — permitted): the
// per-master service-coverage fan-out lives in the booking feature (Phase
// 14.13) and is REUSED here rather than duplicated, so the masters grid can be
// filtered by the selected service without a second bespoke fan-out. Only
// triggered while a service filter is active (see [_MastersTab]).
import 'package:beautica_mobile/features/booking/application/salon_master_coverage_notifier.dart';
import 'package:beautica_mobile/features/booking/domain/salon_booking_args.dart';
import 'package:beautica_mobile/features/favorites/application/favorite_toggle_notifier.dart';
import 'package:beautica_mobile/features/favorites/domain/favorite_target.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/feedback/show_velvet_snack.dart';
import 'package:beautica_mobile/shared/formatters/address_lines.dart';
import 'package:beautica_mobile/shared/utils/instagram_url.dart';
import 'package:beautica_mobile/shared/widgets/contact_tile.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:beautica_mobile/shared/widgets/expandable_note.dart';
import 'package:beautica_mobile/shared/widgets/skeleton_shimmer.dart';

import '../application/public_salon_profile_notifier.dart';
import '../application/salon_portfolio_notifier.dart';
import '../application/salon_service_catalog_notifier.dart';
import '../application/salon_service_filter_notifier.dart';
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
  ///
  /// The only parameter this screen takes. An earlier cut also accepted an
  /// `initialServiceId`/`initialMastersTab` pair, seeded from
  /// `?serviceId=…&tab=masters` query params, that landed the profile on a
  /// pre-filtered "Майстри" tab for the salon-arm wish-list CTA. That CTA now
  /// opens the salon booking flow's step-2 master picker directly, so the
  /// parameters, their route parsing and the one-shot seed were deleted as
  /// redundant. The service→masters filter this screen still applies when the
  /// client TAPS a service in the "Послуги" tab is unaffected — see
  /// [salonServiceFilterProvider].
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
    // Watched at the screen level (not inside a single tab) so the selection
    // survives in-screen tab switches — the SELECTING widget (Послуги tab) and
    // the CONSUMING widget (Майстри grid) are only ever mounted one at a time.
    // autoDispose then resets it when the profile is popped.
    final SalonServiceSelection? serviceFilter = ref.watch(
      salonServiceFilterProvider(widget.salonId),
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
              serviceFilter: serviceFilter,
              topInset: topInset,
              coverHeight: _coverHeight,
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
    required this.serviceFilter,
    required this.topInset,
    required this.coverHeight,
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

  /// The service the masters grid is currently filtered by, or null for none.
  final SalonServiceSelection? serviceFilter;
  final double topInset;
  final double coverHeight;
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
              1 => _MastersTab(
                salonId: salonId,
                masters: masters,
                filter: serviceFilter,
              ),
              2 => _ServicesTab(
                salonId: salonId,
                selectedServiceId: serviceFilter?.id,
                // Selecting a service jumps to the Майстри tab (index 1) so the
                // client immediately sees the narrowed roster.
                onSwitchToMasters: () => onTabSelected(1),
              ),
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
///
/// Phase 224 — the hero card now embeds an [ExpandableNote] for
/// `salon.locationNote` (moved back in from the About tab's «Як дістатись»
/// section — see [_SalonHeroCard]). Expanded, that note can add several
/// hundred px of height (the field is up to 1000 chars). Before this phase
/// the hero card was `Positioned(bottom: 0)` inside a `Stack` sized to
/// `coverHeight + heroProtrusion`, so its protrusion into the cover tracked
/// its OWN content height (`cardHeight - heroProtrusion`) — fine while that
/// height was bounded by maxLines caps on the name/address, but an expanded
/// note has no such cap, and the old formula would push the card's top edge
/// arbitrarily far up the cover, over the back/favourite buttons.
///
/// This is now a [Stack]: a fixed-height cover (with the back/favourite
/// controls layered over it) [Positioned] to its own `coverHeight`
/// regardless of anything else, plus the hero card as the Stack's ONE
/// non-`Positioned` child, offset from the top by a small FIXED amount
/// (`coverHeight - _cardCoverOverlap`) via an ordinary [Padding] rather than
/// the cover's own height. Because the card is the only non-positioned
/// child, it alone determines the Stack's total size — `coverHeight -
/// _cardCoverOverlap` of top inset plus the card's own natural (content-
/// driven) height — so any extra height the card needs (a note, an
/// EXPANDED note, a long address) grows the STACK downward only, pushing
/// the tab bar and the rest of the page down with it, while the
/// `Positioned` cover (and therefore the back/favourite buttons) always
/// renders at its own full `coverHeight`, never depending on the card's
/// size.
///
/// An earlier version of this fix pinned the overlap with a hand-written
/// [RenderShiftedBox] subclass that painted the card at a negative offset
/// relative to a deliberately-shrunk reported `size`. That has two sharp
/// edges standard widgets don't: `RenderBox.hitTest()` gates on
/// `_size.contains(position)` *before* it ever calls `hitTestChildren()`,
/// and a negative paint offset always lands the "overhang" portion at
/// negative *local* coordinates — which `Size.contains()` can never
/// consider inside the box, no matter how `size` itself is tuned. The top
/// `_cardCoverOverlap` px of the card were therefore never hit-testable —
/// taps there silently fell through to the cover underneath. The custom
/// object also had no `computeDryLayout` override (none of
/// `RenderShiftedBox`'s framework subclasses get one for free), tripping an
/// assert under any future `IntrinsicHeight` ancestor or layout/golden test.
///
/// `Padding`'s reported `size` always includes its own inset, so it has no
/// "painted-but-not-reported" region for `hitTest()` to gate out, and it
/// inherits a correct `computeDryLayout` from the framework — neither
/// problem can recur here. (A simpler-looking `Transform.translate` was
/// tried and rejected: `RenderTransform.hitTest` *does* skip the usual
/// `size` gate and apply the inverse transform to reach its child, but only
/// when the `Transform` itself is the render object the parent's
/// `hitTestChildren` calls directly. Any ordinary `RenderShiftedBox`
/// ancestor between that call site and the `Transform` — even an
/// unrelated horizontal-only `Padding` — re-applies the *default*,
/// non-transform-aware `size.contains()` gate first and rejects the
/// negative offset before the `Transform` is ever reached. `Transform`
/// also never shrinks the reported layout size the way the old render
/// object did, so the Stack/Column it sits in ends up `_cardCoverOverlap`
/// px taller than the card's true visual bottom — dead space that would
/// have to be clawed back from a trailing gap, and `VelvetSpacing.lg`
/// (24px) is smaller than `_cardCoverOverlap` (25px), so that reduction
/// goes negative. The [Positioned]-cover / [Padding]-inset-card split below
/// has neither problem: it reproduces the exact old total height with a
/// direct, non-derived sum, not a measure-then-subtract trick.)
class _CoverAndHero extends StatelessWidget {
  const _CoverAndHero({
    required this.coverHeight,
    required this.topInset,
    required this.salon,
    required this.reveal,
    required this.anim0,
    required this.slide0,
  });

  final double coverHeight;
  final double topInset;
  final Salon salon;
  final Widget Function(Animation<double>, Animation<Offset>, Widget) reveal;
  final Animation<double> anim0;
  final Animation<Offset> slide0;

  /// Fixed pixel amount by which the hero card overlaps (protrudes into) the
  /// bottom of the cover photo, independent of the card's own content
  /// height — see the class doc for why this replaced the old
  /// content-driven formula. Chosen to match what that formula produced for
  /// a typical locality+street card with no note (measured 25px at the time
  /// of writing), so the common no-note case looks the same as before.
  ///
  /// It is FIXED rather than derived from `cardHeight` on purpose: the hero
  /// card can now carry an [ExpandableNote] up to 1000 chars long, and an
  /// expanded note can grow the card by several hundred px — a
  /// content-driven overlap would grow right along with it and push the
  /// card up over the cover's back/favourite buttons (see the class doc's
  /// note on the old `cardHeight - _heroProtrusion` formula). Pinning the
  /// overlap independent of content height means extra content height only
  /// ever grows the card downward, never upward into the cover.
  ///
  /// Deliberately NOT a `VelvetSpacing` token: it doesn't express a spacing
  /// rhythm between two elements, it encodes a geometric relationship to
  /// `coverHeight` (how far the card's top edge sits above the cover's
  /// bottom edge) — a `VelvetSpacing` value would be a coincidence, not a
  /// contract.
  ///
  /// The exact value of 25 is pinned by three geometry tests in the
  /// `hero card overlap is a fixed constant, independent of content height`
  /// group in `public_salon_profile_screen_test.dart` — minimal content,
  /// worst-case collapsed content, and a 1000-char expanded note all assert
  /// this overlap to within 0.5px. Do not change this value without
  /// updating (and getting sign-off on) those tests.
  static const double _cardCoverOverlap = 25;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        // Cover artwork + back/favourite controls — `Positioned` to its own
        // full `coverHeight`, so it never contributes to (or shrinks with)
        // this Stack's own sizing; that comes solely from the card below.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: coverHeight,
          child: Stack(
            children: <Widget>[
              SalonCover(
                height: coverHeight,
                topInset: topInset,
                imageUrl: salon.coverImageUrl,
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
            ],
          ),
        ),
        // Hero card — the Stack's only non-`Positioned` child, so it alone
        // drives the Stack's total height (see class doc). Painted LAST so
        // it layers on top of the cover in the overlap band, and — being a
        // plain [Padding] rather than a custom RenderObject with a shrunk
        // `size` — its reported box always spans its whole painted
        // footprint, so the overlap band is hit-testable like any other
        // part of the card.
        Padding(
          padding: EdgeInsets.fromLTRB(
            VelvetSpacing.lg,
            coverHeight - _cardCoverOverlap,
            VelvetSpacing.lg,
            0,
          ),
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

  /// Diameter of the [SalonLogo] avatar at the card's leading edge. Shared
  /// with the location row's leading indent below so the two never drift
  /// apart (the same class of bug that previously bit `_heroProtrusion`/
  /// `_coverHeight`).
  static const double _logoDiameter = 68;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final String? monogram = salon.name.trim().isEmpty
        ? null
        : salon.name.trim()[0].toUpperCase();
    final String ratingLabel = salon.avgRating?.toStringAsFixed(1) ?? '—';
    // Phase 223 (b) — locality + street/building, each its own line, one
    // `Text` per helper, both `maxLines: 1`. `locationNote` is never
    // concatenated onto either of these lines — it renders as its own
    // [ExpandableNote] below (Phase 224) — so a note up to 1000 chars long
    // can never push the address itself out of its budget the way a single
    // combined line did pre-223.
    final String? localityLine = _localityLine(salon);
    final String? streetLine = _streetLine(salon);
    // Phase 224 — `locationNote` moved back onto the hero card (it briefly
    // lived on the About tab under Phase 223 (b) — see the `_AboutTab` and
    // `_CoverAndHero` class docs for why/how). Sanitization happens INSIDE
    // `ExpandableNote` (mirrors the public master profile's identical
    // convention — see that widget's class doc); pre-sanitizing here would
    // be a redundant no-op pass.
    final String? noteText = (salon.locationNote?.isNotEmpty ?? false)
        ? salon.locationNote
        : null;
    final bool hasAddress = localityLine != null || streetLine != null;

    return NeumorphicCard(
      key: const Key('salon-profile-hero-card'),
      color: const Color(0xFFEDE4D5),
      padding: const EdgeInsets.all(VelvetSpacing.md + 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // Static content — logo, name/rating row, address rows — isolated
          // in its own RepaintBoundary, sibling to the [ExpandableNote]
          // below.
          //
          // mobile-perf audit fix (Phase 224 follow-up): before this, the
          // whole card shared ONE RepaintBoundary with the note — the one
          // `reveal()` wraps around this whole widget in [_CoverAndHero].
          // The note's 220ms expand/collapse `AnimatedSize` resizes
          // `NeumorphicCard`'s Column, and that layout change bubbles up to
          // the shared boundary, forcing it to repaint EVERYTHING inside —
          // including this static content's `SalonLogo` gradient/border/
          // shadow and `NeumorphicCard`'s own extruded shadow — on all ~13
          // frames of the animation, even though only the note's text is
          // changing size. This never happened while the note lived in the
          // About tab's plain `Padding` (Phase 223). It is the exact class
          // of bug `ExpandableNote`'s own class doc
          // (`expandable_note.dart:47-57`) documents fixing for the master
          // profile's `ProfileAvatar`/`MaskFilter.blur` case; that
          // precedent wasn't reapplied here when the note moved onto this
          // card (Phase 224). Isolating this subtree in its own layer
          // confines an expand/collapse repaint to just the note (which
          // already isolates its own `AnimatedSize` — see
          // `expandable_note.dart`) and this card's outer shadow.
          RepaintBoundary(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    SalonLogo(diameter: _logoDiameter, monogram: monogram),
                    const SizedBox(width: VelvetSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            salon.name,
                            key: const Key('salon-profile-name'),
                            style: VelvetText.displayName20,
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
                                  // Keyed so the review-invalidation regression
                                  // can pin the hero's COUNT half of the
                                  // aggregate by widget rather than by a
                                  // localised string (M2) — `avgRating` alone
                                  // moving is not proof the whole snapshot
                                  // refreshed.
                                  key: const Key('salon-profile-review-count'),
                                  style: VelvetText.feedbackMuted13,
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
                if (hasAddress) ...<Widget>[
                  // Tight gap (matches the name→rating spacing above) rather
                  // than the old VelvetSpacing.md (16px): the location line
                  // is a tightly-coupled continuation of the rating row,
                  // not a loosely separated address section
                  // (mobile-debugger fix — restores the hero card's natural
                  // height so it protrudes into the cover again; see
                  // [_CoverAndHero] for how the card's growth is now kept
                  // from pushing that protrusion any further). Mirrored
                  // below (outside this boundary) for the note-only,
                  // no-address case.
                  const SizedBox(height: 5),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      // Indents the icon+text to align with the name/rating
                      // text column above (logo diameter + the gap after
                      // it), so the location line reads as "under the
                      // rating", not "under the logo image". Purely a
                      // horizontal offset — it does not change this row's
                      // height.
                      const SizedBox(width: _logoDiameter + VelvetSpacing.md),
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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            // Line 1: locality, or the street line promoted
                            // here when there is no locality (mirrors the
                            // master identity card's promotion convention
                            // in `shared/formatters/address_lines.dart`).
                            // `maxLines: 1` (not 2, as the pre-223 combined
                            // line allowed) is what makes the budget FIXED
                            // rather than variable — this row can occupy at
                            // most 2 lines total, ever.
                            Text(
                              localityLine ?? streetLine!,
                              key: localityLine != null
                                  ? const Key('salon-profile-locality-text')
                                  : const Key('salon-profile-address-text'),
                              style: VelvetText.bookFeedbackSec13,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            // Line 2: street + building — only when a
                            // locality is ALSO present (otherwise it was
                            // already promoted to line 1 above).
                            if (localityLine != null &&
                                streetLine != null) ...<Widget>[
                              const SizedBox(height: 2),
                              Text(
                                streetLine,
                                key: const Key('salon-profile-address-text'),
                                style: VelvetText.bookFeedbackSec13,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          // The note renders whenever present, even for a salon with
          // NEITHER a locality NOR a street (a note-only location, e.g. a
          // salon that only describes "яка вивіска шукати" without a
          // formal address) — unlike the public master profile, where the
          // equivalent note is nested INSIDE the address-only `if`, this
          // one is gated on its own so it is never silently dropped for a
          // salon with a note but no address on file. Deliberately OUTSIDE
          // the static-content [RepaintBoundary] above — see that
          // boundary's doc comment.
          if (noteText != null) ...<Widget>[
            // `hasAddress` ? the tight 2px gap after the address block :
            // the same 5px gap the address block itself would have used
            // (this is the note-only, no-address case — nothing else has
            // consumed that leading gap yet).
            if (hasAddress)
              const SizedBox(height: 2)
            else
              const SizedBox(height: 5),
            Padding(
              padding: const EdgeInsets.only(
                left: _logoDiameter + VelvetSpacing.md,
              ),
              child: ExpandableNote(
                key: const Key('salon-profile-location-note'),
                text: noteText,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static final TextStyle _ratingInlineStyle = VelvetText.bodyStrong14;

  /// The hero card's locality (city) line, or `null` when unavailable.
  ///
  /// Unlike [Master]'s identity card, this never resolves `cityId` to a
  /// human-readable name — a lookup would need `LocationRepository
  /// .fetchCities(salon.oblastId)` plus a live network round-trip, which this
  /// synchronous hero-card builder can't do; the raw id is not rendered
  /// directly. When the taxonomy `street` field is set, this method
  /// deliberately returns `null` rather than falling back to the legacy
  /// `city` field: the backend stopped
  /// writing legacy `city`/`address` once a salon re-saves its location under
  /// the taxonomy (Phase 10.6+), so a still-populated `city` alongside a
  /// fresh `street` would be a STALE value the mapper never clears (mirrors
  /// the pre-Phase-223 `_buildLocationLine`'s taxonomy branch, which never
  /// rendered `city` once `street` was present).
  static String? _localityLine(Salon salon) {
    if (_hasTaxonomyStreet(salon)) return null;
    return buildLocalityLine(salon.city);
  }

  /// Whether the salon has a taxonomy `street` with VISIBLE content.
  ///
  /// mobile-qa Phase 224 fix — this used to be a raw `salon.street?.isNotEmpty`
  /// check in both [_localityLine] and [_streetLine], which is a DIFFERENT
  /// notion of "present" from the one `shared/formatters/address_lines.dart`
  /// uses since it started sanitizing-then-testing (`_visibleOrNull`). The two
  /// disagreed for a street made only of characters that reduce to nothing —
  /// whitespace, or a zero-width space (backend validation on these fields is
  /// `@Size`-only, so provider-authored free text can be exactly that):
  ///   - `_localityLine` saw `isNotEmpty == true`, concluded "this salon uses
  ///     the taxonomy fields", and returned `null` — suppressing the city;
  ///   - `_streetLine` took the taxonomy branch and got `null` back from
  ///     `buildStreetLine`, which now correctly treats the field as absent.
  /// Both lines null ⇒ `hasAddress == false` ⇒ the ENTIRE address row was
  /// dropped, pin included, and a salon with a perfectly good «Київ» on file
  /// rendered no location at all. (Before the `_visibleOrNull` refactor the
  /// same salon rendered a junk `"   , 22"` line instead — different symptom,
  /// same root cause: two definitions of "present".)
  ///
  /// Routing the gate through `buildStreetLine` makes it the SAME definition
  /// the formatters use, by construction, so the two can no longer drift.
  static bool _hasTaxonomyStreet(Salon salon) =>
      buildStreetLine(salon.street) != null;

  /// The hero card's street/building (or legacy address) line, or `null`
  /// when unavailable.
  ///
  /// Prefers the structured taxonomy fields (`street` + `buildingNo`,
  /// Phase 10.6+) over the legacy free-text `address` field — see
  /// [_localityLine] for why the two are never mixed. Falls back to the
  /// legacy `address` (a pre-composed free-text string with no separate
  /// building-number component of its own, so it is passed through as this
  /// line's sole content) only when the salon predates Phase 10.6 or has
  /// never been re-saved since (mobile-side fix for `PublicSalonResponse`
  /// commit `ef96845`).
  ///
  /// Never includes `locationNote` — that field renders as its OWN
  /// [ExpandableNote] below this line (see the Phase 224 note in
  /// [_SalonHeroCard.build]), never concatenated onto it, so it can never
  /// evict this line from its fixed one-line budget the way the pre-223
  /// combined line allowed.
  static String? _streetLine(Salon salon) {
    if (_hasTaxonomyStreet(salon)) {
      return buildStreetLine(salon.street, salon.buildingNo);
    }
    return buildStreetLine(salon.address);
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
    // Phase 224 — `locationNote` moved back onto the hero card (its
    // «Як дістатись» heading + [ExpandableNote] briefly lived here under
    // Phase 223 (b); see [_SalonHeroCard] for the current render site and
    // [_CoverAndHero] for how the hero card now absorbs the note's height
    // without pushing into the cover photo).

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

  /// Same top-level-route reasoning as `PublicMasterProfileScreen`'s identical
  /// method: this route is registered OUTSIDE the CLIENT `StatefulShellRoute`,
  /// pushed full-screen over `ClientShell` (which it replaces entirely), and
  /// its own bottom slot is the local `_BookingShelf` CTA, not the shared
  /// `ClientBottomNav` — so no `bottomInset` is needed here.
  static void _showInstagramError(BuildContext context) {
    showErrorSnack(
      context,
      AppLocalizations.of(context).masterInstagramOpenError,
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
/// hero card's address lines hide entirely when absent (see
/// [_SalonHeroCard._localityLine] / [_SalonHeroCard._streetLine]).
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
    // The https-only + host-allowlist guard, decode-bounding and disk cache
    // now live in RemoteImage (core/media/beautica_image.dart). Its shared
    // [isAllowedMediaUrl] also RESTORES the null/empty-URL check this site's
    // old inline `scheme == 'https'` guard omitted. `excludeFromSemantics` is
    // set because the enclosing Semantics already labels the tile as an image.
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
          child: RemoteImage(
            url: photo.url,
            width: _size,
            height: _size,
            shape: RemoteImageShape.roundedRect,
            borderRadius: _radius,
            excludeFromSemantics: true,
            fallback: _errorTile(),
          ),
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

class _MastersTab extends ConsumerStatefulWidget {
  const _MastersTab({
    required this.salonId,
    required this.masters,
    required this.filter,
  });

  final String salonId;
  final List<SalonMasterSummary> masters;

  /// The active service filter, or null to show every master (default).
  final SalonServiceSelection? filter;

  @override
  ConsumerState<_MastersTab> createState() => _MastersTabState();
}

class _MastersTabState extends ConsumerState<_MastersTab> {
  // Flips true once the user explicitly taps "show all" — a one-time,
  // user-triggered build of the remainder is an acceptable cost; it is
  // ONLY the unconditional first-paint build this guards against.
  bool _showAll = false;

  @override
  void didUpdateWidget(covariant _MastersTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    // `_showAll` is shared by the filtered and unfiltered `_buildGrid` paths.
    // Whenever the active filter changes — applied, cleared, or swapped for a
    // different service — the visible set changes, so the first-paint cap must
    // re-arm. Without this reset a "show all" from one set leaks into the next
    // (e.g. show-all on a filtered set → clear the filter → the full roster
    // would render eagerly, defeating the kSalonMastersInitialCount cap).
    if (oldWidget.filter != widget.filter) {
      _showAll = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final List<SalonMasterSummary> masters = widget.masters;
    final SalonServiceSelection? filter = widget.filter;

    // Salon has no masters at all — nothing a filter could change.
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

    // No filter — the original behaviour: every master, capped-then-show-all.
    if (filter == null) {
      return _buildGrid(context, masters);
    }

    // Filter active — a clear-filter chip above the (coverage-gated) grid.
    // The chip renders in every coverage sub-state so the client can always
    // dismiss the filter, even mid-load. Coverage is the Phase 14.13/23.x
    // bookable-masters read, scoped to just the ONE filtered service — fired
    // ONLY now that a service is selected, never on a plain profile visit.
    // [coverageArgs] reuses [SalonBookingMasterSelectionArgs] as the family
    // key (same type the booking flow's master-selection step uses) with a
    // single-element [selectedServiceIds]; freezed's deep-collection equality
    // means a fresh instance here still resolves to the same cached family
    // member across rebuilds.
    final SalonBookingMasterSelectionArgs coverageArgs =
        SalonBookingMasterSelectionArgs(
          salonId: widget.salonId,
          selectedServiceIds: <String>[filter.id],
        );
    final AsyncValue<Map<String, Map<String, String>>> coverageAsync = ref
        .watch(salonMasterServiceCoverageProvider(coverageArgs));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            VelvetSpacing.lg,
            0,
            VelvetSpacing.lg,
            VelvetSpacing.md,
          ),
          child: _ServiceFilterChip(
            serviceName: filter.name,
            onClear: () => ref
                .read(salonServiceFilterProvider(widget.salonId).notifier)
                .clear(),
          ),
        ),
        coverageAsync.when(
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
            onRetry: () => ref.invalidate(
              salonMasterServiceCoverageProvider(coverageArgs),
            ),
          ),
          data: (Map<String, Map<String, String>> coverage) {
            final List<SalonMasterSummary> filtered = masters
                .where(
                  (SalonMasterSummary m) =>
                      coverage[m.masterId]?.containsKey(filter.id) ?? false,
                )
                .toList();
            if (filtered.isEmpty) {
              return const _MastersForServiceEmpty();
            }
            return _buildGrid(context, filtered);
          },
        ),
      ],
    );
  }

  /// The 2-column masters grid over [masters], with the first-paint cap +
  /// "show all" reveal. Shared by the unfiltered and filtered paths so the
  /// [kSalonMastersInitialCount] cap always applies to whatever set is shown.
  Widget _buildGrid(BuildContext context, List<SalonMasterSummary> masters) {
    final l10n = AppLocalizations.of(context);
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
              // Prefer the master's own professional title/label; fall back to
              // the generic type role ("Майстер салону" etc.) only when the
              // master has not set one.
              final String? ownTitle = master.professionalTitle?.trim();
              final String role = (ownTitle != null && ownTitle.isNotEmpty)
                  ? ownTitle
                  : _roleLabel(master.type, l10n);
              return SalonMasterCard(
                key: Key('salon-master-card-${master.masterId}'),
                // First name only on the salon master card (surname omitted).
                name: master.firstName,
                role: role,
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

/// The active-service-filter pill shown above the masters grid whenever a
/// service is selected in the "Послуги" tab. A camel-washed extruded pill —
/// a leading spa glyph, the `Послуга: <name>` label, and a tappable ✕ (its own
/// hit target + semantics node) that clears the filter and restores the full
/// roster.
class _ServiceFilterChip extends StatelessWidget {
  const _ServiceFilterChip({required this.serviceName, required this.onClear});

  final String serviceName;
  final VoidCallback onClear;

  /// Subtle camel wash over the base — matches the selected service row's fill
  /// so the chip reads as the same "active filter" surface.
  static final Color _fill = Color.alphaBlend(
    BrandColors.accent.withValues(alpha: 0.16),
    BrandColors.base,
  );

  /// Chip label scale — invariant, so hoisted to a static (matching this
  /// file's `_ratingInlineStyle`/`_priceStyle`/`_nameStyle` convention) so
  /// build() never allocates a new [TextStyle] per frame.
  static final TextStyle _labelStyle = VelvetText.bodyStrong13.copyWith(
    color: BrandColors.accentDeep,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      key: const Key('salon-masters-filter-chip'),
      padding: const EdgeInsets.fromLTRB(
        VelvetSpacing.md,
        VelvetSpacing.xs + 2,
        VelvetSpacing.xs + 2,
        VelvetSpacing.xs + 2,
      ),
      decoration: BoxDecoration(
        color: _fill,
        borderRadius: BorderRadius.circular(VelvetRadii.pill),
        boxShadow: VelvetShadows.extrudedSmall,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(
            Icons.spa_outlined,
            size: 16,
            color: BrandColors.accentDeep,
          ),
          const SizedBox(width: VelvetSpacing.xs + 2),
          Flexible(
            child: Text(
              l10n.salonMasterFilterChipLabel(serviceName),
              style: _labelStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: VelvetSpacing.xs),
          Semantics(
            button: true,
            label: l10n.salonMasterFilterClearLabel,
            child: GestureDetector(
              key: const Key('salon-masters-filter-clear'),
              behavior: HitTestBehavior.opaque,
              onTap: onClear,
              child: Container(
                width: 24,
                height: 24,
                decoration: const BoxDecoration(
                  color: BrandColors.base,
                  shape: BoxShape.circle,
                  boxShadow: VelvetShadows.extrudedSmall,
                ),
                child: const Icon(
                  Icons.close_rounded,
                  size: 15,
                  color: BrandColors.accentDeep,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Friendly empty state for the masters grid when a service filter is active
/// but no master in the salon performs the selected service — a soft
/// neumorphic badge over a muted one-liner, mirroring the "Майстри" tab's
/// empty vocabulary rather than leaving a blank grid.
class _MastersForServiceEmpty extends StatelessWidget {
  const _MastersForServiceEmpty();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      key: const Key('salon-masters-for-service-empty'),
      padding: const EdgeInsets.symmetric(
        horizontal: VelvetSpacing.lg,
        vertical: VelvetSpacing.md,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              color: BrandColors.base,
              shape: BoxShape.circle,
              boxShadow: VelvetShadows.extrudedSmall,
            ),
            child: const Icon(
              Icons.person_search_outlined,
              size: 26,
              color: BrandColors.accent,
            ),
          ),
          const SizedBox(height: VelvetSpacing.md),
          Text(
            l10n.salonMastersForServiceEmpty,
            textAlign: TextAlign.center,
            style: VelvetText.feedback(BrandColors.muted),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _ServicesTab — "Послуги": own AsyncValue (independent of the hero load)
// ---------------------------------------------------------------------------

class _ServicesTab extends ConsumerWidget {
  const _ServicesTab({
    required this.salonId,
    required this.selectedServiceId,
    required this.onSwitchToMasters,
  });

  final String salonId;

  /// The catalog id of the currently-filtered service, or null for none.
  final String? selectedServiceId;

  /// Called after a service is picked, to reveal the narrowed masters grid.
  final VoidCallback onSwitchToMasters;

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
          : SalonServicesAccordion(
              categories: categories,
              selectedServiceId: selectedServiceId,
              onServiceTap: (SalonCatalogService service) {
                final SalonServiceFilter notifier = ref.read(
                  salonServiceFilterProvider(salonId).notifier,
                );
                // Re-tapping the active service clears the filter and stays
                // put; tapping a new one selects it and jumps to Майстри.
                if (selectedServiceId == service.id) {
                  notifier.clear();
                } else {
                  notifier.select((id: service.id, name: service.name));
                  onSwitchToMasters();
                }
              },
            ),
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
    // See `_showInstagramError`'s doc above — no `bottomInset` needed on this
    // top-level route.
    if (failure != null && mounted) {
      showErrorSnack(context, failure.userMessage(context));
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

/// The pinned bottom booking shelf. A salon booking is fundamentally
/// different from a single-master booking (multi-service selection against
/// the salon's FULL catalogue → per-service master assignment → N
/// appointments across possibly-different masters), so this CTA routes into
/// the dedicated salon booking flow (Phase 14.12) rather than the
/// independent-master flow.
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
                context.push(RouteNames.salonBookingServices, extra: salon.id),
          ),
        ),
      ),
    );
  }
}
