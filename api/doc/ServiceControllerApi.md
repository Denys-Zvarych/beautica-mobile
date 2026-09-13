# beautica_api.api.ServiceControllerApi

## Load the API package
```dart
import 'package:beautica_api/api.dart';
```

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**addIndependentMasterService**](ServiceControllerApi.md#addindependentmasterservice) | **POST** /api/v1/independent-masters/me/services | 
[**addServiceToSalon**](ServiceControllerApi.md#addservicetosalon) | **POST** /api/v1/salons/{salonId}/services | 
[**assignServiceToMaster**](ServiceControllerApi.md#assignservicetomaster) | **POST** /api/v1/salons/{salonId}/masters/{masterId}/services | 
[**bulkCreateMasterServices**](ServiceControllerApi.md#bulkcreatemasterservices) | **POST** /api/v1/salons/{salonId}/masters/{masterId}/services/bulk | Bulk-create a salon master&#39;s services
[**bulkCreateMyServices**](ServiceControllerApi.md#bulkcreatemyservices) | **POST** /api/v1/independent-masters/me/services/bulk | Bulk-create my services
[**deactivateServiceDefinition**](ServiceControllerApi.md#deactivateservicedefinition) | **DELETE** /api/v1/services/{serviceDefId} | 
[**getMasterServices**](ServiceControllerApi.md#getmasterservices) | **GET** /api/v1/masters/{masterId}/services | 
[**getMyServices**](ServiceControllerApi.md#getmyservices) | **GET** /api/v1/independent-masters/me/services | List my own active services
[**getSalonMasterServices**](ServiceControllerApi.md#getsalonmasterservices) | **GET** /api/v1/salons/{salonId}/masters/{masterId}/services | 
[**getSalonServiceCatalog**](ServiceControllerApi.md#getsalonservicecatalog) | **GET** /api/v1/salons/{salonId}/services | Salon&#39;s public bookable service catalog
[**unassignServiceFromMaster**](ServiceControllerApi.md#unassignservicefrommaster) | **DELETE** /api/v1/salons/{salonId}/masters/{masterId}/services/{serviceDefId} | 
[**updateMasterServiceBand**](ServiceControllerApi.md#updatemasterserviceband) | **PATCH** /api/v1/salons/{salonId}/masters/{masterId}/services/{serviceDefId} | 
[**updateServiceDefinition**](ServiceControllerApi.md#updateservicedefinition) | **PATCH** /api/v1/services/{serviceDefId} | 
[**updateServicePhoto**](ServiceControllerApi.md#updateservicephoto) | **PATCH** /api/v1/services/{serviceDefId}/photo | 


# **addIndependentMasterService**
> ApiResponseMasterServiceResponse addIndependentMasterService(createServiceDefinitionRequest)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getServiceControllerApi();
final CreateServiceDefinitionRequest createServiceDefinitionRequest = ; // CreateServiceDefinitionRequest | 

try {
    final response = api.addIndependentMasterService(createServiceDefinitionRequest);
    print(response);
} catch on DioException (e) {
    print('Exception when calling ServiceControllerApi->addIndependentMasterService: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **createServiceDefinitionRequest** | [**CreateServiceDefinitionRequest**](CreateServiceDefinitionRequest.md)|  | 

### Return type

[**ApiResponseMasterServiceResponse**](ApiResponseMasterServiceResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **addServiceToSalon**
> ApiResponseServiceDefinitionResponse addServiceToSalon(salonId, createServiceDefinitionRequest)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getServiceControllerApi();
final String salonId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final CreateServiceDefinitionRequest createServiceDefinitionRequest = ; // CreateServiceDefinitionRequest | 

try {
    final response = api.addServiceToSalon(salonId, createServiceDefinitionRequest);
    print(response);
} catch on DioException (e) {
    print('Exception when calling ServiceControllerApi->addServiceToSalon: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **salonId** | **String**|  | 
 **createServiceDefinitionRequest** | [**CreateServiceDefinitionRequest**](CreateServiceDefinitionRequest.md)|  | 

### Return type

[**ApiResponseServiceDefinitionResponse**](ApiResponseServiceDefinitionResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **assignServiceToMaster**
> ApiResponseMasterServiceResponse assignServiceToMaster(salonId, masterId, assignServiceToMasterRequest)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getServiceControllerApi();
final String salonId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final String masterId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | Master row id (NOT a user id)
final AssignServiceToMasterRequest assignServiceToMasterRequest = ; // AssignServiceToMasterRequest | 

try {
    final response = api.assignServiceToMaster(salonId, masterId, assignServiceToMasterRequest);
    print(response);
} catch on DioException (e) {
    print('Exception when calling ServiceControllerApi->assignServiceToMaster: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **salonId** | **String**|  | 
 **masterId** | **String**| Master row id (NOT a user id) | 
 **assignServiceToMasterRequest** | [**AssignServiceToMasterRequest**](AssignServiceToMasterRequest.md)|  | 

### Return type

[**ApiResponseMasterServiceResponse**](ApiResponseMasterServiceResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **bulkCreateMasterServices**
> ApiResponseListMasterServiceResponse bulkCreateMasterServices(salonId, masterId, bulkCreateServicesRequest)

Bulk-create a salon master's services

Creates every selected service for the given master in one transaction (all-or-nothing). Additive — callable whether or not the master already has services.

### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getServiceControllerApi();
final String salonId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final String masterId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | Master row id (NOT a user id)
final BulkCreateServicesRequest bulkCreateServicesRequest = ; // BulkCreateServicesRequest | 

try {
    final response = api.bulkCreateMasterServices(salonId, masterId, bulkCreateServicesRequest);
    print(response);
} catch on DioException (e) {
    print('Exception when calling ServiceControllerApi->bulkCreateMasterServices: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **salonId** | **String**|  | 
 **masterId** | **String**| Master row id (NOT a user id) | 
 **bulkCreateServicesRequest** | [**BulkCreateServicesRequest**](BulkCreateServicesRequest.md)|  | 

### Return type

[**ApiResponseListMasterServiceResponse**](ApiResponseListMasterServiceResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **bulkCreateMyServices**
> ApiResponseListMasterServiceResponse bulkCreateMyServices(bulkCreateServicesRequest)

Bulk-create my services

Creates every selected service in one transaction (all-or-nothing). Additive — callable whether or not the master already has services.

### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getServiceControllerApi();
final BulkCreateServicesRequest bulkCreateServicesRequest = ; // BulkCreateServicesRequest | 

try {
    final response = api.bulkCreateMyServices(bulkCreateServicesRequest);
    print(response);
} catch on DioException (e) {
    print('Exception when calling ServiceControllerApi->bulkCreateMyServices: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **bulkCreateServicesRequest** | [**BulkCreateServicesRequest**](BulkCreateServicesRequest.md)|  | 

### Return type

[**ApiResponseListMasterServiceResponse**](ApiResponseListMasterServiceResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **deactivateServiceDefinition**
> deactivateServiceDefinition(serviceDefId)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getServiceControllerApi();
final String serviceDefId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 

try {
    api.deactivateServiceDefinition(serviceDefId);
} catch on DioException (e) {
    print('Exception when calling ServiceControllerApi->deactivateServiceDefinition: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **serviceDefId** | **String**|  | 

### Return type

void (empty response body)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: Not defined

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getMasterServices**
> ApiResponseListMasterServiceResponse getMasterServices(masterId)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getServiceControllerApi();
final String masterId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 

try {
    final response = api.getMasterServices(masterId);
    print(response);
} catch on DioException (e) {
    print('Exception when calling ServiceControllerApi->getMasterServices: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **masterId** | **String**|  | 

### Return type

[**ApiResponseListMasterServiceResponse**](ApiResponseListMasterServiceResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getMyServices**
> ApiResponseListMasterServiceResponse getMyServices()

List my own active services

Returns the authenticated master's own active services. Owner-scoped to the authenticated principal; never exposes another master's services.

### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getServiceControllerApi();

try {
    final response = api.getMyServices();
    print(response);
} catch on DioException (e) {
    print('Exception when calling ServiceControllerApi->getMyServices: $e\n');
}
```

### Parameters
This endpoint does not need any parameter.

### Return type

[**ApiResponseListMasterServiceResponse**](ApiResponseListMasterServiceResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getSalonMasterServices**
> ApiResponseListMasterServiceResponse getSalonMasterServices(salonId, masterId)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getServiceControllerApi();
final String salonId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final String masterId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | Master row id (NOT a user id)

try {
    final response = api.getSalonMasterServices(salonId, masterId);
    print(response);
} catch on DioException (e) {
    print('Exception when calling ServiceControllerApi->getSalonMasterServices: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **salonId** | **String**|  | 
 **masterId** | **String**| Master row id (NOT a user id) | 

### Return type

[**ApiResponseListMasterServiceResponse**](ApiResponseListMasterServiceResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **getSalonServiceCatalog**
> ApiResponseSalonServiceCatalogResponse getSalonServiceCatalog(salonId)

Salon's public bookable service catalog

A service appears here iff ALL of: (1) its definition is owner_type=SALON with owner_id=salonId; (2) the definition is active; (3) at least one master_services assignment for it is active; (4) that assignment's master belongs to this salon and is active; (5) that master has a free future slot for the service's effective duration. Condition 5 is DELIBERATE, not a bug: a master with no working hours configured has none of their services listed here, because this endpoint answers \"what can a client book right now\", not \"what does the staff list on paper\".

### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getServiceControllerApi();
final String salonId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 

try {
    final response = api.getSalonServiceCatalog(salonId);
    print(response);
} catch on DioException (e) {
    print('Exception when calling ServiceControllerApi->getSalonServiceCatalog: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **salonId** | **String**|  | 

### Return type

[**ApiResponseSalonServiceCatalogResponse**](ApiResponseSalonServiceCatalogResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **unassignServiceFromMaster**
> unassignServiceFromMaster(salonId, masterId, serviceDefId)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getServiceControllerApi();
final String salonId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final String masterId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | Master row id (NOT a user id)
final String serviceDefId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 

try {
    api.unassignServiceFromMaster(salonId, masterId, serviceDefId);
} catch on DioException (e) {
    print('Exception when calling ServiceControllerApi->unassignServiceFromMaster: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **salonId** | **String**|  | 
 **masterId** | **String**| Master row id (NOT a user id) | 
 **serviceDefId** | **String**|  | 

### Return type

void (empty response body)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: Not defined

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **updateMasterServiceBand**
> ApiResponseMasterServiceResponse updateMasterServiceBand(salonId, masterId, serviceDefId, updateMasterServiceBandRequest)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getServiceControllerApi();
final String salonId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final String masterId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | Master row id (NOT a user id)
final String serviceDefId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final UpdateMasterServiceBandRequest updateMasterServiceBandRequest = ; // UpdateMasterServiceBandRequest | 

try {
    final response = api.updateMasterServiceBand(salonId, masterId, serviceDefId, updateMasterServiceBandRequest);
    print(response);
} catch on DioException (e) {
    print('Exception when calling ServiceControllerApi->updateMasterServiceBand: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **salonId** | **String**|  | 
 **masterId** | **String**| Master row id (NOT a user id) | 
 **serviceDefId** | **String**|  | 
 **updateMasterServiceBandRequest** | [**UpdateMasterServiceBandRequest**](UpdateMasterServiceBandRequest.md)|  | 

### Return type

[**ApiResponseMasterServiceResponse**](ApiResponseMasterServiceResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **updateServiceDefinition**
> ApiResponseServiceDefinitionResponse updateServiceDefinition(serviceDefId, updateServiceDefinitionRequest)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getServiceControllerApi();
final String serviceDefId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final UpdateServiceDefinitionRequest updateServiceDefinitionRequest = ; // UpdateServiceDefinitionRequest | 

try {
    final response = api.updateServiceDefinition(serviceDefId, updateServiceDefinitionRequest);
    print(response);
} catch on DioException (e) {
    print('Exception when calling ServiceControllerApi->updateServiceDefinition: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **serviceDefId** | **String**|  | 
 **updateServiceDefinitionRequest** | [**UpdateServiceDefinitionRequest**](UpdateServiceDefinitionRequest.md)|  | 

### Return type

[**ApiResponseServiceDefinitionResponse**](ApiResponseServiceDefinitionResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **updateServicePhoto**
> ApiResponseServiceDefinitionResponse updateServicePhoto(serviceDefId, updateServicePhotoRequest)



### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getServiceControllerApi();
final String serviceDefId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
final UpdateServicePhotoRequest updateServicePhotoRequest = ; // UpdateServicePhotoRequest | 

try {
    final response = api.updateServicePhoto(serviceDefId, updateServicePhotoRequest);
    print(response);
} catch on DioException (e) {
    print('Exception when calling ServiceControllerApi->updateServicePhoto: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **serviceDefId** | **String**|  | 
 **updateServicePhotoRequest** | [**UpdateServicePhotoRequest**](UpdateServicePhotoRequest.md)|  | 

### Return type

[**ApiResponseServiceDefinitionResponse**](ApiResponseServiceDefinitionResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

