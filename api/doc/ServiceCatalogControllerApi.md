# beautica_api.api.ServiceCatalogControllerApi

## Load the API package
```dart
import 'package:beautica_api/api.dart';
```

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**getCategories**](ServiceCatalogControllerApi.md#getcategories) | **GET** /api/v1/service-categories | 
[**getServiceTypesByPlatformCategory**](ServiceCatalogControllerApi.md#getservicetypesbyplatformcategory) | **GET** /api/v1/service-types | 
[**suggestServiceType**](ServiceCatalogControllerApi.md#suggestservicetype) | **POST** /api/v1/service-types/suggest | 


# **getCategories**
> ApiResponseListCatalogCategoryResponse getCategories()



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getServiceCatalogControllerApi();

try {
    final response = api.getCategories();
    print(response);
} catch on DioException (e) {
    print('Exception when calling ServiceCatalogControllerApi->getCategories: $e\n');
}
```

### Parameters
This endpoint does not need any parameter.

### Return type

[**ApiResponseListCatalogCategoryResponse**](ApiResponseListCatalogCategoryResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getServiceTypesByPlatformCategory**
> ApiResponseListPlatformServiceTypeResponse getServiceTypesByPlatformCategory(categoryName)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getServiceCatalogControllerApi();
final String categoryName = categoryName_example; // String | Canonical platform-category name slug (e.g. EYELASH, HAIR). Required.

try {
    final response = api.getServiceTypesByPlatformCategory(categoryName);
    print(response);
} catch on DioException (e) {
    print('Exception when calling ServiceCatalogControllerApi->getServiceTypesByPlatformCategory: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **categoryName** | **String**| Canonical platform-category name slug (e.g. EYELASH, HAIR). Required. | 

### Return type

[**ApiResponseListPlatformServiceTypeResponse**](ApiResponseListPlatformServiceTypeResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **suggestServiceType**
> ApiResponseVoid suggestServiceType(suggestServiceTypeRequest)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getServiceCatalogControllerApi();
final SuggestServiceTypeRequest suggestServiceTypeRequest = ; // SuggestServiceTypeRequest | 

try {
    final response = api.suggestServiceType(suggestServiceTypeRequest);
    print(response);
} catch on DioException (e) {
    print('Exception when calling ServiceCatalogControllerApi->suggestServiceType: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **suggestServiceTypeRequest** | [**SuggestServiceTypeRequest**](SuggestServiceTypeRequest.md)|  | 

### Return type

[**ApiResponseVoid**](ApiResponseVoid.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

