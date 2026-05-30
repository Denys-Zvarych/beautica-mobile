# beautica_api.api.ServiceCatalogControllerApi

## Load the API package
```dart
import 'package:beautica_api/api.dart';
```

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**getCategories**](ServiceCatalogControllerApi.md#getcategories) | **GET** /api/v1/service-categories | 
[**getServiceTypes**](ServiceCatalogControllerApi.md#getservicetypes) | **GET** /api/v1/service-types | 
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

# **getServiceTypes**
> ApiResponseListServiceTypeResponse getServiceTypes(categoryId, q)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getServiceCatalogControllerApi();
final String categoryId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final String q = q_example; // String | 

try {
    final response = api.getServiceTypes(categoryId, q);
    print(response);
} catch on DioException (e) {
    print('Exception when calling ServiceCatalogControllerApi->getServiceTypes: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **categoryId** | **String**|  | [optional] 
 **q** | **String**|  | [optional] 

### Return type

[**ApiResponseListServiceTypeResponse**](ApiResponseListServiceTypeResponse.md)

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

