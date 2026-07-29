# beautica_api.api.ReviewControllerApi

## Load the API package
```dart
import 'package:beautica_api/api.dart';
```

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**createAppointmentReview**](ReviewControllerApi.md#createappointmentreview) | **POST** /api/v1/appointments/{appointmentId}/review | 
[**createReview**](ReviewControllerApi.md#createreview) | **POST** /api/v1/reviews | 
[**getMasterReviewSummary**](ReviewControllerApi.md#getmasterreviewsummary) | **GET** /api/v1/masters/{masterId}/reviews/summary | 
[**getMyReviews**](ReviewControllerApi.md#getmyreviews) | **GET** /api/v1/reviews/me | 
[**getReview**](ReviewControllerApi.md#getreview) | **GET** /api/v1/reviews/{reviewId} | 
[**getReviewsByMaster**](ReviewControllerApi.md#getreviewsbymaster) | **GET** /api/v1/masters/{masterId}/reviews | 
[**getSalonReviewSummary**](ReviewControllerApi.md#getsalonreviewsummary) | **GET** /api/v1/salons/{salonId}/reviews/summary | 
[**getSalonReviews**](ReviewControllerApi.md#getsalonreviews) | **GET** /api/v1/salons/{salonId}/reviews | 


# **createAppointmentReview**
> ApiResponseReviewResponse createAppointmentReview(appointmentId, createAppointmentReviewRequest)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getReviewControllerApi();
final String appointmentId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final CreateAppointmentReviewRequest createAppointmentReviewRequest = ; // CreateAppointmentReviewRequest | 

try {
    final response = api.createAppointmentReview(appointmentId, createAppointmentReviewRequest);
    print(response);
} catch on DioException (e) {
    print('Exception when calling ReviewControllerApi->createAppointmentReview: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **appointmentId** | **String**|  | 
 **createAppointmentReviewRequest** | [**CreateAppointmentReviewRequest**](CreateAppointmentReviewRequest.md)|  | 

### Return type

[**ApiResponseReviewResponse**](ApiResponseReviewResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

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

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getMasterReviewSummary**
> ApiResponseMasterReviewSummaryResponse getMasterReviewSummary(masterId)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getReviewControllerApi();
final String masterId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 

try {
    final response = api.getMasterReviewSummary(masterId);
    print(response);
} catch on DioException (e) {
    print('Exception when calling ReviewControllerApi->getMasterReviewSummary: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **masterId** | **String**|  | 

### Return type

[**ApiResponseMasterReviewSummaryResponse**](ApiResponseMasterReviewSummaryResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getMyReviews**
> ApiResponsePageResponseMyReviewResponse getMyReviews(pageable)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getReviewControllerApi();
final Pageable pageable = ; // Pageable | 

try {
    final response = api.getMyReviews(pageable);
    print(response);
} catch on DioException (e) {
    print('Exception when calling ReviewControllerApi->getMyReviews: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **pageable** | [**Pageable**](.md)|  | 

### Return type

[**ApiResponsePageResponseMyReviewResponse**](ApiResponsePageResponseMyReviewResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
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

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getReviewsByMaster**
> ApiResponsePageResponseReviewResponse getReviewsByMaster(masterId, pageable, sort)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getReviewControllerApi();
final String masterId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final Pageable pageable = ; // Pageable | 
final String sort = sort_example; // String | 

try {
    final response = api.getReviewsByMaster(masterId, pageable, sort);
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
 **sort** | **String**|  | [optional] [default to 'NEWEST']

### Return type

[**ApiResponsePageResponseReviewResponse**](ApiResponsePageResponseReviewResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getSalonReviewSummary**
> ApiResponseSalonReviewSummaryResponse getSalonReviewSummary(salonId)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getReviewControllerApi();
final String salonId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 

try {
    final response = api.getSalonReviewSummary(salonId);
    print(response);
} catch on DioException (e) {
    print('Exception when calling ReviewControllerApi->getSalonReviewSummary: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **salonId** | **String**|  | 

### Return type

[**ApiResponseSalonReviewSummaryResponse**](ApiResponseSalonReviewSummaryResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getSalonReviews**
> ApiResponsePageResponseSalonReviewResponse getSalonReviews(salonId, pageable, sort)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getReviewControllerApi();
final String salonId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final Pageable pageable = ; // Pageable | 
final String sort = sort_example; // String | 

try {
    final response = api.getSalonReviews(salonId, pageable, sort);
    print(response);
} catch on DioException (e) {
    print('Exception when calling ReviewControllerApi->getSalonReviews: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **salonId** | **String**|  | 
 **pageable** | [**Pageable**](.md)|  | 
 **sort** | **String**|  | [optional] [default to 'NEWEST']

### Return type

[**ApiResponsePageResponseSalonReviewResponse**](ApiResponsePageResponseSalonReviewResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

