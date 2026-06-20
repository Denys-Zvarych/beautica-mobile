// Unit tests for [PendingLocalityStore] — the async wrapper that mirrors the
// durable [PendingLocality] blob to/from secure storage (silent-data-loss fix).
//
// These tests use the in-memory [FakeSecureStorage] (the same fake the auth
// tokens use) — NO platform channel, NO real keystore. The store is exercised
// directly (not through the verification screen) so the save / read / clear
// contract is pinned in isolation:
//
//   • save → read returns an equivalent blob (Test 1).
//   • read on an empty store returns null (Test 2).
//   • clear after save → read returns null (Test 3).
//   • the blob is written under the namespaced BEAUTICA_PENDING_LOCALITY key
//     only — not the refresh-token / user-json keys (Test 4).
//   • a corrupt (non-JSON) stored value is treated as absent, never thrown
//     into the verification flow (Test 5).
//
// Every test creates a fresh FakeSecureStorage + a fresh store, so there is no
// cross-test state leak.

import 'package:beautica_mobile/core/storage/storage_keys.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/state/pending_locality.dart';
import 'package:beautica_mobile/features/auth/state/pending_locality_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fakes/fake_secure_storage.dart';

void main() {
  late FakeSecureStorage storage;
  late PendingLocalityStore store;

  setUp(() {
    storage = FakeSecureStorage();
    store = PendingLocalityStore(storage);
  });

  const blob = PendingLocality(
    email: 'anya@example.com',
    role: UserRole.client,
    localityProvided: true,
    cityId: 'city-1',
    districtId: 'district-1',
    street: 'вул. Хрещатик',
    buildingNo: '12А',
    locationNote: '3 поверх',
  );

  group('PendingLocalityStore', () {
    // -----------------------------------------------------------------------
    // Test 1 — save → read returns an equivalent blob.
    // -----------------------------------------------------------------------
    test('1. save then read returns an equivalent PendingLocality', () async {
      await store.save(blob);

      final restored = await store.read();

      expect(restored, isNotNull);
      expect(restored!.email, equals('anya@example.com'));
      expect(restored.role, equals(UserRole.client));
      expect(restored.localityProvided, isTrue);
      expect(restored.cityId, equals('city-1'));
      expect(restored.districtId, equals('district-1'));
      expect(restored.street, equals('вул. Хрещатик'));
      expect(restored.buildingNo, equals('12А'));
      expect(restored.locationNote, equals('3 поверх'));
    });

    // -----------------------------------------------------------------------
    // Test 2 — read on an empty store returns null.
    // -----------------------------------------------------------------------
    test('2. read returns null when nothing was saved', () async {
      expect(await store.read(), isNull);
    });

    // -----------------------------------------------------------------------
    // Test 3 — clear after save → read returns null.
    // -----------------------------------------------------------------------
    test('3. clear after save: subsequent read returns null', () async {
      await store.save(blob);
      expect(await store.read(), isNotNull); // sanity: it was there

      await store.clear();

      expect(
        await store.read(),
        isNull,
        reason:
            'After clear() the durable blob must be gone — this is the /done + '
            'logout wipe that prevents stale locality lingering at rest.',
      );
    });

    // -----------------------------------------------------------------------
    // Test 4 — the blob is written under the namespaced pendingLocality key
    //          only (not the token / user-json keys).
    // -----------------------------------------------------------------------
    test('4. save writes under BEAUTICA_PENDING_LOCALITY only', () async {
      await store.save(blob);

      // The dedicated key is populated ...
      expect(await storage.readPendingLocality(), isNotNull);
      // ... and the unrelated keys are untouched.
      expect(await storage.readRefreshToken(), isNull);
      expect(await storage.readUserJson(), isNull);

      // Defensive: the key constant is the namespaced one (rename guard).
      expect(StorageKeys.pendingLocality, equals('BEAUTICA_PENDING_LOCALITY'));
    });

    // -----------------------------------------------------------------------
    // Test 5 — a corrupt stored value is treated as absent (read returns null),
    //          never thrown into the verification flow.
    // -----------------------------------------------------------------------
    test(
      '5. a corrupt (non-JSON) stored value reads as null, not a throw',
      () async {
        // Write a value the store did not produce — invalid JSON.
        await storage.writePendingLocality('}{ not json at all');

        expect(
          await store.read(),
          isNull,
          reason:
              'A malformed blob must be tolerated as absent (FormatException '
              'swallowed) so a corrupt stash never crashes the OTP screen.',
        );
      },
    );

    // -----------------------------------------------------------------------
    // Test 6 — a structurally-valid JSON that is not a PendingLocality (unknown
    //          role) also reads as null via tryFromJson.
    // -----------------------------------------------------------------------
    test('6. valid JSON with an unknown role reads as null', () async {
      await storage.writePendingLocality(
        '{"email":"a@b.c","role":"NOPE","localityProvided":true}',
      );

      expect(await store.read(), isNull);
    });
  });
}
