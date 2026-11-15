import 'package:test/test.dart';
import 'package:beautica_api/beautica_api.dart';

/// tests for AppointmentControllerApi
void main() {
  final instance = BeauticaApi().getAppointmentControllerApi();

  group(AppointmentControllerApi, () {
    //Future<ApiResponseAppointmentDetailResponse> createAppointment(CreateAppointmentRequest createAppointmentRequest, { String idempotencyKey }) async
    test('test createAppointment', () async {
      // TODO
    });

    //Future<ApiResponseAppointmentDetailResponse> getAppointment(String appointmentId) async
    test('test getAppointment', () async {
      // TODO
    });

  });
}
