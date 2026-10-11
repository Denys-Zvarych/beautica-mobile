# beautica_api.api.SalonMasterControllerApi

## Load the API package
```dart
import 'package:beautica_api/api.dart';
```

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**removeMaster**](SalonMasterControllerApi.md#removemaster) | **DELETE** /api/v1/salons/{salonId}/masters/{masterId} | 


# **removeMaster**
> removeMaster(salonId, masterId)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getSalonMasterControllerApi();
final String salonId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final String masterId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 

try {
    api.removeMaster(salonId, masterId);
} catch on DioException (e) {
    print('Exception when calling SalonMasterControllerApi->removeMaster: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **salonId** | **String**|  | 
 **masterId** | **String**|  | 

### Return type

void (empty response body)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: Not defined

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

