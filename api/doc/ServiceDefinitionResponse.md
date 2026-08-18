# beautica_api.model.ServiceDefinitionResponse

## Load the model package
```dart
import 'package:beautica_api/api.dart';
```

## Properties
Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**id** | **String** |  | [optional] 
**name** | **String** |  | [optional] 
**description** | **String** |  | [optional] 
**category** | **String** |  | [optional] 
**baseDurationMinutes** | **int** |  | [optional] 
**bufferMinutesAfter** | **int** |  | [optional] 
**isActive** | **bool** |  | [optional] 
**serviceTypeId** | **String** | Chosen service type id; null when no service type was selected. | [optional] 
**serviceTypeNameUk** | **String** | Ukrainian display name of the chosen service type; null when none was selected. | [optional] 
**serviceTypeSlug** | **String** | Stable slug of the chosen platform service type (matches CategoryServiceOption.key on the client); null when none was selected. | [optional] 
**photoUrl** | **String** |  | [optional] 
**priceType** | **String** |  | [optional] 
**priceMin** | **num** |  | [optional] 
**priceMax** | **num** |  | [optional] 
**priceDisplay** | **String** |  | [optional] 
**isFavorite** | **bool** | true/false only for an authenticated CLIENT caller on GET /salons/{salonId}/services; null everywhere else (anonymous/non-CLIENT callers, every provider-side service-management response, and always null inside the salon-service-catalog cache) — decorated per-request, after the cache read. | [optional] 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


