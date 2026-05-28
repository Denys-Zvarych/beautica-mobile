# beautica_api.api.DeviceControllerApi

## Load the API package
```dart
import 'package:beautica_api/api.dart';
```

All URIs are relative to *http://localhost:8080/api/v1*

Method | HTTP request | Description
------------- | ------------- | -------------
[**registerToken**](DeviceControllerApi.md#registertoken) | **POST** /devices/token | 
[**unregisterToken**](DeviceControllerApi.md#unregistertoken) | **DELETE** /devices/token | 


# **registerToken**
> registerToken(registerDeviceTokenRequest)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getDeviceControllerApi();
final RegisterDeviceTokenRequest registerDeviceTokenRequest = ; // RegisterDeviceTokenRequest | 

try {
    api.registerToken(registerDeviceTokenRequest);
} catch on DioException (e) {
    print('Exception when calling DeviceControllerApi->registerToken: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **registerDeviceTokenRequest** | [**RegisterDeviceTokenRequest**](RegisterDeviceTokenRequest.md)|  | 

### Return type

void (empty response body)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: Not defined

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **unregisterToken**
> unregisterToken(unregisterDeviceTokenRequest)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getDeviceControllerApi();
final UnregisterDeviceTokenRequest unregisterDeviceTokenRequest = ; // UnregisterDeviceTokenRequest | 

try {
    api.unregisterToken(unregisterDeviceTokenRequest);
} catch on DioException (e) {
    print('Exception when calling DeviceControllerApi->unregisterToken: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **unregisterDeviceTokenRequest** | [**UnregisterDeviceTokenRequest**](UnregisterDeviceTokenRequest.md)|  | 

### Return type

void (empty response body)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: Not defined

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

