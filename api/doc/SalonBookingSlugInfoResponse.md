# beautica_api.model.SalonBookingSlugInfoResponse

## Load the model package
```dart
import 'package:beautica_api/api.dart';
```

## Properties
Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**salonId** | **String** |  | 
**name** | **String** |  | 
**city** | **String** | Settlement display name (salons.city, denormalised from the taxonomy city). | [optional] 
**avatarUrl** | **String** |  | [optional] 
**coverImageUrl** | **String** |  | [optional] 
**avgRating** | **num** | null while the salon has no reviews (never a fabricated 0). | [optional] 
**reviewCount** | **int** |  | 
**bookable** | **bool** | false when no master of the salon is bookable yet; masters is then empty. | 
**masters** | [**BuiltList&lt;SalonBookingSlugMasterItem&gt;**](SalonBookingSlugMasterItem.md) |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


