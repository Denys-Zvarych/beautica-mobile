# beautica_api.api.MasterControllerApi

## Load the API package
```dart
import 'package:beautica_api/api.dart';
```

All URIs are relative to *http://localhost:8080/api/v1*

Method | HTTP request | Description
------------- | ------------- | -------------
[**addScheduleException**](MasterControllerApi.md#addscheduleexception) | **POST** /masters/{masterId}/schedule-exceptions | 
[**deactivateMaster**](MasterControllerApi.md#deactivatemaster) | **DELETE** /masters/{masterId} | 
[**getAvailableSlots**](MasterControllerApi.md#getavailableslots) | **GET** /masters/{masterId}/slots | 
[**getMasterCalendar**](MasterControllerApi.md#getmastercalendar) | **GET** /masters/me/calendar | 
[**getMasterDetail**](MasterControllerApi.md#getmasterdetail) | **GET** /masters/{masterId} | 
[**getMastersBySalon1**](MasterControllerApi.md#getmastersbysalon1) | **GET** /masters/by-salon/{salonId} | 
[**removeScheduleException**](MasterControllerApi.md#removescheduleexception) | **DELETE** /masters/{masterId}/schedule-exceptions/{date} | 
[**upsertWorkingHours**](MasterControllerApi.md#upsertworkinghours) | **PATCH** /masters/{masterId}/working-hours | 


# **addScheduleException**
> ApiResponseVoid addScheduleException(masterId, scheduleExceptionRequest)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getMasterControllerApi();
final String masterId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final ScheduleExceptionRequest scheduleExceptionRequest = ; // ScheduleExceptionRequest | 

try {
    final response = api.addScheduleException(masterId, scheduleExceptionRequest);
    print(response);
} catch on DioException (e) {
    print('Exception when calling MasterControllerApi->addScheduleException: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **masterId** | **String**|  | 
 **scheduleExceptionRequest** | [**ScheduleExceptionRequest**](ScheduleExceptionRequest.md)|  | 

### Return type

[**ApiResponseVoid**](ApiResponseVoid.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **deactivateMaster**
> ApiResponseVoid deactivateMaster(masterId)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getMasterControllerApi();
final String masterId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 

try {
    final response = api.deactivateMaster(masterId);
    print(response);
} catch on DioException (e) {
    print('Exception when calling MasterControllerApi->deactivateMaster: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **masterId** | **String**|  | 

### Return type

[**ApiResponseVoid**](ApiResponseVoid.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getAvailableSlots**
> ApiResponseAvailableSlotsResponse getAvailableSlots(masterId, date, serviceId)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getMasterControllerApi();
final String masterId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final Date date = 2013-10-20; // Date | 
final String serviceId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 

try {
    final response = api.getAvailableSlots(masterId, date, serviceId);
    print(response);
} catch on DioException (e) {
    print('Exception when calling MasterControllerApi->getAvailableSlots: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **masterId** | **String**|  | 
 **date** | **Date**|  | 
 **serviceId** | **String**|  | 

### Return type

[**ApiResponseAvailableSlotsResponse**](ApiResponseAvailableSlotsResponse.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getMasterCalendar**
> ApiResponsePageResponseBookingResponse getMasterCalendar(from, to, pageable)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getMasterControllerApi();
final Date from = 2013-10-20; // Date | 
final Date to = 2013-10-20; // Date | 
final Pageable pageable = ; // Pageable | 

try {
    final response = api.getMasterCalendar(from, to, pageable);
    print(response);
} catch on DioException (e) {
    print('Exception when calling MasterControllerApi->getMasterCalendar: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **from** | **Date**|  | 
 **to** | **Date**|  | 
 **pageable** | [**Pageable**](.md)|  | 

### Return type

[**ApiResponsePageResponseBookingResponse**](ApiResponsePageResponseBookingResponse.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getMasterDetail**
> ApiResponseMasterDetailResponse getMasterDetail(masterId)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getMasterControllerApi();
final String masterId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 

try {
    final response = api.getMasterDetail(masterId);
    print(response);
} catch on DioException (e) {
    print('Exception when calling MasterControllerApi->getMasterDetail: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **masterId** | **String**|  | 

### Return type

[**ApiResponseMasterDetailResponse**](ApiResponseMasterDetailResponse.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getMastersBySalon1**
> ApiResponsePageResponseMasterSummaryResponse getMastersBySalon1(salonId, pageable)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getMasterControllerApi();
final String salonId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final Pageable pageable = ; // Pageable | 

try {
    final response = api.getMastersBySalon1(salonId, pageable);
    print(response);
} catch on DioException (e) {
    print('Exception when calling MasterControllerApi->getMastersBySalon1: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **salonId** | **String**|  | 
 **pageable** | [**Pageable**](.md)|  | 

### Return type

[**ApiResponsePageResponseMasterSummaryResponse**](ApiResponsePageResponseMasterSummaryResponse.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **removeScheduleException**
> ApiResponseVoid removeScheduleException(masterId, date)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getMasterControllerApi();
final String masterId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final Date date = 2013-10-20; // Date | 

try {
    final response = api.removeScheduleException(masterId, date);
    print(response);
} catch on DioException (e) {
    print('Exception when calling MasterControllerApi->removeScheduleException: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **masterId** | **String**|  | 
 **date** | **Date**|  | 

### Return type

[**ApiResponseVoid**](ApiResponseVoid.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **upsertWorkingHours**
> ApiResponseListWorkingHoursResponse upsertWorkingHours(masterId, workingHoursRequest)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getMasterControllerApi();
final String masterId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final BuiltList<WorkingHoursRequest> workingHoursRequest = ; // BuiltList<WorkingHoursRequest> | 

try {
    final response = api.upsertWorkingHours(masterId, workingHoursRequest);
    print(response);
} catch on DioException (e) {
    print('Exception when calling MasterControllerApi->upsertWorkingHours: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **masterId** | **String**|  | 
 **workingHoursRequest** | [**BuiltList&lt;WorkingHoursRequest&gt;**](WorkingHoursRequest.md)|  | 

### Return type

[**ApiResponseListWorkingHoursResponse**](ApiResponseListWorkingHoursResponse.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

