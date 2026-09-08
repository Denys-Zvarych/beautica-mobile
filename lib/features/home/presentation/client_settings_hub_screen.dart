// CLIENT settings hub — the pushed screen the home-hub burger icon opens. A
// close affordance + centred "Налаштування" title, then a vertical stack of
// tappable neumorphic rows. Each navigational row pushes its own section edit
// page; the logout row sits apart as the terminal action and raises the real
// logout confirm dialog (see [runLogoutFlow]).
//
// 1:1 transcription of the master [SettingsHubScreen] (same staggered reveal,
// same shared SettingsRow + SectionScaffold + runLogoutFlow). The only changes
// are the destinations of the navigational rows, which point at the CLIENT edit
// routes instead of the master ones:
//   Personal → clientEditPersonal, Contacts → clientEditContacts,
//   Location → clientEditLocation, Account → settings, Help → contactSupport.
//
// Below the logout row sits a CLIENT-only «Видалити акаунт» row (REUSE-FIRST:
// the SAME shared [SettingsRow] widget every other row uses, no new widget).
// It raises its own short confirm dialog and delegates the actual
// confirm→delete→teardown sequence to [runDeleteAccountFlow], which reuses
// [runLogoutFlow]'s exact post-success session teardown + redirect rather than
// hand-rolling a second logout path.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/icons/app_icon.dart';
import 'package:beautica_mobile/core/icons/beautica_asset_icons.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/features/settings/presentation/delete_account_flow.dart';
import 'package:beautica_mobile/features/settings/presentation/logout_action.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';

import 'package:beautica_mobile/features/master/presentation/widgets/section_scaffold.dart';
import 'package:beautica_mobile/features/master/presentation/widgets/settings_row.dart';

/// The CLIENT settings hub reached from the home-hub menu icon.
class ClientSettingsHubScreen extends ConsumerStatefulWidget {
  const ClientSettingsHubScreen({super.key});

  @override
  ConsumerState<ClientSettingsHubScreen> createState() =>
      _ClientSettingsHubScreenState();
}

