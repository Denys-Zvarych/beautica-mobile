// Phase 5.2 — Services List Screen.
//
// The INDEPENDENT_MASTER's "Мої послуги" catalogue. Three AsyncValue states:
//   • loading → three [_SkeletonCard] widgets (shimmer sweep)
//   • data    → if empty: [_EmptyState]; else [ListView.builder] of [ServiceCard]
//   • error   → [ErrorState] with retry
//
// A neumorphic extended FAB (hidden in the empty state: the empty state has its
// own primary CTA) sits bottom-right via [Scaffold.floatingActionButton].
//
// Pull-to-refresh via [RefreshIndicator] delegates to
// [ServicesListNotifier.refresh].
//
// Design source: `docs/signup-designs/ServiceListScreen/lib/screens/service_list_screen.dart`
// and `service_widgets.dart` — transcribed 1:1; local state / Navigator
// replaced by Riverpod notifier + go_router.
//
// Phase 247 (part 1) — [CategoryGroup], [CategorySection],
// [CategoryCountBadge], [ServiceCard], [PhotoThumbnail], [ServiceInfo],
// [MetaLine] and [MetaItem] were PROMOTED out of this file (dropped their
// leading underscore) into
// `presentation/widgets/service_category_list.dart` so the master booking
// wizard (Phase 247 part 2) can reuse the exact same widgets rather than
// forking a lookalike. Pure move — no behaviour change.

import 'dart:async';
import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/core/time/clock_provider.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/app_refresh_indicator.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/features/services/presentation/category_catalogue_freshness.dart';
import 'package:beautica_mobile/features/services/presentation/service_catalogue_invalidation.dart';
import 'package:beautica_mobile/features/services/presentation/service_types_provider.dart';
import 'package:beautica_mobile/features/services/presentation/widgets/service_category_list.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:beautica_mobile/shared/widgets/velvet_bottom_nav_bar.dart';

import 'services_list_notifier.dart';

export 'services_list_notifier.dart' show servicesListProvider;

/// The INDEPENDENT_MASTER's services catalogue screen.
///
/// Handles all three [AsyncValue] states (loading / data / error).
/// Pull-to-refresh triggers [ServicesListNotifier.refresh].
///
/// [initialExpandCategory] — when non-null and non-empty, the matching
/// category section is pre-expanded on first build and all others start
/// collapsed. When null or empty (the default — e.g. "Усі послуги" link or
/// bottom-nav "Послуги" tab) ALL sections start collapsed; the user can
/// toggle any section freely afterward.
/// Passed from the profile screen's category cards via the `expandCategory`
/// query parameter on the `/services` route.
///
/// Converted to [ConsumerStatefulWidget] to manage the [ScreenProtector]
/// lifecycle (SEC MEDIUM-1): screenshot suppression is enabled in release
/// builds on entry and lifted on exit, matching the project-wide pattern
/// used by [MasterProfileScreen].
class ServicesListScreen extends ConsumerStatefulWidget {
  const ServicesListScreen({
    super.key,
    this.initialExpandCategory,
    this.setupRoute,
    this.editRouteBuilder,
    this.writable = true,
    this.showBottomNav = true,
    this.showBack = false,
    this.backFallbackRoute,
    this.navScheduleRoute,
    this.navProfileRoute,
    this.navBookingsRoute,
  });

  /// Optional upper-cased wire slug. When set, the matching category section
  /// is pre-expanded and all others start collapsed on first entry. When null
  /// or empty all sections start collapsed (the default).
  final String? initialExpandCategory;

  /// Phase 317 (D3) — where the FAB and the empty-state CTA push to.
  ///
  /// ADDITIVE and NULLABLE: `null` means [RouteNames.serviceSetup], i.e.
  /// exactly what every call site shipped before phase 317 did, so no existing
  /// caller changes. The salon-target route
  /// ([RouteNames.salonManageStaffServiceSetup]) supplies its own leaf so the
  /// operator stays inside the salon subtree — and therefore inside the
  /// `ProviderScope` that points the repository at that salon master.
  ///
  /// Deliberately NOT `ref.watch(serviceTargetProvider)` inside this screen:
  /// D3 rejects that because the screen would then know about salons, which is
  /// the exact knowledge the repository seam exists to keep out of it.
  final String? setupRoute;

  /// Phase 317 (D3) — how a card's «Редагувати» builds its destination from a
  /// service id. `null` means [RouteNames.serviceEdit]. Same additive/nullable
  /// contract as [setupRoute].
  final String Function(String serviceId)? editRouteBuilder;

  /// Phase 320 (D1) — additive, defaults to `true` so every existing caller
  /// renders exactly as today. `false` removes the FAB, the empty-state CTA
  /// and the card's edit tap (D3) — hidden, not disabled. No route passes
  /// `false` yet — that lands in phase 321.
  final bool writable;

  /// 2026-09-13 audit (M6, mobile-security LOW) — additive, defaults to `true`
  /// so every existing caller renders exactly as today.
  ///
  /// This screen was authored as the INDEPENDENT_MASTER's tab-0 surface and
  /// hardcoded `VelvetBottomNavBar(activeIndex: 0)`. Phase 317/321/322 mounted
  /// it for two more roles, and for a SALON_OWNER / SALON_ADMIN viewing a
  /// staff member's catalogue at `/salons/:id/manage/staff/:member/services`
  /// the master 4-tile bar is simply the wrong chrome — that operator has no
  /// «Мої записи» / «Графік» / «Профіль» of the master shape at all. `false`
  /// removes the bar entirely (the screen keeps its own `AppBar` back
  /// affordance, which is how the operator got here and how they leave).
  final bool showBottomNav;

