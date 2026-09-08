// Shared «Видалити акаунт» confirm → delete → feedback flow for the CLIENT
// settings hub's terminal-adjacent row.
//
// Mirrors [runLogoutFlow] (`logout_action.dart`, same directory) in shape —
// confirm dialog → single network call → post-action handling — and reuses
// runLogoutFlow's EXACT post-success steps rather than hand-rolling a second
// logout path: `DELETE /users/me` denylists the bearer token server-side, so
// the client must tear down its own session and land exactly where an
// explicit logout does. [AuthNotifier.logout] is already tolerant of a
// server-side call failing (the account — and its refresh token — no longer
// exist by the time it runs), so calling it unconditionally after a
// successful delete is safe: it best-effort calls the (now pointless) logout
// endpoint, then unconditionally wipes secure storage.
//
// The dialog copy is deliberately short and generic — no booking COUNT is
// fetched or displayed (locked product decision), just the three facts the
// user asked for: upcoming bookings are cancelled, the action cannot be
// reverted, and the client loses all access and data.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/user/data/user_repository.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/feedback/show_velvet_snack.dart';

/// Runs the full delete-account flow: confirm dialog →
/// [UserRepository.deleteMyAccount] → the same session teardown + redirect
/// [runLogoutFlow] uses. Shows a failure snack on error (surfacing the
/// backend's own message on the booking-limit 422 — see
/// [AccountDeleteBookingLimitFailure]) and leaves the caller on the current
/// screen.
///
/// Two [ValueNotifier<bool>]s, owned by the calling widget, mirror
/// [runLogoutFlow]'s own contract — they do two DIFFERENT jobs and must not
/// be merged back into one flag:
///
/// * [inFlight] is the RE-ENTRANCY GUARD. Never bound to any widget — it
///   only makes a second tap a no-op. Set synchronously HERE, before the
///   `showDialog` await, not after it resolves (identical fix to
///   [runLogoutFlow]'s own — these two flows are maintained as siblings):
///   two rapid taps both used to read `inFlight.value == false` before
///   either await returned, stacking two confirm dialogs and — if both were
///   confirmed — firing two concurrent `DELETE /api/v1/users/me` calls
///   (mobile-security LOW fix, 2026-09-08). Reset on every exit path that
///   does NOT end in navigation: cancel, the post-dialog unmounted
///   early-return, and the error path.
///
/// * [loading] is the UI-VISIBLE flag — what the caller binds to
///   `SettingsRow(loading:)` / `IgnorePointer(ignoring:)`. Set true only
///   AFTER `confirmed == true`, immediately before the network call — never
///   on the initial tap. Setting it before consent made the indeterminate
///   spinner run, and froze every sibling row, for the entire unbounded
///   time the confirm dialog sits open, implying deletion had already
///   started before the user agreed (mobile-perf MEDIUM fix, 2026-09-08).
///   Reset on every exit path that does NOT end in navigation, same as
///   [inFlight].
Future<void> runDeleteAccountFlow(
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
      title: Text(l10n.settingsHubDeleteAccount, style: VelvetText.heading()),
      content: Text(l10n.deleteAccountConfirmBody, style: VelvetText.body()),
      actions: <Widget>[
        TextButton(
          key: const Key('btn-delete-account-cancel'),
          onPressed: () => ctx.pop(false),
          child: Text(l10n.cancel, style: VelvetText.link()),
        ),
        TextButton(
          key: const Key('btn-delete-account-confirm'),
          onPressed: () => ctx.pop(true),
          child: Text(
            l10n.settingsHubDeleteAccount,
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
    // mobile-security LOW fix (2026-09-08) — see the identical note on
    // [runLogoutFlow]: this used to fall through without resetting the
    // guard, which was harmless before `inFlight` was set pre-dialog and a
    // stuck-`true` bug after. `loading` is not set yet at this point (it
    // only flips below, after this check), so there is nothing to reset
    // for it here.
    inFlight.value = false;
    return;
  }

  // UI flag starts here — after consent, immediately before the network
  // call. See the flag-lifetime doc on [runDeleteAccountFlow] above.
  loading.value = true;
  try {
    await ref.read(userRepositoryProvider).deleteMyAccount();
    if (!context.mounted) return;
    // Same session teardown + redirect as [runLogoutFlow] — never a second,
    // hand-rolled logout path. The account (and its refresh token) are
    // already gone server-side, but [AuthNotifier.logout] tolerates that.
    await ref.read(authProvider.notifier).logout();
    if (!context.mounted) return;
    context.go(RouteNames.login);
    // Deliberately no reset of either flag here — navigation away follows,
    // and the calling widget (and its notifiers) is about to be torn down.
  } on Failure catch (f) {
    inFlight.value = false;
    loading.value = false;
    if (!context.mounted) return;
    showErrorSnack(context, f.userMessage(context));
  } catch (_) {
    inFlight.value = false;
    loading.value = false;
    if (!context.mounted) return;
    showErrorSnack(context, l10n.errUnknown);
  }
}
