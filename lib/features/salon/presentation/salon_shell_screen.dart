// Phase 21.8 — Salon Shell Screen.
//
// The main navigation wrapper for `SALON_OWNER` and `SALON_ADMIN` — a
// VelvetTouch bottom-nav shell scoped to one specific salon. Structurally a
// plain `Scaffold(body: IndexedStack(...), bottomNavigationBar:
// SalonBottomNav(...))`, mirroring the design source's
// `salon_shell_screen.dart` for the ONE nav context this phase ships: the
// SHARED 4-tab set (`SalonBottomNav.ownerAdminItems`) — identical for owner
// and admin. The design's owner-as-master 5-tab replacement is Phase 21.15
// (unbuilt: its source field `UserProfileResponse.masterProfile` does not
// exist yet) and is NOT ported here.
//
// Tab hosts (Phase 21.8 scope — see the phase's own scope table):
//   0 Салон    — REAL: `SalonManagementProfileScreen(salonId, embedded: true)`
//   1 Записи   — placeholder (`/salon/bookings` has no screen — Phase 21.12)
//   2 Команда  — REAL: the SAME screen, `initialTab: 1` (its internal
//                `salonManageTabStaff` sub-tab)
//   3 Профіль  — placeholder (owner: Phase 21.14: admin: Phase 21.16)
//
// `salonId` comes from the go_router PATH PARAM (the caller,
// `app_router.dart`); `isOwner` is derived from `authProvider`'s role, never
// from `extra` — an `extra` is null on a cold deep link (e.g. `SALON_ADMIN`
// arriving straight from `SalonHomeResolverScreen`, or any bookmarked URL),
// so reading role from the extra would silently misclassify that path.
//
// LAZY TABS (mobile-perf MEDIUM follow-up, 2026-08-28) — `IndexedStack` lays
// out ALL of its children on every parent rebuild, not just the visible one,
// so unconditionally listing all 4 tabs here meant every bottom-nav tap paid
// to build+layout both full `SalonManagementProfileScreen` subtrees (each
// holding 4 `TextEditingController`s plus cover/hero/tab-bar/staff-grid
// state) regardless of whether either had ever been opened. `_visitedTabs`
// gates each slot: an unvisited tab renders a trivial `SizedBox.shrink()`
// until its index is first selected, then the real widget takes its place —
// permanently, at the SAME list position and Key, which is what makes this
// safe: `IndexedStack` does not use `TickerMode`/`Offstage` for its
// non-current children (unlike a covered go_router route), so it never
// disposes an already-built child on its own. Once built, a tab's element is
// simply left in the tree, so its `State` (a half-scrolled Команда tab, an
// open edit form) survives every subsequent switch exactly as it did when
// all 4 were built eagerly — no `AutomaticKeepAliveClientMixin` needed,
// because there is nothing here for it to protect against. The Салон/Команда
// pair still share ONE `salonManagementProfileProvider(salonId)` fetch
// regardless of visit order: the family is keyed on `salonId`, not on
// mount timing, so whichever of the two mounts first resolves the request
// and the other reads the same cached `AsyncData`.
//
// OWNERSHIP BOUNCE (mobile-security MEDIUM follow-up, 2026-08-28) — see
// [_bounceIfNotOwned].

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/role_home.dart';
import 'package:beautica_mobile/shared/widgets/salon_bottom_nav.dart';

import '../application/my_salons_notifier.dart';
import '../application/salon_shell_provider.dart';
import '../domain/salon.dart';
import 'salon_management_profile_screen.dart';
import 'widgets/salon_shell_tab_placeholder.dart';

/// The `SALON_OWNER`/`SALON_ADMIN` bottom-nav shell for one salon.
class SalonShellScreen extends ConsumerStatefulWidget {
  const SalonShellScreen({super.key, required this.salonId});

  /// Backend Salon-row UUID this shell is scoped to.
  final String salonId;

  @override
  ConsumerState<SalonShellScreen> createState() => _SalonShellScreenState();
}

class _SalonShellScreenState extends ConsumerState<SalonShellScreen> {
  /// Tab indices that have been selected at least once this shell visit —
  /// gates lazy child construction (see the file header LAZY TABS note).
  /// Tab 0 is always the first frame's `tab` value (`SalonShell.build` seeds
  /// `0`), so it is populated by the first `build()` call, not eagerly here.
  final Set<int> _visitedTabs = <int>{};

  List<SalonNavItem>? _navItemsCache;
  AppLocalizations? _navItemsCacheL10n;

  /// Memoized per-locale (mobile-perf LOW follow-up, 2026-08-28) —
  /// `SalonBottomNav.ownerAdminItems` allocates a fresh `List<SalonNavItem>`
  /// plus 4 `SalonNavItem`s every call; recomputing on every `build()` (every
  /// bottom-nav tap, every `authProvider` re-emission) was pure churn since
  /// the result only ever changes when [l10n] itself changes (a locale
  /// switch). Cached against the exact `AppLocalizations` instance so a real
  /// locale change still picks up fresh labels.
  List<SalonNavItem> _navItems(AppLocalizations l10n) {
    if (_navItemsCache == null || _navItemsCacheL10n != l10n) {
      _navItemsCacheL10n = l10n;
      _navItemsCache = SalonBottomNav.ownerAdminItems(l10n);
    }
    return _navItemsCache!;
  }

