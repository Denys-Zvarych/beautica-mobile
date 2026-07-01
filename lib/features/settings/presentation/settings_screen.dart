// Account page («Акаунт») — reached from the master settings hub's Account row.
// A richer account surface: a Мова (language → "Українська") placeholder row and
// a Сповіщення (notifications) toggle placeholder.
//
// No Save button — each control acts immediately (the placeholders show a hint).
//
// Logout is not surfaced here — it lives on the settings hub (the canonical
// logout entry point).
//
// Security: screenshot protection acquired via the app-wide
// ScreenProtectionManager (ref-counted; active in non-debug builds).
//
// Design source: `docs/signup-designs/ProfileSettingsHub/lib/screens/
// account_screen.dart` — ported with real l10n.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/icons/app_icon.dart';
import '../../../core/icons/beautica_asset_icons.dart';
import '../../../core/security/screen_protection.dart';
import '../../../core/theme/brand_colors.dart';
import '../../../core/theme/velvet_geometry.dart';
import '../../../core/theme/velvet_text.dart';
import '../../../features/auth/domain/auth_session.dart';
import '../../../features/auth/presentation/auth_notifier.dart';
import '../../../features/master/presentation/widgets/section_scaffold.dart';
import '../../../features/master/presentation/widgets/settings_row.dart';
import '../../../l10n/app_localizations.dart';
import '../../../routing/role_home.dart';
import '../../../routing/route_names.dart';

/// Account settings page — VelvetTouch neumorphic design.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen>
    with SingleTickerProviderStateMixin {
  // Animation — pre-built in initState; zero allocations in build().
  late final AnimationController _controller;
  late final CurvedAnimation _anim0; // subheading
  late final CurvedAnimation _anim1; // language
  late final CurvedAnimation _anim2; // notifications

  static final Tween<Offset> _slideTween = Tween<Offset>(
    begin: const Offset(0, 0.035),
    end: Offset.zero,
  );

  // Captured in initState so dispose() never touches `ref` — under Riverpod 3.x
  // using `ref` in dispose() throws ("widget is about to or has been
  // unmounted"). Hold the keepAlive manager reference instead.
  late final ScreenProtectionManager _screenProtection;

  @override
  void initState() {
    super.initState();
    // SEC MEDIUM: ref-counted screenshot guard (single app-wide owner;
    // the manager is internally !kDebugMode-guarded).
    _screenProtection = ref.read(screenProtectionProvider)..acquire();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _anim0 = _curve(0.00, 0.40);
    _anim1 = _curve(0.08, 0.50);
    _anim2 = _curve(0.16, 0.58);
    _controller.forward();
  }

  CurvedAnimation _curve(double start, double end) => CurvedAnimation(
    parent: _controller,
    curve: Interval(start, end, curve: Curves.easeOutCubic),
  );

  @override
  void dispose() {
    _screenProtection.release();
    _anim0.dispose();
    _anim1.dispose();
    _anim2.dispose();
    _controller.dispose();
    super.dispose();
  }

  Widget _reveal(CurvedAnimation anim, Widget child) {
    final Animation<Offset> slide = _slideTween.animate(anim);
    return FadeTransition(
      opacity: anim,
      child: SlideTransition(position: slide, child: child),
    );
  }

  void _showLanguageSoon() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).accountLanguageSoon),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return SectionScaffold(
      title: l10n.accountTitle,
      backKey: const Key('btn-back-account'),
      backSemanticLabel: l10n.masterCancelButton,
      onBack: () {
        if (context.canPop()) {
          context.pop();
        } else {
          // /settings is reachable by any authenticated role (CLIENT via the
          // Home Hub burger; INDEPENDENT_MASTER via the master menu). Resolve
          // the fallback destination from the authenticated session so that a
          // CLIENT with an empty navigator stack returns to /home rather than
          // being sent to /master/menu (a master-only surface that the router
          // gate would immediately redirect away from anyway, causing a flash).
          final session = ref.read(authProvider);
          final fallback = session.value is Authenticated
              ? roleHomePath((session.value! as Authenticated).user.role)
              : RouteNames.login;
          context.go(fallback);
        }
      },
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _reveal(
            _anim0,
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: VelvetSpacing.lg),
              child: Text(l10n.accountSubheading, style: VelvetText.body()),
            ),
          ),
          _reveal(
            _anim1,
            SettingsRow(
              key: const Key('row-language'),
              icon: Icons.language_rounded,
              label: l10n.accountLanguageLabel,
              value: l10n.accountLanguageValue,
              onTap: _showLanguageSoon,
            ),
          ),
          const SizedBox(height: VelvetSpacing.md),
          _reveal(
            _anim2,
            SettingsToggleRow(
              key: const Key('row-notifications'),
              switchKey: const Key('switch-notifications'),
              icon: Icons.notifications_none_rounded,
              // Match the top-bar idle bell (BellButton): the dotless
              // `notificationPlain` SVG, tinted + sized to the settings-row
              // glyph spec (19 px, accentDeep) so it sits identically.
              iconWidget: const AppIcon(
                BeauticaAssetIcons.notificationPlain,
                size: 19,
                color: BrandColors.accentDeep,
              ),
              label: l10n.accountNotificationsLabel,
              subtitle: l10n.accountNotificationsSubtitle,
              initialValue: true,
            ),
          ),
        ],
      ),
    );
  }
}
