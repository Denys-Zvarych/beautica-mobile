import 'package:test/test.dart';
import 'package:beautica_api/beautica_api.dart';

/// tests for SalonMasterControllerApi
void main() {
  final instance = BeauticaApi().getSalonMasterControllerApi();

  group(SalonMasterControllerApi, () {
    //Future disableOwnerMaster(String salonId) async
    test('test disableOwnerMaster', () async {
      // TODO
    });

    //Future<ApiResponseMasterDetailResponse> enableOwnerMaster(String salonId) async
    test('test enableOwnerMaster', () async {
      // TODO
    });
  });
}
