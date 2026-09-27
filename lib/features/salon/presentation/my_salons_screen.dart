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
//   [NeumorphicButton], [NeumorphicIconButton] — `core/widgets/neumorphic.dart`
//   [ErrorState]                         — `shared/widgets/error_state.dart`
//   [SkeletonShimmerScope]/[SkeletonBlock] — `shared/widgets/skeleton_shimmer.dart`
//   [SalonHubCard]                       — `widgets/salon_hub_card.dart`
//     (Phase 21.6 — PROMOTED out of this file, where it was the private
//     `_SalonHubCard`, so the rotate-admin destination picker renders the
//     SAME card instead of a fork; its API is unchanged and this screen
//     renders identically. It resolves its own locality from taxonomy
//     `cityId` via `resolvedLocalityProvider`, the same provider
//     `_ManagementHeroCard` uses.)
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
//
// Swipe-to-delete (added alongside the delete-landing fix that routes every
// `runDeleteSalonFlow` caller here, `delete_salon_flow.dart`) — REUSE-FIRST:
// `_HubContent` wraps each card in a `Dismissible` (`endToStart` only) that
// calls the SAME [runDeleteSalonFlow] the account settings hub's
// `row-delete-salon` uses; no second confirm dialog, no hand-rolled delete
// call. `confirmDismiss` always returns `false` — the row is never removed
// by Dismissible's own slide-out/resize animation, because this screen is a
// `keepAlive` provider (`mySalonsProvider`) rebuild away from doing that
// removal itself the instant `deleteSalon()` invalidates it, and letting
// BOTH mechanisms race is exactly the
// `A dismissed Dismissible widget is still part of the tree` assertion
// trap. Owner-gating: `Salon` carries no per-item ownership field, and this
// screen doesn't need one — `/salons/mine` is gated SALON_OWNER-only by
// `mySalonsGuard` (`app_router.dart`) and `GET /salons/mine` only ever
// returns salons the caller owns, so every card this screen renders is
// already owned by the viewer for as long as their role is `salonOwner`. The
// swipe checks that role directly via the shared [isSalonOwnerProvider]
// (`auth/presentation/auth_selectors.dart`) — fail-closed: any other role
// — unreachable in practice past the route guard — renders a plain,
// un-swipeable card.

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
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:beautica_mobile/shared/widgets/skeleton_shimmer.dart';

