# beautica_api.api.NotificationsApi

## Load the API package
```dart
import 'package:beautica_api/api.dart';
```

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**listFeed**](NotificationsApi.md#listfeed) | **GET** /api/v1/notifications | The recipient&#39;s own notification feed, newest first
[**markAllRead**](NotificationsApi.md#markallread) | **PATCH** /api/v1/notifications/read-all | Marks every still-unread item created at or before the given cutoff (default: now) read
[**markRead**](NotificationsApi.md#markread) | **PATCH** /api/v1/notifications/{id}/read | Marks one item read — idempotent; 404 for a missing or foreign id (never 403)
[**unreadCount**](NotificationsApi.md#unreadcount) | **GET** /api/v1/notifications/unread-count | The bell red-dot count, capped at 99


# **listFeed**
> PageResponseNotificationResponse listFeed(page, size)

The recipient's own notification feed, newest first

### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getNotificationsApi();
final int page = 56; // int | 
final int size = 56; // int | 

try {
    final response = api.listFeed(page, size);
    print(response);
} catch on DioException (e) {
    print('Exception when calling NotificationsApi->listFeed: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **page** | **int**|  | [optional] [default to 0]
 **size** | **int**|  | [optional] [default to 20]

### Return type

[**PageResponseNotificationResponse**](PageResponseNotificationResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **markAllRead**
> ApiResponseMarkAllReadResponse markAllRead(markAllReadRequest)

Marks every still-unread item created at or before the given cutoff (default: now) read

### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getNotificationsApi();
final MarkAllReadRequest markAllReadRequest = ; // MarkAllReadRequest | 

try {
    final response = api.markAllRead(markAllReadRequest);
    print(response);
} catch on DioException (e) {
    print('Exception when calling NotificationsApi->markAllRead: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **markAllReadRequest** | [**MarkAllReadRequest**](MarkAllReadRequest.md)|  | [optional] 

### Return type

[**ApiResponseMarkAllReadResponse**](ApiResponseMarkAllReadResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **markRead**
> markRead(id)

Marks one item read — idempotent; 404 for a missing or foreign id (never 403)

### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getNotificationsApi();
final String id = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 

try {
    api.markRead(id);
} catch on DioException (e) {
    print('Exception when calling NotificationsApi->markRead: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **id** | **String**|  | 

### Return type

void (empty response body)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: Not defined

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **unreadCount**
> ApiResponseUnreadCountResponse unreadCount()

The bell red-dot count, capped at 99

### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getNotificationsApi();

try {
    final response = api.unreadCount();
    print(response);
} catch on DioException (e) {
    print('Exception when calling NotificationsApi->unreadCount: $e\n');
}
```

### Parameters
This endpoint does not need any parameter.

### Return type

[**ApiResponseUnreadCountResponse**](ApiResponseUnreadCountResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

