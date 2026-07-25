import 'package:test/test.dart';
import 'package:beautica_api/beautica_api.dart';

/// tests for ClientReviewControllerApi
void main() {
  final instance = BeauticaApi().getClientReviewControllerApi();

  group(ClientReviewControllerApi, () {
    //Future<ApiResponseClientReviewResponse> create(CreateClientReviewRequest createClientReviewRequest) async
    test('test create', () async {
      // TODO
    });
  });
}
