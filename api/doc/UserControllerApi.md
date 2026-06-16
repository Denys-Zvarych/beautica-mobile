# beautica_api.api.UserControllerApi

## Load the API package
```dart
import 'package:beautica_api/api.dart';
```

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**getMe**](UserControllerApi.md#getme) | **GET** /api/v1/users/me | 
[**updateMe**](UserControllerApi.md#updateme) | **PATCH** /api/v1/users/me | 


# **getMe**
> ApiResponseUserProfileResponse getMe()



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getUserControllerApi();

try {
    final response = api.getMe();
    print(response);
} catch on DioException (e) {
    print('Exception when calling UserControllerApi->getMe: $e\n');
}
```

### Parameters
This endpoint does not need any parameter.

### Return type

[**ApiResponseUserProfileResponse**](ApiResponseUserProfileResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **updateMe**
> ApiResponseUserProfileResponse updateMe(updateProfileRequest)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getUserControllerApi();
final UpdateProfileRequest updateProfileRequest = ; // UpdateProfileRequest | 

try {
    final response = api.updateMe(updateProfileRequest);
    print(response);
} catch on DioException (e) {
    print('Exception when calling UserControllerApi->updateMe: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **updateProfileRequest** | [**UpdateProfileRequest**](UpdateProfileRequest.md)|  | 

### Return type

[**ApiResponseUserProfileResponse**](ApiResponseUserProfileResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

