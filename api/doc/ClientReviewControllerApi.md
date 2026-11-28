# beautica_api.api.ClientReviewControllerApi

## Load the API package
```dart
import 'package:beautica_api/api.dart';
```

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**create**](ClientReviewControllerApi.md#create) | **POST** /api/v1/client-reviews | 
[**deleteOwn**](ClientReviewControllerApi.md#deleteown) | **DELETE** /api/v1/client-reviews/{reviewId} | 


# **create**
> ApiResponseClientReviewResponse create(createClientReviewRequest)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getClientReviewControllerApi();
final CreateClientReviewRequest createClientReviewRequest = ; // CreateClientReviewRequest | 

try {
    final response = api.create(createClientReviewRequest);
    print(response);
} catch on DioException (e) {
    print('Exception when calling ClientReviewControllerApi->create: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **createClientReviewRequest** | [**CreateClientReviewRequest**](CreateClientReviewRequest.md)|  | 

### Return type

[**ApiResponseClientReviewResponse**](ApiResponseClientReviewResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **deleteOwn**
> deleteOwn(reviewId)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getClientReviewControllerApi();
final String reviewId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 

try {
    api.deleteOwn(reviewId);
} catch on DioException (e) {
    print('Exception when calling ClientReviewControllerApi->deleteOwn: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **reviewId** | **String**|  | 

### Return type

void (empty response body)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: Not defined

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

