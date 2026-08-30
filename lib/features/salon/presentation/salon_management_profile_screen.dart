// Phase 21.2 — Salon Profile (Owner + Admin, editable).
//
// Structurally a mirror of the shipped read-only `public_salon_profile_screen
// .dart`: full-bleed cover + overlapping hero identity card, a 4-tab switcher
// (Про салон / Персонал / Послуги / Відгуки). Owner/admin deltas layered on
// top, per the phase doc's locked 2026-07-06 decision — **admin sees the
// identical screen as owner**, with exactly one structural difference: admin
// has no salon-delete action (owner-only, `SalonController.java:104`).
//
// REUSE-FIRST — widgets reused verbatim from
// `features/salon/presentation/widgets/`:
//   [SalonCover], [CoverIconButton], [SalonLogo] — cover/hero chrome
//   [SalonTabBar]                                — the 4-tab switcher
//   [SalonMasterCard]                             — the «Персонал» grid cards
//   [SalonServicesAccordion]                      — «Послуги» tab (unchanged)
//   [SalonReviewsSection]                         — «Відгуки» tab (unchanged)
// `ContactTile` (shared/widgets) for the phone/Instagram rows. None of these
// were forked or copied.
//
// NOT reused from `public_salon_profile_screen.dart`: its `_SalonHeroCard`/
// `_CoverAndHero` are PRIVATE to that file and bundle client-only geometry
// (an `ExpandableNote`-driven variable-height overlap, Phase 224) this screen
// doesn't need — the design source's preview `_OwnerHeroCard` is a much
// simpler fixed-content card, so this file writes its own small
// `_ManagementHeroCard` from the already-shared [SalonLogo] + [NeumorphicCard]
// rather than pulling in geometry built for a feature (the location note)
// this screen never renders.
//
// EDIT — the top-right `Icons.tune_rounded` cover control pushes
// [SalonSettingsScreen]; editing itself now lives entirely in three
// dedicated screens reached from there — `SalonProfileEditScreen` (name/
// description), `SalonContactsEditScreen` (phone/Instagram) and
// `SalonAddressEditScreen` (street/building/note). This screen's «Про салон»
// tab is read-only (see [_AboutReadView]) and never mutates state itself; the
// inline edit-mode form this comment used to describe was removed once the
// settings screen stopped popping a `true` result to trigger it (dead code,
// deleted — see git history for `_editMode` if it's ever needed again).
//
// Portfolio management (an owner "+" add-photo tile) is likewise NOT built
// here — no media-upload endpoint is wired for this phase's Implementation
// Steps, so the read-only description + contacts are all «Про салон» shows.
//
// «Персонал» — Phase 21.4 (Invite Staff, form only) is BUILT: the trailing
// "+" tile pushes [InviteStaffScreen] via `RouteNames.salonInviteStaff`.
// Phase 21.5 (Master Management Profile) is BUILT too: staff-card taps push
// `RouteNames.salonManageStaffMember` (see [_openStaffMember]). The roster
// itself now lists both masters and admins — `getSalonStaff` (GET
// `/salons/{salonId}/staff`), not a masters-only endpoint — a deliberate,
// user-approved behaviour change landed alongside 21.5.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/icons/beautica_asset_icons.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/location/domain/resolved_locality.dart';
import 'package:beautica_mobile/features/location/state/resolved_locality_provider.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/role_home.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/feedback/show_velvet_snack.dart';
import 'package:beautica_mobile/shared/formatters/address_lines.dart';
import 'package:beautica_mobile/shared/utils/instagram_url.dart';
import 'package:beautica_mobile/shared/widgets/contact_tile.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:beautica_mobile/shared/widgets/expandable_note.dart';
import 'package:beautica_mobile/shared/widgets/rating_star.dart';

import '../application/my_salons_notifier.dart';
import '../application/salon_management_profile_notifier.dart';
import '../application/salon_service_catalog_notifier.dart';
import '../domain/salon.dart';
import '../domain/salon_service_catalog.dart';
import '../domain/salon_staff_member.dart';
import 'widgets/salon_cover_widgets.dart';
import 'widgets/salon_master_card.dart';
import 'widgets/salon_reviews_section.dart';
import 'widgets/salon_services_accordion.dart';

/// Owner/admin editable profile for the salon identified by [salonId].
class SalonManagementProfileScreen extends ConsumerStatefulWidget {
  const SalonManagementProfileScreen({
    super.key,
    required this.salonId,
    this.tab,
    this.onTabSelected,
    this.embedded = false,
  });

  /// Backend Salon-row UUID of the profile being managed.
  final String salonId;

