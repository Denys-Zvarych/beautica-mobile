import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'firebase_bootstrap.dart';

part 'push_available_provider.g.dart';

/// Injection seam for the Firebase initialiser (tests override it with a fake
/// `Future<bool> Function()`); defaults to [initFirebaseSafely].
@Riverpod(keepAlive: true)
Future<bool> Function() firebaseInitializer(Ref ref) => initFirebaseSafely;

/// Whether Firebase initialised (phase 066). Runs `initFirebaseSafely()` once
/// (keep-alive) and awaits its result (a slow init still enables push; only the
/// 30 s hang guard in `initFirebaseSafely` yields `false`); never errors. `main.dart` kicks it
/// off AFTER `runApp` so it is off the cold-start critical path; token
/// registration (067) and message handling (068) `await` `.future`.
@Riverpod(keepAlive: true)
Future<bool> pushAvailable(Ref ref) => ref.read(firebaseInitializerProvider)();
