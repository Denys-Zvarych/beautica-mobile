# beautica_api.api.RegistrationPhoneControllerApi

## Load the API package
```dart
import 'package:beautica_api/api.dart';
```

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**send1**](RegistrationPhoneControllerApi.md#send1) | **POST** /api/v1/auth/register/phone/otp/send | 
[**verify1**](RegistrationPhoneControllerApi.md#verify1) | **POST** /api/v1/auth/register/phone/otp/verify | 


# **send1**
> ApiResponseVoid send1(registrationOtpSendRequest)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getRegistrationPhoneControllerApi();
final RegistrationOtpSendRequest registrationOtpSendRequest = ; // RegistrationOtpSendRequest | 

try {
    final response = api.send1(registrationOtpSendRequest);
    print(response);
} catch on DioException (e) {
    print('Exception when calling RegistrationPhoneControllerApi->send1: $e\n');
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

# **verify1**
> ApiResponseRegistrationTicketResponse verify1(registrationOtpVerifyRequest)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getRegistrationPhoneControllerApi();
final RegistrationOtpVerifyRequest registrationOtpVerifyRequest = ; // RegistrationOtpVerifyRequest | 

try {
    final response = api.verify1(registrationOtpVerifyRequest);
    print(response);
} catch on DioException (e) {
    print('Exception when calling RegistrationPhoneControllerApi->verify1: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **registrationOtpVerifyRequest** | [**RegistrationOtpVerifyRequest**](RegistrationOtpVerifyRequest.md)|  | 

### Return type

[**ApiResponseRegistrationTicketResponse**](ApiResponseRegistrationTicketResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

