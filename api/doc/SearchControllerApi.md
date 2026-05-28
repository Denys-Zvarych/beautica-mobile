# beautica_api.api.SearchControllerApi

## Load the API package
```dart
import 'package:beautica_api/api.dart';
```

All URIs are relative to *http://localhost:8080/api/v1*

Method | HTTP request | Description
------------- | ------------- | -------------
[**searchMasters**](SearchControllerApi.md#searchmasters) | **GET** /search/masters | 
[**searchSalons**](SearchControllerApi.md#searchsalons) | **GET** /search/salons | 


# **searchMasters**
> ApiResponsePageResponseMasterSearchResult searchMasters(request)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getSearchControllerApi();
final MasterSearchRequest request = ; // MasterSearchRequest | 

try {
    final response = api.searchMasters(request);
    print(response);
} catch on DioException (e) {
    print('Exception when calling SearchControllerApi->searchMasters: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **request** | [**MasterSearchRequest**](.md)|  | 

### Return type

[**ApiResponsePageResponseMasterSearchResult**](ApiResponsePageResponseMasterSearchResult.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **searchSalons**
> ApiResponsePageResponseSalonSearchResult searchSalons(request)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getSearchControllerApi();
final SalonSearchRequest request = ; // SalonSearchRequest | 

try {
    final response = api.searchSalons(request);
    print(response);
} catch on DioException (e) {
    print('Exception when calling SearchControllerApi->searchSalons: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **request** | [**SalonSearchRequest**](.md)|  | 

### Return type

[**ApiResponsePageResponseSalonSearchResult**](ApiResponsePageResponseSalonSearchResult.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

