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

    test('read returns null when nothing written', () async {
      final s = FakeSecureStorage();
      expect(await s.readRefreshToken(), isNull);
      expect(await s.readUserJson(), isNull);
    });

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
}
