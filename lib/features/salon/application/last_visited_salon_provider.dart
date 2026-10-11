// Phase 288 D7 — the reader of the `StorageKeys.lastSalon` slot.
//
// Watched ONLY by `SalonHomeResolverScreen`'s SALON_OWNER arm (after the
// admin `return`, so an admin never touches storage) and gated there on its
// concrete `AsyncData`, exactly like `mySalonsProvider`.
//
// Auto-dispose (the `@riverpod` default, no `keepAlive`) so every resolver
// mount re-reads the slot: an owner who switches salons and later returns to
// `/salons/home` in the same process gets the fresh pointer, not a cached one.
//
// Never errors: a storage exception and malformed content both resolve to
// `null` ("the app forgot") — which also keeps Riverpod 3's automatic retry
// out of the landing path.

import 'dart:developer';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';

import '../domain/last_visited_salon.dart';

part 'last_visited_salon_provider.g.dart';

/// The last salon viewed on this device, or `null` when nothing (valid) is
/// stored. The caller still checks `userId` against the session and the
/// salon id against the owner's current salon list.
///
/// Generated provider name: `lastVisitedSalonProvider`.
@riverpod
Future<LastVisitedSalon?> lastVisitedSalon(Ref ref) async {
  try {
    return LastVisitedSalon.tryDecode(
      await ref.read(secureStorageProvider).readLastSalon(),
    );
  } on Object catch (e) {
    log(
      'lastSalon read failed (${e.runtimeType}); treating as empty',
      name: 'feature.salon',
      level: 900,
    );
    return null;
  }
}
