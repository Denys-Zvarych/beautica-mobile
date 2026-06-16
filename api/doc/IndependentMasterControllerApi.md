# beautica_api.api.IndependentMasterControllerApi

## Load the API package
```dart
import 'package:beautica_api/api.dart';
```

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**updateLocality**](IndependentMasterControllerApi.md#updatelocality) | **PATCH** /api/v1/independent-masters/me | 
[**updateProfile**](IndependentMasterControllerApi.md#updateprofile) | **PATCH** /api/v1/independent-masters/me/profile | 


# **updateLocality**
> ApiResponseUserProfileResponse updateLocality(independentMasterUpdateRequest)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getIndependentMasterControllerApi();
final IndependentMasterUpdateRequest independentMasterUpdateRequest = ; // IndependentMasterUpdateRequest | 

try {
    final response = api.updateLocality(independentMasterUpdateRequest);
    print(response);
} catch on DioException (e) {
    print('Exception when calling IndependentMasterControllerApi->updateLocality: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **independentMasterUpdateRequest** | [**IndependentMasterUpdateRequest**](IndependentMasterUpdateRequest.md)|  | 

### Return type

[**ApiResponseUserProfileResponse**](ApiResponseUserProfileResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **updateProfile**
> ApiResponseMasterPublicProfileResponse updateProfile(masterProfileUpdateRequest)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getIndependentMasterControllerApi();
final MasterProfileUpdateRequest masterProfileUpdateRequest = ; // MasterProfileUpdateRequest | 

try {
    final response = api.updateProfile(masterProfileUpdateRequest);
    print(response);
} catch on DioException (e) {
    print('Exception when calling IndependentMasterControllerApi->updateProfile: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **masterProfileUpdateRequest** | [**MasterProfileUpdateRequest**](MasterProfileUpdateRequest.md)|  | 

### Return type

[**ApiResponseMasterPublicProfileResponse**](ApiResponseMasterPublicProfileResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

