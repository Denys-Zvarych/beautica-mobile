# beautica_api.api.BookingLinksApi

## Load the API package
```dart
import 'package:beautica_api/api.dart';
```

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**getMine**](BookingLinksApi.md#getmine) | **GET** /api/v1/booking-links/mine | My shareable public booking links


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

