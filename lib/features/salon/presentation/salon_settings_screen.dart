// Phase 21.9 — Salon settings hub (owner/admin), the full multi-row
// settings surface the salon management profile's top-right
// `Icons.tune_rounded` cover control opens. SUPERSEDES the Phase 21.2 2-row
// version («Редагувати профіль» + owner-only «Видалити салон») this file
// used to hold — see git history for that version.
//
// Design source: `docs/signup-designs/SalonManagementDesign/lib/screens/
// salon_settings_screen.dart` — ported literally onto the production shell.
// Its own doc-comments carry decisions the code alone doesn't fully show:
//
//  * «Мої салони» / «Про салон» / «Локація» / «Контакти» are ALL
//    owner-only — admins cannot edit salon info (design `:274`: "Owner-only:
//    admins cannot edit salon info."). «Про салон»/«Локація»/«Контакти»
//    replace the old single «Редагувати профіль» row: the design splits that
//    one inline-edit entry into three dedicated edit screens
//    ([SalonProfileEditScreen] / [SalonAddressEditScreen] /
//    [SalonContactsEditScreen], all already built by Phase 21.10 with no
//    entry point until now).
//  * «Надіслані запрошення» is shown to ALL viewers (owner AND admin,
//    outside the owner-only block). Phase 21.11 built
//    [SalonPendingInvitesScreen] and wired this row to it
//    ([RouteNames.salonPendingInvites]); it shipped in Phase 21.9 as a
//    deliberate no-op placeholder row until then.
//  * «Видалити салон» is explicitly NOT on this screen (design `:44`, `:51`,
//    `:168`, `:339`: "«Видалити салон» is NOT here — it lives at the bottom
//    of the Акаунт screen"). It lives at the bottom of the shared account
//    page ([SettingsScreen], `RouteNames.settings`) instead, reached via the
//    «Загальне» row here — Phase 21.13 already built that page's owner-only
//    `showDeleteSalon` row (delegating to the SAME `runDeleteSalonFlow` this
//    screen used to call directly), so «Загальне» only needs to forward
//    `salonId` + `showDeleteSalon: isOwner` via [AccountSettingsExtras]. The
//    terminal group on THIS screen is therefore hairline + «Вийти» only,
//    exactly like every other settings hub in the app
//    (`features/master/presentation/settings_hub_screen.dart`,
//    `features/home/presentation/client_settings_hub_screen.dart`).
//
// Shell: reuses the production `SectionScaffold` + `SettingsRow` widgets
// (`features/master/presentation/widgets/`) — the SAME shared building
// blocks every other settings hub in the app uses — rather than recreating
// the preview's own bespoke `_SettingsTopBar`/`_SettingsRow` (REUSE-FIRST).
// «Вийти» reuses the shared `runLogoutFlow` (`features/settings/presentation
// /logout_action.dart`) — the same confirm→logout→navigate sequence every
// other hub's logout row runs, not a re-implementation.
//
// Context subheading (design `:227-254`) — NOW PORTED (2026-08-30). It was
// held back on the grounds that this screen receives only a `salonId` and
// fetching a `Salon` for a decorative row was out of scope. That no longer
// holds: [salonManagementProfileProvider] already carries the `Salon` and is
// warm on every real entry path (the `tune_rounded` control lives on
// [SalonManagementProfileScreen], inside the shell that watches the SAME
// family key), so the row costs a `select` on an existing provider — no new
// fetch, no new repository call. See [_ContextSubheading] for how it
// degrades when the value is not there.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';

import '../../auth/domain/auth_session.dart';
import '../../auth/domain/user_role.dart';
import '../../auth/presentation/auth_notifier.dart';
import '../../master/presentation/widgets/section_scaffold.dart';
import '../../master/presentation/widgets/settings_row.dart';
import '../../settings/domain/account_settings_extras.dart';
import '../../settings/presentation/logout_action.dart';
import '../application/salon_management_profile_notifier.dart';
import 'widgets/salon_cover_widgets.dart';

/// The salon settings hub — «Мої салони» / «Про салон» / «Локація» /
/// «Контакти» (all owner-only) / «Надіслані запрошення» / «Загальне» /
/// «Допомога» / «Вийти».
class SalonSettingsScreen extends ConsumerStatefulWidget {
  const SalonSettingsScreen({super.key, required this.salonId});

  /// Backend Salon-row UUID this settings page manages.
  final String salonId;

  @override
  ConsumerState<SalonSettingsScreen> createState() =>
      _SalonSettingsScreenState();
}

