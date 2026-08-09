// VelvetSnack public API — the call shape every screen actually uses.
//
// Wave 1 (infrastructure only): this file, `velvet_snack.dart` and
// `velvet_snack_host.dart` ship the component; the 63 existing
// `ScaffoldMessenger.of(context).showSnackBar(...)` call sites are migrated
// in a later wave. This surface is deliberately small and stable so that
// migration can be briefed against it without touching the overlay
// mechanism in `velvet_snack_host.dart`.
import 'package:flutter/material.dart';

import 'velvet_snack.dart';
import 'velvet_snack_host.dart';

/// Shows a [VelvetSnack] floating above everything, bottom-anchored, with
/// single-slot pre-emption (see `velvet_snack_host.dart` — no FIFO queue: a
/// new snack replaces whatever is currently showing).
///
/// [duration] overrides the default dwell (4s, or 6s when [actionLabel] is
/// supplied — matching the approved design spec). [showClose] adds an
/// explicit dismiss affordance, needed for long, non-actionable messages that
/// should not rely on the dwell timer or a swipe. [bottomInset] is extra
/// bottom clearance — pass the height of a bottom nav bar so the snack sits
/// above it rather than on it; the client shell's 5-tab bar is the only real
/// caller.
///
/// Safe to call from inside `showModalBottomSheet` / `showDialog` builders,
/// and safe to call immediately before a route pop — see
/// `velvet_snack_host.dart`'s file-level doc for why.
VelvetSnackHandle showVelvetSnack(
  BuildContext context, {
  required String message,
  required VelvetSnackVariant variant,
  String? actionLabel,
  VoidCallback? onAction,
  Duration? duration,
  bool showClose = false,
  int maxLines = 2,
  double bottomInset = 0,
}) {
  return showOnVelvetSnackHost(
    context: context,
    variant: variant,
    message: message,
    actionLabel: actionLabel,
    onAction: onAction,
    showClose: showClose,
    maxLines: maxLines,
    dwell: duration,
    bottomInset: bottomInset,
  );
}

/// Success wrapper — «Зміни збережено».
VelvetSnackHandle showSuccessSnack(
  BuildContext context,
  String message, {
  String? actionLabel,
  VoidCallback? onAction,
  Duration? duration,
  bool showClose = false,
  int maxLines = 2,
  double bottomInset = 0,
}) => showVelvetSnack(
  context,
  message: message,
  variant: VelvetSnackVariant.success,
  actionLabel: actionLabel,
  onAction: onAction,
  duration: duration,
  showClose: showClose,
  maxLines: maxLines,
  bottomInset: bottomInset,
);

/// Error wrapper — e.g. «Не вдалося зберегти». Pass [actionLabel] +
/// [onAction] for a retryable failure (the 503 pattern in
/// `service_setup_screen.dart`'s `_showSnack`): the default dwell becomes 6s
/// automatically once an action is present, or pass [duration] explicitly
/// (e.g. 8s) to match a specific server-side retry window.
VelvetSnackHandle showErrorSnack(
  BuildContext context,
  String message, {
  String? actionLabel,
  VoidCallback? onAction,
  Duration? duration,
  bool showClose = false,
  int maxLines = 2,
  double bottomInset = 0,
}) => showVelvetSnack(
  context,
  message: message,
  variant: VelvetSnackVariant.error,
  actionLabel: actionLabel,
  onAction: onAction,
  duration: duration,
  showClose: showClose,
  maxLines: maxLines,
  bottomInset: bottomInset,
);

/// Info wrapper — «Скоро буде доступно».
VelvetSnackHandle showInfoSnack(
  BuildContext context,
  String message, {
  String? actionLabel,
  VoidCallback? onAction,
  Duration? duration,
  bool showClose = false,
  int maxLines = 2,
  double bottomInset = 0,
}) => showVelvetSnack(
  context,
  message: message,
  variant: VelvetSnackVariant.info,
  actionLabel: actionLabel,
  onAction: onAction,
  duration: duration,
  showClose: showClose,
  maxLines: maxLines,
  bottomInset: bottomInset,
);

/// Warning wrapper — e.g. «Досягнуто ліміт послуг».
VelvetSnackHandle showWarningSnack(
  BuildContext context,
  String message, {
  String? actionLabel,
  VoidCallback? onAction,
  Duration? duration,
  bool showClose = false,
  int maxLines = 2,
  double bottomInset = 0,
}) => showVelvetSnack(
  context,
  message: message,
  variant: VelvetSnackVariant.warning,
  actionLabel: actionLabel,
  onAction: onAction,
  duration: duration,
  showClose: showClose,
  maxLines: maxLines,
  bottomInset: bottomInset,
);
