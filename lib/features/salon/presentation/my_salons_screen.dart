// Phase 21.1 — My Salons Hub (SALON_OWNER landing).
//
// Ported verbatim from the approved preview app at
// `docs/signup-designs/SalonManagementDesign/lib/screens/my_salons_screen
// .dart` — staggered fade-up salon cards, the "Основний" primary badge, an
// elevated bottom CTA shelf for "+ Додати салон". See that file for the
// design rationale; this file wires it to real `Salon` data instead of the
// preview's static `demoSalons` list.
//
// THE LANDING FIX (phase doc Step 5, not this file) — `role_home.dart`'s
// `roleHomePath(UserRole.salonOwner)` now points here instead of the bare
// `_Placeholder('home')`; both post-registration (`done_screen.dart`) and
// fresh-login (`auth_redirect.dart`) share that one source of truth.
//
// REUSE-FIRST — widgets reused verbatim from elsewhere in this feature /
// `core/`/`shared/`:
//   [SalonLogo]                          — `widgets/salon_cover_widgets.dart`
//   [NeumorphicButton], [NeumorphicIconButton] — `core/widgets/neumorphic.dart`
//   [ErrorState]                         — `shared/widgets/error_state.dart`
//   [SkeletonShimmerScope]/[SkeletonBlock] — `shared/widgets/skeleton_shimmer.dart`
//   [buildLocalityLine]/[buildStreetLine]  — `shared/formatters/address_lines.dart`
//   [resolvedLocalityProvider]           — `features/location/state/
//     resolved_locality_provider.dart` (Phase 21.14 follow-up — resolves
//     `_SalonHubCard`'s locality from taxonomy `cityId`, same provider
//     `_ManagementHeroCard` uses; see `_SalonHubCardState.build`)
// NOT reused: the preview's `_HubTopBar`/`_BellButton` mirror the shipped
// `ClientTopBar`/`BellButton` (`features/shell/presentation/widgets/
// client_top_bar.dart`) by design, but that widget lives in the `shell`
// feature's `presentation/` — importing it from here would cross the
// feature-boundary import rule (`presentation/` may only import another
// feature's `domain/`/`shared/`, never its `presentation/`). Small private
// equivalents are written below from the same `core/` primitives
// ([AppIcon], [BeauticaAssetIcons], [NeumorphicIconButton]) `ClientTopBar`
// itself is built from, rather than forking its composed shape.
//
// The card footer stats the preview shows (★ rating · staff count) are
// DROPPED here — `GET /salons/mine` returns `SalonResponse`, which carries
// neither an aggregate rating/review count nor a staff count (confirmed
// against the committed `tool/openapi/api-spec.json` snapshot); fabricating
// either would be a lie. [Salon.avgRating]/[Salon.reviewCount] map to
// null/0 for every entry this screen loads (see [SalonMapper.fromUpdateDto],
// reused by `SalonRepository.getMySalons`), so the footer row simply isn't
// rendered.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/icons/app_icon.dart';
import 'package:beautica_mobile/core/icons/beautica_asset_icons.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/location/domain/resolved_locality.dart';
import 'package:beautica_mobile/features/location/state/resolved_locality_provider.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/formatters/address_lines.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:beautica_mobile/shared/widgets/skeleton_shimmer.dart';

import '../application/my_salons_notifier.dart';
import '../domain/salon.dart';
import 'widgets/salon_cover_widgets.dart';

/// The `SALON_OWNER`'s entry point: every salon they own, listed as a
/// tappable card, plus the "+ Додати салон" CTA.
///
/// Tapping a card opens [RouteNames.salonManage] (Phase 21.2, already
/// shipped) — NOT [RouteNames.salonPublicProfile], which is the CLIENT-
/// facing public profile. The «+ Додати салон» CTA pushes
/// [RouteNames.registerSalon] (Phase 21.3).
class MySalonsScreen extends ConsumerStatefulWidget {
  const MySalonsScreen({super.key});

  @override
  ConsumerState<MySalonsScreen> createState() => _MySalonsScreenState();
}

