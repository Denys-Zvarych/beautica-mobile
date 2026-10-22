# beautica_api.model.SalonBookingSlugMasterItem

## Load the model package
```dart
import 'package:beautica_api/api.dart';
```

## Properties
Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**masterSlug** | **String** | The master's public booking slug; use it with GET /api/v1/book/{slug}/info, /availability and /booking. | 
**name** | **String** | Composed \"First Last\". | 
**avatarUrl** | **String** |  | [optional] 
**professionalTitle** | **String** |  | [optional] 
**avgRating** | **num** | The master's rating as the app's salon master card shows it; null while the master has no reviews (never a fabricated 0). | [optional] 
**reviewCount** | **int** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


