import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io' show Platform;

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../config/app_check_config.dart';

/// Hang guard for `Firebase.initializeApp()`, NOT a startup budget: init runs
/// after `runApp` (off the critical path) and `.timeout` does not cancel the
/// native call, so a short bound would resolve the keep-alive provider to
/// `false` for the whole session even when init succeeds moments later. Generous
/// on purpose; only a true hang reaches it.
const Duration kFirebaseInitTimeout = Duration(seconds: 30);

/// Phase 066 — initialises Firebase WITHOUT options (Android reads its config
/// from the git-ignored `android/app/google-services.json` through the Google
/// Services Gradle plugin; no `firebase_options.dart`).
///
/// Returns `true` only when Firebase initialised. Any failure (the file was
/// absent at build time, non-Android platform, plugin error) yields `false`
/// and the app runs push-less. Never throws; logs one line without details.
///
/// Bounded by [timeout] (a hung native init must not pin the provider forever);
/// a timeout yields `false`. A slow-but-successful init within the bound yields `true`. Started AFTER `runApp` (off the cold-start path).
///
/// App Check activation ([appCheckActivator], default
/// [activateAppCheckSafely]) starts only AFTER init succeeds, unawaited and
/// outside the [timeout] budget: a slow or failing activation never turns
/// push off.
///
/// [initializer], [appCheckActivator], [isAndroid] and [timeout] are test
/// seams.
Future<bool> initFirebaseSafely({
  Future<void> Function()? initializer,
  Future<void> Function()? appCheckActivator,
  bool? isAndroid,
  Duration timeout = kFirebaseInitTimeout,
}) async {
  final bool android = isAndroid ?? (!kIsWeb && Platform.isAndroid);
  if (!android) return false;
  try {
    await (initializer ?? Firebase.initializeApp)().timeout(timeout);
  } on Object {
    developer.log(
      'Firebase not configured; push unavailable',
      name: 'core.push',
      level: 500,
    );
    return false;
  }
  _startAppCheck(appCheckActivator ?? activateAppCheckSafely);
  return true;
}

/// Fire-and-forget App Check activation with its own guard: a synchronous or
/// asynchronous failure is logged and swallowed, never surfaced.
void _startAppCheck(Future<void> Function() activate) {
  unawaited(
    Future<void>.sync(activate).catchError((Object e) {
      developer.log(
        'App Check start failed (${e.runtimeType})',
        name: 'core.appcheck',
        level: 900,
      );
    }),
  );
}

/// M515 (AUTH-D14 / AUTH-54) — activates Firebase App Check right after
/// `Firebase.initializeApp()`: the debug provider in debug builds (with the
/// optional `--dart-define=APP_CHECK_DEBUG_TOKEN`), Play Integrity in profile /
/// release. A failure here never turns push off — App Check is best-effort on
/// the client; the backend decides what a missing token means.
///
/// After activation, background token auto-refresh is turned OFF: tokens are
/// only needed on the SMS-sending paths, where `getToken()` fetches one on
/// demand — proactive refresh would only burn Play Integrity quota.
/// [activator] and [setAutoRefresh] are injectable for tests.
@visibleForTesting
Future<void> activateAppCheckSafely({
  Future<void> Function(AndroidAppCheckProvider provider)? activator,
  Future<void> Function(bool enabled)? setAutoRefresh,
  bool debug = kDebugMode,
  String debugToken = kAppCheckDebugToken,
}) async {
  final AndroidAppCheckProvider provider = debug
      ? AndroidDebugProvider(debugToken: debugToken.isEmpty ? null : debugToken)
      : const AndroidPlayIntegrityProvider();
  try {
    await (activator ?? _activateAppCheck)(provider);
  } on Object catch (e) {
    developer.log(
      'App Check activation failed (${e.runtimeType}); SMS calls go without '
      'a token',
      name: 'core.appcheck',
      level: 900,
    );
    return;
  }
  try {
    await (setAutoRefresh ?? _setAppCheckAutoRefresh)(false);
  } on Object catch (e) {
    developer.log(
      'App Check auto-refresh disable failed (${e.runtimeType}); App Check '
      'stays active',
      name: 'core.appcheck',
      level: 900,
    );
  }
}

Future<void> _activateAppCheck(AndroidAppCheckProvider provider) =>
    FirebaseAppCheck.instance.activate(providerAndroid: provider);

Future<void> _setAppCheckAutoRefresh(bool enabled) =>
    FirebaseAppCheck.instance.setTokenAutoRefreshEnabled(enabled);
