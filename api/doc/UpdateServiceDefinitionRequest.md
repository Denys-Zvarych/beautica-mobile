# beautica_api.model.UpdateServiceDefinitionRequest

## Load the model package
```dart
import 'package:beautica_api/api.dart';
```

## Properties
Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**name** | **String** |  | [optional] 
**description** | **String** |  | [optional] 
**category** | **String** |  | [optional] 
**baseDurationMinutes** | **int** |  | [optional] 
**bufferMinutesAfter** | **int** |  | [optional] 
**priceType** | **String** |  | [optional] 
**price** | **num** |  | [optional] 
**priceMin** | **num** |  | [optional] 
**priceMax** | **num** |  | [optional] 
**serviceTypeId** | **String** | Optional id of the platform service type to switch this service to. Omit or send null to leave the current service type unchanged. | [optional] 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