  /// CONTROLLED sub-tab index for the in-screen
  /// «Про салон»/«Команда»/«Послуги»/«Відгуки» switcher.
  ///
  /// `null` (the default, and every routed call site — `app_router.dart`'s
  /// `/salons/:salonId/manage`) leaves the switcher UNCONTROLLED: the screen
  /// keeps its own `_tab` in `State` and behaves exactly as it did before,
  /// starting on 0. Non-null hands ownership of the index to the caller —
  /// [SalonShellScreen] drives it from `salonManageTabProvider(salonId)` so
  /// the in-screen row and the shell's bottom nav stay one shared selection
  /// rather than two that silently disagree.
  ///
  /// Replaces the former `initialTab` (Phase 21.8), which was a one-way
  /// seed: it flowed shell -> screen on first build only and could never
  /// report a later in-screen tap back, which is precisely the desync this
  /// pair fixes. `initialTab: 1` becomes `tab: <watched>` +
  /// [onTabSelected].
  final int? tab;

  /// Fired on every in-screen tab tap, with the newly-selected index —
  /// including when [tab] is `null` (uncontrolled), where the screen ALSO
  /// updates its own `_tab`. `null` (the default) makes every existing
  /// routed call site behave identically to before.
  final ValueChanged<int>? onTabSelected;

  /// Phase 21.8 — `true` when this screen is mounted as one `IndexedStack`
  /// child of [SalonShellScreen] rather than as its own routed, back-
  /// navigable page. Additive, defaults to `false` so every existing call
  /// site (`app_router.dart`'s `/salons/:salonId/manage`) renders IDENTICALLY
  /// to before this phase.
  ///
  /// When `true`:
  ///   * the cover's `salon-manage-back` [CoverIconButton] is hidden — the
  ///     shell's own bottom nav is the only navigation surface, and there is
  ///     nothing on the Navigator stack to pop back to (H1a);
  ///   * [_bounceIfNotOwned] is skipped entirely (H1b) — the shell mounts
  ///     this screen TWICE (Салон + Команда) in one `IndexedStack`, so both
  ///     instances' `ref.listen` would otherwise fire on the same
  ///     `mySalonsProvider` emission and race two `context.go` calls. The
  ///     shell's own route guard (`salonManageGuard`, reused verbatim for
  ///     `/salons/:salonId/shell`) already binds ownership before this
  ///     screen ever mounts, so the second, screen-level check this bounce
  ///     exists for is redundant in the embedded context.
  final bool embedded;

  @override
  ConsumerState<SalonManagementProfileScreen> createState() =>
      _SalonManagementProfileScreenState();
}

