# beautica_api.api.BookingLinksApi

## Load the API package
```dart
import 'package:beautica_api/api.dart';
```

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**getMine**](BookingLinksApi.md#getmine) | **GET** /api/v1/booking-links/mine | My shareable public booking links
[**regenerateMaster**](BookingLinksApi.md#regeneratemaster) | **POST** /api/v1/booking-links/master/regenerate | Regenerate my master booking link
[**regenerateSalon**](BookingLinksApi.md#regeneratesalon) | **POST** /api/v1/booking-links/salons/{salonId}/regenerate | Regenerate a salon booking link
[**revokeMaster**](BookingLinksApi.md#revokemaster) | **DELETE** /api/v1/booking-links/master | Revoke my master booking link
[**revokeSalon**](BookingLinksApi.md#revokesalon) | **DELETE** /api/v1/booking-links/salons/{salonId} | Revoke a salon booking link


# **getMine**
> ApiResponseBookingLinksResponse getMine()

My shareable public booking links

INDEPENDENT_MASTER gets its own MASTER link (https://beautica.app/book/{slug}). SALON_OWNER gets ONLY SALON links (https://beautica.app/book/s/{slug}), one per active owned salon, ordered by salon name, and no personal MASTER link; SALON_ADMIN gets the SALON link of the active salon it is bound to (the same link the owner shares). Inactive salons and inactive master rows yield no link. SALON_MASTER gets no links. A legacy master's or salon's slug is issued on the first call and never changes, not even on rename. bookable reports whether the public page can take a booking today (for a salon: at least one bookable master). When sharing is switched off server-side, shareEnabled is false and links is empty. 409 when a slug issue cannot acquire its lock in time (retry).

### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getBookingLinksApi();

try {
    final response = api.getMine();
    print(response);
} catch on DioException (e) {
    print('Exception when calling BookingLinksApi->getMine: $e\n');
}
```

### Parameters
This endpoint does not need any parameter.

### Return type

[**ApiResponseBookingLinksResponse**](ApiResponseBookingLinksResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **regenerateMaster**
> ApiResponseBookingLinkResponse regenerateMaster(bookingLinkMutationRequest)

Regenerate my master booking link

INDEPENDENT_MASTER only. Retires the current slug (if any) and issues a new one; from a REVOKED link this creates a new active link. Body: {\"currentSlug\": \"<the slug the app shows>\"} or {\"currentSlug\": null} when the link is REVOKED (optimistic concurrency). The retired slug is never issued to anyone again. 404 when sharing is switched off server-side or the master / salon is not active; 409 when currentSlug is stale (refresh and retry) or no unique slug could be allocated; 429 after 10 regenerate/revoke calls per user per hour (all four routes share the budget).

### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getBookingLinksApi();
final BookingLinkMutationRequest bookingLinkMutationRequest = ; // BookingLinkMutationRequest | 

try {
    final response = api.regenerateMaster(bookingLinkMutationRequest);
    print(response);
} catch on DioException (e) {
    print('Exception when calling BookingLinksApi->regenerateMaster: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **bookingLinkMutationRequest** | [**BookingLinkMutationRequest**](BookingLinkMutationRequest.md)|  | 

### Return type

[**ApiResponseBookingLinkResponse**](ApiResponseBookingLinkResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **regenerateSalon**
> ApiResponseBookingLinkResponse regenerateSalon(salonId, bookingLinkMutationRequest)

Regenerate a salon booking link

SALON_OWNER of the salon (any salon they own) or the SALON_ADMIN bound to it; any other salon → 403. Retires the current slug (if any) and issues a new one. Body: {\"currentSlug\": \"<the slug the app shows>\"} or {\"currentSlug\": null} when the link is REVOKED (optimistic concurrency). The retired slug is never issued to anyone again. 404 when sharing is switched off server-side or the master / salon is not active; 409 when currentSlug is stale (refresh and retry) or no unique slug could be allocated; 429 after 10 regenerate/revoke calls per user per hour (all four routes share the budget).

### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getBookingLinksApi();
final String salonId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final BookingLinkMutationRequest bookingLinkMutationRequest = ; // BookingLinkMutationRequest | 

try {
    final response = api.regenerateSalon(salonId, bookingLinkMutationRequest);
    print(response);
} catch on DioException (e) {
    print('Exception when calling BookingLinksApi->regenerateSalon: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **salonId** | **String**|  | 
 **bookingLinkMutationRequest** | [**BookingLinkMutationRequest**](BookingLinkMutationRequest.md)|  | 

### Return type

[**ApiResponseBookingLinkResponse**](ApiResponseBookingLinkResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **revokeMaster**
> ApiResponseBookingLinkResponse revokeMaster(bookingLinkMutationRequest)

Revoke my master booking link

INDEPENDENT_MASTER only. Switches the link off: the slug is retired, GET /mine shows status REVOKED and never re-issues it. Idempotent when already revoked (currentSlug null). Body: {\"currentSlug\": \"<the slug the app shows>\"} or {\"currentSlug\": null} when the link is REVOKED (optimistic concurrency). The retired slug is never issued to anyone again. 404 when sharing is switched off server-side or the master / salon is not active; 409 when currentSlug is stale (refresh and retry) or no unique slug could be allocated; 429 after 10 regenerate/revoke calls per user per hour (all four routes share the budget).

### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getBookingLinksApi();
final BookingLinkMutationRequest bookingLinkMutationRequest = ; // BookingLinkMutationRequest | 

try {
    final response = api.revokeMaster(bookingLinkMutationRequest);
    print(response);
} catch on DioException (e) {
    print('Exception when calling BookingLinksApi->revokeMaster: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **bookingLinkMutationRequest** | [**BookingLinkMutationRequest**](BookingLinkMutationRequest.md)|  | 

### Return type

[**ApiResponseBookingLinkResponse**](ApiResponseBookingLinkResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **revokeSalon**
> ApiResponseBookingLinkResponse revokeSalon(salonId, bookingLinkMutationRequest)

Revoke a salon booking link

SALON_OWNER of the salon or the SALON_ADMIN bound to it; any other salon → 403. Switches the salon link off (status REVOKED, never re-issued by GET /mine). Idempotent when already revoked (currentSlug null). Body: {\"currentSlug\": \"<the slug the app shows>\"} or {\"currentSlug\": null} when the link is REVOKED (optimistic concurrency). The retired slug is never issued to anyone again. 404 when sharing is switched off server-side or the master / salon is not active; 409 when currentSlug is stale (refresh and retry) or no unique slug could be allocated; 429 after 10 regenerate/revoke calls per user per hour (all four routes share the budget).

### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getBookingLinksApi();
final String salonId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final BookingLinkMutationRequest bookingLinkMutationRequest = ; // BookingLinkMutationRequest | 

try {
    final response = api.revokeSalon(salonId, bookingLinkMutationRequest);
    print(response);
} catch on DioException (e) {
    print('Exception when calling BookingLinksApi->revokeSalon: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **salonId** | **String**|  | 
 **bookingLinkMutationRequest** | [**BookingLinkMutationRequest**](BookingLinkMutationRequest.md)|  | 

### Return type

[**ApiResponseBookingLinkResponse**](ApiResponseBookingLinkResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

