# beautica_api.api.PublicSalonBookingControllerApi

## Load the API package
```dart
import 'package:beautica_api/api.dart';
```

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**availability1**](PublicSalonBookingControllerApi.md#availability1) | **GET** /api/v1/book/s/{slug}/masters/{masterId}/availability | 
[**book1**](PublicSalonBookingControllerApi.md#book1) | **POST** /api/v1/book/s/{slug}/masters/{masterId}/booking | 
[**bookableDays1**](PublicSalonBookingControllerApi.md#bookabledays1) | **GET** /api/v1/book/s/{slug}/masters/{masterId}/bookable-days | 


# **availability1**
> BuiltList<AvailableSlotResponse> availability1(slug, masterId, date, serviceId)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getPublicSalonBookingControllerApi();
final String slug = slug_example; // String | 
final String masterId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final Date date = 2013-10-20; // Date | 
final BuiltList<String> serviceId = ; // BuiltList<String> | 

try {
    final response = api.availability1(slug, masterId, date, serviceId);
    print(response);
} catch on DioException (e) {
    print('Exception when calling PublicSalonBookingControllerApi->availability1: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **slug** | **String**|  | 
 **masterId** | **String**|  | 
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

# **book1**
> GuestBookingResponse book1(slug, masterId, guestBookingRequest, authorization)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getPublicSalonBookingControllerApi();
final String slug = slug_example; // String | 
final String masterId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final GuestBookingRequest guestBookingRequest = ; // GuestBookingRequest | 
final String authorization = authorization_example; // String | 

try {
    final response = api.book1(slug, masterId, guestBookingRequest, authorization);
    print(response);
} catch on DioException (e) {
    print('Exception when calling PublicSalonBookingControllerApi->book1: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **slug** | **String**|  | 
 **masterId** | **String**|  | 
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

# **bookableDays1**
> BuiltList<MasterWorkingDayResponse> bookableDays1(slug, masterId, from, to, serviceId)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getPublicSalonBookingControllerApi();
final String slug = slug_example; // String | 
final String masterId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final Date from = 2013-10-20; // Date | 
final Date to = 2013-10-20; // Date | 
final BuiltList<String> serviceId = ; // BuiltList<String> | 

try {
    final response = api.bookableDays1(slug, masterId, from, to, serviceId);
    print(response);
} catch on DioException (e) {
    print('Exception when calling PublicSalonBookingControllerApi->bookableDays1: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **slug** | **String**|  | 
 **masterId** | **String**|  | 
 **from** | **Date**|  | 
 **to** | **Date**|  | 
 **serviceId** | [**BuiltList&lt;String&gt;**](String.md)|  | 

### Return type

[**BuiltList&lt;MasterWorkingDayResponse&gt;**](MasterWorkingDayResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

