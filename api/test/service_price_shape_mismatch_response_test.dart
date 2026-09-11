import 'package:test/test.dart';
import 'package:beautica_api/beautica_api.dart';

// tests for ServicePriceShapeMismatchResponse
void main() {
  final instance = ServicePriceShapeMismatchResponseBuilder();
  // TODO add properties to the builder and call build()

  group(ServicePriceShapeMismatchResponse, () {
    // Stable machine-readable error code. Always present — the only field the client branches on.
    // String code
    test('to test the property `code`', () async {
      // TODO
    });

    // Display name of the service whose shape clashed (the service type's Ukrainian name).
    // String serviceName
    test('to test the property `serviceName`', () async {
      // TODO
    });

    // Id of the salon definition that governs the shape, for a deep-link.
    // String existingServiceDefId
    test('to test the property `existingServiceDefId`', () async {
      // TODO
    });

    // The salon definition's pricing mode — the shape the submitted item had to match.
    // String salonPriceType
    test('to test the property `salonPriceType`', () async {
      // TODO
    });

    // ServicePriceShapeMismatchResponseSalonPriceMin salonPriceMin
    test('to test the property `salonPriceMin`', () async {
      // TODO
    });

    // ServicePriceShapeMismatchResponseSalonPriceMax salonPriceMax
    test('to test the property `salonPriceMax`', () async {
      // TODO
    });
  });
}
