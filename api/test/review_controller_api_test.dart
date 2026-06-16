import 'package:test/test.dart';
import 'package:beautica_api/beautica_api.dart';

/// tests for ReviewControllerApi
void main() {
  final instance = BeauticaApi().getReviewControllerApi();

  group(ReviewControllerApi, () {
    //Future<ApiResponseReviewResponse> createReview(CreateReviewRequest createReviewRequest) async
    test('test createReview', () async {
      // TODO
    });

    //Future<ApiResponseReviewResponse> getReview(String reviewId) async
    test('test getReview', () async {
      // TODO
    });

    //Future<ApiResponsePageResponseReviewResponse> getReviewsByMaster(String masterId, Pageable pageable) async
    test('test getReviewsByMaster', () async {
      // TODO
    });
  });
}
