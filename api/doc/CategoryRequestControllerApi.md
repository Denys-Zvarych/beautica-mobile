# beautica_api.api.CategoryRequestControllerApi

## Load the API package
```dart
import 'package:beautica_api/api.dart';
```

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**listApproved**](CategoryRequestControllerApi.md#listapproved) | **GET** /api/v1/service-categories/approved | 
[**submitRequest**](CategoryRequestControllerApi.md#submitrequest) | **POST** /api/v1/service-categories/requests | 


# **listApproved**
> ApiResponseListApprovedCategoryResponse listApproved()



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getCategoryRequestControllerApi();

try {
    final response = api.listApproved();
    print(response);
} catch on DioException (e) {
    print('Exception when calling CategoryRequestControllerApi->listApproved: $e\n');
}
```

### Parameters
This endpoint does not need any parameter.

### Return type

[**ApiResponseListApprovedCategoryResponse**](ApiResponseListApprovedCategoryResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **submitRequest**
> ApiResponseCategoryRequestResponse submitRequest(createCategoryRequestRequest)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getCategoryRequestControllerApi();
final CreateCategoryRequestRequest createCategoryRequestRequest = ; // CreateCategoryRequestRequest | 

try {
    final response = api.submitRequest(createCategoryRequestRequest);
    print(response);
} catch on DioException (e) {
    print('Exception when calling CategoryRequestControllerApi->submitRequest: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **createCategoryRequestRequest** | [**CreateCategoryRequestRequest**](CreateCategoryRequestRequest.md)|  | 

### Return type

[**ApiResponseCategoryRequestResponse**](ApiResponseCategoryRequestResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

