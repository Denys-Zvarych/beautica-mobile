// Phase 2.8 — Settings screen (minimal — full settings UI ships in Phase 5+).
//
// Purpose: provides an accessible logout entry point so users can clear their
// session. Future phases will expand this screen with notification preferences,
// account management, and language selection.
//
// Logout flow:
//   1. Tap the logout tile → call authProvider.notifier.logout().
//   2. Check mounted after await (avoids setState-after-dispose crash).
//   3. Navigate to /login via go_router (the router guard would catch it
//      anyway, but we navigate explicitly for snappier UX).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../features/auth/presentation/auth_notifier.dart';
import '../../../l10n/app_localizations.dart';
import '../../../routing/route_names.dart';

/// Minimal settings screen.
///
/// Contains a single logout action. Navigation back to the login screen is
/// explicit — the Phase 2.9 router guard provides a second safety net.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListView(
        children: [
          ListTile(
            key: const Key('btn-logout'),
            leading: const Icon(Icons.logout),
            title: Text(l10n.logout),
            onTap: () async {
              await ref.read(authProvider.notifier).logout();
              if (!context.mounted) return;
              context.go(RouteNames.login);
            },
          ),
        ],
      ),
    );
  }
}
