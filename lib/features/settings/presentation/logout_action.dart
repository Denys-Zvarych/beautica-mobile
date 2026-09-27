// Shared logout flow used by the settings hub's terminal row and the account
// page's terminal row. Extracted from the former standalone settings_screen so
// both entry points share one confirm-dialog → authProvider.logout() →
// go(/login) implementation with a single double-tap guard.
//
// Two [ValueNotifier<bool>]s, owned by the caller (each page holds one pair
// for its lifetime), do two DIFFERENT jobs — see the mobile-perf fix note
// below for why they must not be merged back into one flag.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/feedback/show_velvet_snack.dart';

/// Runs the full logout flow: confirm dialog → [AuthNotifier.logout] →
/// `context.go(RouteNames.login)`. Shows a failure snack on error.
///
/// Two flags, two different lifetimes — DO NOT merge them back into one:
///
/// * [inFlight] is the RE-ENTRANCY GUARD. It is never bound to any widget —
///   it exists purely to make a second tap a no-op. Set synchronously HERE,
///   before the `showDialog` await, not after it resolves: two rapid taps
///   (finger bounce, or a double-activate via a screen reader) both used to
///   read `inFlight.value == false` before either await returned, stacking
///   two confirm dialogs and — if both were confirmed — firing two
///   concurrent logout calls (mobile-security LOW fix, 2026-09-08). Reset on
///   every exit path that does NOT end in navigation: cancel, the
///   post-dialog unmounted early-return, and the error path.
///
/// * [loading] is the UI-VISIBLE flag — what the caller binds to
///   `SettingsRow(loading:)` / `IgnorePointer(ignoring:)`. It is set true
///   only AFTER `confirmed == true`, immediately before the network call —
///   never on the initial tap. Setting it before consent (the original,
///   single-flag version of this fix) made the indeterminate spinner run,
///   and froze sibling rows, for the entire unbounded time the confirm
///   dialog sits open — implying the logout had already started
///   (mobile-perf MEDIUM fix, 2026-09-08). Reset on every exit path that
///   does NOT end in navigation, same as [inFlight].
Future<void> runLogoutFlow(
  BuildContext context,
  WidgetRef ref, {
  required ValueNotifier<bool> inFlight,
  required ValueNotifier<bool> loading,
}) async {
  if (inFlight.value) return;
  inFlight.value = true;

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

  if (confirmed != true) {
    inFlight.value = false;
    return;
  }
  if (!context.mounted) {
    // mobile-security LOW fix (2026-09-08) — this used to fall straight
    // through without resetting the guard. Before `inFlight` was set
    // synchronously pre-dialog it didn't matter (nothing was set yet); now
    // it must be reset or a screen torn down mid-dialog (e.g. an auth
    // redirect) leaves the guard stuck `true` forever. `loading` is not
    // set yet at this point — it only flips below, after this check — so
    // there is nothing to reset for it here.
    inFlight.value = false;
    return;
  }

  // UI flag starts here — after consent, immediately before the network
  // call. See the flag-lifetime doc on [runLogoutFlow] above.
  loading.value = true;
  try {
    await ref.read(authProvider.notifier).logout();
    if (!context.mounted) return;
    context.go(RouteNames.login);
    // Deliberately no reset of either flag here — navigation away follows,
    // and the calling widget (and its notifiers) is about to be torn down.
  } catch (_) {
    inFlight.value = false;
    loading.value = false;
    if (!context.mounted) return;
    showErrorSnack(context, l10n.logoutFailed);
  }
}