  /// Phase 323 — additive, defaults to `false` so every existing caller
  /// renders EXACTLY as today.
  ///
  /// `true` supplies an explicit [AppBar.leading] back affordance (the shared
  /// [NeumorphicIconButton] arrow idiom, identical to the one
  /// `schedule_editor_stubs.dart` and `booking_detail_screen.dart` already
  /// place in an `AppBar.leading` slot) that pops the route.
  ///
  /// WHY A FLAG AND NOT `automaticallyImplyLeading`: this screen is mounted on
  /// three routes with three different needs.
  ///
  ///  • `/services` (INDEPENDENT_MASTER, pushed onto the ROOT navigator) —
  ///    `automaticallyImplyLeading` already draws Material's own arrow, so
  ///    this stays `false` and NOTHING about that screen changes. The default
  ///    branch deliberately does NOT set `automaticallyImplyLeading: false`,
  ///    which would regress that working arrow.
  ///  • `/staff/services` (SALON_MASTER bottom-nav tab, entered with
  ///    `context.go`) — a tab root has nowhere to go back TO, so it stays
  ///    `false` and stays bare.
  ///  • `/salons/:salonId/manage/staff/:memberId/services` (SALON_OWNER /
  ///    SALON_ADMIN) — this is the case the flag exists for. That leaf is a
  ///    `ShellRoute` child declared WITHOUT a `navigatorKey`, so go_router
  ///    mints a private nested `Navigator` and the list is page #1 inside it.
  ///    `ModalRoute.impliesAppBarDismissal` walks THAT navigator's history,
  ///    reaches itself and returns false, so `AppBar` suppresses the automatic
  ///    arrow. Android system-back still exits (the delegate falls through the
  ///    one-page shell navigator to the root), so this was a missing
  ///    AFFORDANCE, never a broken exit.
  final bool showBack;

  /// 2026-09-14 audit (mobile-security LOW) — where [showBack]'s arrow goes
  /// when there is NOTHING to pop. Additive and nullable; only meaningful when
  /// [showBack] is `true`, so both `showBack: false` mounts are untouched.
  ///
  /// `GoRouterDelegate.pop` THROWS `GoError('There is nothing to pop')` in
  /// release, not just in debug. An empty root stack is reachable on the
  /// opted-in route: `ServiceSetupScreen`'s own no-stack branch calls
  /// `context.go(exitRoute)`, and `app_router.dart` aims that `exitRoute` at
  /// `RouteNames.salonManageStaffServices(...)` — i.e. back at this screen.
  /// Since that same mount passes `showBottomNav: false`, the arrow is the
  /// operator's ONLY on-screen exit, so an unguarded pop would throw and
  /// strand them inside the privileged salon-manage shell.
  ///
  /// Same additive-route-parameter shape as [setupRoute] /
  /// [ServiceSetupScreen.exitRoute]: the SCREEN stays ignorant of salons, the
  /// ROUTE supplies the destination. The salon-manage leaf passes
  /// [RouteNames.salonManageStaffMember] — the staff profile the operator
  /// pushed from.
  ///
  /// `null` + nothing to pop absorbs the tap rather than throwing.
  final String? backFallbackRoute;

  /// Test contract for the [showBack] affordance. Mirrors
  /// [VelvetTopBar.backKey] / `booking_detail_screen.dart`'s
  /// `Key('booking-detail-back')`: a stable handle widget and integration
  /// tests tap, so the control cannot be renamed out from under them.
  static const Key backKey = Key('services-list-back');

  /// 2026-09-13 audit (M6) — additive nav-bar destination overrides, threaded
  /// straight through to [VelvetBottomNavBar]'s own additive params. `null`
  /// (every pre-existing caller) means that widget's own literals, so the
  /// INDEPENDENT_MASTER surface is byte-identical to before.
  ///
  /// The SALON_MASTER's `/staff/services` route passes
  /// [RouteNames.salonMasterSchedule] / [RouteNames.salonMasterProfile]:
  /// without them tiles 2 and 3 targeted `/master/*`, which
  /// `auth_redirect.dart` bounces straight back to `roleHomePath` — a tap
  /// that visibly does nothing.
  final String? navScheduleRoute;
  final String? navProfileRoute;

  /// Tile 1 («Мої записи»). No `/staff/*` counterpart exists for a
  /// SALON_MASTER yet, so this stays `null` at every call site and that tile
  /// keeps its documented bounce — see [VelvetBottomNavBar.bookingsRoute].
  final String? navBookingsRoute;

  /// Resolved setup destination — the parameter, or today's literal.
  String get resolvedSetupRoute => setupRoute ?? RouteNames.serviceSetup;

  /// Resolved edit-destination builder — the parameter, or today's literal.
  String Function(String serviceId) get resolvedEditRouteBuilder =>
      editRouteBuilder ?? RouteNames.serviceEdit;

  @override
  ConsumerState<ServicesListScreen> createState() => _ServicesListScreenState();
}

class _ServicesListScreenState extends ConsumerState<ServicesListScreen> {
  // Captured in initState so dispose() never touches `ref` — under Riverpod
  // 3.x using `ref` in dispose() throws. Hold the keepAlive manager instead.
  late final ScreenProtectionManager _screenProtection;

