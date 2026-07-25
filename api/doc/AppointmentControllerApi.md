# beautica_api.api.AppointmentControllerApi

## Load the API package
```dart
import 'package:beautica_api/api.dart';
```

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**cancelAppointment**](AppointmentControllerApi.md#cancelappointment) | **PATCH** /api/v1/appointments/{appointmentId}/cancel | 
[**completeAppointment**](AppointmentControllerApi.md#completeappointment) | **PATCH** /api/v1/appointments/{appointmentId}/complete | 
[**createAppointment**](AppointmentControllerApi.md#createappointment) | **POST** /api/v1/appointments | 
[**declineAppointment**](AppointmentControllerApi.md#declineappointment) | **PATCH** /api/v1/appointments/{appointmentId}/decline | 
[**getAppointment**](AppointmentControllerApi.md#getappointment) | **GET** /api/v1/appointments/{appointmentId} | 
[**notCompleteAppointment**](AppointmentControllerApi.md#notcompleteappointment) | **PATCH** /api/v1/appointments/{appointmentId}/not-complete | 
[**rescheduleAppointment**](AppointmentControllerApi.md#rescheduleappointment) | **PATCH** /api/v1/appointments/{appointmentId}/reschedule | 


# **cancelAppointment**
> cancelAppointment(appointmentId, appointmentCancelRequest)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getAppointmentControllerApi();
final String appointmentId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final AppointmentCancelRequest appointmentCancelRequest = ; // AppointmentCancelRequest | 

try {
    api.cancelAppointment(appointmentId, appointmentCancelRequest);
} catch on DioException (e) {
    print('Exception when calling AppointmentControllerApi->cancelAppointment: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **appointmentId** | **String**|  | 
 **appointmentCancelRequest** | [**AppointmentCancelRequest**](AppointmentCancelRequest.md)|  | [optional] 

### Return type

void (empty response body)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: Not defined

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **completeAppointment**
> completeAppointment(appointmentId)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getAppointmentControllerApi();
final String appointmentId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 

try {
    api.completeAppointment(appointmentId);
} catch on DioException (e) {
    print('Exception when calling AppointmentControllerApi->completeAppointment: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **appointmentId** | **String**|  | 

### Return type

void (empty response body)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: Not defined

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **createAppointment**
> ApiResponseAppointmentDetailResponse createAppointment(createAppointmentRequest, idempotencyKey)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getAppointmentControllerApi();
final CreateAppointmentRequest createAppointmentRequest = ; // CreateAppointmentRequest | 
final String idempotencyKey = idempotencyKey_example; // String | 

try {
    final response = api.createAppointment(createAppointmentRequest, idempotencyKey);
    print(response);
} catch on DioException (e) {
    print('Exception when calling AppointmentControllerApi->createAppointment: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **createAppointmentRequest** | [**CreateAppointmentRequest**](CreateAppointmentRequest.md)|  | 
 **idempotencyKey** | **String**|  | [optional] 

### Return type

[**ApiResponseAppointmentDetailResponse**](ApiResponseAppointmentDetailResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **declineAppointment**
> declineAppointment(appointmentId, appointmentProviderNoteRequest)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getAppointmentControllerApi();
final String appointmentId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final AppointmentProviderNoteRequest appointmentProviderNoteRequest = ; // AppointmentProviderNoteRequest | 

try {
    api.declineAppointment(appointmentId, appointmentProviderNoteRequest);
} catch on DioException (e) {
    print('Exception when calling AppointmentControllerApi->declineAppointment: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **appointmentId** | **String**|  | 
 **appointmentProviderNoteRequest** | [**AppointmentProviderNoteRequest**](AppointmentProviderNoteRequest.md)|  | [optional] 

### Return type

void (empty response body)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: Not defined

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getAppointment**
> ApiResponseAppointmentDetailResponse getAppointment(appointmentId)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getAppointmentControllerApi();
final String appointmentId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 

try {
    final response = api.getAppointment(appointmentId);
    print(response);
} catch on DioException (e) {
    print('Exception when calling AppointmentControllerApi->getAppointment: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **appointmentId** | **String**|  | 

### Return type

[**ApiResponseAppointmentDetailResponse**](ApiResponseAppointmentDetailResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **notCompleteAppointment**
> notCompleteAppointment(appointmentId, appointmentProviderNoteRequest)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getAppointmentControllerApi();
final String appointmentId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final AppointmentProviderNoteRequest appointmentProviderNoteRequest = ; // AppointmentProviderNoteRequest | 

try {
    api.notCompleteAppointment(appointmentId, appointmentProviderNoteRequest);
} catch on DioException (e) {
    print('Exception when calling AppointmentControllerApi->notCompleteAppointment: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **appointmentId** | **String**|  | 
 **appointmentProviderNoteRequest** | [**AppointmentProviderNoteRequest**](AppointmentProviderNoteRequest.md)|  | [optional] 

### Return type

void (empty response body)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: Not defined

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **rescheduleAppointment**
> ApiResponseAppointmentDetailResponse rescheduleAppointment(appointmentId, appointmentRescheduleRequest)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getAppointmentControllerApi();
final String appointmentId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final AppointmentRescheduleRequest appointmentRescheduleRequest = ; // AppointmentRescheduleRequest | 

try {
    final response = api.rescheduleAppointment(appointmentId, appointmentRescheduleRequest);
    print(response);
} catch on DioException (e) {
    print('Exception when calling AppointmentControllerApi->rescheduleAppointment: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **appointmentId** | **String**|  | 
 **appointmentRescheduleRequest** | [**AppointmentRescheduleRequest**](AppointmentRescheduleRequest.md)|  | 

### Return type

[**ApiResponseAppointmentDetailResponse**](ApiResponseAppointmentDetailResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

