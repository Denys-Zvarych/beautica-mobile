// Phase 288 D7 — `lastVisitedSalonProvider` never errors: a valid slot
// decodes, and an empty slot, a malformed slot and a throwing storage read
// all resolve to `null`.

import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/salon/application/last_visited_salon_provider.dart';
import 'package:beautica_mobile/features/salon/domain/last_visited_salon.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fakes/fake_secure_storage.dart';
import '../../../helpers/test_container.dart';

class _ThrowingRead extends FakeSecureStorage {
  @override
  Future<String?> readLastSalon() async =>
      throw Exception('keystore unavailable');
}

Future<LastVisitedSalon?> _read(FakeSecureStorage storage) {
  final container = makeTestContainer(
    overrides: <Object>[secureStorageProvider.overrideWithValue(storage)],
    // Belt-and-braces: a provider that DID error must surface here as a
    // thrown future, not be retried into a different outcome.
    retry: (_, _) => null,
  );
  return container.read(lastVisitedSalonProvider.future);
}

void main() {
  test('P1 should_returnDecodedPointer_when_slotHoldsValidJson', () async {
    final storage = FakeSecureStorage();
    await storage.writeLastSalon(
      const LastVisitedSalon(userId: 'owner-1', salonId: 'salon-b').encode(),
    );

    expect(
      await _read(storage),
      const LastVisitedSalon(userId: 'owner-1', salonId: 'salon-b'),
    );
  });

  test('P2 should_returnNull_when_slotEmpty', () async {
    expect(await _read(FakeSecureStorage()), isNull);
  });

  test('P3 should_returnNull_when_storageReadThrows', () async {
    expect(await _read(_ThrowingRead()), isNull);
  });

  test('P4 should_returnNull_when_slotMalformed', () async {
    final storage = FakeSecureStorage();
    await storage.writeLastSalon('{"userId":"owner-1"');

    expect(await _read(storage), isNull);
  });
}
