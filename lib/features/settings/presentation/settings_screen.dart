// Phase 2.8 — Settings screen (minimal — full settings UI ships in Phase 5+).
// Phase MEDIUM-2 fix — ported from glassmorphism (#1A110A + BackdropFilter) to
// VelvetTouch neumorphic design system (BrandColors.base + NeumorphicCard).
//
// Purpose: provides an accessible logout entry point so users can clear their
// session. Future phases will expand this screen with notification preferences,
// account management, and language selection.
//
// Logout flow:
//   1. Tap the logout tile → show a confirmation dialog.
//   2. On confirmation → set _isLoggingOut (double-tap guard).
//   3. Call authProvider.notifier.logout().
//   4. Check mounted after await; navigate to /login on success or show a
//      SnackBar on failure.
//   5. _isLoggingOut reset in the finally block.
//
// Security:
//   - ScreenProtector.preventScreenshotOn() active in non-debug builds to
//     prevent OS-level screenshot capture of the settings surface.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:screen_protector/screen_protector.dart';

import '../../../core/theme/brand_colors.dart';
import '../../../core/theme/velvet_geometry.dart';
import '../../../core/theme/velvet_text.dart';
import '../../../features/auth/presentation/auth_notifier.dart';
import '../../../l10n/app_localizations.dart';
import '../../../routing/route_names.dart';

/// Minimal settings screen — VelvetTouch neumorphic design.
///
/// Contains a single logout action. Navigation back to the login screen is
/// explicit — the Phase 2.9 router guard provides a second safety net.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  // Prevents double-tapping the logout tile while a logout is in flight.
  bool _isLoggingOut = false;

  @override
  void initState() {
    super.initState();
    if (!kDebugMode) ScreenProtector.preventScreenshotOn();
  }

  @override
  void dispose() {
    if (!kDebugMode) ScreenProtector.preventScreenshotOff();
    super.dispose();
  }

  Future<void> _handleLogout(BuildContext context) async {
    if (_isLoggingOut) return;

    final l10n = AppLocalizations.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: BrandColors.base,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(VelvetRadii.card)),
        ),
        title: Text(l10n.logout, style: VelvetText.heading()),
        content: Text(l10n.logoutConfirm, style: VelvetText.body()),
        actions: [
          TextButton(
            key: const Key('btn-logout-cancel'),
            onPressed: () => ctx.pop(false),
            child: Text(l10n.cancel, style: VelvetText.link()),
          ),
          TextButton(
            key: const Key('btn-logout-confirm'),
            onPressed: () => ctx.pop(true),
            child: Text(l10n.logout, style: VelvetText.link()),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!context.mounted) return;

    setState(() => _isLoggingOut = true);
    try {
      await ref.read(authProvider.notifier).logout();
      if (!context.mounted) return;
      context.go(RouteNames.login);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.logoutFailed)));
    } finally {
      if (mounted) setState(() => _isLoggingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: BrandColors.base,
      appBar: AppBar(
        backgroundColor: BrandColors.base,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text(l10n.settingsTitle, style: VelvetText.subheading()),
        iconTheme: const IconThemeData(color: BrandColors.textSecondary),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(
            horizontal: VelvetSpacing.md,
            vertical: VelvetSpacing.md,
          ),
          children: [
            _NeumorphicSettingsTile(
              tileKey: const Key('btn-logout'),
              icon: Icons.logout,
              label: l10n.logout,
              isLoading: _isLoggingOut,
              onTap: () => _handleLogout(context),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _NeumorphicSettingsTile — VelvetTouch neumorphic list tile for settings rows
// ---------------------------------------------------------------------------

class _NeumorphicSettingsTile extends StatelessWidget {
  const _NeumorphicSettingsTile({
    required this.tileKey,
    required this.icon,
    required this.label,
    required this.onTap,
    this.isLoading = false,
  });

  final Key tileKey;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isLoading;

  // Hoisted: VelvetRadii.card is a compile-time constant so the whole
  // BorderRadius can be static const, avoiding an allocation per build.
  static const BorderRadius _tileRadius = BorderRadius.all(
    Radius.circular(VelvetRadii.card),
  );

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: BrandColors.base,
        borderRadius: _tileRadius,
        boxShadow: VelvetShadows.extrudedCard,
      ),
      child: ClipRRect(
        borderRadius: _tileRadius,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            key: tileKey,
            onTap: isLoading ? null : onTap,
            splashColor: BrandColors.accent.withValues(alpha: 0.12),
            highlightColor: BrandColors.accent.withValues(alpha: 0.06),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: VelvetSpacing.md,
                vertical: VelvetSpacing.md,
              ),
              child: Row(
                children: [
                  isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: BrandColors.accent,
                          ),
                        )
                      : Icon(icon, color: BrandColors.accent, size: 20),
                  const SizedBox(width: VelvetSpacing.md),
                  Text(label, style: VelvetText.bodyStrong()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