class _MySalonsScreenState extends ConsumerState<MySalonsScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// One staggered fade-up segment. [start]/[end] are 0–1 fractions of the
  /// entrance run — ported verbatim from the preview.
  ///
  /// mobile-perf HIGH follow-up (2026-08-28) — [start] is now clamped exactly
  /// like [end] already was: an unclamped `start` above `1.0` (an owner with
  /// ≥9 salons, see `_HubContent`'s call site) violated `Interval`'s
  /// `begin <= 1.0` assert — a debug/profile red-screen crash on the owner's
  /// own landing screen. This is a belt-and-braces clamp at the shared
  /// primitive; the actual graceful-degradation fix (so the stagger spreads
  /// out instead of bunching every card past #8 into an instant opaque snap)
  /// lives in `_HubContent._cardRevealStart`, which never hands this method
  /// an out-of-range value in the first place.
  ///
  /// mobile-perf LOW follow-up (same date) — wrapped in [RepaintBoundary]:
  /// this is the owner's landing screen, revisited on every login, so the
  /// 900ms entrance previously repainted the whole subtree unisolated on
  /// every visit. One fix here covers every call site (top bar, heading,
  /// empty state, and every salon card) without special-casing any of them.
  Widget _reveal({
    required double start,
    required double end,
    required Widget child,
  }) {
    final Animation<double> curved = CurvedAnimation(
      parent: _controller,
      curve: Interval(
        start.clamp(0.0, 1.0),
        end.clamp(0.0, 1.0),
        curve: Curves.easeOutCubic,
      ),
    );
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: curved,
        builder: (BuildContext context, Widget? c) => Opacity(
          opacity: curved.value,
          child: Transform.translate(
            offset: Offset(0, (1 - curved.value) * 18),
            child: c,
          ),
        ),
        child: child,
      ),
    );
  }

  // Phase 21.8 — the hub is now a SWITCHER: picking a salon puts the owner
  // IN it (the salon's own shell, one bottom-nav frame), rather than pushing
  // the bare management profile on top of the hub. `go`, not `push` — this
  // is a lateral move between salons, not a drill-down the owner backs out
  // of; the shell itself owns getting back to «Мої салони» (settings hub →
  // «Мої салони» row, Phase 21.8 Step M11), same as tapping a different
  // client-shell bottom-nav tab never leaves a stack entry behind.
  void _openSalon(Salon salon) => context.go(RouteNames.salonShell(salon.id));

  /// Phase 21.3 — pushes the «+ Додати салон» form. A `push` (not `go`) so
  /// [RegisterSalonScreen]'s own `context.pop()` on a successful submit
  /// returns cleanly to this still-scrolled hub — `mySalonsProvider` is
  /// already invalidated by that submit, so the hub re-renders the new
  /// salon on its own the moment it rebuilds, no manual refresh needed.
  void _addSalon() => context.push(RouteNames.registerSalon);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final AsyncValue<List<Salon>> async = ref.watch(mySalonsProvider);

    return Scaffold(
      backgroundColor: BrandColors.base,
      bottomNavigationBar: _AddSalonShelf(
        label: l10n.mySalonsAddCta,
        onAdd: _addSalon,
      ),
      body: SafeArea(
        bottom: false,
        child: async.when(
          loading: () => const _HubSkeleton(),
          error: (Object e, _) => Padding(
            padding: const EdgeInsets.all(VelvetSpacing.lg),
            child: ErrorState(
              failure: e is Failure ? e : UnknownFailure(cause: e),
              onRetry: () => ref.invalidate(mySalonsProvider),
            ),
          ),
          data: (List<Salon> salons) => _HubContent(
            salons: salons,
            reveal: _reveal,
            onOpenSalon: _openSalon,
          ),
        ),
      ),
    );
  }
}

/// The loaded body: top bar, heading + owned-count subtitle, and the
/// staggered salon-card list (or the empty state).
///
/// mobile-perf MEDIUM follow-up (2026-08-28) — was a `SingleChildScrollView`
/// + `Column`, eagerly building and laying out every card even for an
/// unbounded owner salon list. Converted to `ListView.builder`, per the repo
/// convention for scrolling lists. The approved design's staggered fade-up
/// entrance, «Основний» primary badge, and elevated bottom CTA shelf
/// (`Scaffold.bottomNavigationBar`, untouched — still owned by
/// `MySalonsScreen`, not this widget) render IDENTICALLY: the header (top
/// bar + heading) and the salon list/empty-state are now `ListView.builder`
/// items instead of `Column` children, with each item's own trailing
/// `Padding` reproducing the exact spacing the old `SizedBox` siblings gave
/// (`VelvetSpacing.lg` after the header rows, `VelvetSpacing.md` after every
/// card) — the list's own `EdgeInsets.fromLTRB(lg, lg, lg, xl)` padding is
/// unchanged, so the trailing gap after the last card (`md` + `xl`) matches
/// the old Column's `SizedBox(md)` + `SingleChildScrollView`'s `xl` padding
/// exactly.
class _HubContent extends StatelessWidget {
  const _HubContent({
    required this.salons,
    required this.reveal,
    required this.onOpenSalon,
  });

