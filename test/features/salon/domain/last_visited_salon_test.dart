// Phase 288 D8 — unit tests for the `StorageKeys.lastSalon` envelope codec.
//
// C6 is the load-bearing case: C1's round trip stays green under a key
// rename (both sides change together), so only a literal-key assertion pins
// compatibility with slots already written by Phase 287 builds.

import 'dart:convert';

import 'package:beautica_mobile/features/salon/domain/last_visited_salon.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const LastVisitedSalon pointer = LastVisitedSalon(
    userId: 'owner-1',
    salonId: 'salon-b',
  );

  test('C1 should_roundTrip_when_encodedThenDecoded', () {
    expect(LastVisitedSalon.tryDecode(pointer.encode()), pointer);
  });

  test('C2 should_returnNull_when_rawIsNullOrEmpty', () {
    expect(LastVisitedSalon.tryDecode(null), isNull);
    expect(LastVisitedSalon.tryDecode(''), isNull);
  });

  test('C3 should_returnNull_when_jsonIsMalformed', () {
    expect(LastVisitedSalon.tryDecode('{not json'), isNull);
    expect(LastVisitedSalon.tryDecode('salon-b'), isNull);
    // Valid JSON, wrong root shape.
    expect(LastVisitedSalon.tryDecode('["owner-1","salon-b"]'), isNull);
    expect(LastVisitedSalon.tryDecode('"salon-b"'), isNull);
    expect(LastVisitedSalon.tryDecode('null'), isNull);
  });

  test('C4 should_returnNull_when_keyMissing', () {
    expect(LastVisitedSalon.tryDecode('{"salonId":"salon-b"}'), isNull);
    expect(LastVisitedSalon.tryDecode('{"userId":"owner-1"}'), isNull);
  });

  test('C5 should_returnNull_when_valueIsNotANonEmptyString', () {
    for (final String raw in <String>[
      '{"userId":1,"salonId":"salon-b"}',
      '{"userId":"owner-1","salonId":2}',
      '{"userId":null,"salonId":"salon-b"}',
      '{"userId":"owner-1","salonId":null}',
      '{"userId":"","salonId":"salon-b"}',
      '{"userId":"owner-1","salonId":""}',
    ]) {
      expect(LastVisitedSalon.tryDecode(raw), isNull, reason: raw);
    }
  });

  test('C6 should_encodeExactWireKeys', () {
    final Object? decoded = jsonDecode(pointer.encode());
    expect(decoded, <String, Object?>{
      'userId': 'owner-1',
      'salonId': 'salon-b',
    });
    // And the reverse: a slot written by a Phase 287 build (inline map with
    // these literal keys) still decodes.
    expect(
      LastVisitedSalon.tryDecode(
        jsonEncode(<String, String>{'userId': 'owner-1', 'salonId': 'salon-b'}),
      ),
      pointer,
    );
  });

  test('C7 should_redactIds_when_toStringCalled', () {
    final String text = pointer.toString();
    expect(text, 'LastVisitedSalon(<redacted>)');
    expect(text, isNot(contains('owner-1')));
    expect(text, isNot(contains('salon-b')));
  });
}
