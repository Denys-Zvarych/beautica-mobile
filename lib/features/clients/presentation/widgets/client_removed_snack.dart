// M544 (CLI-86) — the undo snack after a client was removed from «Клієнти»:
// «Клієнта прибрано зі списку» + «Повернути», with the velvet snack's
// time-left bar over a fixed 5 s window. ONE call shape for both entry points
// (the list swipe and the card «⋯»), composed only from `showVelvetSnack`.
//
// SESSION BOUNDARY (security audit): the undo belongs to the session that
// removed the client. A session change (logout, another account) dismisses
// the snack, and «Повернути» is a no-op if it is somehow tapped under a
// different signed-in user — it never writes for another session.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/clients/application/client_list_removal.dart'
    show kClientRemoveUndoWindow;
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/feedback/show_velvet_snack.dart';
import 'package:beautica_mobile/shared/feedback/velvet_snack.dart';
import 'package:beautica_mobile/shared/feedback/velvet_snack_host.dart'
    show VelvetSnackHandle;

export 'package:beautica_mobile/features/clients/application/client_list_removal.dart'
    show kClientRemoveUndoWindow;

/// Shows the removal undo snack; [onUndo] runs on «Повернути» — only while
/// the session that showed it is still the signed-in one.
VelvetSnackHandle showClientRemovedSnack(
  BuildContext context, {
  required VoidCallback onUndo,
}) {
  final AppLocalizations l10n = AppLocalizations.of(context);
  final ProviderContainer container = ProviderScope.containerOf(
    context,
    listen: false,
  );
  final String? owner = authUserIdOrNull(container.read(authProvider));
  final VoidCallback guarded = sameSessionUndo(container, owner, onUndo);

  ProviderSubscription<String?>? session;
  Timer? release;
  void stopWatching() {
    session?.close();
    session = null;
    release?.cancel();
    release = null;
  }

  final VelvetSnackHandle handle = showVelvetSnack(
    context,
    message: l10n.clientsRemovedSnack,
    variant: VelvetSnackVariant.info,
    actionLabel: l10n.clientsRemoveUndo,
    onAction: () {
      stopWatching();
      guarded();
    },
    duration: kClientRemoveUndoWindow,
    showCountdown: true,
  );
  session = container.listen<String?>(authProvider.select(authUserIdOrNull), (
    String? _,
    String? next,
  ) {
    if (next == owner) return;
    stopWatching();
    unawaited(handle.dismiss());
  });
  // Once the snack has played out (entrance + window + exit) it is gone on
  // its own: stop watching.
  release = Timer(
    VelvetSnackMotion.enter + kClientRemoveUndoWindow + VelvetSnackMotion.exit,
    stopWatching,
  );
  return handle;
}

/// The undo action bound to the session [owner] that removed the client:
/// runs [onUndo] only while [owner] is still the signed-in user, else does
/// nothing — it never writes under another session (security audit).
@visibleForTesting
VoidCallback sameSessionUndo(
  ProviderContainer container,
  String? owner,
  VoidCallback onUndo,
) => () {
  if (authUserIdOrNull(container.read(authProvider)) != owner) return;
  onUndo();
};
