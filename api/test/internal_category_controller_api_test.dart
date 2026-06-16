import 'package:test/test.dart';
import 'package:beautica_api/beautica_api.dart';

/// tests for InternalCategoryControllerApi
void main() {
  final instance = BeauticaApi().getInternalCategoryControllerApi();

  group(InternalCategoryControllerApi, () {
    //Future<ApiResponsePlatformCategoryResponse> createCategory(CreatePlatformCategoryRequest createPlatformCategoryRequest) async
    test('test createCategory', () async {
      // TODO
    });

    //Future<ApiResponseListPlatformCategoryUsageResponse> listCategories() async
    test('test listCategories', () async {
      // TODO
    });
  });
}
