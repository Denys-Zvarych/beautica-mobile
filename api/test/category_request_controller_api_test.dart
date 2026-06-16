import 'package:test/test.dart';
import 'package:beautica_api/beautica_api.dart';

/// tests for CategoryRequestControllerApi
void main() {
  final instance = BeauticaApi().getCategoryRequestControllerApi();

  group(CategoryRequestControllerApi, () {
    //Future<ApiResponseListApprovedCategoryResponse> listApproved() async
    test('test listApproved', () async {
      // TODO
    });

    //Future<ApiResponseCategoryRequestResponse> submitRequest(CreateCategoryRequestRequest createCategoryRequestRequest) async
    test('test submitRequest', () async {
      // TODO
    });
  });
}
