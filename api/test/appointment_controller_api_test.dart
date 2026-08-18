import 'package:test/test.dart';
import 'package:beautica_api/beautica_api.dart';

/// tests for AppointmentControllerApi
void main() {
  final instance = BeauticaApi().getAppointmentControllerApi();

  group(AppointmentControllerApi, () {
    //Future cancelAppointment(String appointmentId, { AppointmentCancelRequest appointmentCancelRequest }) async
    test('test cancelAppointment', () async {
      // TODO
    });

    //Future completeAppointment(String appointmentId) async
    test('test completeAppointment', () async {
      // TODO
    });

    //Future<ApiResponseAppointmentDetailResponse> createAppointment(CreateAppointmentRequest createAppointmentRequest, { String idempotencyKey }) async
    test('test createAppointment', () async {
      // TODO
    });

    //Future declineAppointment(String appointmentId, { AppointmentProviderNoteRequest appointmentProviderNoteRequest }) async
    test('test declineAppointment', () async {
      // TODO
    });

    //Future<ApiResponseAppointmentDetailResponse> getAppointment(String appointmentId) async
    test('test getAppointment', () async {
      // TODO
    });

    //Future notCompleteAppointment(String appointmentId, { AppointmentProviderNoteRequest appointmentProviderNoteRequest }) async
    test('test notCompleteAppointment', () async {
      // TODO
    });
  });
}
