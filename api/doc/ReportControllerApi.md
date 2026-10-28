# beautica_api.api.ReportControllerApi

## Load the API package
```dart
import 'package:beautica_api/api.dart';
```

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**createReport**](ReportControllerApi.md#createreport) | **POST** /api/v1/reports | Report a review, photo or profile


# **createReport**
> ApiResponseReportResponse createReport(createReportRequest)

Report a review, photo or profile

Reports a piece of user-generated content the caller can currently see. One report per (caller, target): repeating it returns the existing report with 200 instead of 201. Own content cannot be reported (400). A target the caller cannot see answers 404. At most 20 new reports per 24 hours per user (429).

### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getReportControllerApi();
final CreateReportRequest createReportRequest = ; // CreateReportRequest | 

try {
    final response = api.createReport(createReportRequest);
    print(response);
} catch on DioException (e) {
    print('Exception when calling ReportControllerApi->createReport: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **createReportRequest** | [**CreateReportRequest**](CreateReportRequest.md)|  | 

### Return type

[**ApiResponseReportResponse**](ApiResponseReportResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