class _SalonManagementProfileScreenState
    extends ConsumerState<SalonManagementProfileScreen> {
  static const double _coverHeight = 232;
  static const double _heroProtrusion = 116;

  /// UNCONTROLLED fallback — read ONLY when `widget.tab == null`. A
  /// controlled caller ([SalonShellScreen]) owns the index in a provider and
  /// this field is never consulted, so the two can never drift apart.
  int _tab = 0;

  void _openSettings() {
    context.push(RouteNames.salonManageSettings(widget.salonId));
  }

  void _openProfileEdit() =>
      context.push(RouteNames.salonProfileEdit(widget.salonId));

  void _openContactsEdit() =>
      context.push(RouteNames.salonContactsEdit(widget.salonId));

  /// Handles an in-screen tab tap. Updates local state only in the
  /// uncontrolled case, then ALWAYS reports upward so a controlled caller can
  /// reconcile its own (and, in the shell's case, the bottom nav's) index.
  void _onTabSelected(int index) {
    if (widget.tab == null) {
      setState(() => _tab = index);
    }
    widget.onTabSelected?.call(index);
  }

  /// Opens the staff management profile for [member] (Phase 21.5) — works for
  /// both a master and an admin entry; the destination screen branches on
  /// [member.role] internally.
  void _openStaffMember(SalonStaffMember member) => context.push(
    RouteNames.salonManageStaffMember(widget.salonId, member.userId),
  );

  void _openInviteStaff() =>
      context.push(RouteNames.salonInviteStaff(widget.salonId));

  // mobile-security LOW follow-up (2026-08-28) — `salonManageGuard`'s
  // `SALON_OWNER` arm (`app_router.dart`) admits a cold deep link BEFORE
  // `mySalonsProvider` resolves (documented, synchronous-`redirect:`-only
  // design — see that guard's own comment). `GET /salons/{salonId}` (this
  // screen's own data source, `salonManagementProfileProvider`) is the SAME
  // publicly-readable endpoint `public_salon_profile_notifier.dart` uses, so
  // during that window a SALON_OWNER can see a fully-rendered shell of a
  // salon they do not own (not a privilege escalation — `PATCH`/`DELETE`
  // stay backend-gated — but a real exposure gap, same class as the
  // SALON_ADMIN one the guard already closed). Once `mySalonsProvider`
  // resolves, close the window here: bounce off this screen the instant the
  // owner's real salon list turns out not to contain [widget.salonId].
  // SALON_ADMIN is exempt — its ownership check (`User.salonId`) is already
  // synchronous in the guard, so there is no window to close, and gating on
  // role keeps this listener from ever touching `mySalonsProvider` for a
  // role that has no use for it (would otherwise reintroduce the same
  // unwanted-fetch shape the mobile-perf HIGH finding on that provider just
  // closed).
  void _bounceIfNotOwned(AuthSession? session) {
    // Phase 21.8 H1b / mobile-security MEDIUM follow-up (2026-08-28) —
    // embedded (i.e. mounted inside `SalonShellScreen`'s `IndexedStack`) is
    // NOT this screen's job to ownership-bounce. The Salon Shell mounts this
    // screen TWICE in one `IndexedStack` (Салон + Команда, same `salonId`) —
    // if each instance carried its own `ref.listen` below, both would fire
    // on the SAME `mySalonsProvider` emission and race two `context.go`
    // calls (and since `roleHomePath(salonOwner)` now points at the shell's
    // own resolver, that race can loop). `SalonShellScreen` itself now owns
    // exactly ONE such listener for the whole shell instead — see its own
    // `_bounceIfNotOwned` in `salon_shell_screen.dart` — so this early
    // return just keeps this screen from adding a second, redundant one when
    // embedded. NOTE: this is NOT because the route guard already bound
    // ownership — `salonManageGuard`'s `SALON_OWNER` arm has a documented
    // "admit while `mySalonsProvider` is unresolved" window, which is
    // exactly what the shell's own listener (not the guard) closes.
    if (widget.embedded) return;
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
      // `salonManageGuard`'s own gate in `app_router.dart` and
      // `SalonShellScreen`'s own `_bounceIfNotOwned`.
      if (next is! AsyncData<List<Salon>>) return;
      final List<Salon> salons = next.value;
      if (salons.any((Salon salon) => salon.id == widget.salonId)) return;
      if (context.mounted) context.go(roleHomePath(session.user.role));
    });
  }

  @override
  Widget build(BuildContext context) {
    final AuthSession? session = ref.watch(authProvider).value;
    _bounceIfNotOwned(session);
    // Same `isOwner` predicate `salon_settings_screen.dart` uses to gate its
    // owner-only rows — see [_AboutReadView.canEdit] for why the two "add"
    // links must not be offered to a SALON_ADMIN.
    final bool isOwner =
        session is Authenticated && session.user.role == UserRole.salonOwner;
    final AsyncValue<SalonManagementProfileData> async = ref.watch(
      salonManagementProfileProvider(widget.salonId),
    );
    final double topInset = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: BrandColors.base,
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.only(bottom: VelvetSpacing.xxl),
        child: async.when(
          loading: () => const Padding(
            padding: EdgeInsets.only(top: 120),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (Object e, _) => Padding(
            padding: EdgeInsets.only(top: topInset + VelvetSpacing.xxl),
            child: ErrorState(
              failure: e is Failure ? e : UnknownFailure(cause: e),
              onRetry: () => ref.invalidate(
                salonManagementProfileProvider(widget.salonId),
              ),
            ),
          ),
          data: (SalonManagementProfileData data) {
            final (Salon salon, List<SalonStaffMember> staff) = data;
            return _LoadedBody(
              salonId: widget.salonId,
              salon: salon,
              staff: staff,
              embedded: widget.embedded,
              topInset: topInset,
              coverHeight: _coverHeight,
              heroProtrusion: _heroProtrusion,
              tab: widget.tab ?? _tab,
              onTabSelected: _onTabSelected,
              canEdit: isOwner,
              onOpenSettings: _openSettings,
              onOpenStaffMember: _openStaffMember,
              onInviteStaff: _openInviteStaff,
              onAddDescription: _openProfileEdit,
              onAddInstagram: _openContactsEdit,
            );
          },
        ),
      ),
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
    required this.staff,
    required this.embedded,
    required this.topInset,
    required this.coverHeight,
    required this.heroProtrusion,
    required this.tab,
    required this.onTabSelected,
    required this.canEdit,
    required this.onOpenSettings,
    required this.onOpenStaffMember,
    required this.onInviteStaff,
    required this.onAddDescription,
    required this.onAddInstagram,
  });

  final String salonId;
  final Salon salon;
  final List<SalonStaffMember> staff;

  /// Phase 21.8 — see [SalonManagementProfileScreen.embedded]. Hides the
  /// `salon-manage-back` cover control (H1a).
  final bool embedded;
  final double topInset;
  final double coverHeight;
  final double heroProtrusion;
  final int tab;
  final ValueChanged<int> onTabSelected;

  /// See [_AboutReadView.canEdit] — `true` only for a `SALON_OWNER`.
  final bool canEdit;

  final VoidCallback onOpenSettings;
  final ValueChanged<SalonStaffMember> onOpenStaffMember;
  final VoidCallback onInviteStaff;
  final VoidCallback onAddDescription;
  final VoidCallback onAddInstagram;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final List<String> tabs = <String>[
      l10n.salonTabAbout,
      l10n.salonManageTabStaff,
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
          embedded: embedded,
          onOpenSettings: onOpenSettings,
        ),
        const SizedBox(height: VelvetSpacing.lg),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: VelvetSpacing.lg),
          child: SalonTabBar(
            tabs: tabs,
            selected: tab,
            onSelect: onTabSelected,
          ),
        ),
        const SizedBox(height: VelvetSpacing.lg),
        KeyedSubtree(
          key: ValueKey<String>('salon-manage-tab-body-${_tabKeys[tab]}'),
          child: switch (tab) {
            0 => _AboutReadView(
              salon: salon,
              canEdit: canEdit,
              onAddDescription: onAddDescription,
              onAddInstagram: onAddInstagram,
            ),
            1 => Padding(
              padding: const EdgeInsets.symmetric(horizontal: VelvetSpacing.lg),
              child: _StaffTab(
                salonId: salonId,
                staff: staff,
                onOpenMember: onOpenStaffMember,
                onInvite: onInviteStaff,
              ),
            ),
            2 => Padding(
              padding: const EdgeInsets.symmetric(horizontal: VelvetSpacing.lg),
              child: _ServicesTab(salonId: salonId),
            ),
            _ => Padding(
              padding: const EdgeInsets.symmetric(horizontal: VelvetSpacing.lg),
              child: SalonReviewsSection(salonId: salonId),
            ),
          },
        ),
      ],
    );
  }

  static const List<String> _tabKeys = <String>[
    'about',
    'staff',
    'services',
    'reviews',
  ];
}

