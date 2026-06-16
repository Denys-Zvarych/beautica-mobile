# beautica_api.api.MediaControllerApi

## Load the API package
```dart
import 'package:beautica_api/api.dart';
```

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**deleteAvatar**](MediaControllerApi.md#deleteavatar) | **DELETE** /api/v1/media/avatar | 
[**deletePortfolioPhoto**](MediaControllerApi.md#deleteportfoliophoto) | **DELETE** /api/v1/media/portfolio/{mediaId} | 
[**getMasterPortfolio**](MediaControllerApi.md#getmasterportfolio) | **GET** /api/v1/masters/{masterId}/portfolio | 
[**getSalonPortfolio**](MediaControllerApi.md#getsalonportfolio) | **GET** /api/v1/salons/{salonId}/portfolio | 
[**uploadAvatar**](MediaControllerApi.md#uploadavatar) | **POST** /api/v1/media/avatar | 
[**uploadPortfolioPhoto**](MediaControllerApi.md#uploadportfoliophoto) | **POST** /api/v1/media/portfolio | 


# **deleteAvatar**
> deleteAvatar()



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getMediaControllerApi();

try {
    api.deleteAvatar();
} catch on DioException (e) {
    print('Exception when calling MediaControllerApi->deleteAvatar: $e\n');
}
```

### Parameters
This endpoint does not need any parameter.

### Return type

void (empty response body)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: Not defined

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **deletePortfolioPhoto**
> deletePortfolioPhoto(mediaId)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getMediaControllerApi();
final String mediaId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 

try {
    api.deletePortfolioPhoto(mediaId);
} catch on DioException (e) {
    print('Exception when calling MediaControllerApi->deletePortfolioPhoto: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **mediaId** | **String**|  | 

### Return type

void (empty response body)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: Not defined

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getMasterPortfolio**
> ApiResponsePageMediaFileResponse getMasterPortfolio(masterId)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getMediaControllerApi();
final String masterId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 

try {
    final response = api.getMasterPortfolio(masterId);
    print(response);
} catch on DioException (e) {
    print('Exception when calling MediaControllerApi->getMasterPortfolio: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **masterId** | **String**|  | 

### Return type

[**ApiResponsePageMediaFileResponse**](ApiResponsePageMediaFileResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getSalonPortfolio**
> ApiResponsePageMediaFileResponse getSalonPortfolio(salonId)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getMediaControllerApi();
final String salonId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 

try {
    final response = api.getSalonPortfolio(salonId);
    print(response);
} catch on DioException (e) {
    print('Exception when calling MediaControllerApi->getSalonPortfolio: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **salonId** | **String**|  | 

### Return type

[**ApiResponsePageMediaFileResponse**](ApiResponsePageMediaFileResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **uploadAvatar**
> ApiResponseAvatarResponse uploadAvatar(uploadPortfolioPhotoRequest)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getMediaControllerApi();
final UploadPortfolioPhotoRequest uploadPortfolioPhotoRequest = ; // UploadPortfolioPhotoRequest | 

try {
    final response = api.uploadAvatar(uploadPortfolioPhotoRequest);
    print(response);
} catch on DioException (e) {
    print('Exception when calling MediaControllerApi->uploadAvatar: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **uploadPortfolioPhotoRequest** | [**UploadPortfolioPhotoRequest**](UploadPortfolioPhotoRequest.md)|  | [optional] 

### Return type

[**ApiResponseAvatarResponse**](ApiResponseAvatarResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **uploadPortfolioPhoto**
> ApiResponseMediaFileResponse uploadPortfolioPhoto(uploadPortfolioPhotoRequest)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getMediaControllerApi();
final UploadPortfolioPhotoRequest uploadPortfolioPhotoRequest = ; // UploadPortfolioPhotoRequest | 

try {
    final response = api.uploadPortfolioPhoto(uploadPortfolioPhotoRequest);
    print(response);
} catch on DioException (e) {
    print('Exception when calling MediaControllerApi->uploadPortfolioPhoto: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **uploadPortfolioPhotoRequest** | [**UploadPortfolioPhotoRequest**](UploadPortfolioPhotoRequest.md)|  | [optional] 

### Return type

[**ApiResponseMediaFileResponse**](ApiResponseMediaFileResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