class _ClientSettingsHubScreenState
    extends ConsumerState<ClientSettingsHubScreen>
    with SingleTickerProviderStateMixin {
  // Logout re-entrancy guard, shared with [runLogoutFlow]. Never bound to a
  // widget — see `logout_action.dart`'s flag-lifetime doc.
  final ValueNotifier<bool> _loggingOut = ValueNotifier<bool>(false);
  // Logout UI-visible loading flag — drives `SettingsRow(loading:)` only.
  // Flips true after consent, immediately before the network call.
  final ValueNotifier<bool> _loggingOutLoading = ValueNotifier<bool>(false);

  // Delete-account re-entrancy guard, shared with [runDeleteAccountFlow].
  // Never bound to a widget — see `delete_account_flow.dart`'s flag-lifetime
  // doc.
  final ValueNotifier<bool> _deletingAccount = ValueNotifier<bool>(false);
  // Delete-account UI-visible loading flag — drives `SettingsRow(loading:)`
  // AND the sibling-row `IgnorePointer`. Flips true after consent,
  // immediately before the network call.
  final ValueNotifier<bool> _deletingAccountLoading = ValueNotifier<bool>(
    false,
  );

  // Animation — pre-built in initState; zero allocations in build().
  late final AnimationController _controller;
  late final CurvedAnimation _anim0; // subheading
  late final CurvedAnimation _anim1; // personal
  late final CurvedAnimation _anim2; // contacts
  late final CurvedAnimation _anim3; // location
  late final CurvedAnimation _anim4; // account
  late final CurvedAnimation _anim5; // help / contact-us
  late final CurvedAnimation _anim6; // hairline
  late final CurvedAnimation _anim7; // logout
  late final CurvedAnimation _anim8; // delete account

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
    _anim0 = _curve(0.00, 0.40);
    _anim1 = _curve(0.06, 0.50);
    _anim2 = _curve(0.14, 0.58);
    _anim3 = _curve(0.22, 0.66);
    _anim4 = _curve(0.30, 0.74);
    _anim5 = _curve(0.36, 0.78); // help / contact-us
    _anim6 = _curve(0.44, 0.84); // hairline
    _anim7 = _curve(0.50, 0.92); // logout
    _anim8 = _curve(0.56, 1.00); // delete account
    _controller.forward();
  }

  CurvedAnimation _curve(double start, double end) => CurvedAnimation(
    parent: _controller,
    curve: Interval(start, end, curve: Curves.easeOutCubic),
  );

  @override
  void dispose() {
    _anim0.dispose();
    _anim1.dispose();
    _anim2.dispose();
    _anim3.dispose();
    _anim4.dispose();
    _anim5.dispose();
    _anim6.dispose();
    _anim7.dispose();
    _anim8.dispose();
    _controller.dispose();
    _loggingOut.dispose();
    _loggingOutLoading.dispose();
    _deletingAccount.dispose();
    _deletingAccountLoading.dispose();
    super.dispose();
  }

  Widget _reveal(CurvedAnimation anim, Widget child) {
    final Animation<Offset> slide = _slideTween.animate(anim);
    return FadeTransition(
      opacity: anim,
      child: SlideTransition(position: slide, child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return SectionScaffold(
      title: l10n.settingsTitle,
      backIcon: Icons.close_rounded,
      backSemanticLabel: l10n.settingsHubClose,
      backKey: const Key('btn-close-hub'),
      onBack: () {
        if (context.canPop()) {
          context.pop();
        } else {
          context.go(RouteNames.clientHome);
        }
      },
      // mobile-perf HIGH + MEDIUM fixes (2026-09-08) — the delete-account UI
      // flag (`_deletingAccountLoading`; flips true only AFTER consent — see
      // `delete_account_flow.dart`) drives two things:
      //   * the delete-account row itself gets `loading: deletingAccount`,
      //     wired onto `SettingsRow`'s EXISTING `loading` param (dims the
      //     row, swaps the chevron for a spinner, absorbs taps) — the same
      //     param + contract the sibling delete-salon row already uses
      //     (`settings_screen.dart`, `loading: _deletingSalon`) — via its
      //     OWN `ValueListenableBuilder` below, so it stays independently
      //     rebuildable;
      //   * every OTHER row (including logout) sits inside an
      //     `IgnorePointer(ignoring: deletingAccount)` so nothing else in
      //     the hub is reachable while the delete call — which can take
      //     several seconds — is in flight; a user can no longer navigate
      //     into an edit screen mid-call and get yanked out of it when the
      //     delete resolves and redirects to `/login`.
      // mobile-perf LOW fix (2026-09-08) — that `IgnorePointer` sits behind
      // its OWN narrowly-scoped `ValueListenableBuilder` (not one wrapping
      // the whole body): the static navigational-rows `Column` is passed via
      // `child:`, built ONCE, and never reconstructed on a flag flip — only
      // `IgnorePointer.ignoring` actually changes. `_ClientSettingsHubScreenState
      // .build()` itself stays untouched — no `setState` here — so this
      // scopes cleanly under the existing `AnimationController`-driven
      // staggered reveal.
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _reveal(
            _anim0,
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: VelvetSpacing.lg),
              child: Text(l10n.settingsHubSubheading, style: VelvetText.body()),
            ),
          ),

          ValueListenableBuilder<bool>(
            valueListenable: _deletingAccountLoading,
            builder: (context, deletingAccountLoading, child) =>
                IgnorePointer(ignoring: deletingAccountLoading, child: child),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                // Navigational group.
                _reveal(
                  _anim1,
                  SettingsRow(
                    key: const Key('row-personal'),
                    icon: Icons.person_outline_rounded,
                    label: l10n.settingsHubPersonal,
                    onTap: () => context.push(RouteNames.clientEditPersonal),
                  ),
                ),
                const SizedBox(height: VelvetSpacing.md),
                _reveal(
                  _anim2,
                  SettingsRow(
                    key: const Key('row-contacts'),
                    icon: Icons.call_outlined,
                    label: l10n.settingsHubContacts,
                    onTap: () => context.push(RouteNames.clientEditContacts),
                  ),
                ),
                const SizedBox(height: VelvetSpacing.md),
                _reveal(
                  _anim3,
                  SettingsRow(
                    key: const Key('row-location'),
                    icon: Icons.location_on_outlined,
                    iconWidget: const AppIcon(
                      BeauticaAssetIcons.locationMarker,
                      size: 19,
                      color: BrandColors.accentDeep,
                    ),
                    label: l10n.settingsHubLocation,
                    onTap: () => context.push(RouteNames.clientEditLocation),
                  ),
                ),
                const SizedBox(height: VelvetSpacing.md),
                _reveal(
                  _anim4,
                  SettingsRow(
                    key: const Key('row-account'),
                    icon: Icons.settings_outlined,
                    label: l10n.settingsHubAccount,
                    onTap: () => context.push(RouteNames.settings),
                  ),
                ),
                const SizedBox(height: VelvetSpacing.md),

                // Help / contact-us — the last navigational row.
                _reveal(
                  _anim5,
                  SettingsRow(
                    key: const Key('row-help'),
                    icon: Icons.help_outline_rounded,
                    label: l10n.settingsHubHelp,
                    onTap: () => context.push(RouteNames.contactSupport),
                  ),
                ),

                // Separation before the terminal action.
                _reveal(
                  _anim6,
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: VelvetSpacing.lg,
                    ),
                    child: Divider(
                      thickness: 0.6,
                      color: BrandColors.accent.withValues(alpha: 0.22),
                    ),
                  ),
                ),

                // Terminal / destructive action — set apart. Wired to its
                // own `_loggingOutLoading` UI flag (same one-line pattern
                // as the delete-account row below), scoped with its own
                // `ValueListenableBuilder` since it tracks a different
                // notifier — not a second listener on
                // `_deletingAccountLoading`.
                _reveal(
                  _anim7,
                  ValueListenableBuilder<bool>(
                    valueListenable: _loggingOutLoading,
                    builder: (context, loggingOutLoading, _) => SettingsRow(
                      key: const Key('row-logout'),
                      icon: Icons.logout_rounded,
                      label: l10n.logout,
                      destructive: true,
                      showChevron: false,
                      loading: loggingOutLoading,
                      onTap: () => runLogoutFlow(
                        context,
                        ref,
                        inFlight: _loggingOut,
                        loading: _loggingOutLoading,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: VelvetSpacing.md),

          // CLIENT-only delete-account row — below logout, same shared
          // SettingsRow, own confirm flow (see [runDeleteAccountFlow]). Own
          // `ValueListenableBuilder` on `_deletingAccountLoading` — kept
          // intact per the mobile-perf LOW fix above, which only narrows the
          // sibling-rows `IgnorePointer`'s listener, not this row's.
          _reveal(
            _anim8,
            ValueListenableBuilder<bool>(
              valueListenable: _deletingAccountLoading,
              builder: (context, deletingAccountLoading, _) => SettingsRow(
                key: const Key('row-delete-account'),
                icon: Icons.delete_outline_rounded,
                label: l10n.settingsHubDeleteAccount,
                destructive: true,
                showChevron: false,
                loading: deletingAccountLoading,
                onTap: () => runDeleteAccountFlow(
                  context,
                  ref,
                  inFlight: _deletingAccount,
                  loading: _deletingAccountLoading,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
