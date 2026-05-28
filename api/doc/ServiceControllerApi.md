# beautica_api.api.ServiceControllerApi

## Load the API package
```dart
import 'package:beautica_api/api.dart';
```

All URIs are relative to *http://localhost:8080/api/v1*

Method | HTTP request | Description
------------- | ------------- | -------------
[**addIndependentMasterService**](ServiceControllerApi.md#addindependentmasterservice) | **POST** /independent-masters/me/services | 
[**addServiceToSalon**](ServiceControllerApi.md#addservicetosalon) | **POST** /salons/{salonId}/services | 
[**assignServiceToMaster**](ServiceControllerApi.md#assignservicetomaster) | **POST** /salons/{salonId}/masters/{masterId}/services | 
[**deactivateServiceDefinition**](ServiceControllerApi.md#deactivateservicedefinition) | **DELETE** /services/{serviceDefId} | 
[**getMasterServices**](ServiceControllerApi.md#getmasterservices) | **GET** /masters/{masterId}/services | 


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

[BearerAuth](../README.md#BearerAuth)

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

[BearerAuth](../README.md#BearerAuth)

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
final String masterId = 38400000-8cf0-11bd-b23e-10b96e4ef00d; // String | 
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
 **masterId** | **String**|  | 
 **assignServiceToMasterRequest** | [**AssignServiceToMasterRequest**](AssignServiceToMasterRequest.md)|  | 

### Return type

[**ApiResponseMasterServiceResponse**](ApiResponseMasterServiceResponse.md)

### Authorization

[BearerAuth](../README.md#BearerAuth)

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

[BearerAuth](../README.md#BearerAuth)

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

[BearerAuth](../README.md#BearerAuth)

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

