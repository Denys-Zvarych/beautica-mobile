# beautica_api.api.BlockControllerApi

## Load the API package
```dart
import 'package:beautica_api/api.dart';
```

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**block**](BlockControllerApi.md#block) | **POST** /api/v1/blocks | Block the client of a booking
[**list**](BlockControllerApi.md#list) | **GET** /api/v1/blocks | List blocked clients
[**unblock**](BlockControllerApi.md#unblock) | **DELETE** /api/v1/blocks/{blockId} | Unblock a client


# **block**
> ApiResponseBlockResponse block(createBlockRequest)

Block the client of a booking

Blocks the client of a booking in the caller's scope: an independent master blocks for themselves, a salon owner/admin for the whole salon. A registered client is blocked by account only, a link guest by the phone verified at booking time; the two are never linked. Silent (the client is not notified) and idempotent: an existing block of the same client in the same scope returns 200. Shares a per-user budget with DELETE (429 with Retry-After).

### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getBlockControllerApi();
final CreateBlockRequest createBlockRequest = ; // CreateBlockRequest | 

try {
    final response = api.block(createBlockRequest);
    print(response);
} catch on DioException (e) {
    print('Exception when calling BlockControllerApi->block: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **createBlockRequest** | [**CreateBlockRequest**](CreateBlockRequest.md)|  | 

### Return type

[**ApiResponseBlockResponse**](ApiResponseBlockResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **list**
> ApiResponseListBlockResponse list()

List blocked clients

The caller's blocks, newest first (salon owner/admin: the salon's). At most 500 rows.

### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getBlockControllerApi();

try {
    final response = api.list();
    print(response);
} catch on DioException (e) {
    print('Exception when calling BlockControllerApi->list: $e\n');
}
```

### Parameters
This endpoint does not need any parameter.

### Return type

[**ApiResponseListBlockResponse**](ApiResponseListBlockResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **unblock**
> unblock(blockId)

Unblock a client

Idempotent: 204 also when the block does not exist or is outside the caller's scope. Shares the per-user budget with POST (429 with Retry-After).

### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getBlockControllerApi();
final String blockId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 

try {
    api.unblock(blockId);
} catch on DioException (e) {
    print('Exception when calling BlockControllerApi->unblock: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **blockId** | **String**|  | 

### Return type

void (empty response body)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: Not defined

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