import '../../auth/presentation/auth_selectors.dart';
import '../application/my_salons_notifier.dart';
import '../domain/salon.dart';
import 'delete_salon_flow.dart';
import 'widgets/salon_hub_card.dart';

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
  ///
  /// mobile-perf LOW follow-up (2026-08-31) — the curve is now
  /// `_controller.drive(CurveTween(...))`, not a `CurvedAnimation`.
  /// `CurvedAnimation` attaches a status listener to its parent and MUST be
  /// disposed; this one was constructed in `build()` — once per reveal, per
  /// build, for a list whose length is the owner's salon count — and never
  /// disposed, so every rebuild leaked another listener onto the controller.
  /// Pre-building them in `initState` is not available here (the `start`/`end`
  /// fractions depend on the resolved salon count, which `build` is the first
  /// to know), so the fix is to stop needing disposal at all: `drive` returns
  /// a lazy evaluation view that holds no listener of its own and forwards
  /// to the controller only while something is listening to IT — which the
  /// [AnimatedBuilder] below already unsubscribes from on unmount. The
  /// per-frame VALUE is identical: [CurvedAnimation] with no `reverseCurve`
  /// applies exactly this curve, and this controller only ever runs forward.
  Widget _reveal({
    required double start,
    required double end,
    required Widget child,
  }) {
    final Animation<double> curved = _controller.drive(
      CurveTween(
        curve: Interval(
          start.clamp(0.0, 1.0),
          end.clamp(0.0, 1.0),
          curve: Curves.easeOutCubic,
        ),
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

  /// Salon ids with an in-flight `runDeleteSalonFlow` delete call — drives
  /// the [_DeleteInFlightOverlay] over the swiped row (mobile-perf MEDIUM
  /// follow-up, 2026-09: `setLoading` used to be a no-op here on the theory
  /// that the dragged-open position itself communicated "in flight", but
  /// Dismissible hides BOTH its child and its background once the move
  /// animation reaches `dismissed` — see `_HubContent`'s call site — so the
  /// row was actually a blank gap for the whole `DELETE /salons/{id}`
  /// round-trip). Owned by this `State`, not `_HubContent`: `_HubContent` is
  /// a `StatelessWidget` rebuilt fresh from `mySalonsProvider`'s
  /// `AsyncValue` on every emission, so it has nowhere to durably hold an
  /// in-flight flag across the `await` inside `confirmDismiss` — and a
  /// second `ConsumerStatefulWidget` wrapping just the affected row would be
  /// a fork of state-holding machinery this screen already has. A `Set`
  /// rather than a single nullable id because nothing prevents an owner
  /// swiping a second row while the first is still deleting (each
  /// `Dismissible` gesture is independent).
  final Set<String> _deletingSalonIds = <String>{};

  /// REUSE-FIRST: delegates to the SAME confirm→delete→feedback flow
  /// `SettingsScreen._deleteSalon()` uses — see this file's header and
  /// `features/salon/presentation/delete_salon_flow.dart`. `setLoading`
  /// flips [_deletingSalonIds] for [salon.id] — see that field's doc.
  /// `setLoading(false)` is only ever called by `runDeleteSalonFlow` on
  /// FAILURE (its own doc: "on success the screen navigates away, so there
  /// is no matching loading=false call"); on success the salon is instead
  /// removed from `mySalonsProvider`'s list entirely (the notifier's
  /// `deleteSalon()` already invalidated it), so the id simply stops being
  /// rendered — a `true` entry surviving in the set for an id that no
  /// longer appears in `salons` is inert, never displayed again.
  Future<void> _deleteSalon(Salon salon) => runDeleteSalonFlow(
    context: context,
    ref: ref,
    salonId: salon.id,
    setLoading: (bool loading) => setState(() {
      if (loading) {
        _deletingSalonIds.add(salon.id);
      } else {
        _deletingSalonIds.remove(salon.id);
      }
    }),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final AsyncValue<List<Salon>> async = ref.watch(mySalonsProvider);
    // Fail-closed owner gate for the swipe — shared with
    // `_SettingsScreenState._showDeleteSalonRow` and
    // `SalonSettingsScreen.build` via the promoted [isSalonOwnerProvider]
    // (see that provider's doc for why `.value` alone is not read directly;
    // this file's header explains why a per-salon field isn't needed).
    final bool isOwner = ref.watch(isSalonOwnerProvider);

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
            canDelete: isOwner,
            onDeleteSalon: _deleteSalon,
            deletingSalonIds: _deletingSalonIds,
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
    required this.canDelete,
    required this.onDeleteSalon,
    required this.deletingSalonIds,
  });

  final List<Salon> salons;
  final Widget Function({
    required double start,
    required double end,
    required Widget child,
  })
  reveal;
  final ValueChanged<Salon> onOpenSalon;

  /// Whether the viewer may swipe a card to delete it — the fail-closed
  /// owner check `MySalonsScreen.build` computes once for the whole list
  /// (see that file's header: `Salon` carries no per-item ownership field,
  /// and this screen's every entry is already the viewer's own).
  final bool canDelete;

  /// Runs the shared delete flow for one [Salon] — see
  /// `MySalonsScreen._deleteSalon`.
  final Future<void> Function(Salon salon) onDeleteSalon;

  /// Salon ids with an in-flight delete call — see
  /// `_MySalonsScreenState._deletingSalonIds`. Owned by the `State` above,
  /// not this `StatelessWidget`: passed straight through so the affected
  /// row can render [_DeleteInFlightOverlay] instead of the blank gap
  /// Dismissible leaves once its move animation is `dismissed` (both its
  /// `child` and `background` are hidden at that point — see the
  /// `Dismissible` call site below).
  final Set<String> deletingSalonIds;

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
              child: Text(
                l10n.mySalonsSubtitle(salons.length),
                style: VelvetText.body(),
              ),
            ),
          );
        }
        if (salons.isEmpty) {
          return reveal(start: 0.2, end: 0.6, child: const _EmptyHub());
        }
        final int i = index - 2;
        final double start = _cardRevealStart(i, salons.length);
        final Salon salon = salons[i];
        final Widget card = SalonHubCard(
          key: ValueKey<String>('my_salons_card_${salon.id}'),
          salon: salon,
          onTap: () => onOpenSalon(salon),
        );
        // mobile-perf HIGH follow-up (swipe-to-delete audit 2026-09):
        // `RepaintBoundary` around the Dismissible's `child` — Dismissible's
        // `SlideTransition` translates `card` directly every drag-update
        // frame, and with no boundary here that forced `SalonHubCard`'s
        // `AnimatedContainer` (`salon_hub_card.dart` — dual
        // `BoxShadow(blurRadius: 18)` via `VelvetShadows.extrudedCard`) to
        // re-rasterize on every frame instead of compositing a cached layer.
        // NOT the same boundary as `_reveal`'s (outside the Dismissible,
        // isolating the 900ms entrance fade from sibling rows) — this one
        // isolates the drag transform itself.
        final Widget dismissibleCard = Dismissible(
          key: ValueKey<String>('my_salons_dismissible_${salon.id}'),
          direction: DismissDirection.endToStart,
          background: const _DeleteSalonSwipeBackground(),
          // Always `false`: the row is removed by
          // `mySalonsProvider` invalidating + rebuilding (fired
          // inside `deleteSalon()` on success) once
          // `onDeleteSalon` resolves, never by Dismissible's own
          // slide-out. Returning `true` here would race that
          // rebuild and risk "A dismissed Dismissible widget is
          // still part of the tree" — see this file's header.
          confirmDismiss: (DismissDirection _) async {
            await onDeleteSalon(salon);
            return false;
          },
          child: RepaintBoundary(child: card),
        );
        final bool isDeleting = deletingSalonIds.contains(salon.id);
        return Padding(
          padding: const EdgeInsets.only(bottom: VelvetSpacing.md),
          child: reveal(
            start: start,
            end: start + _cardRevealSpan,
            // `dismissibleCard` is ALWAYS the base child here (never
            // conditionally swapped for a different widget) so the
            // Dismissible's Element — and the async `confirmDismiss` future
            // it is awaiting — survives the `isDeleting` flag flipping true
            // partway through the wait; only the overlay ON TOP of it is
            // conditional. See `_DeleteInFlightOverlay`'s doc for why the
            // overlay can't just be Dismissible's own `background`.
            child: canDelete
                ? Stack(
                    children: <Widget>[
                      dismissibleCard,
                      if (isDeleting)
                        const Positioned.fill(child: _DeleteInFlightOverlay()),
                    ],
                  )
                : card,
          ),
        );
      },
    );
  }
}