  final List<Salon> salons;
  final Widget Function({
    required double start,
    required double end,
    required Widget child,
  })
  reveal;
  final ValueChanged<Salon> onOpenSalon;

  static const double _cardStaggerBase = 0.12;
  static const double _cardRevealSpan = 0.48;
  // The last card's `start` never exceeds this, leaving room for its
  // `_cardRevealSpan` before hitting `Interval`'s `1.0` ceiling — the fixed
  // `0.12`-per-card step the design shipped with is preserved for small
  // counts (its own step is smaller than the cap below up to ~5 salons) and
  // shrinks gracefully for a salon-chain owner instead of bunching every
  // card past #8 into an instant, un-staggered opaque snap.
  static const double _cardStaggerBudget = 0.7;

  /// The staggered `start` fraction for card [index] of [count] — see the
  /// fields above for the budget this stays inside of.
  static double _cardRevealStart(int index, int count) {
    if (count <= 1) return _cardStaggerBase;
    final double step = ((_cardStaggerBudget - _cardStaggerBase) / (count - 1))
        .clamp(0.0, _cardStaggerBase);
    return _cardStaggerBase + index * step;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Item 0 = top bar, item 1 = heading block, then either the empty state
    // (1 item) or one item per owned salon.
    final int listedCount = salons.isEmpty ? 1 : salons.length;
    final int itemCount = 2 + listedCount;

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        VelvetSpacing.lg,
        VelvetSpacing.lg,
        VelvetSpacing.lg,
        VelvetSpacing.xl,
      ),
      itemCount: itemCount,
      itemBuilder: (BuildContext context, int index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: VelvetSpacing.lg),
            child: reveal(
              start: 0.0,
              end: 0.34,
              child: _HubTopBar(
                onBack: () {
                  if (context.canPop()) context.pop();
                },
                onBell: () {},
              ),
            ),
          );
        }
        if (index == 1) {
          return Padding(
            padding: const EdgeInsets.only(bottom: VelvetSpacing.lg),
            child: reveal(
              start: 0.1,
              end: 0.46,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(l10n.mySalonsTitle, style: VelvetText.heading()),
                  const SizedBox(height: VelvetSpacing.xs),
                  Text(
                    l10n.mySalonsSubtitle(salons.length),
                    style: VelvetText.body(),
                  ),
                ],
              ),
            ),
          );
        }
        if (salons.isEmpty) {
          return reveal(start: 0.2, end: 0.6, child: const _EmptyHub());
        }
        final int i = index - 2;
        final double start = _cardRevealStart(i, salons.length);
        return Padding(
          padding: const EdgeInsets.only(bottom: VelvetSpacing.md),
          child: reveal(
            start: start,
            end: start + _cardRevealSpan,
            child: _SalonHubCard(
              key: ValueKey<String>('my_salons_card_${salons[i].id}'),
              salon: salons[i],
              onTap: () => onOpenSalon(salons[i]),
            ),
          ),
        );
      },
    );
  }
}

/// The hub's slim top bar — a back affordance, the lowercase "beautica"
/// wordmark, and a notification bell — mirroring the shipped CLIENT shell
/// top bar's composition (see this file's header for why that widget isn't
/// imported directly).
class _HubTopBar extends StatelessWidget {
  const _HubTopBar({required this.onBack, required this.onBell});

  final VoidCallback onBack;
  final VoidCallback onBell;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: NeumorphicIconButton.extent,
      child: Row(
        children: <Widget>[
          NeumorphicIconButton(
            key: const Key('my_salons_back_button'),
            icon: Icons.arrow_back_ios_new_rounded,
            semanticLabel: AppLocalizations.of(context).salonProfileBackLabel,
            onTap: onBack,
          ),
          const SizedBox(width: VelvetSpacing.md),
          Text(
            // raw-ui-string-ok: brand wordmark, deliberately NOT translated —
            // same treatment as ClientTopBar's own "beautica" literal.
            'beautica',
            style: VelvetText.wordmark(),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
          const Spacer(),
          _BellButton(onTap: onBell),
        ],
      ),
    );
  }
}

