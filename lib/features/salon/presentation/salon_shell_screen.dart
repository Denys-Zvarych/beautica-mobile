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
// Nav destinations (Phase 21.8 scope — see the phase's own scope table):
//   0 Салон    — REAL: `SalonManagementProfileScreen(salonId, embedded: true)`
//   1 Записи   — placeholder (`/salon/bookings` has no screen — Phase 21.12)
//   2 Команда  — the SAME screen instance as destination 0, on its staff
//                sub-tab (see NAV INDEX vs STACK SLOT below)
//   3 Профіль  — owner: REAL: `OwnerOwnProfileScreen(embedded: true)`
//                (Phase 21.14); admin: REAL:
//                `AdminOwnProfileScreen(embedded: true)` (Phase 21.16)
//
// NAV INDEX vs STACK SLOT (mobile-perf LOW follow-up, 2026-08-30) — these two
// indices are NOT the same number and must never be conflated; the mapping is
// [_navToStackSlot] / [_stackSlotFor], and it is the ONLY place either index
// is converted into the other.
//
//   nav 0 «Салон»   ─┐
//                    ├─> stack slot 0 — the ONE hosted profile screen
//   nav 2 «Команда» ─┘
//   nav 1 «Записи»  ───> stack slot 1 — bookings placeholder
//   nav 3 «Профіль» ───> stack slot 2 — own profile (owner and admin each
//                        get their own real screen)
//
// Destinations 0 and 2 were previously two SEPARATE children of the same
// `IndexedStack`, built from byte-identical configurations (same `salonId`,
// `embedded`, `tab`, `onTabSelected`) and differing only by `Key`. Since the
// tab-sync fix made both CONTROLLED from the one shared sub-tab index, that
// second instance rendered, offstage, a pixel-for-pixel duplicate of whatever
// the user was already looking at — a whole second cover image, hero card,
// tab body and set of `TextEditingController`s, plus a second
// `_SalonReviewsSectionState` holding its own `_sort` and therefore keeping a
// second `salonReviewsProvider(salonId, <stale sort>)` family instance alive
// after any sort change. Hosting ONE instance and pointing both destinations
// at it removes both costs by construction, with no `Consumer`/`select`
// narrowing needed (the watched value is an `int`; narrowing would only ever
// have spared a cheap nav bar).
//
// `SalonBottomNav.currentIndex` is still the NAV index — the shell's selected
// destination is what the highlight means, and it stays 0..3 even though the
// stack now only has 3 slots.
//
// TAB SYNC — destinations 0 and 2 are two views of ONE screen, whose own
// 4-tab in-screen switcher used to be private `setState` state that touched
// no provider. The nav highlight therefore never moved when the in-screen
// «Команда» tab was tapped, and (because `IndexedStack` never disposes a
// visited child) the «Салон» destination could keep rendering the staff grid
// after a round trip. The screen is now CONTROLLED from
// `salonManageTabProvider(salonId)`, and the two directions of the sync live
// in [_onSubTabSelected] / [_onNavSelected]. This stays SHARED STATE, not
// routing: the shell is deliberately a standalone `GoRoute`, not a
// `StatefulShellRoute`, so the four sub-tabs get no sub-routes of their own.
//
// `salonId` comes from the go_router PATH PARAM (the caller,
// `app_router.dart`); `isOwner` is derived from `authProvider`'s role, never
// from `extra` — an `extra` is null on a cold deep link (e.g. `SALON_ADMIN`
// arriving straight from `SalonHomeResolverScreen`, or any bookmarked URL),
// so reading role from the extra would silently misclassify that path.
//
// LAZY SLOTS (mobile-perf MEDIUM follow-up, 2026-08-28) — `IndexedStack` lays
// out ALL of its children on every parent rebuild, not just the visible one,
// so unconditionally listing every slot here meant every bottom-nav tap paid
// to build+layout the full `SalonManagementProfileScreen` subtree (4
// `TextEditingController`s plus cover/hero/tab-bar/staff-grid state)
// regardless of whether it had ever been opened. `_visitedSlots` gates each
// STACK SLOT (not each nav destination — see the mapping above): an unvisited
// slot renders a trivial `SizedBox.shrink()` until a destination that maps to
// it is first selected, then the real widget takes its place — permanently,
// at the SAME list position and Key, which is what makes this safe:
// `IndexedStack` does not use `TickerMode`/`Offstage` for its non-current
// children (unlike a covered go_router route), so it never disposes an
// already-built child on its own. Once built, a slot's element is simply left
// in the tree, so its `State` (a half-scrolled staff grid, an open edit form)
// survives every subsequent switch exactly as it did when all slots were
// built eagerly — no `AutomaticKeepAliveClientMixin` needed, because there is
// nothing here for it to protect against. Slot 0 is the first frame's slot
// (`SalonShell.build` seeds nav 0), so the shared profile host is built
// exactly when it always was; deduping removed a build, it added none.
//
// OWNERSHIP BOUNCE (mobile-security MEDIUM follow-up, 2026-08-28) — see
// [_bounceIfNotOwned].

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
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
import 'admin_own_profile_screen.dart';
import 'owner_own_profile_screen.dart';
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
  /// `IndexedStack` SLOT indices (never nav indices — see the file header's
  /// NAV INDEX vs STACK SLOT note) that have been reached at least once this
  /// shell visit — gates lazy child construction (see the LAZY SLOTS note).
  /// Slot 0 is always the first frame's slot (`SalonShell.build` seeds nav
  /// `0`), so it is populated by the first `build()` call, not eagerly here.
  final Set<int> _visitedSlots = <int>{};

  List<SalonNavItem>? _navItemsCache;
  AppLocalizations? _navItemsCacheL10n;

  @override
  void initState() {
    super.initState();
    // Phase 287 D2 — the write happens AFTER the first frame, unawaited, so
    // a Keystore write is never on the critical path of paint; the shell
    // must render at exactly the speed it renders today. A `!mounted` guard
    // covers the callback firing after this element has already been
    // disposed (e.g. a very fast salon switch), and [_writeLastSalon] itself
    // swallows any storage failure — a failed write just degrades to "the
    // app forgot", which Phase 288's reader already tolerates.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_writeLastSalon(widget.salonId));
    });
  }

  @override
  void didUpdateWidget(covariant SalonShellScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Phase 287 D3 — this is a route-level widget, so a `go` between two
    // shells can reuse the element instead of remounting it. Re-issue the
    // write ONLY when the salon actually changed; a plain rebuild (e.g. an
    // `authProvider` re-emission) must not re-write. Missing this case is
    // the classic bug: switch salons, kill the app, reopen the previous one.
    if (widget.salonId != oldWidget.salonId) {
      unawaited(_writeLastSalon(widget.salonId));
    }
  }

  /// Durably records `{userId, salonId}` under `StorageKeys.lastSalon`
  /// (Phase 287) so a later cold start can reopen this salon (Phase 288's
  /// reader). Phase 286 D2 fixed the envelope as `{userId, salonId}`, not a
  /// bare id, so Phase 288 can treat a `userId` mismatch as "no value
  /// stored" — mirrors `PendingLocalityStore`'s JSON-blob style.
  ///
  /// Unconditional across roles (D4): an admin's slot simply always holds
  /// their one salon, and branching on role here would be a second place
  /// encoding "who has many salons".
  ///
  /// No dedicated notifier/provider (D5) — the slot is write-only here and
  /// read once at cold start, never observed reactively, so this reads
  /// [secureStorageProvider] directly via `ref.read`.
  Future<void> _writeLastSalon(String salonId) async {
    final AuthSession? session = ref.read(authProvider).value;
    if (session is! Authenticated) return;
    // mobile-security MEDIUM-1 audit cycle 1 follow-up (2026-09-02) — a
    // `logout()` in progress wipes secure storage several `await`s BEFORE it
    // flips [authProvider]'s state to `Unauthenticated` (see that method's
    // doc comment for why the ordering is deliberate). Across that window
    // `session is Authenticated` above still passes with the OUTGOING
    // session, so without this check a shell rebuild landing mid-logout would
    // re-populate the just-wiped `lastSalon` slot. Read synchronously and
    // immediately before the write — never `watch`/`listen` a state-holder's
    // own provider.
    if (ref.read(authProvider.notifier).logoutInFlight) return;
    try {
      await ref
          .read(secureStorageProvider)
          .writeLastSalon(
            jsonEncode(<String, String>{
              'userId': session.user.id,
              'salonId': salonId,
            }),
          );
    } catch (_) {
      // D2 — a storage failure never surfaces to the user and never blocks
      // a frame; it degrades to "the app forgot".
    }
  }

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
  /// `SalonManagementProfileScreen` it hosts (which is exactly why that
  /// screen's own listener early-returns when `embedded == true` — see its
  /// doc). The shell used to mount that screen TWICE in one `IndexedStack`
  /// (Салон + Команда, same `salonId`), and two `ref.listen`s on the same
  /// `mySalonsProvider` emission would have raced two `context.go` calls (the
  /// original H1b hazard). The duplicate host is gone as of the 2026-08-30
  /// dedupe, but this listener stays HERE regardless: one listener for the
  /// whole shell keeps that race impossible by construction, independently of
  /// how many hosts a future phase adds — `build()` runs once per frame no
  /// matter how many slots it holds.
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

  /// Renders [build] only once stack [slot] has been reached; otherwise a
  /// trivial placeholder. See the file header LAZY SLOTS note for why this is
  /// safe to leave un-kept-alive.
  ///
  /// [slot] is a STACK SLOT, not a nav index — the lazy placeholder's own Key
  /// says `slot` for exactly that reason.
  Widget _lazySlot(int slot, Widget Function() build) =>
      _visitedSlots.contains(slot)
      ? build()
      : SizedBox.shrink(key: Key('salon-shell-slot-$slot-lazy'));

  /// Bottom-nav destination index -> `IndexedStack` child index.
  ///
  /// Indexed BY nav destination (0..3, `SalonBottomNav.ownerAdminItems`);
  /// the value is the stack slot that destination renders. «Салон» (0) and
  /// «Команда» (2) deliberately share slot 0 — they are two sub-tabs of ONE
  /// hosted `SalonManagementProfileScreen`, not two screens (see the file
  /// header's NAV INDEX vs STACK SLOT note). The stack therefore has 3
  /// children while the nav still has 4 destinations.
  static const List<int> _navToStackSlot = <int>[0, 1, 0, 2];

  /// The `IndexedStack` child index that bottom-nav destination [navIndex]
  /// renders. The single conversion point between the two index spaces.
  static int _stackSlotFor(int navIndex) => _navToStackSlot[navIndex];

  /// Bottom-nav destinations that map to the shared profile host (slot 0).
  static const int _navSalon = 0;

  /// Phase 21.6 audit follow-up — was a third hand-written `2`. It now
  /// ALIASES the constant declared beside `SalonBottomNav.ownerAdminItems`
  /// itself, so the shell, [StaffSettingsScreen] and [MoveAdminSalonScreen]
  /// can no longer drift apart, and the unit pin on that constant
  /// (`staff_settings_screen_test.dart`) covers this call site too.
  static const int _navTeam = kSalonTeamNavTab;

  /// The in-screen sub-tab index that the bottom-nav destination implies.
  /// [_navTeam] IS the profile screen's staff sub-tab (1); [_navSalon] is its
  /// «Про салон» sub-tab (0). Any other destination hosts no profile screen
  /// at all and leaves the sub-tab untouched.
  /// Aliases the constant declared beside [kSalonManageTabKeys] — see
  /// [_navTeam] for why the third hand-written literal was removed.
  static const int _staffSubTab = kSalonStaffSubTab;
  static const int _aboutSubTab = 0;

  /// Reconciles BOTH indices after an in-screen tab tap.
  ///
  /// The in-screen row is the source of the change here, so the sub-tab is
  /// set verbatim and the bottom-nav highlight follows it: the staff sub-tab
  /// is the «Команда» destination, every other sub-tab («Про салон»,
  /// «Послуги», «Відгуки») is the «Салон» destination. Without the second
  /// half the reported bug appears — tapping the in-screen «Команда» leaves
  /// the nav highlight on the previous destination. The FIRST half is what
  /// keeps the mirror case honest: from «Команда», tapping in-screen
  /// «Послуги» moves the nav back to «Салон», and because both destinations
  /// now render the SAME host the two can no longer disagree about which
  /// sub-tab is showing.
  ///
  /// Both destinations map to stack slot 0, so this never changes
  /// `IndexedStack.index` — only the nav highlight and the sub-tab move.
  void _onSubTabSelected(int subTab) {
    ref.read(salonManageTabProvider(widget.salonId).notifier).select(subTab);
    ref
        .read(salonShellProvider(widget.salonId).notifier)
        .select(subTab == _staffSubTab ? _navTeam : _navSalon);
  }

  /// Reconciles the sub-tab after a BOTTOM-NAV tap — the other direction of
  /// the same sync. Without this, selecting «Команда» from the nav would
  /// leave the sub-tab wherever an earlier in-screen tap had parked it, and
  /// the «Команда» destination would render «Про салон». Destinations that
  /// host no profile screen (1 «Записи», 3 «Профіль») leave the sub-tab alone
  /// so coming back to «Салон»/«Команда» restores what was there.
  ///
  /// This is also what makes the shared host safe: since one instance serves
  /// both destinations, the sub-tab write below is the ONLY thing that
  /// distinguishes them.
  void _onNavSelected(int navIndex) {
    ref.read(salonShellProvider(widget.salonId).notifier).select(navIndex);
    if (navIndex == _navSalon) {
      ref
          .read(salonManageTabProvider(widget.salonId).notifier)
          .select(_aboutSubTab);
    } else if (navIndex == _navTeam) {
      ref
          .read(salonManageTabProvider(widget.salonId).notifier)
          .select(_staffSubTab);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final AsyncValue<AuthSession> authAsync = ref.watch(authProvider);
    final AuthSession? session = authAsync.value;
    final bool isOwner =
        session is Authenticated && session.user.role == UserRole.salonOwner;

    _bounceIfNotOwned(session);

    final int navIndex = ref.watch(salonShellProvider(widget.salonId));
    // The SHARED in-screen sub-tab index. The one hosted profile screen below
    // is driven from it, which is what keeps the in-screen row and the bottom
    // nav one selection instead of two.
    final int subTab = ref.watch(salonManageTabProvider(widget.salonId));
    final int stackSlot = _stackSlotFor(navIndex);
    _visitedSlots.add(stackSlot);

    final List<Widget> children = <Widget>[
      // Slot 0 — «Салон» (nav 0) AND «Команда» (nav 2). ONE embedded host for
      // both destinations (no back chevron; ownership is bound by this shell's
      // own `_bounceIfNotOwned` above, not by the embedded screen — see that
      // screen's `embedded` doc for why it skips its own equivalent check).
      //
      // The two destinations differ ONLY in which sub-tab they select, which
      // is why a second instance was pure duplication (see the file header).
      // Switching between them changes neither this child's position nor its
      // `Key`, so the element and its `State` are reused — no dispose, no
      // re-mount, no lost scroll offset, no refetch.
      //
      // CONTROLLED, not merely seeded: `IndexedStack` never disposes a
      // visited child (see the LAZY SLOTS note above), so an uncontrolled
      // host would keep whatever sub-tab an earlier in-screen tap left in its
      // `State` — a round trip through «Команда» and back would land the
      // «Салон» destination on the staff grid.
      _lazySlot(
        0,
        () => SalonManagementProfileScreen(
          key: const Key('salon-shell-slot-profile'),
          salonId: widget.salonId,
          embedded: true,
          tab: subTab,
          onTabSelected: _onSubTabSelected,
        ),
      ),
      // Slot 1 — «Записи» (nav 1). No host screen exists yet
      // (`/salon/bookings` — see `app_router.dart`'s own note on why this
      // route is unregistered).
      _lazySlot(
        1,
        () => SalonShellTabPlaceholder(
          key: const Key('salon-shell-tab-bookings'),
          icon: Symbols.calendar_month_rounded,
          title: l10n.salonShellBookingsSoonTitle,
          blurb: l10n.salonShellBookingsSoonBlurb,
        ),
      ),
      // TODO(phase-21.12): swap in the real salon-wide schedule host.

      // Slot 2 — «Профіль» (nav 3). Phase 21.14 shipped the OWNER host and
      // Phase 21.16 the ADMIN one; both branches are now real screens.
      //
      // Both branches keep their existing `Key`s
      // (`salon-shell-tab-profile-owner` / `-admin`) — those are the handles
      // the shell's own tests use to assert WHICH role's profile a slot
      // renders, and they stayed stable across the placeholder swap so the
      // admin case is still distinguishable from the owner case by key alone.
      //
      // `onSalonTap:` (admin only) — the affiliation card's "take me to this
      // salon" destination is a NAV MOVE inside this shell, not a route, so
      // the shell hands down [_onNavSelected]. Reusing that method rather than
      // writing `salonShellProvider(...).select(0)` inline is what keeps the
      // sub-tab reconciliation attached to it (see [_onNavSelected]'s doc): a
      // raw index write would land on «Салон» while leaving the shared
      // `salonManageTabProvider` parked on whatever sub-tab an earlier
      // in-screen tap chose — the exact desync the TAB SYNC note above exists
      // to prevent.
      //
      // `embedded: true` — this is a tab ROOT: there is nothing to pop, so no
      // back chevron, and the shell already supplies the `SalonBottomNav`.
      //
      // `visible:` (mobile-perf MEDIUM + LOW follow-up, 2026-08-31) — a raw
      // `IndexedStack` sets neither `Offstage` nor `TickerMode` on its
      // non-current children (see the LAZY SLOTS note above), so an
      // off-screen slot has no way to know it is off-screen. BOTH of this
      // slot's screens need that signal for two things — spending its one-shot
      // entrance animation on a VISIBLE frame, and holding the PII
      // screen-protection refcount only while its own phone/Instagram is
      // actually on screen — so the shell, which owns the index, passes it
      // down. See `OwnerOwnProfileScreen.visible` for the two defects.
      _lazySlot(
        2,
        () => isOwner
            ? OwnerOwnProfileScreen(
                key: const Key('salon-shell-tab-profile-owner'),
                embedded: true,
                visible: stackSlot == 2,
              )
            : AdminOwnProfileScreen(
                key: const Key('salon-shell-tab-profile-admin'),
                embedded: true,
                visible: stackSlot == 2,
                // `hostSalonId:` (mobile-perf LOW, 2026-09-05) — the admin
                // profile's «Салон» card reads
                // `salonManagementProfileProvider`, the SAME family slot 0
                // above is keyed on. It used to derive that key itself from
                // `User.salonId` (a `GET /users/me` field); any casing or
                // formatting divergence from this PATH PARAM resolved a
                // DIFFERENT family element and cold-started a second copy of
                // the salon + staff-roster reads inside a shell where the
                // correct cost is zero. Handing down the shell's own key
                // makes the two provably the same element.
                hostSalonId: widget.salonId,
                onSalonTap: () => _onNavSelected(_navSalon),
              ),
      ),
    ];

    return Scaffold(
      key: const Key('salon-shell-screen'),
      backgroundColor: BrandColors.base,
      // STACK SLOT here…
      body: IndexedStack(index: stackSlot, children: children),
      bottomNavigationBar: SalonBottomNav(
        key: const Key('salon-shell-bottom-nav'),
        // …but the NAV index here: the highlight tracks the destination the
        // user chose, which stays 0..3 even though «Салон» and «Команда»
        // resolve to the same stack slot. Passing `stackSlot` would light up
        // «Салон» while standing on «Команда» — the exact desync this chain
        // just fixed.
        currentIndex: navIndex,
        items: _navItems(l10n),
        onSelect: _onNavSelected,
      ),
    );
  }
}
