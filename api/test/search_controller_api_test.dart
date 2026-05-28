import 'package:test/test.dart';
import 'package:beautica_api/beautica_api.dart';

/// tests for SearchControllerApi
void main() {
  final instance = BeauticaApi().getSearchControllerApi();

  group(SearchControllerApi, () {
    //Future<ApiResponsePageResponseMasterSearchResult> searchMasters(MasterSearchRequest request) async
    test('test searchMasters', () async {
      // TODO
    });

    //Future<ApiResponsePageResponseSalonSearchResult> searchSalons(SalonSearchRequest request) async
    test('test searchSalons', () async {
      // TODO
    });
  });
}
