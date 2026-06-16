import 'package:test/test.dart';
import 'package:beautica_api/beautica_api.dart';

/// tests for MasterControllerApi
void main() {
  final instance = BeauticaApi().getMasterControllerApi();

  group(MasterControllerApi, () {
    //Future<ApiResponseVoid> addScheduleException(String masterId, ScheduleExceptionRequest scheduleExceptionRequest) async
    test('test addScheduleException', () async {
      // TODO
    });

    //Future<ApiResponseVoid> deactivateMaster(String masterId) async
    test('test deactivateMaster', () async {
      // TODO
    });

    //Future<ApiResponseAvailableSlotsResponse> getAvailableSlots(String masterId, Date date, String serviceId) async
    test('test getAvailableSlots', () async {
      // TODO
    });

    //Future<ApiResponsePageResponseBookingResponse> getMasterCalendar(Date from, Date to, Pageable pageable) async
    test('test getMasterCalendar', () async {
      // TODO
    });

    //Future<ApiResponseMasterDetailResponse> getMasterDetail(String masterId) async
    test('test getMasterDetail', () async {
      // TODO
    });

    //Future<ApiResponsePageResponseMasterSummaryResponse> getMastersBySalon1(String salonId, Pageable pageable) async
    test('test getMastersBySalon1', () async {
      // TODO
    });

    //Future<ApiResponseVoid> removeScheduleException(String masterId, Date date) async
    test('test removeScheduleException', () async {
      // TODO
    });

    //Future<ApiResponseListWorkingHoursResponse> upsertWorkingHours(String masterId, BuiltList<WorkingHoursRequest> workingHoursRequest) async
    test('test upsertWorkingHours', () async {
      // TODO
    });
  });
}