class _SalonSettingsScreenState extends ConsumerState<SalonSettingsScreen>
    with SingleTickerProviderStateMixin {
  // Logout double-tap guard, shared with [runLogoutFlow].
  final ValueNotifier<bool> _loggingOut = ValueNotifier<bool>(false);

  late final AnimationController _controller;
  late final CurvedAnimation _animContext; // salon logo + name subheading
  late final CurvedAnimation _animMySalons; // «Мої салони» (owner-only)
  late final CurvedAnimation _animAbout; // «Про салон» (owner-only)
  late final CurvedAnimation _animLocation; // «Локація» (owner-only)
  late final CurvedAnimation _animContacts; // «Контакти» (owner-only)
  late final CurvedAnimation _animInvites; // «Надіслані запрошення»
  late final CurvedAnimation _animGeneral; // «Загальне»
  late final CurvedAnimation _animHelp; // «Допомога / Напишіть нам»
  late final CurvedAnimation _animDivider; // hairline
  late final CurvedAnimation _animLogout; // «Вийти»

  static final Tween<Offset> _slideTween = Tween<Offset>(
    begin: const Offset(0, 0.035),
    end: Offset.zero,
  );

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    // Head of the cascade — the design's own `_anim0` / `_anim9` values
    // (preview `:113`, `:122-123`: "top «Мої салони» — reveals just after
    // subhead"). «Мої салони» moved off 0.00 to make room for the
    // subheading, exactly as the preview stages it; every row below keeps
    // the interval it already shipped with.
    _animContext = _curve(0.00, 0.36);
    _animMySalons = _curve(0.04, 0.42);
    _animAbout = _curve(0.06, 0.50);
    _animLocation = _curve(0.14, 0.58);
    _animContacts = _curve(0.22, 0.66);
    _animInvites = _curve(0.28, 0.70);
    _animGeneral = _curve(0.34, 0.74);
    _animHelp = _curve(0.40, 0.78);
    _animDivider = _curve(0.46, 0.84);
    _animLogout = _curve(0.52, 0.92);
    _controller.forward();
  }

  CurvedAnimation _curve(double start, double end) => CurvedAnimation(
    parent: _controller,
    curve: Interval(start, end, curve: Curves.easeOutCubic),
  );

  @override
  void dispose() {
    _animContext.dispose();
    _animMySalons.dispose();
    _animAbout.dispose();
    _animLocation.dispose();
    _animContacts.dispose();
    _animInvites.dispose();
    _animGeneral.dispose();
    _animHelp.dispose();
    _animDivider.dispose();
    _animLogout.dispose();
    _controller.dispose();
    _loggingOut.dispose();
    super.dispose();
  }

  Widget _reveal(CurvedAnimation anim, Widget child) {
    final Animation<Offset> slide = _slideTween.animate(anim);
    return FadeTransition(
      opacity: anim,
      child: SlideTransition(position: slide, child: child),
    );
  }

  void _close() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(RouteNames.salonManage(widget.salonId));
    }
  }

  /// «Загальне» — pushes the shared account page, forwarding [widget.salonId]
  /// and the owner-only «Видалити салон» flag so [SettingsScreen] (Phase
  /// 21.13) can surface that destructive row at its own bottom. Every OTHER
  /// caller of `RouteNames.settings` pushes with no `extra` at all, so a
  /// non-owner viewer here still resolves to `showDeleteSalon: false` —
  /// [AccountSettingsExtras.showDeleteSalon] fails closed a second time on
  /// the session's own role regardless (see `SettingsScreen
  /// ._showDeleteSalonRow`).
  void _openAccount(bool isOwner) {
    context.push(
      RouteNames.settings,
      extra: AccountSettingsExtras(
        salonId: widget.salonId,
        showDeleteSalon: isOwner,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final bool isOwner = ref.watch(
      authProvider.select(
        (AsyncValue<AuthSession> s) =>
            s.value is Authenticated &&
            (s.value! as Authenticated).user.role == UserRole.salonOwner,
      ),
    );

    return SectionScaffold(
      title: l10n.settingsTitle,
      backIcon: Icons.close_rounded,
      backSemanticLabel: l10n.settingsHubClose,
      backKey: const Key('btn-close-salon-settings'),
      onBack: _close,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Context subheading — WHICH salon these settings belong to.
          _reveal(_animContext, _ContextSubheading(salonId: widget.salonId)),

          // Navigational group — owner-only. Admins cannot edit salon info
          // (design doc `:274`) and have no multi-salon list to return to.
          if (isOwner) ...<Widget>[
            _reveal(
              _animMySalons,
              SettingsRow(
                key: const Key('row-my-salons'),
                icon: Icons.storefront_outlined,
                label: l10n.salonSettingsMySalons,
                onTap: () => context.push(RouteNames.mySalons),
              ),
            ),
            const SizedBox(height: VelvetSpacing.md),
            _reveal(
              _animAbout,
              SettingsRow(
                key: const Key('row-salon-about'),
                icon: Icons.storefront_outlined,
                label: l10n.salonSettingsAbout,
                onTap: () =>
                    context.push(RouteNames.salonProfileEdit(widget.salonId)),
              ),
            ),
            const SizedBox(height: VelvetSpacing.md),
            _reveal(
              _animLocation,
              SettingsRow(
                key: const Key('row-salon-location'),
                icon: Icons.place_outlined,
                label: l10n.salonSettingsLocation,
                onTap: () =>
                    context.push(RouteNames.salonAddressEdit(widget.salonId)),
              ),
            ),
            const SizedBox(height: VelvetSpacing.md),
            _reveal(
              _animContacts,
              SettingsRow(
                key: const Key('row-salon-contacts'),
                icon: Icons.phone_outlined,
                label: l10n.salonSettingsContacts,
                onTap: () =>
                    context.push(RouteNames.salonContactsEdit(widget.salonId)),
              ),
            ),
            const SizedBox(height: VelvetSpacing.md),
          ],

          // «Надіслані запрошення» — shown to ALL viewers (owner AND admin,
          // outside the owner-only block above), matching the design.
          // Phase 21.11 replaced this row's no-op placeholder with the real
          // push: [SalonPendingInvitesScreen] now exists, and its route is
          // gated by `salonManageGuard` (owner + admin) rather than the
          // owner-only guard the three edit forms above use — matching this
          // row's position outside the owner-only block.
          _reveal(
            _animInvites,
            SettingsRow(
              key: const Key('row-salon-sent-invites'),
              icon: Icons.mark_email_unread_outlined,
              label: l10n.salonSettingsSentInvites,
              onTap: () =>
                  context.push(RouteNames.salonPendingInvites(widget.salonId)),
            ),
          ),
          const SizedBox(height: VelvetSpacing.md),

          // «Загальне» — the shared account page. All viewers; carries the
          // owner-only «Видалити салон» row at ITS bottom (see [_openAccount]
          // doc above) rather than here.
          _reveal(
            _animGeneral,
            SettingsRow(
              key: const Key('row-salon-general'),
              icon: Icons.manage_accounts_outlined,
              label: l10n.salonSettingsGeneral,
              onTap: () => _openAccount(isOwner),
            ),
          ),
          const SizedBox(height: VelvetSpacing.md),

          // «Допомога / Напишіть нам» — the last navigational row, before the
          // terminal group.
          _reveal(
            _animHelp,
            SettingsRow(
              key: const Key('row-salon-help'),
              icon: Icons.help_outline_rounded,
              label: l10n.settingsHubHelp,
              onTap: () => context.push(RouteNames.contactSupport),
            ),
          ),

          // Terminal group — hairline + «Вийти» only. «Видалити салон» is
          // NOT here (see this file's header doc).
          _reveal(
            _animDivider,
            const Padding(
              padding: EdgeInsets.symmetric(vertical: VelvetSpacing.lg),
              child: Divider(
                key: Key('salon-settings-divider'),
                thickness: 0.6,
                color: Color(0x38B89A7A), // accent @ ~22%
              ),
            ),
          ),
          _reveal(
            _animLogout,
            SettingsRow(
              key: const Key('row-logout'),
              icon: Icons.logout_rounded,
              label: l10n.logout,
              destructive: true,
              showChevron: false,
              onTap: () => runLogoutFlow(context, ref, _loggingOut),
            ),
          ),
        ],
      ),
    );
  }
}

