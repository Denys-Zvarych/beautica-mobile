import 'package:test/test.dart';
import 'package:beautica_api/beautica_api.dart';

/// tests for GuestReviewsApi
void main() {
  final instance = BeauticaApi().getGuestReviewsApi();

  group(GuestReviewsApi, () {
    // Read a review invite
    //
    // The visit to rate, or state=ALREADY_REVIEWED once the token was used. Unknown, expired and malformed tokens are one identical 404.
    //
    //Future<ReviewInviteResponse> getInvite(String token) async
    test('test getInvite', () async {
      // TODO
    });

    // Stop review-invite SMS for this phone
    //
    // Idempotent; valid for 30 days after the invite was sent, also after reviewing.
    //
    //Future optOut(String token, { ReviewInviteOptOutRequest reviewInviteOptOutRequest }) async
    test('test optOut', () async {
      // TODO
    });

    // Submit the guest's review(s)
    //
    // Rates any subset of the visit's services, once per token.
    //
    //Future<GuestReviewSubmitResponse> submit(String token, GuestReviewSubmitRequest guestReviewSubmitRequest) async
    test('test submit', () async {
      // TODO
    });
  });
}
