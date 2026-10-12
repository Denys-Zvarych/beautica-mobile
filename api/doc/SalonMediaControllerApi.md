# beautica_api.api.SalonMediaControllerApi

## Load the API package
```dart
import 'package:beautica_api/api.dart';
```

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**deleteSalonImage**](SalonMediaControllerApi.md#deletesalonimage) | **DELETE** /api/v1/salons/{salonId}/media/{slot} | Remove the salon logo or cover (SALON_OWNER of this salon only)
[**deleteSalonPortfolioPhoto**](SalonMediaControllerApi.md#deletesalonportfoliophoto) | **DELETE** /api/v1/salons/{salonId}/portfolio/{mediaId} | Remove a photo from the salon portfolio (SALON_OWNER or the salon&#39;s SALON_ADMIN)
[**uploadSalonImage**](SalonMediaControllerApi.md#uploadsalonimage) | **POST** /api/v1/salons/{salonId}/media/{slot} | Upload or replace the salon logo or cover (SALON_OWNER of this salon only)
[**uploadSalonPortfolioPhoto**](SalonMediaControllerApi.md#uploadsalonportfoliophoto) | **POST** /api/v1/salons/{salonId}/portfolio | Add a photo to the salon portfolio (SALON_OWNER or the salon&#39;s SALON_ADMIN)


# **deleteSalonImage**
> deleteSalonImage(salonId, slot)

Remove the salon logo or cover (SALON_OWNER of this salon only)

Idempotent: 204 even when the slot is already empty.

### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getSalonMediaControllerApi();
final String salonId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final String slot = slot_example; // String | 

try {
    api.deleteSalonImage(salonId, slot);
} catch on DioException (e) {
    print('Exception when calling SalonMediaControllerApi->deleteSalonImage: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **salonId** | **String**|  | 
 **slot** | **String**|  | 

### Return type

void (empty response body)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: Not defined

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **deleteSalonPortfolioPhoto**
> deleteSalonPortfolioPhoto(salonId, mediaId)

Remove a photo from the salon portfolio (SALON_OWNER or the salon's SALON_ADMIN)

Any manager of the salon may remove any of its photos, whoever uploaded it.

### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getSalonMediaControllerApi();
final String salonId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final String mediaId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 

try {
    api.deleteSalonPortfolioPhoto(salonId, mediaId);
} catch on DioException (e) {
    print('Exception when calling SalonMediaControllerApi->deleteSalonPortfolioPhoto: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **salonId** | **String**|  | 
 **mediaId** | **String**|  | 

### Return type

void (empty response body)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: Not defined

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **uploadSalonImage**
> ApiResponseSalonResponse uploadSalonImage(salonId, slot, file)

Upload or replace the salon logo or cover (SALON_OWNER of this salon only)

Multipart field `file`: JPEG, PNG or WebP (detected by magic bytes), max 5 MB. `slot` is `logo` (1:1) or `cover` (16:9). Returns the updated salon.

### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getSalonMediaControllerApi();
final String salonId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final String slot = slot_example; // String | 
final MultipartFile file = BINARY_DATA_HERE; // MultipartFile | 

try {
    final response = api.uploadSalonImage(salonId, slot, file);
    print(response);
} catch on DioException (e) {
    print('Exception when calling SalonMediaControllerApi->uploadSalonImage: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **salonId** | **String**|  | 
 **slot** | **String**|  | 
 **file** | **MultipartFile**|  | 

### Return type

[**ApiResponseSalonResponse**](ApiResponseSalonResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: multipart/form-data
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **uploadSalonPortfolioPhoto**
> ApiResponseMediaFileResponse uploadSalonPortfolioPhoto(salonId, file)

Add a photo to the salon portfolio (SALON_OWNER or the salon's SALON_ADMIN)

Multipart field `file`: JPEG, PNG or WebP (detected by magic bytes), max 5 MB. A portfolio holds at most 30 photos; the next upload is rejected with 409 (`data.code` = `PORTFOLIO_LIMIT_REACHED`).

### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getSalonMediaControllerApi();
final String salonId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final MultipartFile file = BINARY_DATA_HERE; // MultipartFile | 

try {
    final response = api.uploadSalonPortfolioPhoto(salonId, file);
    print(response);
} catch on DioException (e) {
    print('Exception when calling SalonMediaControllerApi->uploadSalonPortfolioPhoto: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **salonId** | **String**|  | 
 **file** | **MultipartFile**|  | 

### Return type

[**ApiResponseMediaFileResponse**](ApiResponseMediaFileResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: multipart/form-data
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

