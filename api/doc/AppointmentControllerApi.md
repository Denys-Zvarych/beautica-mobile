# beautica_api.api.AppointmentControllerApi

## Load the API package
```dart
import 'package:beautica_api/api.dart';
```

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**cancelAppointment**](AppointmentControllerApi.md#cancelappointment) | **PATCH** /api/v1/appointments/{appointmentId}/cancel | 
[**cancelAppointmentItem**](AppointmentControllerApi.md#cancelappointmentitem) | **PATCH** /api/v1/appointments/{appointmentId}/services/{bookingId}/cancel | Cancel one service line of a visit
[**completeAppointment**](AppointmentControllerApi.md#completeappointment) | **PATCH** /api/v1/appointments/{appointmentId}/complete | 
[**completeAppointmentItem**](AppointmentControllerApi.md#completeappointmentitem) | **PATCH** /api/v1/appointments/{appointmentId}/services/{bookingId}/complete | Complete one service line of a visit
[**createAppointment**](AppointmentControllerApi.md#createappointment) | **POST** /api/v1/appointments | 
[**declineAppointment**](AppointmentControllerApi.md#declineappointment) | **PATCH** /api/v1/appointments/{appointmentId}/decline | 
[**declineAppointmentItem**](AppointmentControllerApi.md#declineappointmentitem) | **PATCH** /api/v1/appointments/{appointmentId}/services/{bookingId}/decline | 
[**getAppointment**](AppointmentControllerApi.md#getappointment) | **GET** /api/v1/appointments/{appointmentId} | 
[**notCompleteAppointment**](AppointmentControllerApi.md#notcompleteappointment) | **PATCH** /api/v1/appointments/{appointmentId}/not-complete | 
[**rescheduleAppointment**](AppointmentControllerApi.md#rescheduleappointment) | **PATCH** /api/v1/appointments/{appointmentId}/reschedule | 
[**rescheduleAppointmentItem**](AppointmentControllerApi.md#rescheduleappointmentitem) | **PATCH** /api/v1/appointments/{appointmentId}/services/{bookingId}/reschedule | Reschedule one service line of a visit


# **cancelAppointment**
> cancelAppointment(appointmentId, appointmentCancelRequest)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getAppointmentControllerApi();
final String appointmentId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final AppointmentCancelRequest appointmentCancelRequest = ; // AppointmentCancelRequest | 

try {
    api.cancelAppointment(appointmentId, appointmentCancelRequest);
} catch on DioException (e) {
    print('Exception when calling AppointmentControllerApi->cancelAppointment: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **appointmentId** | **String**|  | 
 **appointmentCancelRequest** | [**AppointmentCancelRequest**](AppointmentCancelRequest.md)|  | [optional] 

### Return type

void (empty response body)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: Not defined

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **cancelAppointmentItem**
> cancelAppointmentItem(appointmentId, bookingId, cancelBookingRequest)

Cancel one service line of a visit

Client-initiated cancel of ONE service line of a multi-service visit. Delegates verbatim to the same logic as PATCH /bookings/{bookingId}/cancel, so the two routes can never diverge.

### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getAppointmentControllerApi();
final String appointmentId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final String bookingId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final CancelBookingRequest cancelBookingRequest = ; // CancelBookingRequest | 

try {
    api.cancelAppointmentItem(appointmentId, bookingId, cancelBookingRequest);
} catch on DioException (e) {
    print('Exception when calling AppointmentControllerApi->cancelAppointmentItem: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **appointmentId** | **String**|  | 
 **bookingId** | **String**|  | 
 **cancelBookingRequest** | [**CancelBookingRequest**](CancelBookingRequest.md)|  | 

### Return type

void (empty response body)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: Not defined

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **completeAppointment**
> completeAppointment(appointmentId)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getAppointmentControllerApi();
final String appointmentId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 

try {
    api.completeAppointment(appointmentId);
} catch on DioException (e) {
    print('Exception when calling AppointmentControllerApi->completeAppointment: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **appointmentId** | **String**|  | 

### Return type

void (empty response body)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: Not defined

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **completeAppointmentItem**
> completeAppointmentItem(appointmentId, bookingId)

Complete one service line of a visit

Provider-initiated completion of ONE service line of a multi-service visit. Siblings stay CONFIRMED. The header collapses to COMPLETED, and the visit's single review-requested notification fires, only once the last CONFIRMED sibling completes.

### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getAppointmentControllerApi();
final String appointmentId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final String bookingId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 

try {
    api.completeAppointmentItem(appointmentId, bookingId);
} catch on DioException (e) {
    print('Exception when calling AppointmentControllerApi->completeAppointmentItem: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **appointmentId** | **String**|  | 
 **bookingId** | **String**|  | 

### Return type

void (empty response body)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: Not defined

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **createAppointment**
> ApiResponseAppointmentDetailResponse createAppointment(createAppointmentRequest, idempotencyKey)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getAppointmentControllerApi();
final CreateAppointmentRequest createAppointmentRequest = ; // CreateAppointmentRequest | 
final String idempotencyKey = idempotencyKey_example; // String | 

try {
    final response = api.createAppointment(createAppointmentRequest, idempotencyKey);
    print(response);
} catch on DioException (e) {
    print('Exception when calling AppointmentControllerApi->createAppointment: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **createAppointmentRequest** | [**CreateAppointmentRequest**](CreateAppointmentRequest.md)|  | 
 **idempotencyKey** | **String**|  | [optional] 

### Return type

[**ApiResponseAppointmentDetailResponse**](ApiResponseAppointmentDetailResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **declineAppointment**
> declineAppointment(appointmentId, appointmentProviderNoteRequest)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getAppointmentControllerApi();
final String appointmentId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final AppointmentProviderNoteRequest appointmentProviderNoteRequest = ; // AppointmentProviderNoteRequest | 

try {
    api.declineAppointment(appointmentId, appointmentProviderNoteRequest);
} catch on DioException (e) {
    print('Exception when calling AppointmentControllerApi->declineAppointment: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **appointmentId** | **String**|  | 
 **appointmentProviderNoteRequest** | [**AppointmentProviderNoteRequest**](AppointmentProviderNoteRequest.md)|  | [optional] 

### Return type

void (empty response body)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: Not defined

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **declineAppointmentItem**
> declineAppointmentItem(appointmentId, bookingId, appointmentProviderNoteRequest)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getAppointmentControllerApi();
final String appointmentId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final String bookingId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final AppointmentProviderNoteRequest appointmentProviderNoteRequest = ; // AppointmentProviderNoteRequest | 

try {
    api.declineAppointmentItem(appointmentId, bookingId, appointmentProviderNoteRequest);
} catch on DioException (e) {
    print('Exception when calling AppointmentControllerApi->declineAppointmentItem: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **appointmentId** | **String**|  | 
 **bookingId** | **String**|  | 
 **appointmentProviderNoteRequest** | [**AppointmentProviderNoteRequest**](AppointmentProviderNoteRequest.md)|  | [optional] 

### Return type

void (empty response body)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: Not defined

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getAppointment**
> ApiResponseAppointmentDetailResponse getAppointment(appointmentId)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getAppointmentControllerApi();
final String appointmentId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 

try {
    final response = api.getAppointment(appointmentId);
    print(response);
} catch on DioException (e) {
    print('Exception when calling AppointmentControllerApi->getAppointment: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **appointmentId** | **String**|  | 

### Return type

[**ApiResponseAppointmentDetailResponse**](ApiResponseAppointmentDetailResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **notCompleteAppointment**
> notCompleteAppointment(appointmentId, appointmentProviderNoteRequest)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getAppointmentControllerApi();
final String appointmentId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final AppointmentProviderNoteRequest appointmentProviderNoteRequest = ; // AppointmentProviderNoteRequest | 

try {
    api.notCompleteAppointment(appointmentId, appointmentProviderNoteRequest);
} catch on DioException (e) {
    print('Exception when calling AppointmentControllerApi->notCompleteAppointment: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **appointmentId** | **String**|  | 
 **appointmentProviderNoteRequest** | [**AppointmentProviderNoteRequest**](AppointmentProviderNoteRequest.md)|  | [optional] 

### Return type

void (empty response body)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: Not defined

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **rescheduleAppointment**
> ApiResponseAppointmentDetailResponse rescheduleAppointment(appointmentId, appointmentRescheduleRequest)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getAppointmentControllerApi();
final String appointmentId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final AppointmentRescheduleRequest appointmentRescheduleRequest = ; // AppointmentRescheduleRequest | 

try {
    final response = api.rescheduleAppointment(appointmentId, appointmentRescheduleRequest);
    print(response);
} catch on DioException (e) {
    print('Exception when calling AppointmentControllerApi->rescheduleAppointment: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **appointmentId** | **String**|  | 
 **appointmentRescheduleRequest** | [**AppointmentRescheduleRequest**](AppointmentRescheduleRequest.md)|  | 

### Return type

[**ApiResponseAppointmentDetailResponse**](ApiResponseAppointmentDetailResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **rescheduleAppointmentItem**
> ApiResponseAppointmentDetailResponse rescheduleAppointmentItem(appointmentId, bookingId, appointmentItemRescheduleRequest)

Reschedule one service line of a visit

Moves ONE service line of a multi-service visit to a new time. Siblings keep their windows; the visit may become non-contiguous afterwards (gaps are legal, overlaps are not). Returns the whole enriched visit.

### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getAppointmentControllerApi();
final String appointmentId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final String bookingId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final AppointmentItemRescheduleRequest appointmentItemRescheduleRequest = ; // AppointmentItemRescheduleRequest | 

try {
    final response = api.rescheduleAppointmentItem(appointmentId, bookingId, appointmentItemRescheduleRequest);
    print(response);
} catch on DioException (e) {
    print('Exception when calling AppointmentControllerApi->rescheduleAppointmentItem: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **appointmentId** | **String**|  | 
 **bookingId** | **String**|  | 
 **appointmentItemRescheduleRequest** | [**AppointmentItemRescheduleRequest**](AppointmentItemRescheduleRequest.md)|  | 

### Return type

[**ApiResponseAppointmentDetailResponse**](ApiResponseAppointmentDetailResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