  @override
  void initState() {
    super.initState();
    // SEC MEDIUM: ref-counted screenshot + iOS app-switcher-snapshot guard
    // (single app-wide owner; the manager is internally !kDebugMode-guarded).
    _screenProtection = ref.read(screenProtectionProvider)..acquire();
    // The approved-category list ([approvedCategoriesProvider], keepAlive) is
    // cached in the root container for the whole session, so the picker can go
    // stale after an admin approves a category server-side. Refreshing on
    // first entry guarantees a fresh fetch. (Returns to this kept-alive route
    // are handled by [_openAndRefresh], since initState does NOT re-fire on
    // pop-back.)
    //
    // 2026-09-13 audit (M8) — entry and pop-back now share ONE path,
    // [_refreshCategoryCataloguesIfStale], which is rate-limited by
    // [kCategoryCatalogueFreshFor]. Unconditional busting cost a salon
    // operator three app-wide category fetches for a single
    // `services → edit → back → edit → back` sitting.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refreshCategoryCataloguesIfStale();
    });
  }

  /// Drops the two APP-WIDE category caches — but at most once per
  /// [kCategoryCatalogueFreshFor].
  ///
  /// Both caches are root-scoped `keepAlive` providers shared with the service
  /// form, the client discovery filters and every other salon-scoped mount of
  /// this screen, so an unconditional bust here is an app-wide cost paid for a
  /// list that only changes when an admin approves a category server-side.
  ///
  /// Returns `true` when it actually refreshed — used by the tests that pin
  /// the guard, and deliberately NOT used to drive any UI.
  bool _refreshCategoryCataloguesIfStale() {
    final DateTime now = ref.read(clockProvider)();
    if (!ref.read(categoryCatalogueFreshnessProvider.notifier).isStaleAt(now)) {
      return false;
    }
    _refreshCategoryCatalogues(now);
    return true;
  }

  /// The unconditional bust. Pull-to-refresh calls this directly: an explicit
  /// user request for fresh data is never rate-limited.
  ///
  /// AUDIT cycle-2 (N1, mobile-perf LOW) — the freshness marker is stamped on
  /// SUCCESS ONLY, never eagerly.
  ///
  /// Stamping before the refetch settled meant a FAILED category read still
  /// marked the caches fresh for [kCategoryCatalogueFreshFor]: the screen kept
  /// rendering humanized-slug fallback labels (`SERVICE_TYPE` instead of «Тип
  /// послуги») with NO automatic retry for five minutes, and pull-to-refresh
  /// was the only escape — which nobody discovers as the remedy for wrong
  /// labels. Before the rate limit shipped, every entry retried; the guard
  /// must not turn a transient failure into a five-minute stale window.
  ///
  /// So the stamp hangs off the refreshed read settling successfully. The
  /// `.future` read is what FORCES that refetch to happen (an `invalidate`
  /// alone is lazy, and a refresh nobody awaits has no observable outcome to
  /// key the stamp on).
  ///
  /// AUDIT cycle-3 (C2) — what that forced read actually costs, per arm.
  /// The earlier wording ("merely PRE-fetches what that body is about to
  /// ask for") was TRUE of two arms and FALSE of the third:
  ///
  ///   • LOADED (non-empty list) — no extra round trip. `_LoadedBody` watches
  ///     [approvedCategoriesProvider] on every build, so the refetch happens
  ///     regardless; the `.future` read only joins the one already in flight.
  ///   • EMPTY — a genuine PRE-fetch. `_EmptyState`'s only affordance is the
  ///     «Додати послугу» CTA into the setup screen, whose category picker
  ///     reads this same provider, so the fetch is MOVED EARLIER, not added.
  ///   • ERROR — a NET-NEW request. Nothing on the error scaffold watches
  ///     [approvedCategoriesProvider], so before the stamp existed this arm
  ///     issued ZERO category reads and now issues exactly one.
  ///
  /// That net-new read in the error arm is ACCEPTED DELIBERATELY, not an
  /// oversight:
  ///
  ///   • Skipping it here is the cycle-2 N1 bug through a side door. With no
  ///     settled read to key on, the stamp either goes back to being written
  ///     EAGERLY — a failed refresh marks the caches fresh for five minutes,
  ///     which is exactly what N1 removed — or never lands at all in this
  ///     arm, which makes the rate limit a no-op and undoes M8.
  ///   • It is capped at ONE per [kCategoryCatalogueFreshFor] per container,
  ///     on a screen the user is already blocked on.
  ///   • It is not wasted on the recovery path, which is the likely one:
  ///     «Повторити» re-fetches the services list, `_LoadedBody` mounts, and
  ///     it reads this now-warm cache instead of issuing its own fetch.
  ///
  /// Pinned by "the ERROR state issues EXACTLY ONE category read" in
  /// `services_list_screen_refresh_test.dart`, so neither dropping it (0) nor
  /// doubling it (2) can land unnoticed.
  ///
  /// `mounted` is re-checked in the continuation: the screen can be popped
  /// while the refetch is in flight, and touching `ref` after dispose throws
  /// under Riverpod 3.x.
  void _refreshCategoryCatalogues(DateTime now) {
    ref.invalidate(approvedCategoriesProvider);
    // Also drop the whole service-types family (no arg = all categories):
    // a type newly approved under an EXISTING category must appear on entry.
    ref.invalidate(serviceTypesProvider);
    unawaited(_stampWhenRefreshSucceeds(now));
  }

  /// Settles on the refreshed [approvedCategoriesProvider] read and records
  /// the freshness stamp only when it actually resolved. A failure returns
  /// silently — leaving the caches STALE is the whole point, so the very next
  /// entry retries instead of waiting out the window.
  Future<void> _stampWhenRefreshSucceeds(DateTime now) async {
    try {
      await ref.read(approvedCategoriesProvider.future);
    } on Object {
      return;
    }
    if (!mounted) return;
    ref.read(categoryCatalogueFreshnessProvider.notifier).stamp(now);
  }

  @override
  void dispose() {
    _screenProtection.release();
    super.dispose();
  }

  /// Pushes [location] and, once the pushed flow pops back to this (kept-alive)
  /// screen, invalidates [approvedCategoriesProvider] so a category approved
  /// by an admin while the user was away appears without a cold restart.
  ///
  /// This is the route-return hook: because the /services route is kept alive,
  /// [initState] fires only on first entry and will NOT re-run on pop-back —
  /// awaiting the [GoRouter.push] Future (which completes when the destination
  /// pops) is the simplest mechanism that reliably re-fires on every return
  /// from the setup / edit / request-category flows.
  ///
  /// CONTRACT: every destination opened through here MUST exit by POPPING.
  /// A `context.go(...)` exit replaces the stack instead of popping, so this
  /// Future never completes, the invalidation never fires, and the awaited call
  /// leaks — the exact bug that shipped when [ServiceSetupScreen] exited with
  /// `go`. That screen now pops (see its `_leave`), which is why this hook is
  /// sound for both the FAB and the empty-state CTA.
  Future<void> _openAndRefresh(String location) async {
    await context.push<void>(location);
    if (mounted) _refreshCategoryCataloguesIfStale();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final asyncServices = ref.watch(servicesListProvider);

    return Scaffold(
      backgroundColor: BrandColors.base,
      appBar: _ServicesAppBar(
        title: l10n.servicesTitle,
        showBack: widget.showBack,
        backFallbackRoute: widget.backFallbackRoute,
      ),
      // Tile 0 ("Послуги") — this screen IS that destination. Hosted via
      // Scaffold's own slot (not nested inside a body SafeArea) so it mounts
      // identically to the other three master tab screens — see
      // `VelvetBottomNavBar`'s doc comment and `ProfileScaffold.bottomNavBar`.
      bottomNavigationBar: widget.showBottomNav
          ? VelvetBottomNavBar(
              activeIndex: 0,
              scheduleRoute: widget.navScheduleRoute,
              profileRoute: widget.navProfileRoute,
              bookingsRoute: widget.navBookingsRoute,
            )
          : null,
      floatingActionButton: asyncServices.maybeWhen(
        data: (list) => (list.isEmpty || !widget.writable)
            ? null
            : _NeumorphicExtendedFab(
                key: const Key('btn-create-service'),
                label: l10n.servicesAdd,
                // ONE "add services" surface for both cases: the FAB (master
                // already has services) and the empty-state CTA below both open
                // the multi-select setup screen. The backend bulk endpoint is
                // additive, so the same screen appends to an existing catalogue.
                onTap: () => _openAndRefresh(widget.resolvedSetupRoute),
              ),
        orElse: () => null,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      body: AppRefreshIndicator(
        // Pull-to-refresh refreshes BOTH the master's own services AND the
        // approved-category cache, so a category approved by an admin appears
        // on the next pull without a cold restart. `refresh()` awaits the
        // services reload; the category provider is invalidated (re-fetches
        // lazily on the next watch) — both are kicked off here.
        onRefresh: () async {
          // UNCONDITIONAL (unlike entry / pop-back): a pull is an explicit
          // request for fresh data. Stamping through the same helper keeps a
          // re-entry moments later from busting the caches all over again.
          _refreshCategoryCatalogues(ref.read(clockProvider)());
          // approvedCategoriesProvider and serviceTypesProvider are intentionally
          // NOT awaited: their stale humanized-label fallback degrades gracefully,
          // and the spinner dismissal is gated only on the services re-fetch below.
          await ref.read(servicesListProvider.notifier).refresh();
        },
        child: asyncServices.when(
          loading: () => const _LoadingBody(),
          error: (e, _) {
            if (kDebugMode) {
              // Log the runtime type only — never the exception object, which
              // can carry server data in its message.
              log(
                'ServicesListScreen: async error — ${e.runtimeType}',
                name: 'feature.services.presentation',
                level: 900,
              );
            }
            final failure = e is Failure ? e : UnknownFailure(cause: e);
            return _errorScrollable(
              ErrorState(
                key: const Key('services_error_state'),
                failure: failure,
                // N2: routed through the ONE fan-out helper rather than
                // `ref.invalidate(servicesListProvider)`. Measured honestly:
                // the old form still worked here, because the screen holds a
                // live subscription and Riverpod re-runs the errored upstream
                // when the rebuilt wrapper re-watches it. It is kept out of the
                // screen anyway so the structural guard in
                // `services_catalogue_invalidation_test.dart` can be absolute —
                // no `onRetry` exemption, and no dependence on a `dart format`
                // line break landing in the right place to keep that exemption
                // working. Behaviourally covered by "the error-state RETRY
                // BUTTON re-fetches and recovers to the list" in
                // `services_list_screen_test.dart`, which had no coverage at
                // all before N2.
                onRetry: () => invalidateMasterServiceCatalogues(ref),
              ),
            );
          },
          data: (list) {
            if (list.isEmpty) {
              // Same destination as the FAB — the multi-select setup screen is
              // the only "add services" surface. It POPs back here on save /
              // close, which is what lets [_openAndRefresh]'s awaited push
              // resolve and re-fire the category invalidation.
              return _EmptyState(
                // Phase 320 (D3): null hides the CTA entirely rather than
                // disabling it — a greyed "Додати послугу" would promise a
                // write the backend refuses.
                onCreate: widget.writable
                    ? () => _openAndRefresh(widget.resolvedSetupRoute)
                    : null,
              );
            }
            return _LoadedBody(
              onOpen: _openAndRefresh,
              editRouteBuilder: widget.resolvedEditRouteBuilder,
              services: list,
              initialExpandCategory: widget.initialExpandCategory,
              writable: widget.writable,
            );
          },
        ),
      ),
    );
  }

  /// Wraps [child] in a [SingleChildScrollView] with [AlwaysScrollableScrollPhysics]
  /// so [RefreshIndicator] can still be triggered even on the error state, which
  /// might not have enough content to scroll naturally.
  Widget _errorScrollable(Widget child) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: SizedBox(height: 400, child: child),
    );
  }
}

