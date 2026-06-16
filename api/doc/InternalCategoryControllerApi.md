# beautica_api.api.InternalCategoryControllerApi

## Load the API package
```dart
import 'package:beautica_api/api.dart';
```

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**createCategory**](InternalCategoryControllerApi.md#createcategory) | **POST** /api/v1/internal/service-categories | 
[**listCategories**](InternalCategoryControllerApi.md#listcategories) | **GET** /api/v1/internal/service-categories | 


# **createCategory**
> ApiResponsePlatformCategoryResponse createCategory(createPlatformCategoryRequest)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getInternalCategoryControllerApi();
final CreatePlatformCategoryRequest createPlatformCategoryRequest = ; // CreatePlatformCategoryRequest | 

try {
    final response = api.createCategory(createPlatformCategoryRequest);
    print(response);
} catch on DioException (e) {
    print('Exception when calling InternalCategoryControllerApi->createCategory: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **createPlatformCategoryRequest** | [**CreatePlatformCategoryRequest**](CreatePlatformCategoryRequest.md)|  | 

### Return type

[**ApiResponsePlatformCategoryResponse**](ApiResponsePlatformCategoryResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **listCategories**
> ApiResponseListPlatformCategoryUsageResponse listCategories()



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getInternalCategoryControllerApi();

try {
    final response = api.listCategories();
    print(response);
} catch on DioException (e) {
    print('Exception when calling InternalCategoryControllerApi->listCategories: $e\n');
}
```

### Parameters
This endpoint does not need any parameter.

### Return type

[**ApiResponseListPlatformCategoryUsageResponse**](ApiResponseListPlatformCategoryUsageResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

