import 'package:test/test.dart';
import 'package:beautica_api/beautica_api.dart';

/// tests for AuthControllerApi
void main() {
  final instance = BeauticaApi().getAuthControllerApi();

  group(AuthControllerApi, () {
    //Future<ApiResponseAuthResponse> acceptInvite(InviteAcceptRequest inviteAcceptRequest) async
    test('test acceptInvite', () async {
      // TODO
    });

    //Future<ApiResponseVoid> forgotPassword(ForgotPasswordRequest forgotPasswordRequest) async
    test('test forgotPassword', () async {
      // TODO
    });

    //Future<ApiResponseAuthResponse> login(LoginRequest loginRequest) async
    test('test login', () async {
      // TODO
    });

    //Future logout() async
    test('test logout', () async {
      // TODO
    });

    //Future<ApiResponseAuthResponse> refresh(RefreshRequest refreshRequest) async
    test('test refresh', () async {
      // TODO
    });

    //Future<ApiResponseRegistrationResponse> register(RegisterRequest registerRequest) async
    test('test register', () async {
      // TODO
    });

    //Future<ApiResponseRegistrationResponse> registerIndependentMaster(RegisterIndependentMasterRequest registerIndependentMasterRequest) async
    test('test registerIndependentMaster', () async {
      // TODO
    });

    //Future<ApiResponseRegistrationResponse> resendVerification(ResendVerificationRequest resendVerificationRequest) async
    test('test resendVerification', () async {
      // TODO
    });

    //Future<ApiResponseVoid> resetPassword(ResetPasswordRequest resetPasswordRequest) async
    test('test resetPassword', () async {
      // TODO
    });

    //Future<ApiResponseInviteResponse> sendInvite(InviteRequest inviteRequest) async
    test('test sendInvite', () async {
      // TODO
    });

    //Future<ApiResponseInvitePreviewResponse> validateInvite(String token) async
    test('test validateInvite', () async {
      // TODO
    });

    //Future<ApiResponseAuthResponse> verifyEmail(VerifyEmailRequest verifyEmailRequest) async
    test('test verifyEmail', () async {
      // TODO
    });
  });
}
