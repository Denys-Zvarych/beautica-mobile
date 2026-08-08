# beautica_api.model.FavoriteServiceResponse

## Load the model package
```dart
import 'package:beautica_api/api.dart';
```

## Properties
Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**masterServiceId** | **String** |  | [optional] 
**masterId** | **String** |  | [optional] 
**serviceName** | **String** |  | [optional] 
**masterFirstName** | **String** |  | [optional] 
**masterLastName** | **String** |  | [optional] 
**masterAvatarUrl** | **String** | users.avatar_url of the performing master; null when unset. | [optional] 
**durationMinutes** | **int** |  | [optional] 
**priceType** | **String** |  | [optional] 
**priceMin** | **num** |  | [optional] 
**priceMax** | **num** | RANGE ceiling; null for FIXED. | [optional] 
**priceDisplay** | **String** | Pre-formatted band, e.g. \"600 ₴\" or \"від 600 до 900 ₴\"; null only for a legacy definition with no price. | [optional] 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