// ---------------------------------------------------------------------------
// App bar
// ---------------------------------------------------------------------------

class _ServicesAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _ServicesAppBar({
    required this.title,
    this.showBack = false,
    this.backFallbackRoute,
  });

  final String title;

  /// See [ServicesListScreen.showBack]. `false` (the default, and what both
  /// pre-existing mounts pass) emits the byte-identical `AppBar` this bar
  /// shipped with — `leading: null` leaves `automaticallyImplyLeading` at its
  /// `true` default, so the root-navigator `/services` push keeps Material's
  /// automatic arrow untouched.
  final bool showBack;

  /// See [ServicesListScreen.backFallbackRoute].
  final String? backFallbackRoute;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  /// 2026-09-14 audit (mobile-security LOW) — the GUARDED pop.
  ///
  /// `GoRouterDelegate.pop` does not merely assert on an empty stack: it
  /// THROWS `GoError('There is nothing to pop')` in release too. That state is
  /// reachable here — `service_setup_screen.dart`'s no-stack branch falls back
  /// to `context.go(exitRoute)` and `app_router.dart` points that `exitRoute`
  /// at THIS route, so the operator can legitimately arrive with an empty root
  /// stack. Combined with `showBottomNav: false` this arrow is then their only
  /// on-screen exit, so an unguarded `pop()` would throw and strand them
  /// inside the privileged salon-manage shell.
  ///
  /// REUSE-FIRST: the same `canPop() ? pop() : <fallback>` idiom
  /// `service_edit_screen.dart`'s `_popServiceEditScreen` already established
  /// for this feature, with the fallback supplied by the route rather than
  /// hard-coded, exactly as `ServiceSetupScreen.exitRoute` is.
  void _handleBack(BuildContext context) {
    final GoRouter router = GoRouter.of(context);
    if (router.canPop()) {
      router.pop();
      return;
    }
    final String? fallback = backFallbackRoute;
    if (fallback != null) {
      router.go(fallback);
    }
    // No fallback and nothing to pop: absorb the tap. Throwing would be worse
    // than a no-op, and the two `showBack: false` mounts never reach here.
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return AppBar(
      backgroundColor: BrandColors.base,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      // GEOMETRY NOTE (2026-09-14 audit) — MEASURED, not reasoned. A probe on
      // this leading slot's laid-out `RenderBox` returns Size(56, 56) at
      // (0,0)-(56,56): `AppBar` constrains `leading` TIGHT ON BOTH AXES
      // (`_kLeadingWidth == kToolbarHeight == 56`), so `NeumorphicIconButton`'s
      // own 48x48 `Container` is stretched to 56x56 with zero clearance.
      //
      // `extrudedSmall`'s light shadow is `Offset(-5, -5)` at blur 12
      // (`velvet_geometry.dart:199-210`), reaching ~17 dp left of a pillow
      // whose left edge already sits at x = 0, so it IS clipped horizontally.
      // ACCEPTED for parity with `schedule_editor_stubs.dart:51`, which puts
      // the same button in the same `AppBar.leading` slot.
      leading: showBack
          ? NeumorphicIconButton(
              key: ServicesListScreen.backKey,
              icon: Icons.arrow_back_ios_new_rounded,
              semanticLabel: l10n.servicesListBackSemanticLabel,
              onTap: () => _handleBack(context),
            )
          : null,
      title: Text(title, style: VelvetText.pageTitle),
    );
  }
}

