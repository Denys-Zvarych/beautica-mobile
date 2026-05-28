import 'package:test/test.dart';
import 'package:beautica_api/beautica_api.dart';

/// tests for ServiceCatalogControllerApi
void main() {
  final instance = BeauticaApi().getServiceCatalogControllerApi();

  group(ServiceCatalogControllerApi, () {
    //Future<ApiResponseListCatalogCategoryResponse> getCategories() async
    test('test getCategories', () async {
      // TODO
    });

    //Future<ApiResponseListServiceTypeResponse> getServiceTypes({ String categoryId, String q }) async
    test('test getServiceTypes', () async {
      // TODO
    });

    //Future<ApiResponseVoid> suggestServiceType(SuggestServiceTypeRequest suggestServiceTypeRequest) async
    test('test suggestServiceType', () async {
      // TODO
    });
  });
}
