import 'package:test/test.dart';
import 'package:beautica_api/beautica_api.dart';

/// tests for PhoneOtpControllerApi
void main() {
  final instance = BeauticaApi().getPhoneOtpControllerApi();

  group(PhoneOtpControllerApi, () {
    //Future<ApiResponseVoid> send(PhoneOtpSendRequest phoneOtpSendRequest) async
    test('test send', () async {
      // TODO
    });

    //Future<ApiResponseGuestTokenResponse> verify(PhoneOtpVerifyRequest phoneOtpVerifyRequest) async
    test('test verify', () async {
      // TODO
    });
  });
}
