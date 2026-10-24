import 'package:test/test.dart';
import 'package:beautica_api/beautica_api.dart';

// tests for BookingLinksResponse
void main() {
  final instance = BookingLinksResponseBuilder();
  // TODO add properties to the builder and call build()

  group(BookingLinksResponse, () {
    // Server kill-switch; false = sharing is hidden and links is empty
    // bool shareEnabled
    test('to test the property `shareEnabled`', () async {
      // TODO
    });

    // MASTER link first, then SALON links by salon name
    // BuiltList<BookingLinkResponse> links
    test('to test the property `links`', () async {
      // TODO
    });
  });
}
