# beautica_api.api.AuthControllerApi

## Load the API package
```dart
import 'package:beautica_api/api.dart';
```

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**acceptInvite**](AuthControllerApi.md#acceptinvite) | **POST** /api/v1/auth/invite/accept | 
[**forgotPassword**](AuthControllerApi.md#forgotpassword) | **POST** /api/v1/auth/forgot-password | 
[**login**](AuthControllerApi.md#login) | **POST** /api/v1/auth/login | 
[**logout**](AuthControllerApi.md#logout) | **POST** /api/v1/auth/logout | 
[**refresh**](AuthControllerApi.md#refresh) | **POST** /api/v1/auth/refresh | 
[**register**](AuthControllerApi.md#register) | **POST** /api/v1/auth/register | 
[**registerIndependentMaster**](AuthControllerApi.md#registerindependentmaster) | **POST** /api/v1/auth/register/independent-master | 
[**resendVerification**](AuthControllerApi.md#resendverification) | **POST** /api/v1/auth/resend-verification | 
[**resetPassword**](AuthControllerApi.md#resetpassword) | **POST** /api/v1/auth/reset-password | 
[**sendInvite**](AuthControllerApi.md#sendinvite) | **POST** /api/v1/auth/invite | 
[**validateInvite**](AuthControllerApi.md#validateinvite) | **GET** /api/v1/auth/invite/validate | 
[**verifyEmail**](AuthControllerApi.md#verifyemail) | **POST** /api/v1/auth/verify-email | 
[**verifyPasswordResetOtp**](AuthControllerApi.md#verifypasswordresetotp) | **POST** /api/v1/auth/verify-password-reset-otp | 


# **acceptInvite**
> ApiResponseAuthResponse acceptInvite(inviteAcceptRequest)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getAuthControllerApi();
final InviteAcceptRequest inviteAcceptRequest = ; // InviteAcceptRequest | 

try {
    final response = api.acceptInvite(inviteAcceptRequest);
    print(response);
} catch on DioException (e) {
    print('Exception when calling AuthControllerApi->acceptInvite: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **inviteAcceptRequest** | [**InviteAcceptRequest**](InviteAcceptRequest.md)|  | 

### Return type

[**ApiResponseAuthResponse**](ApiResponseAuthResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **forgotPassword**
> ApiResponseVoid forgotPassword(forgotPasswordRequest)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getAuthControllerApi();
final ForgotPasswordRequest forgotPasswordRequest = ; // ForgotPasswordRequest | 

try {
    final response = api.forgotPassword(forgotPasswordRequest);
    print(response);
} catch on DioException (e) {
    print('Exception when calling AuthControllerApi->forgotPassword: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **forgotPasswordRequest** | [**ForgotPasswordRequest**](ForgotPasswordRequest.md)|  | 

### Return type

[**ApiResponseVoid**](ApiResponseVoid.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **login**
> ApiResponseAuthResponse login(loginRequest)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getAuthControllerApi();
final LoginRequest loginRequest = ; // LoginRequest | 

try {
    final response = api.login(loginRequest);
    print(response);
} catch on DioException (e) {
    print('Exception when calling AuthControllerApi->login: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **loginRequest** | [**LoginRequest**](LoginRequest.md)|  | 

### Return type

[**ApiResponseAuthResponse**](ApiResponseAuthResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **logout**
> logout()



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getAuthControllerApi();

try {
    api.logout();
} catch on DioException (e) {
    print('Exception when calling AuthControllerApi->logout: $e\n');
}
```

### Parameters
This endpoint does not need any parameter.

### Return type

void (empty response body)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: Not defined

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **refresh**
> ApiResponseAuthResponse refresh(refreshRequest)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getAuthControllerApi();
final RefreshRequest refreshRequest = ; // RefreshRequest | 

try {
    final response = api.refresh(refreshRequest);
    print(response);
} catch on DioException (e) {
    print('Exception when calling AuthControllerApi->refresh: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **refreshRequest** | [**RefreshRequest**](RefreshRequest.md)|  | 

### Return type

[**ApiResponseAuthResponse**](ApiResponseAuthResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **register**
> ApiResponseRegistrationResponse register(registerRequest)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getAuthControllerApi();
final RegisterRequest registerRequest = ; // RegisterRequest | 

try {
    final response = api.register(registerRequest);
    print(response);
} catch on DioException (e) {
    print('Exception when calling AuthControllerApi->register: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **registerRequest** | [**RegisterRequest**](RegisterRequest.md)|  | 

### Return type

[**ApiResponseRegistrationResponse**](ApiResponseRegistrationResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **registerIndependentMaster**
> ApiResponseRegistrationResponse registerIndependentMaster(registerIndependentMasterRequest)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getAuthControllerApi();
final RegisterIndependentMasterRequest registerIndependentMasterRequest = ; // RegisterIndependentMasterRequest | 

try {
    final response = api.registerIndependentMaster(registerIndependentMasterRequest);
    print(response);
} catch on DioException (e) {
    print('Exception when calling AuthControllerApi->registerIndependentMaster: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **registerIndependentMasterRequest** | [**RegisterIndependentMasterRequest**](RegisterIndependentMasterRequest.md)|  | 

### Return type

[**ApiResponseRegistrationResponse**](ApiResponseRegistrationResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **resendVerification**
> ApiResponseRegistrationResponse resendVerification(resendVerificationRequest)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getAuthControllerApi();
final ResendVerificationRequest resendVerificationRequest = ; // ResendVerificationRequest | 

try {
    final response = api.resendVerification(resendVerificationRequest);
    print(response);
} catch on DioException (e) {
    print('Exception when calling AuthControllerApi->resendVerification: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **resendVerificationRequest** | [**ResendVerificationRequest**](ResendVerificationRequest.md)|  | 

### Return type

[**ApiResponseRegistrationResponse**](ApiResponseRegistrationResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **resetPassword**
> ApiResponseVoid resetPassword(resetPasswordRequest)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getAuthControllerApi();
final ResetPasswordRequest resetPasswordRequest = ; // ResetPasswordRequest | 

try {
    final response = api.resetPassword(resetPasswordRequest);
    print(response);
} catch on DioException (e) {
    print('Exception when calling AuthControllerApi->resetPassword: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **resetPasswordRequest** | [**ResetPasswordRequest**](ResetPasswordRequest.md)|  | 

### Return type

[**ApiResponseVoid**](ApiResponseVoid.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **sendInvite**
> ApiResponseInviteResponse sendInvite(inviteRequest)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getAuthControllerApi();
final InviteRequest inviteRequest = ; // InviteRequest | 

try {
    final response = api.sendInvite(inviteRequest);
    print(response);
} catch on DioException (e) {
    print('Exception when calling AuthControllerApi->sendInvite: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **inviteRequest** | [**InviteRequest**](InviteRequest.md)|  | 

### Return type

[**ApiResponseInviteResponse**](ApiResponseInviteResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **validateInvite**
> ApiResponseInvitePreviewResponse validateInvite(token)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getAuthControllerApi();
final String token = token_example; // String | 

try {
    final response = api.validateInvite(token);
    print(response);
} catch on DioException (e) {
    print('Exception when calling AuthControllerApi->validateInvite: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **token** | **String**|  | 

### Return type

[**ApiResponseInvitePreviewResponse**](ApiResponseInvitePreviewResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **verifyEmail**
> ApiResponseAuthResponse verifyEmail(verifyEmailRequest)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getAuthControllerApi();
final VerifyEmailRequest verifyEmailRequest = ; // VerifyEmailRequest | 

try {
    final response = api.verifyEmail(verifyEmailRequest);
    print(response);
} catch on DioException (e) {
    print('Exception when calling AuthControllerApi->verifyEmail: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **verifyEmailRequest** | [**VerifyEmailRequest**](VerifyEmailRequest.md)|  | 

### Return type

[**ApiResponseAuthResponse**](ApiResponseAuthResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **verifyPasswordResetOtp**
> ApiResponseVerifyPasswordResetOtpResponse verifyPasswordResetOtp(verifyPasswordResetOtpRequest)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getAuthControllerApi();
final VerifyPasswordResetOtpRequest verifyPasswordResetOtpRequest = ; // VerifyPasswordResetOtpRequest | 

try {
    final response = api.verifyPasswordResetOtp(verifyPasswordResetOtpRequest);
    print(response);
} catch on DioException (e) {
    print('Exception when calling AuthControllerApi->verifyPasswordResetOtp: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **verifyPasswordResetOtpRequest** | [**VerifyPasswordResetOtpRequest**](VerifyPasswordResetOtpRequest.md)|  | 

### Return type

[**ApiResponseVerifyPasswordResetOtpResponse**](ApiResponseVerifyPasswordResetOtpResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

