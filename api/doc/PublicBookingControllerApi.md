# beautica_api.api.PublicBookingControllerApi

## Load the API package
```dart
import 'package:beautica_api/api.dart';
```

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**availability**](PublicBookingControllerApi.md#availability) | **GET** /api/v1/book/{slug}/availability | 
[**book**](PublicBookingControllerApi.md#book) | **POST** /api/v1/book/{slug}/booking | 
[**cancel**](PublicBookingControllerApi.md#cancel) | **POST** /api/v1/book/cancel/{token} | 
[**cancelInfo**](PublicBookingControllerApi.md#cancelinfo) | **GET** /api/v1/book/cancel/{token} | 
[**info**](PublicBookingControllerApi.md#info) | **GET** /api/v1/book/{slug}/info | 


# **availability**
> BuiltList<AvailableSlotResponse> availability(slug, date, serviceId)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getPublicBookingControllerApi();
final String slug = slug_example; // String | 
final Date date = 2013-10-20; // Date | 
final BuiltList<String> serviceId = ; // BuiltList<String> | 

try {
    final response = api.availability(slug, date, serviceId);
    print(response);
} catch on DioException (e) {
    print('Exception when calling PublicBookingControllerApi->availability: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **slug** | **String**|  | 
 **date** | **Date**|  | 
 **serviceId** | [**BuiltList&lt;String&gt;**](String.md)|  | 

### Return type

[**BuiltList&lt;AvailableSlotResponse&gt;**](AvailableSlotResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **book**
> GuestBookingResponse book(slug, guestBookingRequest, authorization)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getPublicBookingControllerApi();
final String slug = slug_example; // String | 
final GuestBookingRequest guestBookingRequest = ; // GuestBookingRequest | 
final String authorization = authorization_example; // String | 

try {
    final response = api.book(slug, guestBookingRequest, authorization);
    print(response);
} catch on DioException (e) {
    print('Exception when calling PublicBookingControllerApi->book: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **slug** | **String**|  | 
 **guestBookingRequest** | [**GuestBookingRequest**](GuestBookingRequest.md)|  | 
 **authorization** | **String**|  | [optional] 

### Return type

[**GuestBookingResponse**](GuestBookingResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **cancel**
> cancel(token)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getPublicBookingControllerApi();
final String token = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 

try {
    api.cancel(token);
} catch on DioException (e) {
    print('Exception when calling PublicBookingControllerApi->cancel: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **token** | **String**|  | 

### Return type

void (empty response body)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: Not defined

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **cancelInfo**
> CancelTokenInfoResponse cancelInfo(token)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getPublicBookingControllerApi();
final String token = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 

try {
    final response = api.cancelInfo(token);
    print(response);
} catch on DioException (e) {
    print('Exception when calling PublicBookingControllerApi->cancelInfo: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **token** | **String**|  | 

### Return type

[**CancelTokenInfoResponse**](CancelTokenInfoResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **info**
> BookingSlugInfoResponse info(slug)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getPublicBookingControllerApi();
final String slug = slug_example; // String | 

try {
    final response = api.info(slug);
    print(response);
} catch on DioException (e) {
    print('Exception when calling PublicBookingControllerApi->info: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **slug** | **String**|  | 

### Return type

[**BookingSlugInfoResponse**](BookingSlugInfoResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