/// Notification bell — state-driven asset swap identical to `ClientTopBar`'s
/// own `BellButton`, kept private here for the feature-import-boundary
/// reason this file's header explains.
///
// TODO(14.9): bind `hasUnread` from the unread-notifications provider once
// the notification center ships. Until then it stays dotless, matching
// every other pre-Phase-14.9 call site.
class _BellButton extends StatelessWidget {
  const _BellButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: AppLocalizations.of(context).homeHubNotificationsLabel,
      child: GestureDetector(
        key: const Key('my_salons_bell_button'),
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: const Padding(
          padding: EdgeInsets.all(VelvetSpacing.xs),
          child: AppIcon(
            BeauticaAssetIcons.notificationPlain,
            size: 24,
            color: BrandColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// A salon card in the hub: logo + name + "Основний" badge (primary only) +
/// locality/address. Depresses on press.
///
/// `ConsumerStatefulWidget` (Phase 21.14 follow-up — was `StatefulWidget`)
/// so [_SalonHubCardState.build] can `ref.watch` [resolvedLocalityProvider]
/// for the taxonomy city name — see that method for the fallback chain and
/// why `salon.city` is not read directly. Mirrors `_ManagementHeroCard` in
/// `salon_management_profile_screen.dart`, reusing the SAME promoted
/// provider rather than a second resolution path.
class _SalonHubCard extends ConsumerStatefulWidget {
  const _SalonHubCard({super.key, required this.salon, required this.onTap});

  final Salon salon;
  final VoidCallback onTap;

  @override
  ConsumerState<_SalonHubCard> createState() => _SalonHubCardState();
}

class _SalonHubCardState extends ConsumerState<_SalonHubCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final Salon s = widget.salon;
    // `salon.city` is legacy free-text, frozen (no longer written by the
    // backend since Phase 10.6 — see `Salon.city`'s own doc): once a salon's
    // address has been edited through the taxonomy cascade, `city` can be
    // stale or blank while `cityId`/`oblastId` carry the real location. This
    // watches the SAME promoted `resolvedLocalityProvider`
    // (`features/location/state/resolved_locality_provider.dart`)
    // `_ManagementHeroCard` uses — no second by-id scan here.
    //
    // PER-ROW watch, not hoisted above the list: `resolvedLocalityProvider`
    // is a family, but the `oblastList`/`cityList(oblastId)`/
    // `districtList(cityId)` providers it reads underneath are
    // `keepAlive: true` and memoized for the app's lifetime. An owner's
    // salons are typically in the same oblast/city, so distinct
    // `(oblastId, cityId, districtId)` triples across N cards collapse to at
    // most a handful of family instances — and even those only ever hit the
    // network once per distinct oblast/city/district; every other card
    // resolving the same triple (or a triple sharing an already-fetched
    // oblast/city) re-scans an in-memory list, not a fresh HTTP round trip.
    // Hoisting a single resolve above the list would only help if every
    // salon shared one identical triple, which the model doesn't guarantee
    // (an owner can have salons in different cities) — per-row is both
    // simpler and correct here.
    //
    // `AsyncValue.value` is nullable (Riverpod 3.x) and collapses BOTH
    // "still loading" and "resolution failed" to `null` uniformly — no
    // spinner, no error box, no layout jump. `city` falls back to the legacy
    // `s.city` ONLY when the salon genuinely has no taxonomy id at all
    // (`s.cityId` null/blank) — a pre-Phase-10.6 salon that was never
    // re-saved. While `cityId` IS set but resolution hasn't completed yet,
    // the line is simply blank until it fills in — never the stale legacy
    // text, which would risk showing a WRONG city before the correct one
    // arrives.
    final ResolvedLocality? resolved = ref
        .watch(
          resolvedLocalityProvider(
            oblastId: s.oblastId,
            cityId: s.cityId,
            districtId: s.districtId,
          ),
        )
        .value;
    final bool hasTaxonomyCity = s.cityId?.trim().isNotEmpty ?? false;
    final String? locality = buildLocalityLine(
      resolved?.city?.name ?? (hasTaxonomyCity ? null : s.city),
    );
    final String? street = buildStreetLine(s.street, s.buildingNo);
    final String? monogram = s.name.trim().isEmpty
        ? null
        : s.name.trim()[0].toUpperCase();

    return Semantics(
      button: true,
      label: AppLocalizations.of(
        context,
      ).mySalonsCardSemanticLabel(s.name, locality ?? ''),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) {
          setState(() => _pressed = false);
          widget.onTap();
        },
        child: AnimatedScale(
          scale: _pressed ? 0.99 : 1,
          duration: const Duration(milliseconds: 110),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              color: BrandColors.base,
              borderRadius: BorderRadius.circular(VelvetRadii.card),
              boxShadow: _pressed ? null : VelvetShadows.extrudedCard,
            ),
            padding: const EdgeInsets.all(VelvetSpacing.md + 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SalonLogo(diameter: 58, monogram: monogram),
                const SizedBox(width: VelvetSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Flexible(
                            child: Text(
                              s.name,
                              style: VelvetText.displayName21,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (s.isPrimary ?? false) ...<Widget>[
                            const SizedBox(width: VelvetSpacing.sm),
                            const _PrimaryBadge(),
                          ],
                        ],
                      ),
                      if (locality != null || street != null) ...<Widget>[
                        const SizedBox(height: 5),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            const Padding(
                              padding: EdgeInsets.only(top: 1),
                              child: Icon(
                                Icons.location_on_outlined,
                                size: 14,
                                color: BrandColors.accentDeep,
                              ),
                            ),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Text(
                                <String>[?locality, ?street].join('\n'),
                                style: VelvetText.salonHubAddressLine,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(top: VelvetSpacing.sm),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    color: BrandColors.faint,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The camel "Основний" primary-salon badge.
class _PrimaryBadge extends StatelessWidget {
  const _PrimaryBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: VelvetSpacing.sm,
        vertical: VelvetSpacing.xs - 1,
      ),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[BrandColors.accentLatte, BrandColors.accentDeep],
        ),
        borderRadius: BorderRadius.circular(VelvetRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.star_rounded,
            size: 12,
            color: BrandColors.white.withValues(alpha: 0.95),
          ),
          const SizedBox(width: 3),
          Text(
            AppLocalizations.of(context).mySalonsPrimaryBadgeLabel,
            style: VelvetText.salonHubPrimaryBadgeLabel,
          ),
        ],
      ),
    );
  }
}

/// The pinned bottom shelf carrying the prominent "+ Додати салон" CTA.
///
/// Same elevated-shelf shape as `public_salon_profile_screen.dart`'s and
/// `public_master_profile_screen.dart`'s own private `_BookingShelf` —
/// mirrored here (not imported: both are file-private) rather than forked
/// from scratch.
class _AddSalonShelf extends StatelessWidget {
  const _AddSalonShelf({required this.label, required this.onAdd});

  final String label;
  final VoidCallback onAdd;

  static const Color _shelfSurface = Color(0xFFEDE4D5);

  @override
  Widget build(BuildContext context) {
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
            key: const Key('my_salons_add_cta'),
            label: label,
            icon: Icons.add_business_rounded,
            onPressed: onAdd,
          ),
        ),
      ),
    );
  }
}