/// The `Dismissible` background revealed by the owner's swipe-to-delete
/// gesture on a salon card ([DismissDirection.endToStart] only).
///
/// Flat `BrandColors.error` fill (the same warm terracotta-red
/// `SettingsRow(destructive: true)` already uses for `row-delete-salon` —
/// reused, not a new colour), rounded to the SAME `VelvetRadii.card` radius
/// as [SalonHubCard] so the reveal reads as "what's under the card" rather
/// than a separate decorated banner. Trailing-aligned icon + label (the card
/// slides away to the left, so the reveal grows in from the right) using the
/// `deleteSalonAction` ARB key already shared by the settings-hub delete
/// row and [DeleteSalonDialog]. No gradient, no blur, no second shadow — the
/// sliding card above still carries its own `VelvetShadows.extrudedCard`.
///
/// mobile-perf LOW/INFO adjudication (swipe-to-delete audit 2026-09) — this
/// widget is unconditionally CONSTRUCTED for every owner row `Dismissible`
/// wraps (clipped to zero width at rest, per `Dismissible`'s own
/// implementation — it always builds `widget.background` and animates a
/// clip around it, rather than lazily building it only once dragging
/// starts). NO CHANGE: this is `Dismissible`'s own documented API shape, not
/// a mistake in this file — there is no supported way to defer building a
/// `Dismissible.background` until the drag begins, short of not using
/// `Dismissible` at all (a far larger rewrite unjustified for a `const`,
/// single-`Container`+`Row` widget with no state, no listeners, and no
/// per-frame work of its own). It is also already bounded to the *visible*
/// viewport by `ListView.builder` — an owner with 50 salons does not
/// construct 50 of these, only however many rows are on/near screen. Nothing
/// to fix here.
class _DeleteSalonSwipeBackground extends StatelessWidget {
  const _DeleteSalonSwipeBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: VelvetSpacing.lg),
      decoration: BoxDecoration(
        color: BrandColors.error,
        borderRadius: BorderRadius.circular(VelvetRadii.card),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(
            Icons.delete_outline_rounded,
            color: BrandColors.white,
            size: 24,
          ),
          const SizedBox(width: VelvetSpacing.xs),
          Text(
            AppLocalizations.of(context).deleteSalonAction,
            style: VelvetText.bodyStrong().copyWith(color: BrandColors.white),
          ),
        ],
      ),
    );
  }
}

