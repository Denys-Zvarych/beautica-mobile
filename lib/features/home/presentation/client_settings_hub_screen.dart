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
// The CLIENT-only «Видалити акаунт» row lives on the «Акаунт» page
// (`RouteNames.settings` → `settings_screen.dart`), NOT here — it was
// relocated off this hub because `row-account` above is what actually reads
// «Акаунт» to the user; this hub screen's own title is «Налаштування». See
// `settings_screen.dart`'s header doc for the row + [runDeleteAccountFlow]
// wiring.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/icons/app_icon.dart';
import 'package:beautica_mobile/core/icons/beautica_asset_icons.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
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
    _controller.dispose();
    _loggingOut.dispose();
    _loggingOutLoading.dispose();
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
              padding: const EdgeInsets.symmetric(vertical: VelvetSpacing.lg),
              child: Divider(
                thickness: 0.6,
                color: BrandColors.accent.withValues(alpha: 0.22),
              ),
            ),
          ),

          // Terminal / destructive action — set apart. Wired to its own
          // `_loggingOutLoading` UI flag, scoped with its own
          // `ValueListenableBuilder`.
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
    );
  }
}
