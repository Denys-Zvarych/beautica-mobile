// Phase 2.1 — Unit tests for FakeSecureStorage.
//
// These tests validate the in-memory fake, not the production
// FlutterSecureStorageImpl (which requires a platform channel). The fake is
// the test double used by every feature test that needs SecureStorage — so
// correctness here means correctness of all downstream test scaffolding.
//
// No ProviderContainer is needed: FakeSecureStorage is a plain Dart class.

import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fakes/fake_secure_storage.dart';

void main() {
  group('FakeSecureStorage', () {
    test(
      'writeRefreshToken then readRefreshToken returns same value',
      () async {
        final s = FakeSecureStorage();
        await s.writeRefreshToken('rt-123');
        expect(await s.readRefreshToken(), 'rt-123');
      },
    );

    test('writeUserJson then readUserJson returns same value', () async {
      final s = FakeSecureStorage();
      await s.writeUserJson('{"id":"u1"}');
      expect(await s.readUserJson(), '{"id":"u1"}');
    });

    test('deleteAll wipes both keys', () async {
      final s = FakeSecureStorage();
      await s.writeRefreshToken('rt');
      await s.writeUserJson('{"id":"u"}');
      await s.deleteAll();
      expect(await s.readRefreshToken(), isNull);
      expect(await s.readUserJson(), isNull);
    });

    test(
      'read returns null for both keys when nothing has been written',
      () async {
        final s = FakeSecureStorage();
        expect(await s.readRefreshToken(), isNull);
        expect(await s.readUserJson(), isNull);
      },
    );

    test('overwrite works — last write wins', () async {
      final s = FakeSecureStorage();
      await s.writeRefreshToken('first');
      await s.writeRefreshToken('second');
      expect(await s.readRefreshToken(), 'second');
    });

    test('deleteAll on empty storage does not throw', () async {
      final s = FakeSecureStorage();
      await expectLater(s.deleteAll(), completes);
    });

    test('refreshToken and userJson are independent keys', () async {
      final s = FakeSecureStorage();
      await s.writeRefreshToken('rt-abc');
      await s.writeUserJson('{"id":"u2"}');
      // Overwriting one key does not affect the other.
      await s.writeRefreshToken('rt-xyz');
      expect(await s.readUserJson(), '{"id":"u2"}');
      expect(await s.readRefreshToken(), 'rt-xyz');
    });
  });

  // ---------------------------------------------------------------------
  // Phase 286 — last-visited salon storage slot.
  //
  // Storage-only: nothing in lib/ reads or writes StorageKeys.lastSalon yet
  // (Phase 287 adds the writer, Phase 288 the reader). These tests pin the
  // round-trip contract of the new SecureStorage members themselves.
  // ---------------------------------------------------------------------
  group('FakeSecureStorage — lastSalon (Phase 286)', () {
    test('should_returnNull_when_noLastSalonStored', () async {
      final s = FakeSecureStorage();
      expect(await s.readLastSalon(), isNull);
    });

    test('should_roundTripValue_when_lastSalonWritten', () async {
      final s = FakeSecureStorage();
      const json = '{"userId":"u1","salonId":"s1"}';
      await s.writeLastSalon(json);
      expect(await s.readLastSalon(), json);
    });

    test('should_overwriteValue_when_lastSalonWrittenTwice', () async {
      final s = FakeSecureStorage();
      await s.writeLastSalon('{"userId":"u1","salonId":"s1"}');
      await s.writeLastSalon('{"userId":"u1","salonId":"s2"}');
      expect(await s.readLastSalon(), '{"userId":"u1","salonId":"s2"}');
    });

    test('should_returnNull_when_lastSalonDeleted', () async {
      final s = FakeSecureStorage();
      await s.writeLastSalon('{"userId":"u1","salonId":"s1"}');
      await s.deleteLastSalon();
      expect(await s.readLastSalon(), isNull);
    });

    test('should_clearLastSalon_when_deleteAllCalled — D5 pin: deleteAll() is '
        'key-agnostic and must wipe lastSalon alongside every other key, not '
        'just the ones deleteAll() was written against originally', () async {
      final s = FakeSecureStorage();
      await s.writeRefreshToken('rt');
      await s.writeUserJson('{"id":"u"}');
      await s.writeLastSalon('{"userId":"u1","salonId":"s1"}');

      await s.deleteAll();

      expect(await s.readLastSalon(), isNull);
      expect(await s.readRefreshToken(), isNull);
      expect(await s.readUserJson(), isNull);
    });

    test('lastSalon is independent of the other keys', () async {
      final s = FakeSecureStorage();
      await s.writeRefreshToken('rt');
      await s.writeUserJson('{"id":"u"}');
      await s.writeLastSalon('{"userId":"u1","salonId":"s1"}');

      await s.deleteLastSalon();

      expect(await s.readLastSalon(), isNull);
      expect(await s.readRefreshToken(), 'rt');
      expect(await s.readUserJson(), '{"id":"u"}');
    });
  });
}
