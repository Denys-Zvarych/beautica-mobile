import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'firebase_messaging_provider.g.dart';

/// Phase 067 — the ONE seam through which the app touches [FirebaseMessaging]
/// (tests override it with a mocktail fake).
///
/// Reading `FirebaseMessaging.instance` throws while Firebase is not
/// initialised, so callers MUST first await `pushAvailableProvider.future`
/// and read this only when it resolved `true`.
@Riverpod(keepAlive: true)
FirebaseMessaging firebaseMessaging(Ref ref) => FirebaseMessaging.instance;

/// Phase 068 — the foreground-message stream. `FirebaseMessaging.onMessage` is
/// STATIC (not on the instance), so it gets its own seam for tests. Like
/// [firebaseMessaging], call it only after push is known to be available.
@Riverpod(keepAlive: true)
Stream<RemoteMessage> Function() firebaseForegroundMessages(Ref ref) =>
    () => FirebaseMessaging.onMessage;

/// Phase 069 — taps on a notification while the app is in the BACKGROUND.
/// `FirebaseMessaging.onMessageOpenedApp` is STATIC, hence its own seam. The
/// cold-start tap is `firebaseMessaging.getInitialMessage()` (an instance
/// method, so it goes through [firebaseMessaging]). Call only after push is
/// known to be available.
@Riverpod(keepAlive: true)
Stream<RemoteMessage> Function() firebaseOpenedAppMessages(Ref ref) =>
    () => FirebaseMessaging.onMessageOpenedApp;
