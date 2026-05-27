// Phase 2.3 — StorageKeys value-pinning tests.
//
// These tests assert the exact string values of each [StorageKeys] constant.
// They exist to prevent accidental renames that would silently corrupt
// existing user sessions on device (the key string IS the lookup key in the
// platform Keystore — renaming it makes previously-stored values unreadable).
//
// If a key rename is intentional, a migration strategy must be in place first,
// and THEN these tests may be updated.

import 'package:beautica_mobile/core/storage/storage_keys.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StorageKeys — value pinning', () {
    test('refreshToken key has expected value', () {
      expect(StorageKeys.refreshToken, 'BEAUTICA_REFRESH_TOKEN');
    });

    test('userJson key has expected value', () {
      expect(StorageKeys.userJson, 'BEAUTICA_USER_JSON');
    });
  });
}