// ---------------------------------------------------------------------------
// Cover + hero
// ---------------------------------------------------------------------------

class _CoverAndHero extends StatelessWidget {
  const _CoverAndHero({
    required this.coverHeight,
    required this.heroProtrusion,
    required this.topInset,
    required this.salon,
    required this.embedded,
    required this.onOpenSettings,
  });

  final double coverHeight;
  final double heroProtrusion;
  final double topInset;
  final Salon salon;

  /// Phase 21.8 H1a — when `true`, the back control is omitted: the shell has
  /// no Navigator entry to pop back to for this `IndexedStack` child.
  final bool embedded;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
        if (!embedded)
          Positioned(
            top: topInset + VelvetSpacing.sm,
            left: VelvetSpacing.lg,
            child: CoverIconButton(
              key: const Key('salon-manage-back'),
              icon: Icons.arrow_back_ios_new_rounded,
              semanticLabel: l10n.salonProfileBackLabel,
              onTap: () => context.pop(),
            ),
          ),
        Positioned(
          top: topInset + VelvetSpacing.sm,
          right: VelvetSpacing.lg,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // Static demo unread state; tap is a placeholder — the
              // notification centre is out of scope (all notifications stay
              // dark until release, see mobile-backlog).
              //
              // The glyph keeps its baked-in unread dot verbatim per the
              // approved design (docs/signup-designs/SalonManagementDesign/
              // lib/screens/salon_profile_screen.dart:407-425) — do not add
              // an overlay dot or swap the icon. But the accessible name
              // deliberately does NOT say "unread": onTap is a no-op, so a
              // screen-reader user would be told about unread notifications
              // with no way to act on or dismiss the claim. Keep the label
              // plain ("Сповіщення" / "Notifications") until a real
              // notification centre exists — do not restore the longer
              // "…, unread" label from the preview app.
              CoverIconButton(
                key: const Key('salon-manage-notifications'),
                svgIcon: BeauticaAssetIcons.notificationUnread,
                semanticLabel: l10n.salonManageNotificationsSemanticLabel,
                onTap: () {},
              ),
              const SizedBox(width: VelvetSpacing.sm),
              CoverIconButton(
                key: const Key('salon-manage-settings'),
                icon: Icons.tune_rounded,
                iconColor: BrandColors.accentDeep,
                semanticLabel: l10n.salonManageSettingsSemanticLabel,
                onTap: onOpenSettings,
              ),
            ],
          ),
        ),
        Positioned(
          left: VelvetSpacing.lg,
          right: VelvetSpacing.lg,
          bottom: 0,
          child: _ManagementHeroCard(salon: salon),
        ),
      ],
    );
  }
}

