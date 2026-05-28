# beautica_api.api.SalonMasterControllerApi

## Load the API package
```dart
import 'package:beautica_api/api.dart';
```

All URIs are relative to *http://localhost:8080/api/v1*

Method | HTTP request | Description
------------- | ------------- | -------------
[**disableOwnerMaster**](SalonMasterControllerApi.md#disableownermaster) | **DELETE** /salons/{salonId}/master | 
[**enableOwnerMaster**](SalonMasterControllerApi.md#enableownermaster) | **POST** /salons/{salonId}/master | 


# **disableOwnerMaster**
> disableOwnerMaster(salonId)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getSalonMasterControllerApi();
final String salonId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 

try {
    api.disableOwnerMaster(salonId);
} catch on DioException (e) {
    print('Exception when calling SalonMasterControllerApi->disableOwnerMaster: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **salonId** | **String**|  | 

### Return type

void (empty response body)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: Not defined

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **enableOwnerMaster**
> ApiResponseMasterDetailResponse enableOwnerMaster(salonId)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getSalonMasterControllerApi();
final String salonId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 

try {
    final response = api.enableOwnerMaster(salonId);
    print(response);
} catch on DioException (e) {
    print('Exception when calling SalonMasterControllerApi->enableOwnerMaster: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **salonId** | **String**|  | 

### Return type

[**ApiResponseMasterDetailResponse**](ApiResponseMasterDetailResponse.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

