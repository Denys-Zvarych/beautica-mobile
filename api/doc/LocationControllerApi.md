# beautica_api.api.LocationControllerApi

## Load the API package
```dart
import 'package:beautica_api/api.dart';
```

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**getCitiesByOblast**](LocationControllerApi.md#getcitiesbyoblast) | **GET** /api/v1/locations/oblasts/{oblastId}/cities | 
[**getDistrictsByCity**](LocationControllerApi.md#getdistrictsbycity) | **GET** /api/v1/locations/cities/{cityId}/districts | 
[**getOblasts**](LocationControllerApi.md#getoblasts) | **GET** /api/v1/locations/oblasts | 


# **getCitiesByOblast**
> ApiResponseListCityResponse getCitiesByOblast(oblastId)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getLocationControllerApi();
final String oblastId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 

try {
    final response = api.getCitiesByOblast(oblastId);
    print(response);
} catch on DioException (e) {
    print('Exception when calling LocationControllerApi->getCitiesByOblast: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **oblastId** | **String**|  | 

### Return type

[**ApiResponseListCityResponse**](ApiResponseListCityResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getDistrictsByCity**
> ApiResponseListCityDistrictResponse getDistrictsByCity(cityId)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getLocationControllerApi();
final String cityId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 

try {
    final response = api.getDistrictsByCity(cityId);
    print(response);
} catch on DioException (e) {
    print('Exception when calling LocationControllerApi->getDistrictsByCity: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **cityId** | **String**|  | 

### Return type

[**ApiResponseListCityDistrictResponse**](ApiResponseListCityDistrictResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getOblasts**
> ApiResponseListOblastResponse getOblasts()



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getLocationControllerApi();

try {
    final response = api.getOblasts();
    print(response);
} catch on DioException (e) {
    print('Exception when calling LocationControllerApi->getOblasts: $e\n');
}
```

### Parameters
This endpoint does not need any parameter.

### Return type

[**ApiResponseListOblastResponse**](ApiResponseListOblastResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