/// The owner/admin identity card — logo + name + ★ rating · review count,
/// then the full resolved location (city → district → street + building)
/// and an optional location note. No inline edit affordances (editing lives
/// behind the settings hub → «Редагувати профіль»).
///
/// `ConsumerWidget` (Phase 21.14 — was `StatelessWidget`) so it can
/// `ref.watch` [resolvedLocalityProvider] for the city/district display
/// names (the provider also resolves the oblast, needed internally to drive
/// the cascade, but the oblast itself never renders here — product decision
/// 2026-08-29) — see [build] for the fallback chain and why
/// `salon.city`/`salon.region` are never read.
class _ManagementHeroCard extends ConsumerWidget {
  const _ManagementHeroCard({required this.salon});

  final Salon salon;

  static const double _logoDiameter = 68;

  /// Icon width (15) + the gap after it (`VelvetSpacing.xs + 1`) — the exact
  /// horizontal offset the address row's `Icon` + `SizedBox` already produce
  /// below, reused here so the location note lines up under the address
  /// TEXT, not under its leading pin icon.
  static const double _addressTextIndent = 15 + VelvetSpacing.xs + 1;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final String? monogram = salon.name.trim().isEmpty
        ? null
        : salon.name.trim()[0].toUpperCase();
    final String ratingLabel = salon.avgRating?.toStringAsFixed(1) ?? '—';

    // Phase 21.14 — this hero card renders the FULL resolved location
    // (city → district → street/building) rather than the legacy free-text
    // `city` + street/buildingNo it showed before. This is a DELIBERATE
    // extension beyond the approved design (`docs/signup-designs/
    // SalonManagementDesign/lib/screens/salon_profile_screen.dart:513-519`,
    // which renders only `'${salon.locality}, ${salon.address}'` — two
    // segments, no district, and no note row at all) — requested by the
    // user 2026-08-29. Do NOT "restore" the design's two-segment line.
    // The oblast (region) is deliberately excluded from this line too —
    // separate product decision, same date: a salon's oblast never renders
    // to the client, even though it is resolved below (see the doc on
    // `resolvedLocalityProvider`'s watch just above [addressLine]).
    //
    // `salon.city`/`salon.region` are never read here: both are legacy
    // free-text fields the backend stopped writing at Phase 10.6
    // (`SalonService.updateSalon` — see `Salon.city`'s own doc), so either
    // one can be stale (frozen at whatever it was before the salon's last
    // taxonomy edit) the moment a resolved oblast/city name is also on
    // screen — rendering both next to each other risks showing two
    // DIFFERENT addresses for the same salon.
    //
    // `resolvedLocalityProvider` resolves the taxonomy `oblastId`/`cityId`/
    // `districtId` UUIDs to display names via the SAME memoized
    // (`keepAlive: true`) `oblastList`/`cityList`/`districtList` provider
    // chain `SalonAddressEditScreen` uses — this scan was promoted out of
    // that screen's own private method into the shared provider (REUSE-FIRST;
    // see that provider's doc) rather than re-implemented here.
    //
    // ASYNC FALLBACK (chosen deliberately): `AsyncValue.value` is nullable in
    // Riverpod 3.x (the removed `valueOrNull` — see `auth_selectors.dart`)
    // and collapses BOTH "still loading" and "resolution failed" down to
    // `null` uniformly — no spinner, no error box ever enters this card.
    // Whatever is already known SYNCHRONOUSLY from `salon` itself
    // (street/buildingNo — plain fields, no lookup needed) renders on the
    // very first frame via [buildFullAddressLine]'s independent-per-segment
    // composition; the city/district text simply fills in on the
    // rebuild once the provider resolves. A salon whose lookup never
    // resolves (or fails) still shows its street/building line (or the
    // legacy `address` fallback below) — never nothing, never an error.
    final ResolvedLocality? resolved = ref
        .watch(
          resolvedLocalityProvider(
            oblastId: salon.oblastId,
            cityId: salon.cityId,
            districtId: salon.districtId,
          ),
        )
        .value;
    final String? addressLine =
        buildFullAddressLine(
          cityName: resolved?.city?.name,
          districtName: resolved?.district?.name,
          street: salon.street,
          buildingNo: salon.buildingNo,
        ) ??
        // Last resort: a salon that predates Phase 10.6 (or was never
        // re-saved since) has no taxonomy fields at all — only the legacy
        // pre-composed `address` string is left. Mirrors the identical
        // fallback `public_salon_profile_screen.dart`'s `_streetLine` uses,
        // for the same reason (that field is frozen, not stale — it was
        // never overwritten because the salon was never re-saved).
        (salon.address?.trim().isNotEmpty ?? false ? salon.address : null);
    // Sanitization happens INSIDE `ExpandableNote` (must run on the exact
    // same string the widget measures for overflow AND renders) — mirrors
    // `public_master_profile_screen.dart`'s identical convention; not
    // pre-sanitized here.
    final String? noteText = (salon.locationNote?.trim().isNotEmpty ?? false)
        ? salon.locationNote
        : null;

