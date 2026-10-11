// Phase 288 D8 — the ONE codec for the `StorageKeys.lastSalon` envelope.
//
// Phase 286 D2 fixed the slot's shape as `{userId, salonId}` (not a bare id)
// so a reader can treat a `userId` mismatch as "nothing stored". Both sides of
// the slot go through this class: the Phase 287 writer
// (`SalonShellScreen._writeLastSalon`) calls [LastVisitedSalon.encode], the
// Phase 288 reader (`lastVisitedSalonProvider`) calls
// [LastVisitedSalon.tryDecode]. The JSON key names are spelled HERE ONLY — a
// second hand-written copy would let a rename on one side fail silently (the
// resolver would just fall back to `salons.first`).

import 'dart:convert';

import 'package:flutter/foundation.dart';

/// The last salon an account viewed on this device, as persisted under
/// `StorageKeys.lastSalon`.
@immutable
final class LastVisitedSalon {
  const LastVisitedSalon({required this.userId, required this.salonId});

  /// Wire key for [userId]. Changing it orphans every slot already written.
  static const String _userIdKey = 'userId';

  /// Wire key for [salonId]. Changing it orphans every slot already written.
  static const String _salonIdKey = 'salonId';

  /// The account that recorded the pointer — compared against the current
  /// session so a pointer never crosses accounts on a shared device.
  final String userId;

  /// The salon that account last viewed.
  final String salonId;

  /// JSON envelope written to secure storage.
  String encode() =>
      jsonEncode(<String, String>{_userIdKey: userId, _salonIdKey: salonId});

  /// Decodes [raw] or returns `null` — on a null/empty input, malformed JSON,
  /// a non-object root, a missing key, or a value that is not a non-empty
  /// `String`. Never throws: a corrupt slot degrades to "nothing stored".
  static LastVisitedSalon? tryDecode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, Object?>) return null;
    final Object? userId = decoded[_userIdKey];
    final Object? salonId = decoded[_salonIdKey];
    if (userId is! String || userId.isEmpty) return null;
    if (salonId is! String || salonId.isEmpty) return null;
    return LastVisitedSalon(userId: userId, salonId: salonId);
  }

  @override
  bool operator ==(Object other) =>
      other is LastVisitedSalon &&
      other.userId == userId &&
      other.salonId == salonId;

  @override
  int get hashCode => Object.hash(userId, salonId);

  @override
  // Redacted: ids must never reach a log line or an error message through an
  // interpolation (mobile-security INFO, Phase 288).
  String toString() => 'LastVisitedSalon(<redacted>)';
}
