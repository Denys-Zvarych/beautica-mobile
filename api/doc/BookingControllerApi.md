# beautica_api.api.BookingControllerApi

## Load the API package
```dart
import 'package:beautica_api/api.dart';
```

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**cancelBooking**](BookingControllerApi.md#cancelbooking) | **PATCH** /api/v1/bookings/{bookingId}/cancel | 
[**completeBooking**](BookingControllerApi.md#completebooking) | **PATCH** /api/v1/bookings/{bookingId}/complete | 
[**createBooking**](BookingControllerApi.md#createbooking) | **POST** /api/v1/bookings | 
[**declineBooking**](BookingControllerApi.md#declinebooking) | **PATCH** /api/v1/bookings/{bookingId}/decline | 
[**getBooking**](BookingControllerApi.md#getbooking) | **GET** /api/v1/bookings/{bookingId} | 
[**getSalonBookings**](BookingControllerApi.md#getsalonbookings) | **GET** /api/v1/bookings/salon/{salonId} | List salon bookings (owner/admin)
[**getUnclosedCount**](BookingControllerApi.md#getunclosedcount) | **GET** /api/v1/bookings/me/unclosed-count | 
[**listMyBookedDays**](BookingControllerApi.md#listmybookeddays) | **GET** /api/v1/bookings/me/booked-days | 
[**listMyBookings**](BookingControllerApi.md#listmybookings) | **GET** /api/v1/bookings/me | 
[**notCompleteBooking**](BookingControllerApi.md#notcompletebooking) | **PATCH** /api/v1/bookings/{bookingId}/not-complete | 
[**rescheduleBooking**](BookingControllerApi.md#reschedulebooking) | **PATCH** /api/v1/bookings/{bookingId}/reschedule | 


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

No authorization required

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

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: Not defined

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **createBooking**
> ApiResponseBookingDetailResponse createBooking(createBookingRequest, idempotencyKey)



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

[**ApiResponseBookingDetailResponse**](ApiResponseBookingDetailResponse.md)

### Authorization

No authorization required

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

No authorization required

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

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getSalonBookings**
> ApiResponsePageResponseBookingDetailResponse getSalonBookings(salonId, pageable, masterId, status, from, to)

List salon bookings (owner/admin)

### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getBookingControllerApi();
final String salonId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final Pageable pageable = ; // Pageable | 
final String masterId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | Filter to one master's bookings within the salon. Omit for every master.
final String status = status_example; // String | Filter by a single status. Omit for no status predicate.
final Date from = 2013-10-20; // Date | Bookings starting on/after the start of this local day (Europe/Kyiv). Omit for an open-ended future window.
final Date to = 2013-10-20; // Date | Bookings starting on/before the end of this local day (Europe/Kyiv), inclusive. Omit for an open-ended past window.

try {
    final response = api.getSalonBookings(salonId, pageable, masterId, status, from, to);
    print(response);
} catch on DioException (e) {
    print('Exception when calling BookingControllerApi->getSalonBookings: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **salonId** | **String**|  | 
 **pageable** | [**Pageable**](.md)|  | 
 **masterId** | **String**| Filter to one master's bookings within the salon. Omit for every master. | [optional] 
 **status** | **String**| Filter by a single status. Omit for no status predicate. | [optional] 
 **from** | **Date**| Bookings starting on/after the start of this local day (Europe/Kyiv). Omit for an open-ended future window. | [optional] 
 **to** | **Date**| Bookings starting on/before the end of this local day (Europe/Kyiv), inclusive. Omit for an open-ended past window. | [optional] 

### Return type

[**ApiResponsePageResponseBookingDetailResponse**](ApiResponsePageResponseBookingDetailResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getUnclosedCount**
> ApiResponseUnclosedCountResponse getUnclosedCount()



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getBookingControllerApi();

try {
    final response = api.getUnclosedCount();
    print(response);
} catch on DioException (e) {
    print('Exception when calling BookingControllerApi->getUnclosedCount: $e\n');
}
```

### Parameters
This endpoint does not need any parameter.

### Return type

[**ApiResponseUnclosedCountResponse**](ApiResponseUnclosedCountResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **listMyBookedDays**
> ApiResponseListLocalDate listMyBookedDays(from, to)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getBookingControllerApi();
final Date from = 2013-10-20; // Date | Range start (inclusive), local Europe/Kyiv day. Required.
final Date to = 2013-10-20; // Date | Range end (inclusive), local Europe/Kyiv day. Required.

try {
    final response = api.listMyBookedDays(from, to);
    print(response);
} catch on DioException (e) {
    print('Exception when calling BookingControllerApi->listMyBookedDays: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **from** | **Date**| Range start (inclusive), local Europe/Kyiv day. Required. | 
 **to** | **Date**| Range end (inclusive), local Europe/Kyiv day. Required. | 

### Return type

[**ApiResponseListLocalDate**](ApiResponseListLocalDate.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **listMyBookings**
> ApiResponsePageResponseBookingDetailResponse listMyBookings(pageable, status, from, to, serviceId, partition)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getBookingControllerApi();
final Pageable pageable = ; // Pageable | 
final BuiltList<String> status = ; // BuiltList<String> | Repeatable status filter, e.g. ?status=CONFIRMED&status=DECLINED. Omit for no status predicate. IGNORED whenever `partition` is present — see that parameter's doc for the precedence rule.
final Date from = 2013-10-20; // Date | Bookings starting on/after the start of this local day (Europe/Kyiv). Omit for an open-ended future window.
final Date to = 2013-10-20; // Date | Bookings starting on/before the end of this local day (Europe/Kyiv), inclusive. Omit for an open-ended past window.
final BuiltList<String> serviceId = ; // BuiltList<String> | Repeatable MasterService id filter, e.g. ?serviceId=<A>&serviceId=<B>. Omit for no service predicate.
final String partition = partition_example; // String | Time-based partition: UPCOMING (status=CONFIRMED and not yet elapsed), PAST (COMPLETED/NOT_COMPLETED, or an elapsed unclosed CONFIRMED), or CANCELLED (CANCELLED/DECLINED) — a total, disjoint cover of every booking status. AWAITING_CLOSURE is a named subset of PAST (an elapsed unclosed CONFIRMED booking only). HISTORY is a union view spanning PAST and CANCELLED, i.e. every booking EXCEPT UPCOMING, in one correctly-paginated request — use it for an \"archive\"/history list that must include cancelled and declined bookings alongside finished ones. When present, `status` is IGNORED — NOT a 400 — this is the additive rollout safety valve: a client sending both params degrades cleanly to the pre-partition `status`-only behaviour against a backend that does not yet know `partition`. Omit for byte-identical pre-Phase-28 behaviour.

try {
    final response = api.listMyBookings(pageable, status, from, to, serviceId, partition);
    print(response);
} catch on DioException (e) {
    print('Exception when calling BookingControllerApi->listMyBookings: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **pageable** | [**Pageable**](.md)|  | 
 **status** | [**BuiltList&lt;String&gt;**](String.md)| Repeatable status filter, e.g. ?status=CONFIRMED&status=DECLINED. Omit for no status predicate. IGNORED whenever `partition` is present — see that parameter's doc for the precedence rule. | [optional] 
 **from** | **Date**| Bookings starting on/after the start of this local day (Europe/Kyiv). Omit for an open-ended future window. | [optional] 
 **to** | **Date**| Bookings starting on/before the end of this local day (Europe/Kyiv), inclusive. Omit for an open-ended past window. | [optional] 
 **serviceId** | [**BuiltList&lt;String&gt;**](String.md)| Repeatable MasterService id filter, e.g. ?serviceId=<A>&serviceId=<B>. Omit for no service predicate. | [optional] 
 **partition** | **String**| Time-based partition: UPCOMING (status=CONFIRMED and not yet elapsed), PAST (COMPLETED/NOT_COMPLETED, or an elapsed unclosed CONFIRMED), or CANCELLED (CANCELLED/DECLINED) — a total, disjoint cover of every booking status. AWAITING_CLOSURE is a named subset of PAST (an elapsed unclosed CONFIRMED booking only). HISTORY is a union view spanning PAST and CANCELLED, i.e. every booking EXCEPT UPCOMING, in one correctly-paginated request — use it for an \"archive\"/history list that must include cancelled and declined bookings alongside finished ones. When present, `status` is IGNORED — NOT a 400 — this is the additive rollout safety valve: a client sending both params degrades cleanly to the pre-partition `status`-only behaviour against a backend that does not yet know `partition`. Omit for byte-identical pre-Phase-28 behaviour. | [optional] 

### Return type

[**ApiResponsePageResponseBookingDetailResponse**](ApiResponsePageResponseBookingDetailResponse.md)

### Authorization

No authorization required

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

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: Not defined

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **rescheduleBooking**
> ApiResponseBookingDetailResponse rescheduleBooking(bookingId, rescheduleBookingRequest)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getBookingControllerApi();
final String bookingId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final RescheduleBookingRequest rescheduleBookingRequest = ; // RescheduleBookingRequest | 

try {
    final response = api.rescheduleBooking(bookingId, rescheduleBookingRequest);
    print(response);
} catch on DioException (e) {
    print('Exception when calling BookingControllerApi->rescheduleBooking: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **bookingId** | **String**|  | 
 **rescheduleBookingRequest** | [**RescheduleBookingRequest**](RescheduleBookingRequest.md)|  | 

### Return type

[**ApiResponseBookingDetailResponse**](ApiResponseBookingDetailResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