// ---------------------------------------------------------------------------
// Loaded body
// ---------------------------------------------------------------------------

class _LoadedBody extends ConsumerStatefulWidget {
  const _LoadedBody({
    required this.onOpen,
    required this.editRouteBuilder,
    required this.services,
    this.initialExpandCategory,
    this.writable = true,
  });

  /// Pushes a route and invalidates [approvedCategoriesProvider] on return.
  /// Provided by [_ServicesListScreenState._openAndRefresh].
  final Future<void> Function(String location) onOpen;

  /// Phase 317 (D3) — already resolved by
  /// [ServicesListScreen.resolvedEditRouteBuilder], so this private widget
  /// never re-applies the `?? RouteNames.serviceEdit` default and cannot drift
  /// from the public one.
  final String Function(String serviceId) editRouteBuilder;

  final List<MasterService> services;

  /// Upper-cased wire slug of the category to pre-expand on first build.
  /// When null or empty all sections start collapsed (the default).
  final String? initialExpandCategory;

  /// Phase 320 (D3) — already resolved by [ServicesListScreen.writable].
  /// `false` passes a null `onEdit` to every [ServiceCard], which
  /// [ServiceCard] itself treats as "not tappable" (D3).
  final bool writable;

  @override
  ConsumerState<_LoadedBody> createState() => _LoadedBodyState();
}

