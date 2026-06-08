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
**serviceTypeId** | **String** | Optional id of the chosen platform service type. Omit or send null when the master skips the (optional) service-type picker. | [optional] 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


