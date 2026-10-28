// Shared "open an external URI, or show the error snack" helper.
//
// PROMOTED (REUSE-FIRST, 2026-10-27) — the identical
// launch → catch → `context.mounted` → error-snack sequence was hand-copied
// in five places: the Instagram openers on `MasterProfileScreen`,
// `PublicMasterProfileScreen`, `PublicSalonProfileScreen` and
// `SalonManagementProfileScreen`, and the guest tap-to-call on
// `BookingDetailScreen`. The registration terms/privacy links and the Account
// page's legal rows needed it a sixth and seventh time, so the sequence lives
// here once and every caller is rewired onto it.
//
// Behaviour (identical to every original copy):
//   * `uri == null` (a caller's sanitiser rejected the raw value) → the error
//     snack, no launch attempt;
//   * the launch throws, or reports `false` → the error snack;
//   * `context.mounted` is re-checked after the await before touching the
//     tree.
// The URI itself is NEVER logged (it may carry a phone number or a handle).

import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/network/logging_interceptor.dart' show LogSink;
import '../feedback/show_velvet_snack.dart';

/// The production sink — `dart:developer`'s `log()`, never `print()`.
void _developerLogSink(
  String message, {
  String name = '',
  int level = 0,
  Object? error,
}) => log(message, name: name, level: level, error: error);

/// Where [openExternalUri]'s debug-only "launch threw" line goes.
///
/// Exists ONLY so tests can observe what reaches the log (`dart:developer`'s
/// `log()` cannot be intercepted from `flutter test`) and pin the rule that
/// the line carries the `PlatformException` code or the error type — never
/// the URI or the exception message. Tests overwrite it and restore the
/// saved value in `tearDown`; production code never assigns it.
@visibleForTesting
LogSink debugOpenExternalUriLogSink = _developerLogSink;

/// Launches [uri] with [mode]; on a null [uri], a thrown launch, or a launch
/// that reports failure, shows [errorMessage] through [showErrorSnack]
/// (lifted by [bottomInset] above a bottom nav when the caller has one).
///
/// [errorMessage] is resolved by the caller BEFORE the await, so no
/// `AppLocalizations.of(context)` lookup happens on a possibly-unmounted
/// context. [logName] tags the debug-only log line for a thrown launch.
Future<void> openExternalUri(
  BuildContext context,
  Uri? uri, {
  required String errorMessage,
  LaunchMode mode = LaunchMode.externalApplication,
  double bottomInset = 0,
  String logName = 'shared.external_uri',
}) async {
  bool launched = false;
  if (uri != null) {
    try {
      launched = await launchUrl(uri, mode: mode);
    } on Object catch (error) {
      if (kDebugMode) {
        // Never the error message or the URI: a tel: PlatformException can
        // embed the (guest) phone number. Type / platform code only.
        final String kind = error is PlatformException
            ? 'PlatformException(${error.code})'
            : error.runtimeType.toString();
        debugOpenExternalUriLogSink(
          'External URI launch threw: $kind',
          name: logName,
          level: 900,
        );
      }
    }
  }
  if (!context.mounted || launched) return;
  showErrorSnack(context, errorMessage, bottomInset: bottomInset);
}