  /// mobile-security MEDIUM follow-up (2026-08-28) — closes, for `/shell`,
  /// the same `salonManageGuard` `SALON_OWNER` "not resolved yet" ADMIT
  /// window that `SalonManagementProfileScreen._bounceIfNotOwned` already
  /// closes for `/manage` (see that screen's own doc). `AuthRefreshNotifier`
  /// (`routing/auth_refresh_notifier.dart`) listens only to `authProvider`,
  /// so go_router's `redirect:` is never re-run once `mySalonsProvider`
  /// resolves AFTER the guard's synchronous ADMIT fallback — without a
  /// listener here, the one-frame flash `/manage` self-heals via its own
  /// listener becomes a PERMANENT stay on `/shell` for a salon this owner
  /// does not own, for the life of that navigation.
  ///
  /// Lives on [SalonShellScreen] itself, NOT inside the embedded
  /// `SalonManagementProfileScreen` instances it hosts (which is exactly why
  /// that screen's own listener early-returns when `embedded == true` — see
  /// its doc). The shell mounts that screen TWICE in one `IndexedStack`
  /// (Салон + Команда, same `salonId`); two `ref.listen`s on the same
  /// `mySalonsProvider` emission would race two `context.go` calls (the
  /// original H1b hazard). ONE listener here, for the whole shell, makes
  /// that race impossible by construction — `build()` runs once per frame no
  /// matter how many tabs it hosts.
  ///
  /// `SALON_ADMIN` is exempt — `salonManageGuard`'s admin arm is an exact
  /// synchronous `User.salonId` check with no unresolved window to close.
  void _bounceIfNotOwned(AuthSession? session) {
    if (session is! Authenticated || session.user.role != UserRole.salonOwner) {
      return;
    }
    ref.listen<AsyncValue<List<Salon>>>(mySalonsProvider, (
      AsyncValue<List<Salon>>? previous,
      AsyncValue<List<Salon>> next,
    ) {
      // Concrete-subtype gate — `copyWithPrevious` keeps a stale `.value`
      // attached to a LATER `AsyncLoading`/`AsyncError` (e.g. mid-retry, or
      // right after a cross-account login on the same device), so only a
      // genuinely resolved `AsyncData` is ever trusted here — mirrors
      // `salonManageGuard`'s own gate in `app_router.dart`.
      if (next is! AsyncData<List<Salon>>) return;
      final List<Salon> salons = next.value;
      if (salons.any((Salon salon) => salon.id == widget.salonId)) return;
      if (context.mounted) context.go(roleHomePath(session.user.role));
    });
  }

  /// Renders [build] only once tab [index] has been visited; otherwise a
  /// trivial placeholder. See the file header LAZY TABS note for why this is
  /// safe to leave un-kept-alive.
  Widget _lazyChild(int index, Widget Function() build) =>
      _visitedTabs.contains(index)
      ? build()
      : SizedBox.shrink(key: Key('salon-shell-tab-$index-lazy'));

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final AsyncValue<AuthSession> authAsync = ref.watch(authProvider);
    final AuthSession? session = authAsync.value;
    final bool isOwner =
        session is Authenticated && session.user.role == UserRole.salonOwner;

    _bounceIfNotOwned(session);

    final int tab = ref.watch(salonShellProvider(widget.salonId));
    _visitedTabs.add(tab);

    final List<Widget> children = <Widget>[
      // Салон — REAL host, embedded (no back chevron; ownership is bound by
      // this shell's own `_bounceIfNotOwned` above, not by the embedded
      // screen — see that screen's `embedded` doc for why it skips its own
      // equivalent check).
      _lazyChild(
        0,
        () => SalonManagementProfileScreen(
          key: const Key('salon-shell-tab-salon'),
          salonId: widget.salonId,
          embedded: true,
        ),
      ),
      // Записи — no host screen exists yet (`/salon/bookings` — see
      // `app_router.dart`'s own note on why this route is unregistered).
      _lazyChild(
        1,
        () => SalonShellTabPlaceholder(
          key: const Key('salon-shell-tab-bookings'),
          icon: Symbols.calendar_month_rounded,
          title: l10n.salonShellBookingsSoonTitle,
          blurb: l10n.salonShellBookingsSoonBlurb,
        ),
      ),
      // TODO(phase-21.12): swap in the real salon-wide schedule host.

      // Команда — the SAME real host, opened on its internal
      // `salonManageTabStaff` sub-tab.
      _lazyChild(
        2,
        () => SalonManagementProfileScreen(
          key: const Key('salon-shell-tab-team'),
          salonId: widget.salonId,
          embedded: true,
          initialTab: 1,
        ),
      ),
      // Профіль — no host screen exists yet for either role.
      _lazyChild(
        3,
        () => SalonShellTabPlaceholder(
          key: Key('salon-shell-tab-profile-${isOwner ? 'owner' : 'admin'}'),
          icon: Symbols.person_rounded,
          title: l10n.salonShellProfileSoonTitle,
          blurb: l10n.salonShellProfileSoonBlurb,
        ),
      ),
      // TODO(phase-21.14): swap in the real owner own-profile host.
      // TODO(phase-21.16): swap in the real admin own-profile host.
    ];

    return Scaffold(
      key: const Key('salon-shell-screen'),
      backgroundColor: BrandColors.base,
      body: IndexedStack(index: tab, children: children),
      bottomNavigationBar: SalonBottomNav(
        key: const Key('salon-shell-bottom-nav'),
        currentIndex: tab,
        items: _navItems(l10n),
        onSelect: (int i) =>
            ref.read(salonShellProvider(widget.salonId).notifier).select(i),
      ),
    );
  }
}
