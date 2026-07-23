import 'package:test/test.dart';
import 'package:beautica_api/beautica_api.dart';

/// tests for ClientControllerApi
void main() {
  final instance = BeauticaApi().getClientControllerApi();

  group(ClientControllerApi, () {
    //Future<ApiResponsePassportResponse> getPassport() async
    test('test getPassport', () async {
      // TODO
    });

    //Future<ApiResponsePageResponseTimelineItemResponse> getTimeline(Pageable pageable) async
    test('test getTimeline', () async {
      // TODO
    });
  });
}
