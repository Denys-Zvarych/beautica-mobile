// Master profile settings hub — the pushed screen the top-right menu icon on the
// profile opens. A close affordance + centred "Налаштування" title, then a
// vertical stack of tappable neumorphic rows. Each navigational row pushes its
// own section edit page; the logout row sits apart as the terminal action and
// raises the real logout confirm dialog (see [runLogoutFlow]).
//
// frontend-design craft within VelvetTouch: the rows reveal on load as one
// orchestrated staggered fade-up, and the destructive logout is separated from
// the navigational group by a quiet hairline + extra space so the eye reads it
// as a different *kind* of action — not just another row.
//
// Animation: a single 1000 ms controller drives staggered fade+translate
// reveals. CurvedAnimation instances are pre-built in initState — zero
// allocations in build(); a static Tween<Offset> is reused across reveals.
//
// Design source: `docs/signup-designs/ProfileSettingsHub/lib/screens/
// settings_hub_screen.dart` — ported 1:1, swapping Navigator.push for go_router
// pushes and the placeholder logout for the production flow.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/features/settings/presentation/logout_action.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';

import 'widgets/section_scaffold.dart';
import 'widgets/settings_row.dart';

/// The settings hub reached from the master profile menu icon.
class SettingsHubScreen extends ConsumerStatefulWidget {
  const SettingsHubScreen({super.key});

  @override
  ConsumerState<SettingsHubScreen> createState() => _SettingsHubScreenState();
}

class _SettingsHubScreenState extends ConsumerState<SettingsHubScreen>
    with SingleTickerProviderStateMixin {
  // Logout double-tap guard, shared with [runLogoutFlow].
  final ValueNotifier<bool> _loggingOut = ValueNotifier<bool>(false);

  // Animation — pre-built in initState; zero allocations in build().
  late final AnimationController _controller;
  late final CurvedAnimation _anim0; // subheading
  late final CurvedAnimation _anim1; // personal
  late final CurvedAnimation _anim2; // contacts
  late final CurvedAnimation _anim3; // location
  late final CurvedAnimation _anim4; // account
  late final CurvedAnimation _anim5; // hairline
  late final CurvedAnimation _anim6; // logout

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
    _anim5 = _curve(0.40, 0.82);
    _anim6 = _curve(0.46, 0.90);
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
          context.go(RouteNames.masterProfile);
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
              onTap: () => context.push(RouteNames.masterEditPersonal),
            ),
          ),
          const SizedBox(height: VelvetSpacing.md),
          _reveal(
            _anim2,
            SettingsRow(
              key: const Key('row-contacts'),
              icon: Icons.call_outlined,
              label: l10n.settingsHubContacts,
              onTap: () => context.push(RouteNames.masterEditContacts),
            ),
          ),
          const SizedBox(height: VelvetSpacing.md),
          _reveal(
            _anim3,
            SettingsRow(
              key: const Key('row-location'),
              icon: Icons.location_on_outlined,
              label: l10n.settingsHubLocation,
              onTap: () => context.push(RouteNames.masterEditLocation),
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

          // Separation before the terminal action.
          _reveal(
            _anim5,
            Padding(
              padding: const EdgeInsets.symmetric(vertical: VelvetSpacing.lg),
              child: Divider(
                thickness: 0.6,
                color: BrandColors.accent.withValues(alpha: 0.22),
              ),
            ),
          ),

          // Terminal / destructive action — set apart.
          _reveal(
            _anim6,
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
