# beautica_api.api.BookingControllerApi

## Load the API package
```dart
import 'package:beautica_api/api.dart';
```

All URIs are relative to *http://localhost:8080/api/v1*

Method | HTTP request | Description
------------- | ------------- | -------------
[**cancelBooking**](BookingControllerApi.md#cancelbooking) | **PATCH** /bookings/{bookingId}/cancel | 
[**completeBooking**](BookingControllerApi.md#completebooking) | **PATCH** /bookings/{bookingId}/complete | 
[**confirmBooking**](BookingControllerApi.md#confirmbooking) | **PATCH** /bookings/{bookingId}/confirm | 
[**createBooking**](BookingControllerApi.md#createbooking) | **POST** /bookings | 
[**declineBooking**](BookingControllerApi.md#declinebooking) | **PATCH** /bookings/{bookingId}/decline | 
[**getBooking**](BookingControllerApi.md#getbooking) | **GET** /bookings/{bookingId} | 
[**listMyBookings**](BookingControllerApi.md#listmybookings) | **GET** /bookings/me | 
[**notCompleteBooking**](BookingControllerApi.md#notcompletebooking) | **PATCH** /bookings/{bookingId}/not-complete | 


# **cancelBooking**
> cancelBooking(bookingId, cancelBookingRequest)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getBookingControllerApi();
final String bookingId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final CancelBookingRequest cancelBookingRequest = ; // CancelBookingRequest | 

try {
    api.cancelBooking(bookingId, cancelBookingRequest);
} catch on DioException (e) {
    print('Exception when calling BookingControllerApi->cancelBooking: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **bookingId** | **String**|  | 
 **cancelBookingRequest** | [**CancelBookingRequest**](CancelBookingRequest.md)|  | 

### Return type

void (empty response body)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: Not defined

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **completeBooking**
> completeBooking(bookingId)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getBookingControllerApi();
final String bookingId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 

try {
    api.completeBooking(bookingId);
} catch on DioException (e) {
    print('Exception when calling BookingControllerApi->completeBooking: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **bookingId** | **String**|  | 

### Return type

void (empty response body)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: Not defined

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **confirmBooking**
> confirmBooking(bookingId)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getBookingControllerApi();
final String bookingId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 

try {
    api.confirmBooking(bookingId);
} catch on DioException (e) {
    print('Exception when calling BookingControllerApi->confirmBooking: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **bookingId** | **String**|  | 

### Return type

void (empty response body)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: Not defined

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **createBooking**
> ApiResponseBookingResponse createBooking(createBookingRequest, idempotencyKey)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getBookingControllerApi();
final CreateBookingRequest createBookingRequest = ; // CreateBookingRequest | 
final String idempotencyKey = idempotencyKey_example; // String | 

try {
    final response = api.createBooking(createBookingRequest, idempotencyKey);
    print(response);
} catch on DioException (e) {
    print('Exception when calling BookingControllerApi->createBooking: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **createBookingRequest** | [**CreateBookingRequest**](CreateBookingRequest.md)|  | 
 **idempotencyKey** | **String**|  | [optional] 

### Return type

[**ApiResponseBookingResponse**](ApiResponseBookingResponse.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **declineBooking**
> declineBooking(bookingId, statusUpdateRequest)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getBookingControllerApi();
final String bookingId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final StatusUpdateRequest statusUpdateRequest = ; // StatusUpdateRequest | 

try {
    api.declineBooking(bookingId, statusUpdateRequest);
} catch on DioException (e) {
    print('Exception when calling BookingControllerApi->declineBooking: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **bookingId** | **String**|  | 
 **statusUpdateRequest** | [**StatusUpdateRequest**](StatusUpdateRequest.md)|  | 

### Return type

void (empty response body)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: Not defined

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getBooking**
> ApiResponseBookingDetailResponse getBooking(bookingId)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getBookingControllerApi();
final String bookingId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 

try {
    final response = api.getBooking(bookingId);
    print(response);
} catch on DioException (e) {
    print('Exception when calling BookingControllerApi->getBooking: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **bookingId** | **String**|  | 

### Return type

[**ApiResponseBookingDetailResponse**](ApiResponseBookingDetailResponse.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **listMyBookings**
> ApiResponsePageResponseBookingResponse listMyBookings(pageable, status)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getBookingControllerApi();
final Pageable pageable = ; // Pageable | 
final String status = status_example; // String | 

try {
    final response = api.listMyBookings(pageable, status);
    print(response);
} catch on DioException (e) {
    print('Exception when calling BookingControllerApi->listMyBookings: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **pageable** | [**Pageable**](.md)|  | 
 **status** | **String**|  | [optional] 

### Return type

[**ApiResponsePageResponseBookingResponse**](ApiResponsePageResponseBookingResponse.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **notCompleteBooking**
> notCompleteBooking(bookingId, statusUpdateRequest)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getBookingControllerApi();
final String bookingId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final StatusUpdateRequest statusUpdateRequest = ; // StatusUpdateRequest | 

try {
    api.notCompleteBooking(bookingId, statusUpdateRequest);
} catch on DioException (e) {
    print('Exception when calling BookingControllerApi->notCompleteBooking: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **bookingId** | **String**|  | 
 **statusUpdateRequest** | [**StatusUpdateRequest**](StatusUpdateRequest.md)|  | 

### Return type

void (empty response body)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: Not defined

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

