// Shared logout flow used by the settings hub's terminal row and the account
// page's terminal row. Extracted from the former standalone settings_screen so
// both entry points share one confirm-dialog → authProvider.logout() →
// go(/login) implementation with a single double-tap guard.
//
// The guard is a [ValueNotifier<bool>] owned by the caller (each page holds one
// for its lifetime) so a logout in flight cannot be triggered twice and the
// caller can reflect the in-flight state in its row if desired.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';

/// Runs the full logout flow: confirm dialog → [AuthNotifier.logout] →
/// `context.go(RouteNames.login)`. Shows a failure SnackBar on error.
///
/// [inFlight] is a double-tap guard owned by the calling widget; this helper
/// flips it true for the duration of the network call and resets it afterwards.
Future<void> runLogoutFlow(
  BuildContext context,
  WidgetRef ref,
  ValueNotifier<bool> inFlight,
) async {
  if (inFlight.value) return;

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
      actions: <Widget>[
        TextButton(
          key: const Key('btn-logout-cancel'),
          onPressed: () => ctx.pop(false),
          child: Text(l10n.cancel, style: VelvetText.link()),
        ),
        TextButton(
          key: const Key('btn-logout-confirm'),
          onPressed: () => ctx.pop(true),
          child: Text(
            l10n.logout,
            style: VelvetText.link().copyWith(color: BrandColors.error),
          ),
        ),
      ],
    ),
  );

  if (confirmed != true) return;
  if (!context.mounted) return;

  inFlight.value = true;
  try {
    await ref.read(authProvider.notifier).logout();
    if (!context.mounted) return;
    context.go(RouteNames.login);
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.logoutFailed)));
  } finally {
    inFlight.value = false;
  }
}
