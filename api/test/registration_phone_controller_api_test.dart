import 'package:test/test.dart';
import 'package:beautica_api/beautica_api.dart';

/// tests for RegistrationPhoneControllerApi
void main() {
  final instance = BeauticaApi().getRegistrationPhoneControllerApi();

  group(RegistrationPhoneControllerApi, () {
    //Future<ApiResponseVoid> send1(RegistrationOtpSendRequest registrationOtpSendRequest) async
    test('test send1', () async {
      // TODO
    });

    //Future<ApiResponseRegistrationTicketResponse> verify1(RegistrationOtpVerifyRequest registrationOtpVerifyRequest) async
    test('test verify1', () async {
      // TODO
    });
  });
}
