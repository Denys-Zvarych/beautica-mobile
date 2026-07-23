# beautica_api.api.FavoriteControllerApi

## Load the API package
```dart
import 'package:beautica_api/api.dart';
```

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**addFavorite**](FavoriteControllerApi.md#addfavorite) | **POST** /api/v1/favorites | 
[**listMasterFavorites**](FavoriteControllerApi.md#listmasterfavorites) | **GET** /api/v1/favorites/masters | 
[**listSalonFavorites**](FavoriteControllerApi.md#listsalonfavorites) | **GET** /api/v1/favorites/salons | 
[**removeFavorite**](FavoriteControllerApi.md#removefavorite) | **DELETE** /api/v1/favorites | 


# **addFavorite**
> ApiResponseFavoriteResponse addFavorite(addFavoriteRequest)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getFavoriteControllerApi();
final AddFavoriteRequest addFavoriteRequest = ; // AddFavoriteRequest | 

try {
    final response = api.addFavorite(addFavoriteRequest);
    print(response);
} catch on DioException (e) {
    print('Exception when calling FavoriteControllerApi->addFavorite: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **addFavoriteRequest** | [**AddFavoriteRequest**](AddFavoriteRequest.md)|  | 

### Return type

[**ApiResponseFavoriteResponse**](ApiResponseFavoriteResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **listMasterFavorites**
> ApiResponsePageResponseFavoriteMasterResponse listMasterFavorites(pageable)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getFavoriteControllerApi();
final Pageable pageable = ; // Pageable | 

try {
    final response = api.listMasterFavorites(pageable);
    print(response);
} catch on DioException (e) {
    print('Exception when calling FavoriteControllerApi->listMasterFavorites: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **pageable** | [**Pageable**](.md)|  | 

### Return type

[**ApiResponsePageResponseFavoriteMasterResponse**](ApiResponsePageResponseFavoriteMasterResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **listSalonFavorites**
> ApiResponsePageResponseFavoriteSalonResponse listSalonFavorites(pageable)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getFavoriteControllerApi();
final Pageable pageable = ; // Pageable | 

try {
    final response = api.listSalonFavorites(pageable);
    print(response);
} catch on DioException (e) {
    print('Exception when calling FavoriteControllerApi->listSalonFavorites: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **pageable** | [**Pageable**](.md)|  | 

### Return type

[**ApiResponsePageResponseFavoriteSalonResponse**](ApiResponsePageResponseFavoriteSalonResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **removeFavorite**
> removeFavorite(targetType, targetId)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getFavoriteControllerApi();
final String targetType = targetType_example; // String | 
final String targetId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 

try {
    api.removeFavorite(targetType, targetId);
} catch on DioException (e) {
    print('Exception when calling FavoriteControllerApi->removeFavorite: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **targetType** | **String**|  | 
 **targetId** | **String**|  | 

### Return type

void (empty response body)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: Not defined

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

