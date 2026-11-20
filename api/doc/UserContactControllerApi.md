# beautica_api.api.UserContactControllerApi

## Load the API package
```dart
import 'package:beautica_api/api.dart';
```

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**requestEmailCode**](UserContactControllerApi.md#requestemailcode) | **POST** /api/v1/users/me/email/request-code | Email a code to a new notifications email
[**sendPhoneCode**](UserContactControllerApi.md#sendphonecode) | **POST** /api/v1/users/me/phone/otp/send | Send an SMS code to a new phone (add or change)
[**verifyEmailCode**](UserContactControllerApi.md#verifyemailcode) | **POST** /api/v1/users/me/email/verify | Confirm the notifications email with its code
[**verifyPhoneCode**](UserContactControllerApi.md#verifyphonecode) | **POST** /api/v1/users/me/phone/otp/verify | Confirm the new phone with its SMS code


# **requestEmailCode**
> ApiResponseVoid requestEmailCode(resendVerificationRequest)

Email a code to a new notifications email

200; 429 within the 60 s cooldown (Retry-After). Never 409: an address held by another account is refused only at verify.

### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getUserContactControllerApi();
final ResendVerificationRequest resendVerificationRequest = ; // ResendVerificationRequest | 

try {
    final response = api.requestEmailCode(resendVerificationRequest);
    print(response);
} catch on DioException (e) {
    print('Exception when calling UserContactControllerApi->requestEmailCode: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **resendVerificationRequest** | [**ResendVerificationRequest**](ResendVerificationRequest.md)|  | 

### Return type

[**ApiResponseVoid**](ApiResponseVoid.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **sendPhoneCode**
> ApiResponseVoid sendPhoneCode(registrationOtpSendRequest)

Send an SMS code to a new phone (add or change)

Needs X-Firebase-AppCheck (AUTH-54). 200; 400 PHONE_NOT_UA_MOBILE (no SMS); 403 APP_CHECK_FAILED; 429 (3 per 15 min per phone, account, IP); 503. Never 409: a number held by another account is refused only at verify.

### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getUserContactControllerApi();
final RegistrationOtpSendRequest registrationOtpSendRequest = ; // RegistrationOtpSendRequest | 

try {
    final response = api.sendPhoneCode(registrationOtpSendRequest);
    print(response);
} catch on DioException (e) {
    print('Exception when calling UserContactControllerApi->sendPhoneCode: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **registrationOtpSendRequest** | [**RegistrationOtpSendRequest**](RegistrationOtpSendRequest.md)|  | 

### Return type

[**ApiResponseVoid**](ApiResponseVoid.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **verifyEmailCode**
> ApiResponseVoid verifyEmailCode(notificationEmailVerifyRequest)

Confirm the notifications email with its code

Stores the email (emailVerified = true) only now. Needs currentPassword (add and change), checked first. 200; 400 data.code CURRENT_PASSWORD_INVALID (counts as a failed try on the code) / INVALID_CODE / CODE_EXPIRED; 409 EMAIL_ALREADY_REGISTERED.

### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getUserContactControllerApi();
final NotificationEmailVerifyRequest notificationEmailVerifyRequest = ; // NotificationEmailVerifyRequest | 

try {
    final response = api.verifyEmailCode(notificationEmailVerifyRequest);
    print(response);
} catch on DioException (e) {
    print('Exception when calling UserContactControllerApi->verifyEmailCode: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **notificationEmailVerifyRequest** | [**NotificationEmailVerifyRequest**](NotificationEmailVerifyRequest.md)|  | 

### Return type

[**ApiResponseVoid**](ApiResponseVoid.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **verifyPhoneCode**
> ApiResponseVoid verifyPhoneCode(phoneChangeVerifyRequest)

Confirm the new phone with its SMS code

Swaps the phone and marks it verified in one write. A CHANGE (the account already has a verified phone) also needs currentPassword, checked first; a first add needs only the code. 200; 400 data.code CURRENT_PASSWORD_INVALID (counts as a failed try on the code) / INVALID_CODE (wrong / expired / exhausted / another account's code); 400 PHONE_NOT_UA_MOBILE; 409 PHONE_ALREADY_REGISTERED.

### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getUserContactControllerApi();
final PhoneChangeVerifyRequest phoneChangeVerifyRequest = ; // PhoneChangeVerifyRequest | 

try {
    final response = api.verifyPhoneCode(phoneChangeVerifyRequest);
    print(response);
} catch on DioException (e) {
    print('Exception when calling UserContactControllerApi->verifyPhoneCode: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **phoneChangeVerifyRequest** | [**PhoneChangeVerifyRequest**](PhoneChangeVerifyRequest.md)|  | 

### Return type

[**ApiResponseVoid**](ApiResponseVoid.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

