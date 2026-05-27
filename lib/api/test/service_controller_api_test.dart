import 'package:test/test.dart';
import 'package:beautica_api/beautica_api.dart';

/// tests for ServiceControllerApi
void main() {
  final instance = BeauticaApi().getServiceControllerApi();

  group(ServiceControllerApi, () {
    //Future<ApiResponseMasterServiceResponse> addIndependentMasterService(CreateServiceDefinitionRequest createServiceDefinitionRequest) async
    test('test addIndependentMasterService', () async {
      // TODO
    });

    //Future<ApiResponseServiceDefinitionResponse> addServiceToSalon(String salonId, CreateServiceDefinitionRequest createServiceDefinitionRequest) async
    test('test addServiceToSalon', () async {
      // TODO
    });

    //Future<ApiResponseMasterServiceResponse> assignServiceToMaster(String salonId, String masterId, AssignServiceToMasterRequest assignServiceToMasterRequest) async
    test('test assignServiceToMaster', () async {
      // TODO
    });

    //Future deactivateServiceDefinition(String serviceDefId) async
    test('test deactivateServiceDefinition', () async {
      // TODO
    });

    //Future<ApiResponseListMasterServiceResponse> getMasterServices(String masterId) async
    test('test getMasterServices', () async {
      // TODO
    });
  });
}
