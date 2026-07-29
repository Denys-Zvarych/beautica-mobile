# beautica_api.api.MasterControllerApi

## Load the API package
```dart
import 'package:beautica_api/api.dart';
```

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**clearOverride**](MasterControllerApi.md#clearoverride) | **DELETE** /api/v1/masters/{masterId}/overrides/{date} | 
[**createWeeklySchedule**](MasterControllerApi.md#createweeklyschedule) | **POST** /api/v1/masters/{masterId}/weekly-schedules | 
[**deactivateMaster**](MasterControllerApi.md#deactivatemaster) | **DELETE** /api/v1/masters/{masterId} | 
[**deleteWeeklySchedule**](MasterControllerApi.md#deleteweeklyschedule) | **DELETE** /api/v1/masters/{masterId}/weekly-schedules/{scheduleId} | 
[**getAvailableSlots**](MasterControllerApi.md#getavailableslots) | **GET** /api/v1/masters/{masterId}/slots | 
[**getEffectiveSchedule**](MasterControllerApi.md#geteffectiveschedule) | **GET** /api/v1/masters/{masterId}/effective-schedule | 
[**getMasterCalendar**](MasterControllerApi.md#getmastercalendar) | **GET** /api/v1/masters/me/calendar | 
[**getMasterDetail**](MasterControllerApi.md#getmasterdetail) | **GET** /api/v1/masters/{masterId} | 
[**getMastersBySalon1**](MasterControllerApi.md#getmastersbysalon1) | **GET** /api/v1/masters/by-salon/{salonId} | 
[**getMyProfile**](MasterControllerApi.md#getmyprofile) | **GET** /api/v1/masters/me | 
[**getOverrides**](MasterControllerApi.md#getoverrides) | **GET** /api/v1/masters/{masterId}/overrides | 
[**getWeeklySchedules**](MasterControllerApi.md#getweeklyschedules) | **GET** /api/v1/masters/{masterId}/weekly-schedules | 
[**getWorkingDays**](MasterControllerApi.md#getworkingdays) | **GET** /api/v1/masters/{masterId}/working-days | 
[**previewOverrideConflicts**](MasterControllerApi.md#previewoverrideconflicts) | **POST** /api/v1/masters/{masterId}/overrides/conflicts | 
[**rotateMasterSalon**](MasterControllerApi.md#rotatemastersalon) | **PATCH** /api/v1/masters/{masterId}/salon | 
[**updateMyProfile**](MasterControllerApi.md#updatemyprofile) | **PATCH** /api/v1/masters/me/profile | 
[**updateWeeklySchedule**](MasterControllerApi.md#updateweeklyschedule) | **PUT** /api/v1/masters/{masterId}/weekly-schedules/{scheduleId} | 
[**upsertOverride**](MasterControllerApi.md#upsertoverride) | **PUT** /api/v1/masters/{masterId}/overrides/{date} | 
[**upsertWorkingHours**](MasterControllerApi.md#upsertworkinghours) | **PATCH** /api/v1/masters/{masterId}/working-hours | 


# **clearOverride**
> ApiResponseVoid clearOverride(masterId, date)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getMasterControllerApi();
final String masterId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final Date date = 2013-10-20; // Date | 

try {
    final response = api.clearOverride(masterId, date);
    print(response);
} catch on DioException (e) {
    print('Exception when calling MasterControllerApi->clearOverride: $e\n');
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

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **createWeeklySchedule**
> ApiResponseWeeklyScheduleResponse createWeeklySchedule(masterId, weeklyScheduleRequest)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getMasterControllerApi();
final String masterId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final WeeklyScheduleRequest weeklyScheduleRequest = ; // WeeklyScheduleRequest | 

try {
    final response = api.createWeeklySchedule(masterId, weeklyScheduleRequest);
    print(response);
} catch on DioException (e) {
    print('Exception when calling MasterControllerApi->createWeeklySchedule: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **masterId** | **String**|  | 
 **weeklyScheduleRequest** | [**WeeklyScheduleRequest**](WeeklyScheduleRequest.md)|  | 

### Return type

[**ApiResponseWeeklyScheduleResponse**](ApiResponseWeeklyScheduleResponse.md)

### Authorization

No authorization required

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

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **deleteWeeklySchedule**
> ApiResponseVoid deleteWeeklySchedule(masterId, scheduleId)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getMasterControllerApi();
final String masterId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final String scheduleId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 

try {
    final response = api.deleteWeeklySchedule(masterId, scheduleId);
    print(response);
} catch on DioException (e) {
    print('Exception when calling MasterControllerApi->deleteWeeklySchedule: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **masterId** | **String**|  | 
 **scheduleId** | **String**|  | 

### Return type

[**ApiResponseVoid**](ApiResponseVoid.md)

### Authorization

No authorization required

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
final BuiltList<String> serviceId = ; // BuiltList<String> | 

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
 **serviceId** | [**BuiltList&lt;String&gt;**](String.md)|  | 

### Return type

[**ApiResponseAvailableSlotsResponse**](ApiResponseAvailableSlotsResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getEffectiveSchedule**
> ApiResponseListEffectiveDayResponse getEffectiveSchedule(masterId, from, to)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getMasterControllerApi();
final String masterId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final Date from = 2013-10-20; // Date | 
final Date to = 2013-10-20; // Date | 

try {
    final response = api.getEffectiveSchedule(masterId, from, to);
    print(response);
} catch on DioException (e) {
    print('Exception when calling MasterControllerApi->getEffectiveSchedule: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **masterId** | **String**|  | 
 **from** | **Date**|  | 
 **to** | **Date**|  | 

### Return type

[**ApiResponseListEffectiveDayResponse**](ApiResponseListEffectiveDayResponse.md)

### Authorization

No authorization required

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

No authorization required

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

No authorization required

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

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getMyProfile**
> ApiResponseMasterDetailResponse getMyProfile()



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getMasterControllerApi();

try {
    final response = api.getMyProfile();
    print(response);
} catch on DioException (e) {
    print('Exception when calling MasterControllerApi->getMyProfile: $e\n');
}
```

### Parameters
This endpoint does not need any parameter.

### Return type

[**ApiResponseMasterDetailResponse**](ApiResponseMasterDetailResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getOverrides**
> ApiResponseListScheduleOverrideResponse getOverrides(masterId, from, to)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getMasterControllerApi();
final String masterId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final Date from = 2013-10-20; // Date | 
final Date to = 2013-10-20; // Date | 

try {
    final response = api.getOverrides(masterId, from, to);
    print(response);
} catch on DioException (e) {
    print('Exception when calling MasterControllerApi->getOverrides: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **masterId** | **String**|  | 
 **from** | **Date**|  | 
 **to** | **Date**|  | 

### Return type

[**ApiResponseListScheduleOverrideResponse**](ApiResponseListScheduleOverrideResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getWeeklySchedules**
> ApiResponseListWeeklyScheduleResponse getWeeklySchedules(masterId)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getMasterControllerApi();
final String masterId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 

try {
    final response = api.getWeeklySchedules(masterId);
    print(response);
} catch on DioException (e) {
    print('Exception when calling MasterControllerApi->getWeeklySchedules: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **masterId** | **String**|  | 

### Return type

[**ApiResponseListWeeklyScheduleResponse**](ApiResponseListWeeklyScheduleResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getWorkingDays**
> ApiResponseListMasterWorkingDayResponse getWorkingDays(masterId, from, to, serviceId)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getMasterControllerApi();
final String masterId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final Date from = 2013-10-20; // Date | 
final Date to = 2013-10-20; // Date | 
final BuiltList<String> serviceId = ; // BuiltList<String> | 

try {
    final response = api.getWorkingDays(masterId, from, to, serviceId);
    print(response);
} catch on DioException (e) {
    print('Exception when calling MasterControllerApi->getWorkingDays: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **masterId** | **String**|  | 
 **from** | **Date**|  | 
 **to** | **Date**|  | 
 **serviceId** | [**BuiltList&lt;String&gt;**](String.md)|  | [optional] 

### Return type

[**ApiResponseListMasterWorkingDayResponse**](ApiResponseListMasterWorkingDayResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **previewOverrideConflicts**
> ApiResponseOverrideConflictPreviewResponse previewOverrideConflicts(masterId, overrideConflictQueryRequest)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getMasterControllerApi();
final String masterId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final OverrideConflictQueryRequest overrideConflictQueryRequest = ; // OverrideConflictQueryRequest | 

try {
    final response = api.previewOverrideConflicts(masterId, overrideConflictQueryRequest);
    print(response);
} catch on DioException (e) {
    print('Exception when calling MasterControllerApi->previewOverrideConflicts: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **masterId** | **String**|  | 
 **overrideConflictQueryRequest** | [**OverrideConflictQueryRequest**](OverrideConflictQueryRequest.md)|  | 

### Return type

[**ApiResponseOverrideConflictPreviewResponse**](ApiResponseOverrideConflictPreviewResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **rotateMasterSalon**
> ApiResponseMasterSummaryResponse rotateMasterSalon(masterId, rotateMasterRequest)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getMasterControllerApi();
final String masterId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final RotateMasterRequest rotateMasterRequest = ; // RotateMasterRequest | 

try {
    final response = api.rotateMasterSalon(masterId, rotateMasterRequest);
    print(response);
} catch on DioException (e) {
    print('Exception when calling MasterControllerApi->rotateMasterSalon: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **masterId** | **String**|  | 
 **rotateMasterRequest** | [**RotateMasterRequest**](RotateMasterRequest.md)|  | 

### Return type

[**ApiResponseMasterSummaryResponse**](ApiResponseMasterSummaryResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **updateMyProfile**
> ApiResponseMasterPublicProfileResponse updateMyProfile(masterProfileUpdateRequest)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getMasterControllerApi();
final MasterProfileUpdateRequest masterProfileUpdateRequest = ; // MasterProfileUpdateRequest | 

try {
    final response = api.updateMyProfile(masterProfileUpdateRequest);
    print(response);
} catch on DioException (e) {
    print('Exception when calling MasterControllerApi->updateMyProfile: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **masterProfileUpdateRequest** | [**MasterProfileUpdateRequest**](MasterProfileUpdateRequest.md)|  | 

### Return type

[**ApiResponseMasterPublicProfileResponse**](ApiResponseMasterPublicProfileResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **updateWeeklySchedule**
> ApiResponseWeeklyScheduleResponse updateWeeklySchedule(masterId, scheduleId, weeklyScheduleRequest)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getMasterControllerApi();
final String masterId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final String scheduleId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final WeeklyScheduleRequest weeklyScheduleRequest = ; // WeeklyScheduleRequest | 

try {
    final response = api.updateWeeklySchedule(masterId, scheduleId, weeklyScheduleRequest);
    print(response);
} catch on DioException (e) {
    print('Exception when calling MasterControllerApi->updateWeeklySchedule: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **masterId** | **String**|  | 
 **scheduleId** | **String**|  | 
 **weeklyScheduleRequest** | [**WeeklyScheduleRequest**](WeeklyScheduleRequest.md)|  | 

### Return type

[**ApiResponseWeeklyScheduleResponse**](ApiResponseWeeklyScheduleResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **upsertOverride**
> ApiResponseScheduleOverrideResponse upsertOverride(masterId, date, scheduleOverrideRequest)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getMasterControllerApi();
final String masterId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final Date date = 2013-10-20; // Date | 
final ScheduleOverrideRequest scheduleOverrideRequest = ; // ScheduleOverrideRequest | 

try {
    final response = api.upsertOverride(masterId, date, scheduleOverrideRequest);
    print(response);
} catch on DioException (e) {
    print('Exception when calling MasterControllerApi->upsertOverride: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **masterId** | **String**|  | 
 **date** | **Date**|  | 
 **scheduleOverrideRequest** | [**ScheduleOverrideRequest**](ScheduleOverrideRequest.md)|  | 

### Return type

[**ApiResponseScheduleOverrideResponse**](ApiResponseScheduleOverrideResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
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

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

