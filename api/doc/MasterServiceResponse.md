# beautica_api.model.MasterServiceResponse

## Load the model package
```dart
import 'package:beautica_api/api.dart';
```

## Properties
Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**id** | **String** |  | [optional] 
**masterId** | **String** |  | [optional] 
**serviceDefinition** | [**ServiceDefinitionResponse**](ServiceDefinitionResponse.md) |  | [optional] 
**priceOverride** | **num** |  | [optional] 
**durationOverrideMinutes** | **int** |  | [optional] 
**effectivePrice** | **num** |  | [optional] 
**effectiveDurationMinutes** | **int** |  | [optional] 
**isActive** | **bool** |  | [optional] 
**priceType** | **String** |  | [optional] 
**priceMin** | **num** |  | [optional] 
**priceMax** | **num** |  | [optional] 
**priceDisplay** | **String** |  | [optional] 
**serviceTypeId** | **String** | Chosen service type id; null when no service type was selected. | [optional] 
**serviceTypeNameUk** | **String** | Ukrainian display name of the chosen service type; null when none was selected. | [optional] 
**serviceTypeSlug** | **String** | Stable slug of the chosen platform service type (matches the search filter's service-type key); null when none was selected. | [optional] 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


