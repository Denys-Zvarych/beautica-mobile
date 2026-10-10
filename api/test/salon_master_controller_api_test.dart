import 'package:test/test.dart';
import 'package:beautica_api/beautica_api.dart';

/// tests for SalonMasterControllerApi
void main() {
  final instance = BeauticaApi().getSalonMasterControllerApi();

  group(SalonMasterControllerApi, () {
    //Future removeMaster(String salonId, String masterId) async
    test('test removeMaster', () async {
      // TODO
    });
  });
}
