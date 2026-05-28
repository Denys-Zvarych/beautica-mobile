# beautica_api.api.SalonControllerApi

## Load the API package
```dart
import 'package:beautica_api/api.dart';
```

All URIs are relative to *http://localhost:8080/api/v1*

Method | HTTP request | Description
------------- | ------------- | -------------
[**createSalon**](SalonControllerApi.md#createsalon) | **POST** /salons | 
[**deactivateSalon**](SalonControllerApi.md#deactivatesalon) | **DELETE** /salons/{salonId} | 
[**getMastersBySalon**](SalonControllerApi.md#getmastersbysalon) | **GET** /salons/{salonId}/masters | 
[**getOwnedSalons**](SalonControllerApi.md#getownedsalons) | **GET** /salons/mine | 
[**getSalon**](SalonControllerApi.md#getsalon) | **GET** /salons/{salonId} | 
[**inviteMaster**](SalonControllerApi.md#invitemaster) | **POST** /salons/{salonId}/invite | 
[**updateSalon**](SalonControllerApi.md#updatesalon) | **PATCH** /salons/{salonId} | 


# **createSalon**
> ApiResponseSalonResponse createSalon(createSalonRequest)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getSalonControllerApi();
final CreateSalonRequest createSalonRequest = ; // CreateSalonRequest | 

try {
    final response = api.createSalon(createSalonRequest);
    print(response);
} catch on DioException (e) {
    print('Exception when calling SalonControllerApi->createSalon: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **createSalonRequest** | [**CreateSalonRequest**](CreateSalonRequest.md)|  | 

### Return type

[**ApiResponseSalonResponse**](ApiResponseSalonResponse.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **deactivateSalon**
> deactivateSalon(salonId)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getSalonControllerApi();
final String salonId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 

try {
    api.deactivateSalon(salonId);
} catch on DioException (e) {
    print('Exception when calling SalonControllerApi->deactivateSalon: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **salonId** | **String**|  | 

### Return type

void (empty response body)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: Not defined

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getMastersBySalon**
> ApiResponsePageResponseMasterSummaryResponse getMastersBySalon(salonId, pageable)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getSalonControllerApi();
final String salonId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final Pageable pageable = ; // Pageable | 

try {
    final response = api.getMastersBySalon(salonId, pageable);
    print(response);
} catch on DioException (e) {
    print('Exception when calling SalonControllerApi->getMastersBySalon: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **salonId** | **String**|  | 
 **pageable** | [**Pageable**](.md)|  | 

### Return type

[**ApiResponsePageResponseMasterSummaryResponse**](ApiResponsePageResponseMasterSummaryResponse.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getOwnedSalons**
> ApiResponseListSalonResponse getOwnedSalons()



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getSalonControllerApi();

try {
    final response = api.getOwnedSalons();
    print(response);
} catch on DioException (e) {
    print('Exception when calling SalonControllerApi->getOwnedSalons: $e\n');
}
```

### Parameters
This endpoint does not need any parameter.

### Return type

[**ApiResponseListSalonResponse**](ApiResponseListSalonResponse.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getSalon**
> ApiResponsePublicSalonResponse getSalon(salonId)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getSalonControllerApi();
final String salonId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 

try {
    final response = api.getSalon(salonId);
    print(response);
} catch on DioException (e) {
    print('Exception when calling SalonControllerApi->getSalon: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **salonId** | **String**|  | 

### Return type

[**ApiResponsePublicSalonResponse**](ApiResponsePublicSalonResponse.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **inviteMaster**
> ApiResponseInviteResponse inviteMaster(salonId, inviteRequest)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getSalonControllerApi();
final String salonId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final InviteRequest inviteRequest = ; // InviteRequest | 

try {
    final response = api.inviteMaster(salonId, inviteRequest);
    print(response);
} catch on DioException (e) {
    print('Exception when calling SalonControllerApi->inviteMaster: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **salonId** | **String**|  | 
 **inviteRequest** | [**InviteRequest**](InviteRequest.md)|  | 

### Return type

[**ApiResponseInviteResponse**](ApiResponseInviteResponse.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **updateSalon**
> ApiResponseSalonResponse updateSalon(salonId, updateSalonRequest)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getSalonControllerApi();
final String salonId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final UpdateSalonRequest updateSalonRequest = ; // UpdateSalonRequest | 

try {
    final response = api.updateSalon(salonId, updateSalonRequest);
    print(response);
} catch on DioException (e) {
    print('Exception when calling SalonControllerApi->updateSalon: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **salonId** | **String**|  | 
 **updateSalonRequest** | [**UpdateSalonRequest**](UpdateSalonRequest.md)|  | 

### Return type

[**ApiResponseSalonResponse**](ApiResponseSalonResponse.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