/// Empty-state — not expected in practice (an owner always has ≥1 salon
/// from registration) but rendered defensively rather than left blank.
class _EmptyHub extends StatelessWidget {
  const _EmptyHub();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: VelvetSpacing.xxl),
      child: Column(
        children: <Widget>[
          const Icon(
            Icons.storefront_outlined,
            size: 48,
            color: BrandColors.muted,
          ),
          const SizedBox(height: VelvetSpacing.md),
          Text(
            l10n.mySalonsEmptyTitle,
            style: VelvetText.subheading(),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: VelvetSpacing.xs),
          Text(
            l10n.mySalonsEmptyBody,
            style: VelvetText.body(),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Loading skeleton — a chrome-shaped block + two card-shaped blocks, shown
/// while [mySalonsProvider] resolves.
class _HubSkeleton extends StatelessWidget {
  const _HubSkeleton();

  static Widget _cardSkeleton() => Container(
    padding: const EdgeInsets.all(VelvetSpacing.md + 2),
    decoration: BoxDecoration(
      color: BrandColors.base,
      borderRadius: BorderRadius.circular(VelvetRadii.card),
      boxShadow: VelvetShadows.extrudedCard,
    ),
    child: const Row(
      children: <Widget>[
        SkeletonBlock(width: 58, height: 58, circle: true),
        SizedBox(width: VelvetSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SkeletonBlock(width: 140, height: 16),
              SizedBox(height: VelvetSpacing.xs),
              SkeletonBlock(width: 180, height: 12),
            ],
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmerScope(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          VelvetSpacing.lg,
          VelvetSpacing.lg,
          VelvetSpacing.lg,
          VelvetSpacing.xl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const SkeletonBlock(width: 150, height: 22),
            const SizedBox(height: VelvetSpacing.xs),
            const SkeletonBlock(width: 220, height: 14),
            const SizedBox(height: VelvetSpacing.lg),
            _cardSkeleton(),
            const SizedBox(height: VelvetSpacing.md),
            _cardSkeleton(),
          ],
        ),
      ),
    );
  }
}
