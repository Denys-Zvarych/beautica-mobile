# beautica_api.api.ClientControllerApi

## Load the API package
```dart
import 'package:beautica_api/api.dart';
```

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**getPassport**](ClientControllerApi.md#getpassport) | **GET** /api/v1/clients/me/passport | 
[**getTimeline**](ClientControllerApi.md#gettimeline) | **GET** /api/v1/clients/me/timeline | 


# **getPassport**
> ApiResponsePassportResponse getPassport()



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getClientControllerApi();

try {
    final response = api.getPassport();
    print(response);
} catch on DioException (e) {
    print('Exception when calling ClientControllerApi->getPassport: $e\n');
}
```

### Parameters
This endpoint does not need any parameter.

### Return type

[**ApiResponsePassportResponse**](ApiResponsePassportResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getTimeline**
> ApiResponsePageResponseTimelineItemResponse getTimeline(pageable)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getClientControllerApi();
final Pageable pageable = ; // Pageable | 

try {
    final response = api.getTimeline(pageable);
    print(response);
} catch on DioException (e) {
    print('Exception when calling ClientControllerApi->getTimeline: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **pageable** | [**Pageable**](.md)|  | 

### Return type

[**ApiResponsePageResponseTimelineItemResponse**](ApiResponsePageResponseTimelineItemResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

