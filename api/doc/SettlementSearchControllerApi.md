# beautica_api.api.SettlementSearchControllerApi

## Load the API package
```dart
import 'package:beautica_api/api.dart';
```

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**searchSettlements**](SettlementSearchControllerApi.md#searchsettlements) | **GET** /api/v1/settlements | 


# **searchSettlements**
> ApiResponseListSettlementSearchResponse searchSettlements(query)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getSettlementSearchControllerApi();
final String query = query_example; // String | 

try {
    final response = api.searchSettlements(query);
    print(response);
} catch on DioException (e) {
    print('Exception when calling SettlementSearchControllerApi->searchSettlements: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **query** | **String**|  | [optional] 

### Return type

[**ApiResponseListSettlementSearchResponse**](ApiResponseListSettlementSearchResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

