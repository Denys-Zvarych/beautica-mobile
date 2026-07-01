# beautica_api.api.PhoneOtpControllerApi

## Load the API package
```dart
import 'package:beautica_api/api.dart';
```

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**send**](PhoneOtpControllerApi.md#send) | **POST** /api/v1/book/otp/send | 
[**verify**](PhoneOtpControllerApi.md#verify) | **POST** /api/v1/book/otp/verify | 


# **send**
> ApiResponseVoid send(phoneOtpSendRequest)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getPhoneOtpControllerApi();
final PhoneOtpSendRequest phoneOtpSendRequest = ; // PhoneOtpSendRequest | 

try {
    final response = api.send(phoneOtpSendRequest);
    print(response);
} catch on DioException (e) {
    print('Exception when calling PhoneOtpControllerApi->send: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **phoneOtpSendRequest** | [**PhoneOtpSendRequest**](PhoneOtpSendRequest.md)|  | 

### Return type

[**ApiResponseVoid**](ApiResponseVoid.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **verify**
> ApiResponseGuestTokenResponse verify(phoneOtpVerifyRequest)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getPhoneOtpControllerApi();
final PhoneOtpVerifyRequest phoneOtpVerifyRequest = ; // PhoneOtpVerifyRequest | 

try {
    final response = api.verify(phoneOtpVerifyRequest);
    print(response);
} catch on DioException (e) {
    print('Exception when calling PhoneOtpControllerApi->verify: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **phoneOtpVerifyRequest** | [**PhoneOtpVerifyRequest**](PhoneOtpVerifyRequest.md)|  | 

### Return type

[**ApiResponseGuestTokenResponse**](ApiResponseGuestTokenResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

