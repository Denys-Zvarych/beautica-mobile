# beautica_api.api.SalonMediaControllerApi

## Load the API package
```dart
import 'package:beautica_api/api.dart';
```

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**deleteSalonImage**](SalonMediaControllerApi.md#deletesalonimage) | **DELETE** /api/v1/salons/{salonId}/media/{slot} | Remove the salon logo or cover (SALON_OWNER of this salon only)
[**uploadSalonImage**](SalonMediaControllerApi.md#uploadsalonimage) | **POST** /api/v1/salons/{salonId}/media/{slot} | Upload or replace the salon logo or cover (SALON_OWNER of this salon only)


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

