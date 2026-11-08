# beautica_api.api.GuestTelegramLinkControllerApi

## Load the API package
```dart
import 'package:beautica_api/api.dart';
```

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**linkToken**](GuestTelegramLinkControllerApi.md#linktoken) | **POST** /api/v1/book/telegram/link-token | 
[**status**](GuestTelegramLinkControllerApi.md#status) | **POST** /api/v1/book/telegram/status | 
[**unlink**](GuestTelegramLinkControllerApi.md#unlink) | **POST** /api/v1/book/telegram/unlink | 


# **linkToken**
> GuestTelegramLinkResponse linkToken(guestTelegramTokenRequest)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getGuestTelegramLinkControllerApi();
final GuestTelegramTokenRequest guestTelegramTokenRequest = ; // GuestTelegramTokenRequest | 

try {
    final response = api.linkToken(guestTelegramTokenRequest);
    print(response);
} catch on DioException (e) {
    print('Exception when calling GuestTelegramLinkControllerApi->linkToken: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **guestTelegramTokenRequest** | [**GuestTelegramTokenRequest**](GuestTelegramTokenRequest.md)|  | 

### Return type

[**GuestTelegramLinkResponse**](GuestTelegramLinkResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **status**
> GuestTelegramStatusResponse status(guestTelegramTokenRequest)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getGuestTelegramLinkControllerApi();
final GuestTelegramTokenRequest guestTelegramTokenRequest = ; // GuestTelegramTokenRequest | 

try {
    final response = api.status(guestTelegramTokenRequest);
    print(response);
} catch on DioException (e) {
    print('Exception when calling GuestTelegramLinkControllerApi->status: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **guestTelegramTokenRequest** | [**GuestTelegramTokenRequest**](GuestTelegramTokenRequest.md)|  | 

### Return type

[**GuestTelegramStatusResponse**](GuestTelegramStatusResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **unlink**
> unlink(guestTelegramTokenRequest)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getGuestTelegramLinkControllerApi();
final GuestTelegramTokenRequest guestTelegramTokenRequest = ; // GuestTelegramTokenRequest | 

try {
    api.unlink(guestTelegramTokenRequest);
} catch on DioException (e) {
    print('Exception when calling GuestTelegramLinkControllerApi->unlink: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **guestTelegramTokenRequest** | [**GuestTelegramTokenRequest**](GuestTelegramTokenRequest.md)|  | 

### Return type

void (empty response body)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: Not defined

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