/// The design's context subheading (`docs/signup-designs/SalonManagementDesign
/// /lib/screens/salon_settings_screen.dart:227-254`) — the salon's [SalonLogo]
/// mark beside its name, so a hub whose every row says «Про салон» / «Локація»
/// / «Контакти» still says WHICH salon.
///
/// Reads the name off [salonManagementProfileProvider] — the family the
/// management profile and the salon shell already watch under this same
/// [salonId] — via a `select` down to the single `String?` it renders, so this
/// widget rebuilds on a name change and on nothing else. It adds no fetch and
/// no repository call of its own; on every real entry path the family is
/// already warm.
///
/// DEGRADATION — the row is orientation, not chrome, so when it has nothing
/// true to say it says nothing: no name (loading, error, or a blank name from
/// the backend) renders `SizedBox.shrink()`, never a spinner, a skeleton, an
/// error line, or an orphaned logo with no label beside it. It can therefore
/// never block, delay, or displace the rows below. Deliberately read through
/// `valueOrNull` rather than `hasValue`/`hasError`: `valueOrNull` keeps the
/// PREVIOUS name visible across a seamless invalidate (no flicker), and it
/// sidesteps `AsyncValue.hasError` being satisfied by `AsyncLoading(retrying:
/// true)`.
class _ContextSubheading extends ConsumerWidget {
  const _ContextSubheading({required this.salonId});

  final String salonId;

  /// Diameter of the mark in this subheading — smaller than the hero's
  /// [SalonLogo], matching the design's `:238`.
  static const double _logoDiameter = 34;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String? name = ref.watch(
      salonManagementProfileProvider(
        salonId,
      ).select((AsyncValue<SalonManagementProfileData> s) => s.value?.$1.name),
    );
    final String trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty) {
      return const SizedBox.shrink(key: Key('salon-settings-context-absent'));
    }

    return Padding(
      key: const Key('salon-settings-context'),
      padding: const EdgeInsets.only(
        left: VelvetSpacing.xs,
        bottom: VelvetSpacing.lg,
      ),
      child: Row(
        children: <Widget>[
          SalonLogo(
            diameter: _logoDiameter,
            monogram: trimmed[0].toUpperCase(),
          ),
          const SizedBox(width: VelvetSpacing.sm),
          Flexible(
            child: Text(
              trimmed,
              style: VelvetText.body(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
