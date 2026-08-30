# beautica_api.model.PublicSalonResponse

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
**city** | **String** |  | [optional] 
**region** | **String** |  | [optional] 
**address** | **String** |  | [optional] 
**cityId** | **String** | Taxonomy city. Every salon has one — salons.city_id is DB-level NOT NULL (V150/V151) and application-enforced from Phase 10.6 (LocalityWriteValidator). Never null on the wire. | 
**oblastId** | **String** | Parent oblast of cityId, resolved at read time (see #from). cities.oblast_id is itself DB-level NOT NULL with a FK to oblasts, and cityId is guaranteed non-null and FK-valid, so resolution always succeeds. Never null on the wire. | 
**districtId** | **String** |  | [optional] 
**street** | **String** |  | [optional] 
**buildingNo** | **String** |  | [optional] 
**locationNote** | **String** |  | [optional] 
**instagramUrl** | **String** |  | [optional] 
**avatarUrl** | **String** |  | [optional] 
**coverImageUrl** | **String** |  | [optional] 
**avgRating** | **num** |  | [optional] 
**reviewCount** | **int** |  | [optional] 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


