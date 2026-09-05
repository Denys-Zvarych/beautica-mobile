import 'package:test/test.dart';
import 'package:beautica_api/beautica_api.dart';

// tests for SiblingSalonOption
void main() {
  final instance = SiblingSalonOptionBuilder();
  // TODO add properties to the builder and call build()

  group(SiblingSalonOption, () {
    // Send this as destinationSalonId to PATCH /salons/{salonId}/admins/{userId}/salon.
    // String id
    test('to test the property `id`', () async {
      // TODO
    });

    // Salon display name.
    // String name
    test('to test the property `name`', () async {
      // TODO
    });

    // Street of the structured address (Phase 10.6). May be null for a salon persisted before that phase.
    // String street
    test('to test the property `street`', () async {
      // TODO
    });

    // Building number of the structured address (Phase 10.6). May be null for a salon persisted before that phase.
    // String buildingNo
    test('to test the property `buildingNo`', () async {
      // TODO
    });
  });
}
