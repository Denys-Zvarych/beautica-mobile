# beautica_api.api.DashboardControllerApi

## Load the API package
```dart
import 'package:beautica_api/api.dart';
```

All URIs are relative to *http://localhost:8080/api/v1*

Method | HTTP request | Description
------------- | ------------- | -------------
[**getRevenueSummary**](DashboardControllerApi.md#getrevenuesummary) | **GET** /dashboard/revenue | 


# **getRevenueSummary**
> ApiResponseRevenueResponse getRevenueSummary(from, to, filterMasterId, serviceDefId, salonId)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getDashboardControllerApi();
final Date from = 2013-10-20; // Date | 
final Date to = 2013-10-20; // Date | 
final String filterMasterId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final String serviceDefId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final String salonId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 

try {
    final response = api.getRevenueSummary(from, to, filterMasterId, serviceDefId, salonId);
    print(response);
} catch on DioException (e) {
    print('Exception when calling DashboardControllerApi->getRevenueSummary: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **from** | **Date**|  | [optional] 
 **to** | **Date**|  | [optional] 
 **filterMasterId** | **String**|  | [optional] 
 **serviceDefId** | **String**|  | [optional] 
 **salonId** | **String**|  | [optional] 

### Return type

[**ApiResponseRevenueResponse**](ApiResponseRevenueResponse.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

