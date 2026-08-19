# beautica_api.api.StaffBookingsApi

## Load the API package
```dart
import 'package:beautica_api/api.dart';
```

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**createStaffBooking**](StaffBookingsApi.md#createstaffbooking) | **POST** /api/v1/masters/{masterId}/bookings | Create a walk-in booking on a master&#39;s calendar


# **createStaffBooking**
> ApiResponseBookingResponse createStaffBooking(masterId, createStaffBookingRequest)

Create a walk-in booking on a master's calendar

Salon owners and admins may book any master of the salon they manage; an independent master may book only themselves. The salon the booking is scoped to is derived from the caller, never from the request. The booking is created CONFIRMED with source STAFF, no cancel token, and created_by_user_id set to the caller. The guest phone is normalised to E.164 server-side; non-Ukrainian numbers are rejected.  A confirmation SMS is dispatched to that phone number after the booking is committed, subject to the platform-wide app.booking.sms.enabled switch. Delivery is best-effort: it never changes the response, and no field here reports whether a message was sent. No push or email notification is sent by this endpoint.

### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getStaffBookingsApi();
final String masterId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final CreateStaffBookingRequest createStaffBookingRequest = ; // CreateStaffBookingRequest | 

try {
    final response = api.createStaffBooking(masterId, createStaffBookingRequest);
    print(response);
} catch on DioException (e) {
    print('Exception when calling StaffBookingsApi->createStaffBooking: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **masterId** | **String**|  | 
 **createStaffBookingRequest** | [**CreateStaffBookingRequest**](CreateStaffBookingRequest.md)|  | 

### Return type

[**ApiResponseBookingResponse**](ApiResponseBookingResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