    return NeumorphicCard(
      key: const Key('salon-manage-hero-card'),
      color: const Color(0xFFEDE4D5),
      padding: const EdgeInsets.all(VelvetSpacing.md + 2),
      // Logo centres against the FULL name+rating(+address) stack, not just
      // the name+rating row — a deliberate departure from
      // docs/signup-designs/SalonManagementDesign/lib/screens/
      // salon_profile_screen.dart:501-510, which keeps address in a second
      // band below an empty gutter (the logo then centres above the card's
      // true midpoint whenever an address is present). Requested by the
      // user 2026-08-29; the preview's two-band shape is intentionally NOT
      // restored.
      child: Row(
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
                  key: const Key('salon-manage-name'),
                  style: VelvetText.displayName20,
                  maxLines: 2,
                  softWrap: true,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 5),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    RatingStar(
                      rating: salon.avgRating,
                      size: 16,
                      showLabel: false,
                    ),
                    const SizedBox(width: 4),
                    Text(ratingLabel, style: VelvetText.bodyStrong14),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        '·  ${l10n.salonReviewCountLabel(salon.reviewCount)}',
                        style: VelvetText.feedbackMuted13,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (addressLine != null) ...<Widget>[
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
                          addressLine,
                          key: const Key('salon-manage-address'),
                          style: VelvetText.bookFeedbackSec13,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
                // Phase 21.14 — `locationNote` on its own row beneath the
                // address, never folded into the address line itself
                // (mirrors `public_salon_profile_screen.dart`'s identical
                // separation). Gated independently of `addressLine != null`
                // — a salon with a note but no resolvable address (or no
                // address at all) must still show the note, not silently
                // drop it.
                if (noteText != null) ...<Widget>[
                  SizedBox(height: addressLine != null ? 2 : 5),
                  Padding(
                    padding: const EdgeInsets.only(left: _addressTextIndent),
                    child: ExpandableNote(
                      key: const Key('salon-manage-location-note'),
                      text: noteText,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Про салон tab — read-only view (editing lives in the dedicated edit
// screens reached from the settings hub — see the file-header EDIT note)
// ---------------------------------------------------------------------------

class _AboutReadView extends StatelessWidget {
  const _AboutReadView({
    required this.salon,
    required this.canEdit,
    required this.onAddDescription,
    required this.onAddInstagram,
  });

  final Salon salon;

  /// `true` only for a `SALON_OWNER` — the two "add" links below push the
  /// `/manage/settings/{profile-edit,contacts-edit}` routes, which are gated
  /// by `salonManageOwnerOnlyGuard` (owner-only by locked design: "admins
  /// cannot edit salon info"). Offering an admin a link that would bounce
  /// them straight back is worse than not offering it, so the predicate here
  /// is deliberately the SAME `isOwner` one `salon_settings_screen.dart`
  /// already uses to gate the rows that push those very routes.
  final bool canEdit;

  final VoidCallback onAddDescription;
  final VoidCallback onAddInstagram;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final String? description = (salon.description?.trim().isNotEmpty ?? false)
        ? salon.description!.trim()
        : null;
    final String? phone = (salon.phone?.trim().isNotEmpty ?? false)
        ? salon.phone!.trim()
        : null;
    final String? instagram = (salon.instagramUrl?.isNotEmpty ?? false)
        ? salon.instagramUrl
        : null;

    // COMPOSITION — the «Контакти» section is normally gated on "at least one
    // contact exists" (the same gate `public_salon_profile_screen.dart`
    // uses). The owner's add-link needs somewhere to live when NEITHER
    // contact is on file, so it joins that gate as a third term rather than
    // being hoisted into its own section: the heading stays a real heading
    // for the rows beneath it, and a non-owner (admin) viewer still sees the
    // exact two-term behaviour — section hidden when both are empty.
    final bool showAddInstagram = canEdit && instagram == null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: VelvetSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (description != null)
            Text(
              description,
              key: const Key('salon-manage-about-text'),
              style: VelvetText.bodyStrong(),
            )
          else if (canEdit)
            // The muted «Опис салону поки не додано» placeholder was dead
            // text on an editable screen — an empty state is an invitation to
            // act, so the owner gets the action instead of the observation.
            _AddLink(
              key: const Key('salon-manage-add-description'),
              label: l10n.salonManageAddDescriptionLink,
              onTap: onAddDescription,
            )
          else
            Text(
              l10n.salonAboutEmpty,
              key: const Key('salon-manage-about-text'),
              style: VelvetText.feedback(BrandColors.muted),
            ),
          if (phone != null ||
              instagram != null ||
              showAddInstagram) ...<Widget>[
            const SizedBox(height: VelvetSpacing.xl),
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: VelvetSpacing.xs),
              child: Text(
                l10n.masterContactsLabel,
                style: VelvetText.sectionLabel(),
              ),
            ),
            if (phone != null)
              ContactTile(
                key: const Key('salon-manage-contact-phone'),
                icon: Icons.phone_outlined,
                value: phone,
                semanticLabel: l10n.phoneLabel,
                // Dialing out is not in this phase's Implementation Steps —
                // editing (not calling) is the affordance this tab offers.
                onTap: () {},
              ),
            if (phone != null && (instagram != null || showAddInstagram))
              const SizedBox(height: VelvetSpacing.sm + 2),
            if (instagram != null)
              ContactTile(
                key: const Key('salon-manage-contact-instagram'),
                icon: Icons.alternate_email,
                label: l10n.masterInstagramLabel,
                value: instagram,
                semanticLabel: l10n.masterInstagramLabel,
                onTap: () => _openInstagram(context, instagram),
              )
            else if (showAddInstagram)
              _AddLink(
                key: const Key('salon-manage-add-instagram'),
                label: l10n.salonManageAddInstagramLink,
                onTap: onAddInstagram,
              ),
          ],
        ],
      ),
    );
  }

  static Future<void> _openInstagram(
    BuildContext context,
    String rawValue,
  ) async {
    final Uri? uri = canonicalInstagramUri(rawValue);
    if (uri == null) {
      _showInstagramError(context);
      return;
    }
    bool launched = false;
    try {
      launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on Object {
      launched = false;
    }
    if (!context.mounted) return;
    if (!launched) _showInstagramError(context);
  }

  static void _showInstagramError(BuildContext context) {
    showErrorSnack(
      context,
      AppLocalizations.of(context).masterInstagramOpenError,
    );
  }
}

/// A small inline "add this" text link — a leading `+` glyph and a mocha
/// [VelvetText.link] label, nothing else. Used twice by [_AboutReadView]
/// («Додати опис», «Додати посилання»).
///
/// REUSE-FIRST note: no existing widget fits. `NeumorphicButton` (the
/// `masterAddServices` empty-state affordance) is a full-height 54 dp
/// gradient CTA — the brief here is explicitly a text link, and a CTA button
/// inside a read-only tab would outrank the tab's real content. The
/// `masterAllServices`/`salonMastersShowAll` inline link is the closest
/// shape, but it is a bare `Text` + trailing chevron built inline at each
/// call site with no shared widget to import, and its trailing chevron means
/// "go see more of what is already here" — the opposite of these two links.
/// The LEADING `+` is borrowed from [_AddStaffTile] on this very screen, so
/// the tab already speaks that vocabulary.
///
/// PRIVATE deliberately: the only consumer is this screen. The links are
/// owner-only and must never appear on `public_salon_profile_screen.dart`
/// (a client viewing a stranger's salon is not invited to describe it), so
/// there is no second call site to promote this to.
class _AddLink extends StatelessWidget {
  const _AddLink({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          // Vertical padding only — the link stays flush with the column's
          // left edge, exactly where the placeholder text it replaces sat,
          // while still clearing a comfortable touch target.
          padding: const EdgeInsets.symmetric(vertical: VelvetSpacing.xs),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                Icons.add_rounded,
                size: 14,
                color: BrandColors.accentDeep,
              ),
              const SizedBox(width: 3),
              Text(label, style: VelvetText.link()),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Персонал tab — staff management grid
// ---------------------------------------------------------------------------

class _StaffTab extends StatelessWidget {
  const _StaffTab({
    required this.salonId,
    required this.staff,
    required this.onOpenMember,
    required this.onInvite,
  });

  final String salonId;
  final List<SalonStaffMember> staff;
  final ValueChanged<SalonStaffMember> onOpenMember;
  final VoidCallback onInvite;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (staff.isEmpty)
          Padding(
            key: const Key('salon-manage-staff-empty'),
            padding: const EdgeInsets.only(bottom: VelvetSpacing.md),
            child: Text(
              l10n.salonManageStaffEmpty,
              style: VelvetText.feedback(BrandColors.muted),
            ),
          ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: VelvetSpacing.md,
            crossAxisSpacing: VelvetSpacing.md,
            mainAxisExtent: kSalonMasterCardHeight,
          ),
          itemCount: staff.length + 1,
          itemBuilder: (BuildContext context, int i) {
            if (i == staff.length) {
              return _AddStaffTile(onTap: onInvite);
            }
            final SalonStaffMember member = staff[i];
            final bool isAdmin = member.role == SalonStaffRole.admin;
            final String? ownTitle = member.professionalTitle?.trim();
            // Phase 21.5 — the roster now includes admins (previously
            // masters-only): an admin has no professional title, so it
            // always shows the admin role label; a master falls back to the
            // generic salon-master label when no own title is set.
            final String role = isAdmin
                ? l10n.salonStaffRoleAdmin
                : (ownTitle != null && ownTitle.isNotEmpty)
                ? ownTitle
                : l10n.masterRoleSalonMaster;
            return SalonMasterCard(
              key: Key('salon-manage-staff-card-${member.userId}'),
              name: member.firstName,
              role: role,
              // Admins carry no service rating — always the placeholder.
              ratingLabel: !isAdmin && member.reviewCount > 0
                  ? (member.avgRating?.toStringAsFixed(1) ?? '—')
                  : '—',
              avatarIndex: i,
              onTap: () => onOpenMember(member),
            );
          },
        ),
      ],
    );
  }
}

