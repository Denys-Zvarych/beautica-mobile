# beautica_api.model.SalonSearchResult

## Load the model package
```dart
import 'package:beautica_api/api.dart';
```

## Properties
Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**salonId** | **String** |  | [optional] 
**name** | **String** |  | [optional] 
**cityLabel** | **String** |  | [optional] 
**districtLabel** | **String** |  | [optional] 
**avatarUrl** | **String** |  | [optional] 
**priceMin** | **num** |  | [optional] 
**priceMax** | **num** |  | [optional] 
**serviceNames** | **BuiltList&lt;String&gt;** |  | [optional] 
**street** | **String** |  | [optional] 
**buildingNo** | **String** |  | [optional] 
**locationNote** | **String** |  | [optional] 
**matchedServiceNames** | **BuiltList&lt;String&gt;** |  | [optional] 
**isFavorite** | **bool** | Whether the signed-in CLIENT has favourited this salon. Always false for anonymous and non-CLIENT callers. Decorated per request, after the cache read. | [optional] [default to false]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


