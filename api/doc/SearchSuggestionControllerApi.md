# beautica_api.api.SearchSuggestionControllerApi

## Load the API package
```dart
import 'package:beautica_api/api.dart';
```

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**suggest**](SearchSuggestionControllerApi.md#suggest) | **GET** /api/v1/search/suggestions | Autocomplete suggestions for the search box


# **suggest**
> ApiResponseListSearchSuggestionResponse suggest(request)

Autocomplete suggestions for the search box

Ranked CATEGORY and SERVICE suggestions available at the caller's place (or the national list with no place chosen). Never 404s; no match or nothing available returns an empty list.

### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getSearchSuggestionControllerApi();
final SearchSuggestionRequest request = ; // SearchSuggestionRequest | 

try {
    final response = api.suggest(request);
    print(response);
} catch on DioException (e) {
    print('Exception when calling SearchSuggestionControllerApi->suggest: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **request** | [**SearchSuggestionRequest**](.md)|  | 

### Return type

[**ApiResponseListSearchSuggestionResponse**](ApiResponseListSearchSuggestionResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