/// The trailing "invite staff" tile, always the last cell in the «Персонал»
/// grid. Reuses [SalonMasterCard]'s exact shell dimensions
/// ([kSalonMasterCardHeight], `VelvetRadii.card`, `VelvetShadows.extrudedCard`)
/// so it sits flush with the real cards, but there is no existing production
/// "add tile" widget to reuse (the client-facing masters grid never has one) —
/// this is a small, genuinely new widget, private to this screen.
class _AddStaffTile extends StatefulWidget {
  const _AddStaffTile({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_AddStaffTile> createState() => _AddStaffTileState();
}

class _AddStaffTileState extends State<_AddStaffTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      button: true,
      label: l10n.salonManageAddStaffLabel,
      child: GestureDetector(
        key: const Key('salon-manage-add-staff'),
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) {
          setState(() => _pressed = false);
          widget.onTap();
        },
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: kSalonMasterCardHeight,
            decoration: BoxDecoration(
              color: BrandColors.base,
              borderRadius: BorderRadius.circular(VelvetRadii.card),
              boxShadow: _pressed ? null : VelvetShadows.extrudedCard,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: VelvetSpacing.md - 2,
              vertical: VelvetSpacing.md,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Container(
                  height: 73,
                  width: 73,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: BrandColors.accent.withValues(alpha: 0.10),
                    border: Border.all(
                      color: BrandColors.accent.withValues(alpha: 0.55),
                      width: 1.4,
                    ),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.add_rounded,
                      color: BrandColors.accentDeep,
                      size: 36,
                    ),
                  ),
                ),
                const SizedBox(height: VelvetSpacing.sm),
                Text(
                  l10n.salonManageAddStaffLabel,
                  style: VelvetText.subheading13Accent,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Послуги tab — reuses the same read the public profile uses
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
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: VelvetSpacing.xl),
          child: CircularProgressIndicator(),
        ),
      ),
      error: (Object e, _) => ErrorState(
        failure: e is Failure ? e : UnknownFailure(cause: e),
        onRetry: () => ref.invalidate(salonServiceCatalogProvider(salonId)),
      ),
      data: (List<SalonServiceCategoryEntry> categories) => categories.isEmpty
          ? Text(
              l10n.salonServicesEmpty,
              style: VelvetText.feedback(BrandColors.muted),
            )
          : SalonServicesAccordion(categories: categories),
    );
  }
}
