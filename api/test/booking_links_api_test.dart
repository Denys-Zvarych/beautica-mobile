import 'package:test/test.dart';
import 'package:beautica_api/beautica_api.dart';

/// tests for BookingLinksApi
void main() {
  final instance = BeauticaApi().getBookingLinksApi();

  group(BookingLinksApi, () {
    // My shareable public booking links
    //
    // INDEPENDENT_MASTER and SALON_OWNER get their own MASTER link (https://beautica.app/book/{slug}). SALON_OWNER additionally gets one SALON link (https://beautica.app/book/s/{slug}) per active owned salon, ordered by salon name; SALON_ADMIN gets the SALON link of the active salon it is bound to. Inactive salons and inactive master rows yield no link. SALON_MASTER gets no links. A legacy master's or salon's slug is issued on the first call and never changes, not even on rename. bookable reports whether the public page can take a booking today (for a salon: at least one bookable master). When sharing is switched off server-side, shareEnabled is false and links is empty. 409 when a slug issue cannot acquire its lock in time (retry).
    //
    //Future<ApiResponseBookingLinksResponse> getMine() async
    test('test getMine', () async {
      // TODO
    });
  });
}
