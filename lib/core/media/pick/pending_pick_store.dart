// Phase 073 audit — binds an in-flight media pick to the account and the media
// kind that started it.
//
// image_picker's Android "lost data" record survives a process death AND a
// logout, so on its own it would let the next account resume the previous
// account's photo. A small `{ownerId, kind}` tag is written (secure storage)
// BEFORE a pick starts and cleared when it settles; recovery only proceeds
// when the tag matches the current user and the expected kind, otherwise the
// lost file is drained and deleted instead. Opaque id + enum name: no PII.
//
// Never throws: a storage failure must not break a pick, and an unreadable tag
// reads as "not ours" (fail closed).

import 'dart:convert';
import 'dart:developer';

import 'package:beautica_mobile/core/media/pick/media_kind.dart';
import 'package:beautica_mobile/core/storage/secure_storage.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'pending_pick_store.g.dart';

/// Who started the pick in flight, and for which media kind.
final class PendingPick {
  const PendingPick({required this.ownerId, required this.kind});

  final String ownerId;
  final MediaKind kind;

  /// Whether this pick may be resumed by [userId] for [expected].
  bool belongsTo(String? userId, MediaKind expected) =>
      userId != null && userId == ownerId && kind == expected;
}

final class PendingPickStore {
  PendingPickStore(this._storage);

  final SecureStorage _storage;

  /// Lost-pick recovery is Android-only (`retrieveLostData`), so elsewhere the
  /// tag is never read — skip the keystore I/O. Same gate as `recoverLost`
  /// (tests flip it with `debugDefaultTargetPlatformOverride`).
  bool get _recoveryApplies => defaultTargetPlatform == TargetPlatform.android;

  /// Records that [ownerId] is picking a [kind].
  Future<void> begin(String? ownerId, MediaKind kind) async {
    if (ownerId == null || !_recoveryApplies) return;
    try {
      await _storage.writePendingPick(
        jsonEncode(<String, String>{'ownerId': ownerId, 'kind': kind.name}),
      );
    } on Object {
      log('pending pick write failed', name: 'media.pick', level: 900);
    }
  }

  /// The recorded pick, or `null` when none / unreadable / malformed.
  Future<PendingPick?> read() async {
    try {
      final String? raw = await _storage.readPendingPick();
      if (raw == null) return null;
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) return null;
      final Object? owner = decoded['ownerId'];
      final Object? kindName = decoded['kind'];
      if (owner is! String || kindName is! String) return null;
      for (final MediaKind k in MediaKind.values) {
        if (k.name == kindName) return PendingPick(ownerId: owner, kind: k);
      }
      return null;
    } on Object {
      return null;
    }
  }

  /// Forgets the recorded pick.
  Future<void> clear() async {
    if (!_recoveryApplies) return;
    try {
      await _storage.deletePendingPick();
    } on Object {
      log('pending pick clear failed', name: 'media.pick', level: 900);
    }
  }
}

/// App-wide [PendingPickStore]. Read lazily (never from a startup path): the
/// secure-storage provider is keystore-backed.
@Riverpod(keepAlive: true)
PendingPickStore pendingPickStore(Ref ref) =>
    PendingPickStore(ref.read(secureStorageProvider));
