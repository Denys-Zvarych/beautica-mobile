import 'package:test/test.dart';
import 'package:beautica_api/beautica_api.dart';

// tests for DuplicateServiceResponse
void main() {
  final instance = DuplicateServiceResponseBuilder();
  // TODO add properties to the builder and call build()

  group(DuplicateServiceResponse, () {
    // Stable machine-readable error code. Always present — the only field the client branches on.
    // String code
    test('to test the property `code`', () async {
      // TODO
    });

    // Human-readable label for the conflicting service, so the client can name it without a second round-trip: the service TYPE's name when the service-layer pre-check caught the conflict, the name the caller just SUBMITTED when the DB index caught a race instead. Null only on the bulk path.
    // String serviceName
    test('to test the property `serviceName`', () async {
      // TODO
    });

    // Id of the existing service definition, for a deep-link. Null when the DB index caught the conflict rather than the service-layer pre-check.
    // String existingServiceDefId
    test('to test the property `existingServiceDefId`', () async {
      // TODO
    });
  });
}
