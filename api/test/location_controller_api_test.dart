import 'package:test/test.dart';
import 'package:beautica_api/beautica_api.dart';

/// tests for LocationControllerApi
void main() {
  final instance = BeauticaApi().getLocationControllerApi();

  group(LocationControllerApi, () {
    //Future<ApiResponseListCityResponse> getCitiesByOblast(String oblastId) async
    test('test getCitiesByOblast', () async {
      // TODO
    });

    //Future<ApiResponseListCityDistrictResponse> getDistrictsByCity(String cityId) async
    test('test getDistrictsByCity', () async {
      // TODO
    });

    //Future<ApiResponseListOblastResponse> getOblasts() async
    test('test getOblasts', () async {
      // TODO
    });
  });
}
