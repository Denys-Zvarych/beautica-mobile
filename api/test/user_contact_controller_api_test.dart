import 'package:test/test.dart';
import 'package:beautica_api/beautica_api.dart';

/// tests for UserContactControllerApi
void main() {
  final instance = BeauticaApi().getUserContactControllerApi();

  group(UserContactControllerApi, () {
    // Email a code to a new notifications email
    //
    // 200; 429 within the 60 s cooldown (Retry-After). Never 409: an address held by another account is refused only at verify.
    //
    //Future<ApiResponseVoid> requestEmailCode(ResendVerificationRequest resendVerificationRequest) async
    test('test requestEmailCode', () async {
      // TODO
    });

    // Send an SMS code to a new phone (add or change)
    //
    // Needs X-Firebase-AppCheck (AUTH-54). 200; 400 PHONE_NOT_UA_MOBILE (no SMS); 403 APP_CHECK_FAILED; 429 (3 per 15 min per phone, account, IP); 503. Never 409: a number held by another account is refused only at verify.
    //
    //Future<ApiResponseVoid> sendPhoneCode(RegistrationOtpSendRequest registrationOtpSendRequest) async
    test('test sendPhoneCode', () async {
      // TODO
    });

    // Confirm the notifications email with its code
    //
    // Stores the email (emailVerified = true) only now. Needs currentPassword (add and change), checked first. 200; 400 data.code CURRENT_PASSWORD_INVALID (counts as a failed try on the code) / INVALID_CODE / CODE_EXPIRED; 409 EMAIL_ALREADY_REGISTERED.
    //
    //Future<ApiResponseVoid> verifyEmailCode(NotificationEmailVerifyRequest notificationEmailVerifyRequest) async
    test('test verifyEmailCode', () async {
      // TODO
    });

    // Confirm the new phone with its SMS code
    //
    // Swaps the phone and marks it verified in one write. A CHANGE (the account already has a verified phone) also needs currentPassword, checked first; a first add needs only the code. 200; 400 data.code CURRENT_PASSWORD_INVALID (counts as a failed try on the code) / INVALID_CODE (wrong / expired / exhausted / another account's code); 400 PHONE_NOT_UA_MOBILE; 409 PHONE_ALREADY_REGISTERED.
    //
    //Future<ApiResponseVoid> verifyPhoneCode(PhoneChangeVerifyRequest phoneChangeVerifyRequest) async
    test('test verifyPhoneCode', () async {
      // TODO
    });
  });
}
