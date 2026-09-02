// Shared «Видалити салон» confirm → delete → feedback flow.
//
// PROMOTED (REUSE-FIRST, Phase 21.13) out of
// `SalonSettingsScreen._deleteSalon()` (Phase 21.2) — that screen's own
// private method duplicated this exact confirm→call→snack→navigate sequence
// and the shared account-level `SettingsScreen`'s owner-only
// `showDeleteSalon` row needed the identical behaviour. Rather than copy the
// ~20-line method a second time, it is promoted here and BOTH call sites now
// invoke this one function — `salon_settings_screen.dart` rewired onto it
// with zero behavioural change (same dialog, same notifier call, same snack
// copy, same landing route).
//
// Shows [DeleteSalonDialog]; on confirm, calls
// `salonManagementProfileProvider(salonId).notifier.deleteSalon()`
// (`DELETE /salons/{salonId}`, soft-deactivate — owner-only, enforced
// server-side); on success shows a success snack and navigates to the
// auth-derived role home via `roleHomePath` — for SALON_OWNER/SALON_ADMIN
// that resolves to `RouteNames.salonHome`, whose `SalonHomeResolverScreen`
// already re-derives "primary salon, else first remaining salon, else
// `/salons/mine`" against the freshly-invalidated `mySalonsProvider`; on
// failure shows an error snack and leaves the caller on the current screen.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/role_home.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/feedback/show_velvet_snack.dart';

import '../../auth/domain/auth_session.dart';
import '../../auth/presentation/auth_notifier.dart';
import '../application/salon_management_profile_notifier.dart';
import 'widgets/delete_salon_dialog.dart';

/// Runs the shared delete-salon confirm→delete→feedback flow for [salonId].
///
/// [setLoading] is invoked with `true` the instant the owner confirms (so
/// the caller can flip its own `SettingsRow(loading: ...)` flag) and with
/// `false` again only on failure — on success the screen navigates away, so
/// there is no matching "loading=false" call to make.
Future<void> runDeleteSalonFlow({
  required BuildContext context,
  required WidgetRef ref,
  required String salonId,
  required ValueChanged<bool> setLoading,
}) async {
  final l10n = AppLocalizations.of(context);
  final bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => const DeleteSalonDialog(),
  );
  if (confirmed != true || !context.mounted) return;

  setLoading(true);
  final failure = await ref
      .read(salonManagementProfileProvider(salonId).notifier)
      .deleteSalon();
  if (!context.mounted) return;

  if (failure != null) {
    setLoading(false);
    showErrorSnack(context, failure.userMessage(context));
    return;
  }

  showSuccessSnack(context, l10n.deleteSalonSuccess);
  // Auth-derived role home — not the bare '/' placeholder route. Both
  // SALON_OWNER and SALON_ADMIN resolve to `RouteNames.salonHome`, whose
  // resolver re-derives "primary salon, else first remaining salon, else
  // `/salons/mine`" against the freshly-invalidated salon list.
  final session = ref.read(authProvider).value;
  context.go(
    session is Authenticated
        ? roleHomePath(session.user.role)
        : RouteNames.login,
  );
}
