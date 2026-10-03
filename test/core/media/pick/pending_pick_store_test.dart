// Phase 073 audit — the `{ownerId, kind}` tag that binds a media pick to the
// account that started it. Fails closed: anything unreadable is "not ours".

import 'package:beautica_mobile/core/media/pick/media_kind.dart';
import 'package:beautica_mobile/core/media/pick/pending_pick_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fakes/fake_secure_storage.dart';

class _CountingStorage extends FakeSecureStorage {
  int writes = 0;
  int deletes = 0;

  @override
  Future<void> writePendingPick(String json) {
    writes++;
    return super.writePendingPick(json);
  }

  @override
  Future<void> deletePendingPick() {
    deletes++;
    return super.deletePendingPick();
  }
}

void main() {
  late FakeSecureStorage storage;
  late PendingPickStore store;

  setUp(() {
    storage = FakeSecureStorage();
    store = PendingPickStore(storage);
  });

  test('begin -> read round-trips owner and kind; clear forgets it', () async {
    await store.begin('u1', MediaKind.avatar);
    final PendingPick? tag = await store.read();
    expect(tag?.ownerId, 'u1');
    expect(tag?.kind, MediaKind.avatar);

    await store.clear();
    expect(await store.read(), isNull);
  });

  test('belongsTo needs the same user AND the same kind', () {
    const PendingPick tag = PendingPick(ownerId: 'u1', kind: MediaKind.avatar);
    expect(tag.belongsTo('u1', MediaKind.avatar), isTrue);
    expect(tag.belongsTo('u2', MediaKind.avatar), isFalse);
    expect(tag.belongsTo(null, MediaKind.avatar), isFalse);
    expect(tag.belongsTo('u1', MediaKind.servicePhoto), isFalse);
  });

  test('no owner (signed out) writes nothing', () async {
    await store.begin(null, MediaKind.avatar);
    expect(await store.read(), isNull);
  });

  for (final String bad in <String>[
    'not json',
    '[]',
    '{"ownerId":"u1"}',
    '{"ownerId":1,"kind":"avatar"}',
    '{"ownerId":"u1","kind":"nope"}',
  ]) {
    test('malformed tag reads as null: $bad', () async {
      await storage.writePendingPick(bad);
      expect(await store.read(), isNull);
    });
  }

  test('logout (deleteAll) clears the tag', () async {
    await store.begin('u1', MediaKind.avatar);
    await storage.deleteAll();
    expect(await store.read(), isNull);
  });

  test('does no storage I/O off Android; does on Android', () async {
    final _CountingStorage counting = _CountingStorage();
    final PendingPickStore s = PendingPickStore(counting);
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await s.begin('u1', MediaKind.avatar);
      await s.clear();
      expect(counting.writes, 0);
      expect(counting.deletes, 0);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await s.begin('u1', MediaKind.avatar);
      await s.clear();
      expect(counting.writes, 1);
      expect(counting.deletes, 1);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
