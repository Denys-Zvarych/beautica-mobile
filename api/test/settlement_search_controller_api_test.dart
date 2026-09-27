import 'package:test/test.dart';
import 'package:beautica_api/beautica_api.dart';

/// tests for SettlementSearchControllerApi
void main() {
  final instance = BeauticaApi().getSettlementSearchControllerApi();

  group(SettlementSearchControllerApi, () {
    //Future<ApiResponseListSettlementSearchResponse> searchSettlements({ String query }) async
    test('test searchSettlements', () async {
      // TODO
    });
  });
}
