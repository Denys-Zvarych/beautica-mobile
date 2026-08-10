# beautica_api.model.FavoriteServiceResponse

## Load the model package
```dart
import 'package:beautica_api/api.dart';
```

## Properties
Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**sourceType** | **String** | Which favourite arm this row came from — MASTER (a chosen master's assignment) or SALON (a salon-catalogue service, no master chosen yet). | [optional] 
**masterServiceId** | **String** |  | [optional] 
**masterId** | **String** |  | [optional] 
**serviceDefId** | **String** |  | [optional] 
**serviceName** | **String** |  | [optional] 
**masterFirstName** | **String** |  | [optional] 
**masterLastName** | **String** |  | [optional] 
**masterAvatarUrl** | **String** | users.avatar_url of the performing master; null when unset or for a SALON row. | [optional] 
**durationMinutes** | **int** |  | [optional] 
**priceType** | **String** |  | [optional] 
**priceMin** | **num** |  | [optional] 
**priceMax** | **num** | RANGE ceiling; null for FIXED. | [optional] 
**priceDisplay** | **String** | Pre-formatted band, e.g. \"600 ₴\" or \"від 600 до 900 ₴\"; null only for a legacy definition with no price. | [optional] 
**salonId** | **String** | salons.id — null for a MASTER row. | [optional] 
**salonName** | **String** | salons.name — null for a MASTER row. | [optional] 
**salonAvatarUrl** | **String** | salons.avatar_url — null for a MASTER row. | [optional] 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


