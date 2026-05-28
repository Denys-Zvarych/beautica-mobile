# beautica_api.api.ReviewControllerApi

## Load the API package
```dart
import 'package:beautica_api/api.dart';
```

All URIs are relative to *http://localhost:8080/api/v1*

Method | HTTP request | Description
------------- | ------------- | -------------
[**createReview**](ReviewControllerApi.md#createreview) | **POST** /reviews | 
[**getReview**](ReviewControllerApi.md#getreview) | **GET** /reviews/{reviewId} | 
[**getReviewsByMaster**](ReviewControllerApi.md#getreviewsbymaster) | **GET** /masters/{masterId}/reviews | 


# **createReview**
> ApiResponseReviewResponse createReview(createReviewRequest)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getReviewControllerApi();
final CreateReviewRequest createReviewRequest = ; // CreateReviewRequest | 

try {
    final response = api.createReview(createReviewRequest);
    print(response);
} catch on DioException (e) {
    print('Exception when calling ReviewControllerApi->createReview: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **createReviewRequest** | [**CreateReviewRequest**](CreateReviewRequest.md)|  | 

### Return type

[**ApiResponseReviewResponse**](ApiResponseReviewResponse.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getReview**
> ApiResponseReviewResponse getReview(reviewId)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getReviewControllerApi();
final String reviewId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 

try {
    final response = api.getReview(reviewId);
    print(response);
} catch on DioException (e) {
    print('Exception when calling ReviewControllerApi->getReview: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **reviewId** | **String**|  | 

### Return type

[**ApiResponseReviewResponse**](ApiResponseReviewResponse.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getReviewsByMaster**
> ApiResponsePageResponseReviewResponse getReviewsByMaster(masterId, pageable)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getReviewControllerApi();
final String masterId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final Pageable pageable = ; // Pageable | 

try {
    final response = api.getReviewsByMaster(masterId, pageable);
    print(response);
} catch on DioException (e) {
    print('Exception when calling ReviewControllerApi->getReviewsByMaster: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **masterId** | **String**|  | 
 **pageable** | [**Pageable**](.md)|  | 

### Return type

[**ApiResponsePageResponseReviewResponse**](ApiResponsePageResponseReviewResponse.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

