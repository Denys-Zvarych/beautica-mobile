# beautica_api.api.ProviderClientControllerApi

## Load the API package
```dart
import 'package:beautica_api/api.dart';
```

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**getMyGuestCard**](ProviderClientControllerApi.md#getmyguestcard) | **GET** /api/v1/masters/me/clients/guests/{bookingId} | 
[**getMyGuestRatings**](ProviderClientControllerApi.md#getmyguestratings) | **GET** /api/v1/masters/me/clients/guests/{bookingId}/ratings | 
[**getMyGuestVisits**](ProviderClientControllerApi.md#getmyguestvisits) | **GET** /api/v1/masters/me/clients/guests/{bookingId}/visits | 
[**getMyUserCard**](ProviderClientControllerApi.md#getmyusercard) | **GET** /api/v1/masters/me/clients/users/{userId} | 
[**getMyUserRatings**](ProviderClientControllerApi.md#getmyuserratings) | **GET** /api/v1/masters/me/clients/users/{userId}/ratings | 
[**getMyUserVisits**](ProviderClientControllerApi.md#getmyuservisits) | **GET** /api/v1/masters/me/clients/users/{userId}/visits | 
[**getSalonGuestCard**](ProviderClientControllerApi.md#getsalonguestcard) | **GET** /api/v1/salons/{salonId}/clients/guests/{bookingId} | 
[**getSalonGuestRatings**](ProviderClientControllerApi.md#getsalonguestratings) | **GET** /api/v1/salons/{salonId}/clients/guests/{bookingId}/ratings | 
[**getSalonGuestVisits**](ProviderClientControllerApi.md#getsalonguestvisits) | **GET** /api/v1/salons/{salonId}/clients/guests/{bookingId}/visits | 
[**getSalonUserCard**](ProviderClientControllerApi.md#getsalonusercard) | **GET** /api/v1/salons/{salonId}/clients/users/{userId} | 
[**getSalonUserRatings**](ProviderClientControllerApi.md#getsalonuserratings) | **GET** /api/v1/salons/{salonId}/clients/users/{userId}/ratings | 
[**getSalonUserVisits**](ProviderClientControllerApi.md#getsalonuservisits) | **GET** /api/v1/salons/{salonId}/clients/users/{userId}/visits | 
[**listMyClients**](ProviderClientControllerApi.md#listmyclients) | **GET** /api/v1/masters/me/clients | 
[**listSalonClients**](ProviderClientControllerApi.md#listsalonclients) | **GET** /api/v1/salons/{salonId}/clients | 


# **getMyGuestCard**
> ApiResponseClientCardResponse getMyGuestCard(bookingId)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getProviderClientControllerApi();
final String bookingId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 

try {
    final response = api.getMyGuestCard(bookingId);
    print(response);
} catch on DioException (e) {
    print('Exception when calling ProviderClientControllerApi->getMyGuestCard: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **bookingId** | **String**|  | 

### Return type

[**ApiResponseClientCardResponse**](ApiResponseClientCardResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getMyGuestRatings**
> ApiResponsePageResponseClientOwnRatingResponse getMyGuestRatings(bookingId, pageable)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getProviderClientControllerApi();
final String bookingId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final Pageable pageable = ; // Pageable | 

try {
    final response = api.getMyGuestRatings(bookingId, pageable);
    print(response);
} catch on DioException (e) {
    print('Exception when calling ProviderClientControllerApi->getMyGuestRatings: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **bookingId** | **String**|  | 
 **pageable** | [**Pageable**](.md)|  | 

### Return type

[**ApiResponsePageResponseClientOwnRatingResponse**](ApiResponsePageResponseClientOwnRatingResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getMyGuestVisits**
> ApiResponsePageResponseClientVisitResponse getMyGuestVisits(bookingId, pageable)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getProviderClientControllerApi();
final String bookingId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final Pageable pageable = ; // Pageable | 

try {
    final response = api.getMyGuestVisits(bookingId, pageable);
    print(response);
} catch on DioException (e) {
    print('Exception when calling ProviderClientControllerApi->getMyGuestVisits: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **bookingId** | **String**|  | 
 **pageable** | [**Pageable**](.md)|  | 

### Return type

[**ApiResponsePageResponseClientVisitResponse**](ApiResponsePageResponseClientVisitResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getMyUserCard**
> ApiResponseClientCardResponse getMyUserCard(userId)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getProviderClientControllerApi();
final String userId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 

try {
    final response = api.getMyUserCard(userId);
    print(response);
} catch on DioException (e) {
    print('Exception when calling ProviderClientControllerApi->getMyUserCard: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **userId** | **String**|  | 

### Return type

[**ApiResponseClientCardResponse**](ApiResponseClientCardResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getMyUserRatings**
> ApiResponsePageResponseClientOwnRatingResponse getMyUserRatings(userId, pageable)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getProviderClientControllerApi();
final String userId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final Pageable pageable = ; // Pageable | 

try {
    final response = api.getMyUserRatings(userId, pageable);
    print(response);
} catch on DioException (e) {
    print('Exception when calling ProviderClientControllerApi->getMyUserRatings: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **userId** | **String**|  | 
 **pageable** | [**Pageable**](.md)|  | 

### Return type

[**ApiResponsePageResponseClientOwnRatingResponse**](ApiResponsePageResponseClientOwnRatingResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getMyUserVisits**
> ApiResponsePageResponseClientVisitResponse getMyUserVisits(userId, pageable)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getProviderClientControllerApi();
final String userId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final Pageable pageable = ; // Pageable | 

try {
    final response = api.getMyUserVisits(userId, pageable);
    print(response);
} catch on DioException (e) {
    print('Exception when calling ProviderClientControllerApi->getMyUserVisits: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **userId** | **String**|  | 
 **pageable** | [**Pageable**](.md)|  | 

### Return type

[**ApiResponsePageResponseClientVisitResponse**](ApiResponsePageResponseClientVisitResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getSalonGuestCard**
> ApiResponseClientCardResponse getSalonGuestCard(salonId, bookingId, masterId)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getProviderClientControllerApi();
final String salonId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final String bookingId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final String masterId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 

try {
    final response = api.getSalonGuestCard(salonId, bookingId, masterId);
    print(response);
} catch on DioException (e) {
    print('Exception when calling ProviderClientControllerApi->getSalonGuestCard: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **salonId** | **String**|  | 
 **bookingId** | **String**|  | 
 **masterId** | **String**|  | [optional] 

### Return type

[**ApiResponseClientCardResponse**](ApiResponseClientCardResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getSalonGuestRatings**
> ApiResponsePageResponseClientOwnRatingResponse getSalonGuestRatings(salonId, bookingId, pageable, masterId)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getProviderClientControllerApi();
final String salonId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final String bookingId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final Pageable pageable = ; // Pageable | 
final String masterId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 

try {
    final response = api.getSalonGuestRatings(salonId, bookingId, pageable, masterId);
    print(response);
} catch on DioException (e) {
    print('Exception when calling ProviderClientControllerApi->getSalonGuestRatings: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **salonId** | **String**|  | 
 **bookingId** | **String**|  | 
 **pageable** | [**Pageable**](.md)|  | 
 **masterId** | **String**|  | [optional] 

### Return type

[**ApiResponsePageResponseClientOwnRatingResponse**](ApiResponsePageResponseClientOwnRatingResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getSalonGuestVisits**
> ApiResponsePageResponseClientVisitResponse getSalonGuestVisits(salonId, bookingId, pageable, masterId)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getProviderClientControllerApi();
final String salonId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final String bookingId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final Pageable pageable = ; // Pageable | 
final String masterId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 

try {
    final response = api.getSalonGuestVisits(salonId, bookingId, pageable, masterId);
    print(response);
} catch on DioException (e) {
    print('Exception when calling ProviderClientControllerApi->getSalonGuestVisits: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **salonId** | **String**|  | 
 **bookingId** | **String**|  | 
 **pageable** | [**Pageable**](.md)|  | 
 **masterId** | **String**|  | [optional] 

### Return type

[**ApiResponsePageResponseClientVisitResponse**](ApiResponsePageResponseClientVisitResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getSalonUserCard**
> ApiResponseClientCardResponse getSalonUserCard(salonId, userId, masterId)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getProviderClientControllerApi();
final String salonId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final String userId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final String masterId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 

try {
    final response = api.getSalonUserCard(salonId, userId, masterId);
    print(response);
} catch on DioException (e) {
    print('Exception when calling ProviderClientControllerApi->getSalonUserCard: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **salonId** | **String**|  | 
 **userId** | **String**|  | 
 **masterId** | **String**|  | [optional] 

### Return type

[**ApiResponseClientCardResponse**](ApiResponseClientCardResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getSalonUserRatings**
> ApiResponsePageResponseClientOwnRatingResponse getSalonUserRatings(salonId, userId, pageable, masterId)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getProviderClientControllerApi();
final String salonId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final String userId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final Pageable pageable = ; // Pageable | 
final String masterId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 

try {
    final response = api.getSalonUserRatings(salonId, userId, pageable, masterId);
    print(response);
} catch on DioException (e) {
    print('Exception when calling ProviderClientControllerApi->getSalonUserRatings: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **salonId** | **String**|  | 
 **userId** | **String**|  | 
 **pageable** | [**Pageable**](.md)|  | 
 **masterId** | **String**|  | [optional] 

### Return type

[**ApiResponsePageResponseClientOwnRatingResponse**](ApiResponsePageResponseClientOwnRatingResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getSalonUserVisits**
> ApiResponsePageResponseClientVisitResponse getSalonUserVisits(salonId, userId, pageable, masterId)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getProviderClientControllerApi();
final String salonId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final String userId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final Pageable pageable = ; // Pageable | 
final String masterId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 

try {
    final response = api.getSalonUserVisits(salonId, userId, pageable, masterId);
    print(response);
} catch on DioException (e) {
    print('Exception when calling ProviderClientControllerApi->getSalonUserVisits: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **salonId** | **String**|  | 
 **userId** | **String**|  | 
 **pageable** | [**Pageable**](.md)|  | 
 **masterId** | **String**|  | [optional] 

### Return type

[**ApiResponsePageResponseClientVisitResponse**](ApiResponsePageResponseClientVisitResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **listMyClients**
> ApiResponsePageResponseClientListItemResponse listMyClients(pageable, q)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getProviderClientControllerApi();
final Pageable pageable = ; // Pageable | 
final String q = q_example; // String | 

try {
    final response = api.listMyClients(pageable, q);
    print(response);
} catch on DioException (e) {
    print('Exception when calling ProviderClientControllerApi->listMyClients: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **pageable** | [**Pageable**](.md)|  | 
 **q** | **String**|  | [optional] 

### Return type

[**ApiResponsePageResponseClientListItemResponse**](ApiResponsePageResponseClientListItemResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **listSalonClients**
> ApiResponsePageResponseClientListItemResponse listSalonClients(salonId, pageable, masterId, q)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getProviderClientControllerApi();
final String salonId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final Pageable pageable = ; // Pageable | 
final String masterId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final String q = q_example; // String | 

try {
    final response = api.listSalonClients(salonId, pageable, masterId, q);
    print(response);
} catch on DioException (e) {
    print('Exception when calling ProviderClientControllerApi->listSalonClients: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **salonId** | **String**|  | 
 **pageable** | [**Pageable**](.md)|  | 
 **masterId** | **String**|  | [optional] 
 **q** | **String**|  | [optional] 

### Return type

[**ApiResponsePageResponseClientListItemResponse**](ApiResponsePageResponseClientListItemResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

