# beautica_api.api.SalonControllerApi

## Load the API package
```dart
import 'package:beautica_api/api.dart';
```

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**cancelInvite**](SalonControllerApi.md#cancelinvite) | **DELETE** /api/v1/salons/{salonId}/invites/{inviteId} | Cancel a pending invite
[**createSalon**](SalonControllerApi.md#createsalon) | **POST** /api/v1/salons | 
[**deactivateSalon**](SalonControllerApi.md#deactivatesalon) | **DELETE** /api/v1/salons/{salonId} | 
[**getBookableMasters**](SalonControllerApi.md#getbookablemasters) | **GET** /api/v1/salons/{salonId}/services/{serviceDefId}/masters | 
[**getMastersBySalon**](SalonControllerApi.md#getmastersbysalon) | **GET** /api/v1/salons/{salonId}/masters | 
[**getOwnedSalons**](SalonControllerApi.md#getownedsalons) | **GET** /api/v1/salons/mine | 
[**getSalon**](SalonControllerApi.md#getsalon) | **GET** /api/v1/salons/{salonId} | 
[**getSalonStaff**](SalonControllerApi.md#getsalonstaff) | **GET** /api/v1/salons/{salonId}/staff | List salon staff (masters and admins)
[**getSiblingSalons**](SalonControllerApi.md#getsiblingsalons) | **GET** /api/v1/salons/{salonId}/sibling-salons | List sibling salons of the same owner
[**inviteMaster**](SalonControllerApi.md#invitemaster) | **POST** /api/v1/salons/{salonId}/invite | 
[**listSalonInvites**](SalonControllerApi.md#listsaloninvites) | **GET** /api/v1/salons/{salonId}/invites | List the salon&#39;s invite history
[**removeAdmin**](SalonControllerApi.md#removeadmin) | **DELETE** /api/v1/salons/{salonId}/admins/{userId} | 
[**rotateAdmin**](SalonControllerApi.md#rotateadmin) | **PATCH** /api/v1/salons/{salonId}/admins/{userId}/salon | 
[**updateSalon**](SalonControllerApi.md#updatesalon) | **PATCH** /api/v1/salons/{salonId} | 


# **cancelInvite**
> cancelInvite(salonId, inviteId)

Cancel a pending invite

Revokes an invite that is still PENDING. The row is kept as history, relabelled CANCELLED. Any invite that is not PENDING — already accepted, already cancelled, superseded by a re-invite, or simply lapsed — returns 404, as does an invite belonging to another salon: a non-pending invite must never have its recorded outcome rewritten.

### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getSalonControllerApi();
final String salonId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final String inviteId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 

try {
    api.cancelInvite(salonId, inviteId);
} catch on DioException (e) {
    print('Exception when calling SalonControllerApi->cancelInvite: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **salonId** | **String**|  | 
 **inviteId** | **String**|  | 

### Return type

void (empty response body)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: Not defined

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **createSalon**
> ApiResponseSalonResponse createSalon(createSalonRequest)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getSalonControllerApi();
final CreateSalonRequest createSalonRequest = ; // CreateSalonRequest | 

try {
    final response = api.createSalon(createSalonRequest);
    print(response);
} catch on DioException (e) {
    print('Exception when calling SalonControllerApi->createSalon: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **createSalonRequest** | [**CreateSalonRequest**](CreateSalonRequest.md)|  | 

### Return type

[**ApiResponseSalonResponse**](ApiResponseSalonResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **deactivateSalon**
> deactivateSalon(salonId)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getSalonControllerApi();
final String salonId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 

try {
    api.deactivateSalon(salonId);
} catch on DioException (e) {
    print('Exception when calling SalonControllerApi->deactivateSalon: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **salonId** | **String**|  | 

### Return type

void (empty response body)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getBookableMasters**
> ApiResponseListBookableMasterResponse getBookableMasters(salonId, serviceDefId)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getSalonControllerApi();
final String salonId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final String serviceDefId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 

try {
    final response = api.getBookableMasters(salonId, serviceDefId);
    print(response);
} catch on DioException (e) {
    print('Exception when calling SalonControllerApi->getBookableMasters: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **salonId** | **String**|  | 
 **serviceDefId** | **String**|  | 

### Return type

[**ApiResponseListBookableMasterResponse**](ApiResponseListBookableMasterResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getMastersBySalon**
> ApiResponsePageResponseMasterSummaryResponse getMastersBySalon(salonId, pageable)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getSalonControllerApi();
final String salonId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final Pageable pageable = ; // Pageable | 

try {
    final response = api.getMastersBySalon(salonId, pageable);
    print(response);
} catch on DioException (e) {
    print('Exception when calling SalonControllerApi->getMastersBySalon: $e\n');
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

# **getOwnedSalons**
> ApiResponseListSalonResponse getOwnedSalons()



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getSalonControllerApi();

try {
    final response = api.getOwnedSalons();
    print(response);
} catch on DioException (e) {
    print('Exception when calling SalonControllerApi->getOwnedSalons: $e\n');
}
```

### Parameters
This endpoint does not need any parameter.

### Return type

[**ApiResponseListSalonResponse**](ApiResponseListSalonResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getSalon**
> ApiResponsePublicSalonResponse getSalon(salonId)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getSalonControllerApi();
final String salonId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 

try {
    final response = api.getSalon(salonId);
    print(response);
} catch on DioException (e) {
    print('Exception when calling SalonControllerApi->getSalon: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **salonId** | **String**|  | 

### Return type

[**ApiResponsePublicSalonResponse**](ApiResponsePublicSalonResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getSalonStaff**
> ApiResponseListSalonStaffMemberResponse getSalonStaff(salonId)

List salon staff (masters and admins)

Management-scoped roster combining the salon's masters (any type) and SALON_ADMINs, with unmasked contact details. Requires management access to the salon (owner or assigned admin).

### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getSalonControllerApi();
final String salonId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 

try {
    final response = api.getSalonStaff(salonId);
    print(response);
} catch on DioException (e) {
    print('Exception when calling SalonControllerApi->getSalonStaff: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **salonId** | **String**|  | 

### Return type

[**ApiResponseListSalonStaffMemberResponse**](ApiResponseListSalonStaffMemberResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getSiblingSalons**
> ApiResponseListSiblingSalonOption getSiblingSalons(salonId)

List sibling salons of the same owner

Active salons sharing this salon's owner, excluding this salon itself, as id + name + short address. Backs the rotate-admin destination picker. Requires management access to the salon (owner or assigned admin).

### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getSalonControllerApi();
final String salonId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 

try {
    final response = api.getSiblingSalons(salonId);
    print(response);
} catch on DioException (e) {
    print('Exception when calling SalonControllerApi->getSiblingSalons: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **salonId** | **String**|  | 

### Return type

[**ApiResponseListSiblingSalonOption**](ApiResponseListSiblingSalonOption.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **inviteMaster**
> ApiResponseInviteResponse inviteMaster(salonId, inviteRequest)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getSalonControllerApi();
final String salonId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final InviteRequest inviteRequest = ; // InviteRequest | 

try {
    final response = api.inviteMaster(salonId, inviteRequest);
    print(response);
} catch on DioException (e) {
    print('Exception when calling SalonControllerApi->inviteMaster: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **salonId** | **String**|  | 
 **inviteRequest** | [**InviteRequest**](InviteRequest.md)|  | 

### Return type

[**ApiResponseInviteResponse**](ApiResponseInviteResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **listSalonInvites**
> ApiResponseSalonInviteHistoryResponse listSalonInvites(salonId)

List the salon's invite history

Returns every invite the salon has ever dispatched — pending, accepted, expired and cancelled alike — newest-first by createdAt, under `data.invites`. `status` is derived per row at read time and is one of PENDING, ACCEPTED, EXPIRED, CANCELLED; only a PENDING invite can be cancelled. The token value is never exposed. Capped at the 200 most recent invites; `data.truncated` is true when older invites exist beyond that cap and are not included.

### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getSalonControllerApi();
final String salonId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 

try {
    final response = api.listSalonInvites(salonId);
    print(response);
} catch on DioException (e) {
    print('Exception when calling SalonControllerApi->listSalonInvites: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **salonId** | **String**|  | 

### Return type

[**ApiResponseSalonInviteHistoryResponse**](ApiResponseSalonInviteHistoryResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **removeAdmin**
> removeAdmin(salonId, userId)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getSalonControllerApi();
final String salonId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final String userId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 

try {
    api.removeAdmin(salonId, userId);
} catch on DioException (e) {
    print('Exception when calling SalonControllerApi->removeAdmin: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **salonId** | **String**|  | 
 **userId** | **String**|  | 

### Return type

void (empty response body)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: Not defined

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **rotateAdmin**
> ApiResponseSalonAdminResponse rotateAdmin(salonId, userId, rotateAdminRequest)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getSalonControllerApi();
final String salonId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final String userId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final RotateAdminRequest rotateAdminRequest = ; // RotateAdminRequest | 

try {
    final response = api.rotateAdmin(salonId, userId, rotateAdminRequest);
    print(response);
} catch on DioException (e) {
    print('Exception when calling SalonControllerApi->rotateAdmin: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **salonId** | **String**|  | 
 **userId** | **String**|  | 
 **rotateAdminRequest** | [**RotateAdminRequest**](RotateAdminRequest.md)|  | 

### Return type

[**ApiResponseSalonAdminResponse**](ApiResponseSalonAdminResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **updateSalon**
> ApiResponseSalonResponse updateSalon(salonId, updateSalonRequest)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getSalonControllerApi();
final String salonId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final UpdateSalonRequest updateSalonRequest = ; // UpdateSalonRequest | 

try {
    final response = api.updateSalon(salonId, updateSalonRequest);
    print(response);
} catch on DioException (e) {
    print('Exception when calling SalonControllerApi->updateSalon: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **salonId** | **String**|  | 
 **updateSalonRequest** | [**UpdateSalonRequest**](UpdateSalonRequest.md)|  | 

### Return type

[**ApiResponseSalonResponse**](ApiResponseSalonResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

