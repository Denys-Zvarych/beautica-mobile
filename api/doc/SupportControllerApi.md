# beautica_api.api.SupportControllerApi

## Load the API package
```dart
import 'package:beautica_api/api.dart';
```

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**contact**](SupportControllerApi.md#contact) | **POST** /api/v1/support/contact | Send a Help / Contact-us message to support


# **contact**
> ApiResponseContactSupportResponse contact(request, attachments)

Send a Help / Contact-us message to support

Accepts a free-text message plus optional file attachments and emails the whole thing to the support inbox. Authenticated users only; the sender's identity is taken from the JWT, never from the request body.  Constraints: up to 5 attachments, each ≤ 5 MB, total ≤ 5 MB; allowed types JPEG, PNG, WebP, PDF (validated by content, not the declared header).

### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getSupportControllerApi();
final ContactSupportRequest request = ; // ContactSupportRequest | 
final BuiltList<MultipartFile> attachments = /path/to/file.txt; // BuiltList<MultipartFile> | Optional file attachments (≤5 files, ≤5 MB each, ≤5 MB total)

try {
    final response = api.contact(request, attachments);
    print(response);
} catch on DioException (e) {
    print('Exception when calling SupportControllerApi->contact: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **request** | [**ContactSupportRequest**](ContactSupportRequest.md)|  | [optional] 
 **attachments** | [**BuiltList&lt;MultipartFile&gt;**](MultipartFile.md)| Optional file attachments (≤5 files, ≤5 MB each, ≤5 MB total) | [optional] 

### Return type

[**ApiResponseContactSupportResponse**](ApiResponseContactSupportResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: multipart/form-data
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

