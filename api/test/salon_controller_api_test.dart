import 'package:test/test.dart';
import 'package:beautica_api/beautica_api.dart';

/// tests for SalonControllerApi
void main() {
  final instance = BeauticaApi().getSalonControllerApi();

  group(SalonControllerApi, () {
    //Future<ApiResponseSalonResponse> createSalon(CreateSalonRequest createSalonRequest) async
    test('test createSalon', () async {
      // TODO
    });

    //Future deactivateSalon(String salonId) async
    test('test deactivateSalon', () async {
      // TODO
    });

    //Future<ApiResponsePageResponseMasterSummaryResponse> getMastersBySalon(String salonId, Pageable pageable) async
    test('test getMastersBySalon', () async {
      // TODO
    });

    //Future<ApiResponseListSalonResponse> getOwnedSalons() async
    test('test getOwnedSalons', () async {
      // TODO
    });

    //Future<ApiResponsePublicSalonResponse> getSalon(String salonId) async
    test('test getSalon', () async {
      // TODO
    });

    //Future<ApiResponseInviteResponse> inviteMaster(String salonId, InviteRequest inviteRequest) async
    test('test inviteMaster', () async {
      // TODO
    });

    //Future<ApiResponseSalonResponse> updateSalon(String salonId, UpdateSalonRequest updateSalonRequest) async
    test('test updateSalon', () async {
      // TODO
    });
  });
}