class _LoadedBodyState extends ConsumerState<_LoadedBody> {
  // PERF A2 (MEDIUM): the memoized grouping. Re-run [_group] only when the
  // identity of (services, categories.value) changes, so a label-only category
  // refresh ([approvedCategoriesProvider] invalidated on entry / return / pull)
  // does not re-bucket. Living in [State] keeps the cache alive across the
  // frequent rebuilds those invalidations trigger.
  List<MasterService>? _cachedServices;
  List<ServiceCategoryOption>? _cachedCategories;
  List<CategoryGroup>? _cachedGroups;
  // P-M2 fix: cache the _flatten() result. Invalidated whenever _cachedGroups
  // is recomputed (identity change of services or categories).
  List<_ListItem>? _cachedItems;

  List<CategoryGroup> _resolveGroups(
    AsyncValue<List<ServiceCategoryOption>> categoriesAsync,
    String uncategorizedLabel,
  ) {
    final List<ServiceCategoryOption>? categoriesValue = categoriesAsync.value;
    final bool hit =
        _cachedGroups != null &&
        identical(_cachedServices, widget.services) &&
        identical(_cachedCategories, categoriesValue);
    if (hit) return _cachedGroups!;

    final List<CategoryGroup> groups = groupServicesByCategory(
      services: widget.services,
      categoriesAsync: categoriesAsync,
      uncategorizedLabel: uncategorizedLabel,
    );
    _cachedServices = widget.services;
    _cachedCategories = categoriesValue;
    _cachedGroups = groups;
    // P-M2: invalidate the flatten cache whenever groups are recomputed.
    _cachedItems = null;
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final categoriesAsync = ref.watch(approvedCategoriesProvider);

    final List<CategoryGroup> groups = _resolveGroups(
      categoriesAsync,
      l10n.serviceCategoryUncategorized,
    );

    // Normalise the requested slug once for O(1) per-section comparison.
    final String? targetSlug =
        (widget.initialExpandCategory?.trim().toUpperCase() ?? '').isEmpty
        ? null
        : widget.initialExpandCategory!.trim().toUpperCase();

    // PERF A1 (HIGH): flatten the active-count header + ordered groups into a
    // single typed item list (header, section, section, …) once, then drive a
    // lazy [ListView.builder] off it. This restores off-screen / collapsed
    // construction laziness (resolves M1 + L1) — only visible sections are
    // built, so off-screen cards never allocate an AnimationController nor
    // schedule a Future.delayed entrance timer.
    //
    // P-M2 fix: cache the flattened list and only recompute when groups
    // changed by identity (tracked via _cachedItems null-check set by
    // _resolveGroups on cache miss).
    _cachedItems ??= _flatten(l10n, groups, widget.services.length);
    final List<_ListItem> items = _cachedItems!;

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(
        VelvetSpacing.lg,
        VelvetSpacing.md,
        VelvetSpacing.lg,
        // Bottom padding so the last card clears the floating FAB.
        VelvetSpacing.xxl + VelvetSpacing.xl,
      ),
      itemCount: items.length,
      itemBuilder: (BuildContext context, int index) {
        final _ListItem item = items[index];
        switch (item) {
          case _HeaderItem(:final label):
            return Padding(
              padding: const EdgeInsets.only(bottom: VelvetSpacing.sm),
              // Keyed so tests can locate/assert the active-count heading
              // without matching on the localized plural copy itself.
              child: Text(
                label,
                key: const Key('services_count_header'),
                style: VelvetText.label(),
              ),
            );
          case _SectionItem(:final group):
            // When a target slug was requested:
            //   • the matching section starts expanded,
            //   • every other section starts collapsed.
            // When no target slug is set (null — "Усі послуги" link or
            // bottom-nav tab) all sections start collapsed.
            final bool initiallyExpanded =
                targetSlug != null && group.key == targetSlug;
            final String sectionSlug = group.key.isEmpty ? '_none' : group.key;
            return Padding(
              padding: const EdgeInsets.only(bottom: VelvetSpacing.md),
              child: CategorySection(
                // Stable key per bucket so expand/collapse state survives
                // rebuilds (e.g. category-cache invalidation on screen return).
                // Also used by widget tests and profile card navigation.
                key: Key('category_section_$sectionSlug'),
                title: group.label,
                count: group.cards.length,
                slug: group.key.isEmpty ? null : group.key,
                initiallyExpanded: initiallyExpanded,
                // LAZY form (2026-09-13 audit, M10): the cards are built
                // inside [CategorySection]'s own `_expanded` branch, so a
                // COLLAPSED section — which is every section by default on
                // this screen — allocates no [ServiceCard], and therefore no
                // AnimationController / CurvedAnimation / entrance timer.
                // Passing a materialised `children:` list here built them all
                // before CategorySection was even constructed.
                childCount: group.cards.length,
                childBuilder: (BuildContext context, int i) {
                  final CategoryGroupEntry entry = group.cards[i];
                  return Padding(
                    padding: const EdgeInsets.only(top: VelvetSpacing.md),
                    child: ServiceCard(
                      key: Key('service_card_${entry.service.id}'),
                      service: entry.service,
                      // Opt out of the leading photo well (default `true`;
                      // the booking-wizard picker keeps it). Service photo
                      // upload is deferred to Phase 9.x, so on THIS screen
                      // every card renders the identical spa placeholder —
                      // 50 dp of row width (40 well + 10 gap) spent on a
                      // glyph that distinguishes no card from any other, on
                      // the one screen whose whole job is reading and
                      // editing long service names. When Phase 9.x lands a
                      // real photo, drop this line.
                      showPhoto: false,
                      // ALIGNMENT RULE: a service name starts at exactly the
                      // same x as its category section's TITLE, so the two
                      // form one vertical spine down the section. Derived
                      // from the header's own constituents (its `md` padding
                      // + 20 dp glyph slot + `sm` gap) minus the card's own
                      // leading inset — never a literal 36, so it tracks any
                      // future change to the header's padding, icon size or
                      // gap instead of silently drifting off it.
                      //
                      // Dropping the photo well above reclaimed 50 dp but it
                      // was also the only thing indenting the name; this
                      // spends 36 of those 50 to put the name back under its
                      // heading.
                      leadingIndent:
                          CategorySection.headerTitleInset -
                          ServiceCard.contentInset,
                      onEdit: widget.writable
                          ? () => widget.onOpen(
                              widget.editRouteBuilder(entry.service.id),
                            )
                          : null,
                      // P-M3 fix: cap the effective stagger index at 5 so
                      // the maximum outstanding delay is 90*5 = 450 ms,
                      // regardless of list length. Visual behaviour is
                      // identical for the first 6 cards.
                      appearDelay: Duration(
                        milliseconds: 90 * entry.staggerIndex.clamp(0, 5),
                      ),
                    ),
                  );
                },
              ),
            );
        }
      },
    );
  }

  /// Flattens the active-count header + ordered [groups] into a single typed
  /// item list for the lazy [ListView.builder]. Each category section carries
  /// its own cards (with their precomputed continuous stagger index) so the
  /// builder can construct one section at a time as it scrolls into view.
  List<_ListItem> _flatten(
    AppLocalizations l10n,
    List<CategoryGroup> groups,
    int total,
  ) {
    return <_ListItem>[
      _HeaderItem(_activeServicesLabel(l10n, total)),
      for (final CategoryGroup group in groups) _SectionItem(group),
    ];
  }

  /// Formats the count sub-heading.
  ///
  /// Full localisation for plural forms is deferred until the l10n team approves
  /// Ukrainian plural copy; for now a simple Ukrainian string is used inline
  /// (will migrate to ARB once copy is approved — backlog LOW).
  String _activeServicesLabel(AppLocalizations l10n, int count) =>
      '$count ${_serviceWordUk(count)}';

  String _serviceWordUk(int n) {
    if (n % 100 >= 11 && n % 100 <= 14) return 'послуг';
    switch (n % 10) {
      case 1:
        return 'послуга';
      case 2:
      case 3:
      case 4:
        return 'послуги';
      default:
        return 'послуг';
    }
  }
}

