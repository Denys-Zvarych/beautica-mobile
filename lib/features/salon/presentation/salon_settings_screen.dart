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
// NOT ported: the design's decorative top subheading (salon logo + name row,
// its own `_anim0`). This screen only receives a `salonId` (no `Salon`
// object), and fetching one solely to render that row is outside this
// rebuild's scope — see the handoff report for the explicit call-out.
//
// KNOWN COLLATERAL — flagged, not silently fixed: removing «Редагувати
// профіль» orphans `SalonManagementProfileScreen._openSettings()`'s inline
// edit-mode toggle (`_editMode`, tested end-to-end by
// `salon_management_profile_screen_test.dart`'s "edit mode round-trip"
// group). That inline form (name/description/phone/Instagram) is superseded
// by the dedicated edit screens this rebuild finally wires up, but its own
// code + tests are UNTOUCHED here — out of this task's scope. See the
// handoff report.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';

import '../../auth/domain/auth_session.dart';
import '../../auth/domain/user_role.dart';
import '../../auth/presentation/auth_notifier.dart';
import '../../master/presentation/widgets/section_scaffold.dart';
import '../../master/presentation/widgets/settings_row.dart';
import '../../settings/domain/account_settings_extras.dart';
import '../../settings/presentation/logout_action.dart';

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
    _animMySalons = _curve(0.00, 0.40);
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
