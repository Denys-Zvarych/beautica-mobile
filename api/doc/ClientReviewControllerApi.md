# beautica_api.api.ClientReviewControllerApi

## Load the API package
```dart
import 'package:beautica_api/api.dart';
```

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**create**](ClientReviewControllerApi.md#create) | **POST** /api/v1/client-reviews | 


# **create**
> ApiResponseClientReviewResponse create(createClientReviewRequest)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getClientReviewControllerApi();
final CreateClientReviewRequest createClientReviewRequest = ; // CreateClientReviewRequest | 

try {
    final response = api.create(createClientReviewRequest);
    print(response);
} catch on DioException (e) {
    print('Exception when calling ClientReviewControllerApi->create: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **createClientReviewRequest** | [**CreateClientReviewRequest**](CreateClientReviewRequest.md)|  | 

### Return type

[**ApiResponseClientReviewResponse**](ApiResponseClientReviewResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

