# beautica_api.model.ServicePriceShapeMismatchResponse

## Load the model package
```dart
import 'package:beautica_api/api.dart';
```

## Properties
Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**code** | **String** | Stable machine-readable error code. Always present — the only field the client branches on. | [optional] 
**serviceName** | **String** | Display name of the service whose shape clashed (the service type's Ukrainian name). | [optional] 
**existingServiceDefId** | **String** | Id of the salon definition that governs the shape, for a deep-link. | [optional] 
**salonPriceType** | **String** | The salon definition's pricing mode — the shape the submitted item had to match. | [optional] 
**salonPriceMin** | [**ServicePriceShapeMismatchResponseSalonPriceMin**](ServicePriceShapeMismatchResponseSalonPriceMin.md) |  | [optional] 
**salonPriceMax** | [**ServicePriceShapeMismatchResponseSalonPriceMax**](ServicePriceShapeMismatchResponseSalonPriceMax.md) |  | [optional] 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


