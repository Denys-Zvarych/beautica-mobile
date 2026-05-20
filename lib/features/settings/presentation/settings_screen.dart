// Phase 2.8 — Settings screen (minimal — full settings UI ships in Phase 5+).
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
//   - The AppBar BackdropFilter ImageFilter is a static final to avoid
//     per-rebuild allocation.

import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:screen_protector/screen_protector.dart';

import '../../../core/theme/brand_colors.dart';
import '../../../features/auth/presentation/auth_gradient_background.dart';
import '../../../features/auth/presentation/auth_notifier.dart';
import '../../../l10n/app_localizations.dart';
import '../../../routing/route_names.dart';

/// Minimal settings screen — Warm Mocha style.
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

  // Promoted from an inline build()-time allocation to a static final to avoid
  // constructing a new ImageFilter on every rebuild.
  static final _kAppBarBlur = ImageFilter.blur(sigmaX: 20, sigmaY: 20);

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
        backgroundColor: const Color(0xFF1A110A),
        title: Text(
          l10n.logout,
          style: const TextStyle(color: BrandColors.cream),
        ),
        content: Text(
          l10n.logoutConfirm,
          style: const TextStyle(color: Color(0x99F5EDE0)),
        ),
        actions: [
          TextButton(
            key: const Key('btn-logout-cancel'),
            onPressed: () => ctx.pop(false),
            child: Text(
              l10n.cancel,
              style: const TextStyle(color: BrandColors.camel),
            ),
          ),
          TextButton(
            key: const Key('btn-logout-confirm'),
            onPressed: () => ctx.pop(true),
            child: Text(
              l10n.logout,
              style: const TextStyle(color: BrandColors.camel),
            ),
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
      backgroundColor: BrandColors.espresso,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: _kAppBarBlur,
            child: const ColoredBox(color: Color(0x22000000)),
          ),
        ),
        title: const Text(
          'BEAUTICA',
          style: TextStyle(
            color: Color(0xEBFFFFFF),
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.6,
          ),
        ),
        iconTheme: const IconThemeData(color: BrandColors.cream),
      ),
      body: Stack(
        children: [
          // PERF: RepaintBoundary keeps the gradient layer in its own
          // composited layer; ListView scrolls and ScaffoldMessenger toasts
          // would otherwise invalidate it. AuthGradientBackground also wraps
          // itself; Flutter coalesces the duplicate boundary.
          const RepaintBoundary(child: AuthGradientBackground()),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                _WarmMochaListTile(
                  tileKey: const Key('btn-logout'),
                  icon: Icons.logout,
                  label: l10n.logout,
                  isLoading: _isLoggingOut,
                  onTap: () => _handleLogout(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _WarmMochaListTile — glassmorphism list tile for settings rows
// ---------------------------------------------------------------------------

class _WarmMochaListTile extends StatelessWidget {
  const _WarmMochaListTile({
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

  static final _kBlur = ImageFilter.blur(sigmaX: 20, sigmaY: 20);

  static const _kDecoration = BoxDecoration(
    color: Color(0x11FFFFFF),
    borderRadius: BorderRadius.all(Radius.circular(14)),
    border: Border.fromBorderSide(
      BorderSide(color: Color(0x1AFFFFFF), width: 1),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.all(Radius.circular(14)),
      child: Stack(
        children: [
          Positioned.fill(
            child: BackdropFilter(
              filter: _kBlur,
              child: const DecoratedBox(decoration: _kDecoration),
            ),
          ),
          Material(
            type: MaterialType.transparency,
            child: InkWell(
              key: tileKey,
              onTap: isLoading ? null : onTap,
              splashColor: Colors.white.withValues(alpha: 0.06),
              highlightColor: Colors.white.withValues(alpha: 0.03),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: BrandColors.camel,
                            ),
                          )
                        : Icon(icon, color: BrandColors.camel, size: 20),
                    const SizedBox(width: 14),
                    Text(
                      label,
                      style: const TextStyle(
                        color: BrandColors.cream,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