/// Card-sized "in progress" overlay shown ON TOP of a swiped [SalonHubCard]
/// while its delete call is in flight (mobile-perf MEDIUM follow-up,
/// swipe-to-delete audit 2026-09).
///
/// Why not just reuse `Dismissible`'s own [_DeleteSalonSwipeBackground]:
/// Flutter hides `Dismissible`'s `background` once its move animation
/// reaches `dismissed` (`!_moveAnimation.isDismissed` gates it internally) —
/// exactly the state a completed end-to-end swipe is in for the whole async
/// round-trip. With no separate affordance, BOTH the card (translated fully
/// off-screen) and the background (hidden) disappear, leaving a blank gap
/// that reads as "nothing happened" on a slow connection. This widget is
/// stacked ON TOP of the (still-mounted, never swapped-out — see the
/// `Stack` call site in `_HubContent.build`) `Dismissible` instead, so it
/// renders regardless of what `Dismissible` itself is doing internally.
///
/// Composition — `frontend-design`-reviewed, held to the locked VelvetTouch
/// palette: reuses [_DeleteSalonSwipeBackground]'s EXACT fill
/// (`BrandColors.error`, the same warm terracotta-red `SettingsRow
/// (destructive: true)` already uses) and radius (`VelvetRadii.card`) — no
/// new colour, no gradient beyond the locked CTA one (unused here), no blur,
/// no glassmorphism. Centered rather than trailing-aligned (this covers the
/// WHOLE card footprint now, not a partial drag-reveal sliver), with a
/// spinner replacing the static delete icon — sized up from `SettingsRow`'s
/// inline 16×16 loading token to 20×20 since it is the sole content of a
/// full card rather than an accessory beside a label, but keeping that same
/// `strokeWidth: 2` / `BrandColors.accentDeep`-family cream-on-error
/// treatment (`BrandColors.white`, matching the icon it replaces).
class _DeleteInFlightOverlay extends StatelessWidget {
  const _DeleteInFlightOverlay();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: AppLocalizations.of(context).mySalonsDeletingInProgress,
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: BrandColors.error,
            borderRadius: BorderRadius.circular(VelvetRadii.card),
          ),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const SizedBox(
                  key: Key('my_salons_delete_in_flight_spinner'),
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: BrandColors.white,
                  ),
                ),
                const SizedBox(width: VelvetSpacing.sm),
                Text(
                  AppLocalizations.of(context).mySalonsDeletingInProgress,
                  style: VelvetText.bodyStrong().copyWith(
                    color: BrandColors.white,
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

/// The hub's slim top bar — a back affordance, the screen's own
/// `mySalonsTitle` («Мої салони»), and a notification bell — mirroring the
/// shipped CLIENT shell top bar's composition (see this file's header for
/// why that widget isn't imported directly). Uses [VelvetText.pageTitle] —
/// the locked token for every top-level screen title — rather than
/// [VelvetText.wordmark], which is reserved for the literal "beautica" brand
/// mark, not a screen's own title.
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
          Expanded(
            child: Text(
              AppLocalizations.of(context).mySalonsTitle,
              style: VelvetText.pageTitle,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
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
