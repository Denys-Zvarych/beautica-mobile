# beautica_api.model.CreateServiceDefinitionRequest

## Load the model package
```dart
import 'package:beautica_api/api.dart';
```

## Properties
Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**name** | **String** |  | [optional] 
**description** | **String** |  | [optional] 
**category** | **String** |  | 
**baseDurationMinutes** | **int** |  | 
**bufferMinutesAfter** | **int** |  | [optional] 
**priceType** | **String** |  | 
**price** | **num** |  | [optional] 
**priceMin** | **num** |  | [optional] 
**priceMax** | **num** |  | [optional] 
**serviceTypeId** | **String** | Id of the chosen platform service type. Required — the service-type picker cannot be skipped. The type must be active and belong to the selected category. Persisted service_type_id is NOT NULL at the DB level, so an untyped service can never be created (search filters on this column). | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


