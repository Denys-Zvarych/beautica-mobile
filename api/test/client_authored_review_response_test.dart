import 'package:test/test.dart';
import 'package:beautica_api/beautica_api.dart';

// tests for ClientAuthoredReviewResponse
void main() {
  final instance = ClientAuthoredReviewResponseBuilder();
  // TODO add properties to the builder and call build()

  group(ClientAuthoredReviewResponse, () {
    // The client's star rating for this booking, 1-5.
    // int rating
    test('to test the property `rating`', () async {
      // TODO
    });

    // The client's review text, verbatim and unabridged, or null when they rated without writing anything. Already public via GET /masters/{id}/reviews — never truncated or masked here.
    // String comment
    test('to test the property `comment`', () async {
      // TODO
    });
  });
}
