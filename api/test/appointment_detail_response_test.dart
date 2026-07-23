import 'package:test/test.dart';
import 'package:beautica_api/beautica_api.dart';

// tests for AppointmentDetailResponse
void main() {
  final instance = AppointmentDetailResponseBuilder();
  // TODO add properties to the builder and call build()

  group(AppointmentDetailResponse, () {
    // String id
    test('to test the property `id`', () async {
      // TODO
    });

    // String status
    test('to test the property `status`', () async {
      // TODO
    });

    // String masterId
    test('to test the property `masterId`', () async {
      // TODO
    });

    // String masterFirstName
    test('to test the property `masterFirstName`', () async {
      // TODO
    });

    // String masterLastName
    test('to test the property `masterLastName`', () async {
      // TODO
    });

    // The master's professional title/headline. Nullable — a master may never have set one.
    // String masterProfessionalTitle
    test('to test the property `masterProfessionalTitle`', () async {
      // TODO
    });

    // String masterAvatarUrl
    test('to test the property `masterAvatarUrl`', () async {
      // TODO
    });

    // String masterType
    test('to test the property `masterType`', () async {
      // TODO
    });

    // The salon name, or null for an independent master.
    // String salonName
    test('to test the property `salonName`', () async {
      // TODO
    });

    // DateTime startsAt
    test('to test the property `startsAt`', () async {
      // TODO
    });

    // DateTime endsAt
    test('to test the property `endsAt`', () async {
      // TODO
    });

    // int totalDurationMinutes
    test('to test the property `totalDurationMinutes`', () async {
      // TODO
    });

    // num totalPrice
    test('to test the property `totalPrice`', () async {
      // TODO
    });

    // The summed range ceiling of the visit, present ONLY when at least one service was a genuine range at booking time. Null means a single total price — render totalPrice alone. Never re-derived on read.
    // num totalPriceMax
    test('to test the property `totalPriceMax`', () async {
      // TODO
    });

    // The client's booking-creation note for the whole visit.
    // String clientComment
    test('to test the property `clientComment`', () async {
      // TODO
    });

    // DateTime createdAt
    test('to test the property `createdAt`', () async {
      // TODO
    });

    // BuiltList<AppointmentItemResponse> items
    test('to test the property `items`', () async {
      // TODO
    });

    // True iff this visit is COMPLETED, has a registered client, and the client has not yet reviewed it — the CLIENT's one-review-per-visit CTA gate (BE-6). The COMPLETED + no-existing-review predicate, computed by the service, mirrors BookingDetailResponse.canReview lifted to the visit. A visit review is left via POST /appointments/{id}/review.
    // bool canReview
    test('to test the property `canReview`', () async {
      // TODO
    });

    // Written by the provider on the visit /decline or /not-complete. Shown to the CLIENT on both DECLINED and NOT_COMPLETED visits — intentional, by the locked \"all notes visible for all sides\" decision, NOT a privacy leak. Do not suppress for any audience. Same field/rule as BookingDetailResponse.providerComment, lifted to the visit header.
    // String providerComment
    test('to test the property `providerComment`', () async {
      // TODO
    });

    // Written by the CLIENT on the visit /cancel — the symmetric counterpart of providerComment, shown to the provider. Only ever non-null on a CANCELLED visit. Same field/rule as BookingDetailResponse.clientCancellationNote.
    // String clientCancellationNote
    test('to test the property `clientCancellationNote`', () async {
      // TODO
    });

    // Discovery city label (Ukrainian). Resolved by the service through the same district-primary DiscoveryLocationResolver seam as BookingDetailResponse — salon locality when salon-employed, else the master's own user row.
    // String cityLabel
    test('to test the property `cityLabel`', () async {
      // TODO
    });

    // Discovery district label (Ukrainian). Same resolution as cityLabel.
    // String districtLabel
    test('to test the property `districtLabel`', () async {
      // TODO
    });

    // Arrival street — the salon's when salon-employed, else the master's own. Same salon-vs-independent rule as BookingDetailResponse.street; a salon-employed master's PERSONAL street never leaks onto a salon visit.
    // String street
    test('to test the property `street`', () async {
      // TODO
    });

    // Arrival building number.
    // String buildingNo
    test('to test the property `buildingNo`', () async {
      // TODO
    });

    // Provider's free-text arrival hint (e.g. \"3-й поверх, код 1234\"). Same salon-vs-independent resolution as street/buildingNo — a salon booking surfaces the salon's own note, never the master's personal one.
    // String locationNote
    test('to test the property `locationNote`', () async {
      // TODO
    });
  });
}
