import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

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
/// [initializer], [isAndroid] and [timeout] are test seams.
Future<bool> initFirebaseSafely({
  Future<void> Function()? initializer,
  bool? isAndroid,
  Duration timeout = kFirebaseInitTimeout,
}) async {
  final bool android = isAndroid ?? (!kIsWeb && Platform.isAndroid);
  if (!android) return false;
  try {
    await (initializer ?? _initializeDefaultApp)().timeout(timeout);
    return true;
  } on Object {
    developer.log(
      'Firebase not configured; push unavailable',
      name: 'core.push',
      level: 500,
    );
    return false;
  }
}

Future<void> _initializeDefaultApp() async {
  await Firebase.initializeApp();
}