// ---------------------------------------------------------------------------
// Flattened list items (header + sections) for the lazy ListView.builder
// ---------------------------------------------------------------------------

/// One row in the flattened item list driving [ListView.builder].
@immutable
sealed class _ListItem {
  const _ListItem();
}

/// The active-count sub-heading row at the top of the list.
@immutable
class _HeaderItem extends _ListItem {
  const _HeaderItem(this.label);

  final String label;
}

/// A category section (header pillow + its collapsible cards).
@immutable
class _SectionItem extends _ListItem {
  const _SectionItem(this.group);

  final CategoryGroup group;
}

// ---------------------------------------------------------------------------
// Loading body — three shimmer skeleton cards
// ---------------------------------------------------------------------------

class _LoadingBody extends StatelessWidget {
  const _LoadingBody();

  @override
  Widget build(BuildContext context) {
    const List<double> titleWidths = <double>[0.62, 0.45, 0.54];
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        VelvetSpacing.lg,
        VelvetSpacing.md,
        VelvetSpacing.lg,
        VelvetSpacing.lg,
      ),
      children: <Widget>[
        for (int i = 0; i < titleWidths.length; i++) ...<Widget>[
          _SkeletonCard(
            key: Key('skeleton_card_$i'),
            titleWidthFactor: titleWidths[i],
          ),
          const SizedBox(height: VelvetSpacing.md),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Skeleton card
// ---------------------------------------------------------------------------

/// A raised neumorphic card whose content areas are replaced by shimmering
/// inset bars — depth preserved (never flat grey) so the loading state reads
/// on-brand. One [AnimationController] per card (each card is independent).
class _SkeletonCard extends StatefulWidget {
  const _SkeletonCard({super.key, this.titleWidthFactor = 0.62});

  final double titleWidthFactor;

  @override
  State<_SkeletonCard> createState() => _SkeletonCardState();
}

class _SkeletonCardState extends State<_SkeletonCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer;

  @override
  void initState() {
    super.initState();
    _shimmer = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1350),
    )..repeat();
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return NeumorphicCard(
      child: Row(
        children: <Widget>[
          _ShimmerBar(
            controller: _shimmer,
            height: 48,
            width: 48,
            radius: VelvetRadii.field,
          ),
          const SizedBox(width: VelvetSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _ShimmerBar(
                  controller: _shimmer,
                  height: 16,
                  widthFactor: widget.titleWidthFactor,
                  radius: 6,
                ),
                const SizedBox(height: VelvetSpacing.md),
                Row(
                  children: <Widget>[
                    Expanded(
                      flex: 3,
                      child: _ShimmerBar(
                        controller: _shimmer,
                        height: 26,
                        radius: VelvetRadii.pill,
                      ),
                    ),
                    const SizedBox(width: VelvetSpacing.sm),
                    Expanded(
                      flex: 4,
                      child: _ShimmerBar(
                        controller: _shimmer,
                        height: 26,
                        radius: VelvetRadii.pill,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: VelvetSpacing.md),
          _ShimmerBar(
            controller: _shimmer,
            height: 32,
            width: 32,
            radius: VelvetRadii.field,
          ),
        ],
      ),
    );
  }
}

/// A single recessed bar with a travelling camel highlight sweep.
class _ShimmerBar extends StatelessWidget {
  const _ShimmerBar({
    required this.controller,
    required this.height,
    required this.radius,
    this.width,
    this.widthFactor,
  });

  final AnimationController controller;
  final double height;
  final double radius;
  final double? width;
  final double? widthFactor;

  @override
  Widget build(BuildContext context) {
    final Widget bar = AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, _) {
        final double t = controller.value;
        final double pos = -1.3 + t * 2.6;
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            color: BrandColors.shadowDarkCard.withValues(alpha: 0.55),
            gradient: LinearGradient(
              begin: Alignment(pos - 0.6, 0),
              end: Alignment(pos + 0.6, 0),
              colors: <Color>[
                BrandColors.shadowDarkCard.withValues(alpha: 0.0),
                BrandColors.accent.withValues(alpha: 0.35),
                BrandColors.shadowDarkCard.withValues(alpha: 0.0),
              ],
              stops: const <double>[0.0, 0.5, 1.0],
            ),
          ),
          child: SizedBox(height: height),
        );
      },
    );

    if (widthFactor != null) {
      return FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: widthFactor,
        child: bar,
      );
    }
    return SizedBox(width: width, child: bar);
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

/// Vertically centred empty-state: recessed camel medallion + headline +
/// supporting text + single primary CTA. The empty state does NOT show the
/// FAB — the inline CTA is the only first-run path so intent is unmistakable.
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onCreate});

  /// Opens the create form and invalidates the category cache on return.
  /// Provided by [_ServicesListScreenState._openAndRefresh].
  ///
  /// Phase 320 (D3) — nullable: `null` (read-only viewer) hides the CTA
  /// entirely rather than rendering it disabled. Every pre-existing caller
  /// passes a non-null callback and renders exactly as before.
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(VelvetSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox(
              height: 104,
              width: 104,
              child: NeumorphicInset(
                // Circular inset medallion — same carved-in treatment as the
                // empty-state in the approved preview.
                radius: 52,
                child: Center(
                  child: Icon(
                    Icons.spa_rounded,
                    size: 44,
                    color: BrandColors.accent.withValues(alpha: 0.9),
                  ),
                ),
              ),
            ),
            const SizedBox(height: VelvetSpacing.xl),
            Text(
              l10n.servicesEmpty,
              style: VelvetText.headingSm,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: VelvetSpacing.sm),
            Text(
              l10n.servicesEmptyBody,
              style: VelvetText.body(),
              textAlign: TextAlign.center,
            ),
            if (onCreate != null) ...<Widget>[
              const SizedBox(height: VelvetSpacing.xl),
              SizedBox(
                width: 240,
                child: NeumorphicButton(
                  key: const Key('btn-create-service-empty'),
                  label: l10n.servicesAdd,
                  icon: Icons.add_rounded,
                  onPressed: onCreate!,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Neumorphic extended FAB
// ---------------------------------------------------------------------------

/// A hand-built neumorphic extended FAB — camel/mocha gradient pill that
/// depresses on press. Material's [FloatingActionButton.extended] cannot
/// render the paired soft-UI shadows, so this widget replicates the approved
/// preview's approach exactly.
class _NeumorphicExtendedFab extends StatefulWidget {
  const _NeumorphicExtendedFab({
    super.key,
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  State<_NeumorphicExtendedFab> createState() => _NeumorphicExtendedFabState();
}

class _NeumorphicExtendedFabState extends State<_NeumorphicExtendedFab> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.label,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) {
          setState(() => _pressed = false);
          widget.onTap();
        },
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1.0,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: VelvetSpacing.lg),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[
                  BrandColors.accentLatte,
                  BrandColors.accentDeep,
                ],
              ),
              borderRadius: BorderRadius.circular(VelvetRadii.pill),
              boxShadow: _pressed ? null : VelvetShadows.extrudedButtonAccent,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(
                  Icons.add_rounded,
                  color: BrandColors.white,
                  size: 22,
                ),
                const SizedBox(width: VelvetSpacing.sm),
                Text(widget.label, style: VelvetText.cta()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
