// isUuid — the shared server-id gate (MASVS-CODE-4).

import 'package:beautica_mobile/shared/validators/uuid_validator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('accepts a lowercase and an uppercase canonical UUID', () {
    expect(isUuid('5b1f0c8e-3a2d-4f6b-9c7e-1a2b3c4d5e6f'), isTrue);
    expect(isUuid('5B1F0C8E-3A2D-4F6B-9C7E-1A2B3C4D5E6F'), isTrue);
  });

  for (final String bad in <String>[
    '',
    'x/../..?tab=',
    'salon-1',
    '5b1f0c8e3a2d4f6b9c7e1a2b3c4d5e6f',
    '5b1f0c8e-3a2d-4f6b-9c7e-1a2b3c4d5e6',
    '5b1f0c8e-3a2d-4f6b-9c7e-1a2b3c4d5e6f0',
    'gb1f0c8e-3a2d-4f6b-9c7e-1a2b3c4d5e6f',
    ' 5b1f0c8e-3a2d-4f6b-9c7e-1a2b3c4d5e6f',
    '5b1f0c8e-3a2d-4f6b-9c7e-1a2b3c4d5e6f\n',
    '{5b1f0c8e-3a2d-4f6b-9c7e-1a2b3c4d5e6f}',
  ]) {
    test('rejects ${bad.isEmpty ? '<empty>' : bad}', () {
      expect(isUuid(bad), isFalse);
    });
  }
}
