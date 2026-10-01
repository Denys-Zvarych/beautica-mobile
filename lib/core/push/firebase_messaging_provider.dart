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
