// Unit tests for [PendingLocality] — the durable post-OTP locality slice that
// fixes the silent CLIENT-location data-loss bug.
//
// The blob is the persistence vehicle for the registration Step 3 locality
// across the OTP step (the in-memory draft is routinely lost when the user
// backgrounds the app to read the OTP email). These tests pin its contract:
//
//   • toJson → tryFromJson round-trips every field (Test 1, 2).
//   • tryFromJson returns null (treated as "absent" → no crash) for a
//     malformed / partial / unknown-role blob (Test 3, 4, 5).
//   • the serialised map carries NO password and NO otp field — the security
//     invariant that keeps the durable blob from leaking credentials (Test 6).
//
// Pure Dart — no widget tree, no storage. The store wrapper is covered by
// pending_locality_store_test.dart.

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/state/pending_locality.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PendingLocality.toJson / tryFromJson', () {
    // -----------------------------------------------------------------------
    // Test 1 — Full CLIENT round-trip preserves every field.
    // -----------------------------------------------------------------------
    test('1. CLIENT blob round-trips toJson → tryFromJson with all fields', () {
      const original = PendingLocality(
        email: 'anya@example.com',
        role: UserRole.client,
        localityProvided: true,
        cityId: 'city-1',
        districtId: 'district-1',
        street: 'вул. Хрещатик',
        buildingNo: '12А',
        locationNote: '3 поверх',
      );

      final restored = PendingLocality.tryFromJson(original.toJson());

      expect(restored, isNotNull);
      expect(restored!.email, equals('anya@example.com'));
      expect(restored.role, equals(UserRole.client));
      expect(restored.localityProvided, isTrue);
      expect(restored.cityId, equals('city-1'));
      expect(restored.districtId, equals('district-1'));
      expect(restored.street, equals('вул. Хрещатик'));
      expect(restored.buildingNo, equals('12А'));
      expect(restored.locationNote, equals('3 поверх'));
      // CLIENT never stashes salon contact data.
      expect(restored.salonName, isEmpty);
      expect(restored.phone, isEmpty);
    });

    // -----------------------------------------------------------------------
    // Test 2 — SALON_OWNER round-trip preserves salonName + phone.
    // -----------------------------------------------------------------------
    test('2. SALON_OWNER blob round-trips salonName + phone', () {
      const original = PendingLocality(
        email: 'owner@example.com',
        role: UserRole.salonOwner,
        localityProvided: true,
        cityId: 'city-7',
        salonName: 'Salon Lumière',
        phone: '+380671234567',
        street: 'вул. Січових Стрільців',
        buildingNo: '5',
      );

      final restored = PendingLocality.tryFromJson(original.toJson());

      expect(restored, isNotNull);
      expect(restored!.role, equals(UserRole.salonOwner));
      expect(restored.salonName, equals('Salon Lumière'));
      expect(restored.phone, equals('+380671234567'));
      expect(restored.cityId, equals('city-7'));
    });

    // -----------------------------------------------------------------------
    // Test 3 — A genuine CLIENT skip (localityProvided=false, null city)
    //          round-trips so the verification screen can tell a skip from a
    //          lost draft.
    // -----------------------------------------------------------------------
    test(
      '3. CLIENT skip blob (localityProvided=false, null city) round-trips',
      () {
        const original = PendingLocality(
          email: 'skip@example.com',
          role: UserRole.client,
          localityProvided: false,
        );

        final restored = PendingLocality.tryFromJson(original.toJson());

        expect(restored, isNotNull);
        expect(restored!.localityProvided, isFalse);
        expect(restored.cityId, isNull);
        expect(restored.districtId, isNull);
      },
    );

    // -----------------------------------------------------------------------
    // Test 4 — Malformed / partial JSON returns null (treated as absent).
    // -----------------------------------------------------------------------
    test('4. tryFromJson returns null for partial / malformed maps', () {
      // Missing email.
      expect(
        PendingLocality.tryFromJson(<String, dynamic>{'role': 'CLIENT'}),
        isNull,
      );
      // Empty email.
      expect(
        PendingLocality.tryFromJson(<String, dynamic>{
          'email': '',
          'role': 'CLIENT',
        }),
        isNull,
      );
      // Missing role.
      expect(
        PendingLocality.tryFromJson(<String, dynamic>{'email': 'a@b.c'}),
        isNull,
      );
      // Wrong type for email (int, not String).
      expect(
        PendingLocality.tryFromJson(<String, dynamic>{
          'email': 42,
          'role': 'CLIENT',
        }),
        isNull,
      );
      // Empty map.
      expect(PendingLocality.tryFromJson(<String, dynamic>{}), isNull);
    });

    // -----------------------------------------------------------------------
    // Test 5 — Unknown role string returns null (ArgumentError swallowed, never
    //          crashes the verification flow).
    // -----------------------------------------------------------------------
    test('5. tryFromJson returns null for an unknown role string', () {
      final restored = PendingLocality.tryFromJson(<String, dynamic>{
        'email': 'a@b.c',
        'role': 'GALACTIC_OVERLORD',
        'localityProvided': true,
        'cityId': 'city-1',
      });
      expect(restored, isNull);
    });

    // -----------------------------------------------------------------------
    // Test 6 — SECURITY: the serialised map carries NO password and NO otp.
    //          The durable blob must never persist credentials at rest.
    // -----------------------------------------------------------------------
    test('6. toJson() never serializes a password or otp field', () {
      const blob = PendingLocality(
        email: 'anya@example.com',
        role: UserRole.client,
        localityProvided: true,
        cityId: 'city-1',
      );

      final json = blob.toJson();

      expect(
        json.containsKey('password'),
        isFalse,
        reason:
            'PendingLocality must NEVER persist a password — the durable blob '
            'is the credential-leak surface the model is designed to avoid.',
      );
      expect(
        json.containsKey('otp'),
        isFalse,
        reason:
            'PendingLocality must NEVER persist the OTP — it is a transient '
            'one-time secret and has no business in secure storage at rest.',
      );
      // The full key set is exactly the locality slice + email + role.
      expect(
        json.keys.toSet(),
        equals(<String>{
          'email',
          'role',
          'localityProvided',
          'cityId',
          'districtId',
          'street',
          'buildingNo',
          'locationNote',
          'salonName',
          'phone',
        }),
        reason:
            'The serialised key set must be exactly the locality slice + email '
            '+ role — no extra field (especially no credential) may sneak in.',
      );
    });

    // -----------------------------------------------------------------------
    // Test 7 — Empty-string optionals deserialize back to null (asNullableString
    //          guard) so a downstream `cityId == null || isEmpty` check stays
    //          consistent regardless of how the blob was serialised.
    // -----------------------------------------------------------------------
    test('7. empty-string cityId / districtId deserialize to null', () {
      final restored = PendingLocality.tryFromJson(<String, dynamic>{
        'email': 'a@b.c',
        'role': 'CLIENT',
        'localityProvided': false,
        'cityId': '',
        'districtId': '',
        'street': '',
        'buildingNo': '',
        'locationNote': '',
        'salonName': '',
        'phone': '',
      });

      expect(restored, isNotNull);
      expect(restored!.cityId, isNull);
      expect(restored.districtId, isNull);
      // Plain string fields stay as empty strings (not nulled).
      expect(restored.street, isEmpty);
      expect(restored.salonName, isEmpty);
    });
  });
}
