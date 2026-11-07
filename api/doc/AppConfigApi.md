# beautica_api.api.AppConfigApi

## Load the API package
```dart
import 'package:beautica_api/api.dart';
```

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**getConfig**](AppConfigApi.md#getconfig) | **GET** /api/v1/app/config | Minimum and latest supported app builds


# **getConfig**
> ApiResponseAppConfigResponse getConfig()

Minimum and latest supported app builds

Public. Compare against the Android versionCode (pubspec +N), never the semver string.

### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getAppConfigApi();

try {
    final response = api.getConfig();
    print(response);
} catch on DioException (e) {
    print('Exception when calling AppConfigApi->getConfig: $e\n');
}
```

### Parameters
This endpoint does not need any parameter.

### Return type

[**ApiResponseAppConfigResponse**](ApiResponseAppConfigResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

