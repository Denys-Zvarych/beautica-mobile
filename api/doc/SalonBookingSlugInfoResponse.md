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
**region** | **String** | Settlement region label (salons.region). | [optional] 
**street** | **String** | Street; falls back to the legacy free-text address when street is blank. | [optional] 
**buildingNo** | **String** |  | [optional] 
**updatedAt** | [**DateTime**](DateTime.md) | Salon last edited; display/JSON-LD only, never a cache validator. | 
**description** | **String** | As PublicSalonResponse.description. | [optional] 
**locationNote** | **String** | As PublicSalonResponse.locationNote. | [optional] 
**portfolio** | [**BuiltList&lt;MediaFileResponse&gt;**](MediaFileResponse.md) | Newest photos first, capped like the master page (12); the payload of GET /salons/{id}/portfolio. | 
**serviceCategories** | [**BuiltList&lt;SalonServiceCategoryGroup&gt;**](SalonServiceCategoryGroup.md) | Bookable services grouped by category — GET /salons/{id}/services, unchanged. | 
**ratingDistribution** | [**BuiltList&lt;RatingBucket&gt;**](RatingBucket.md) | Zero-filled 5..1 histogram — GET /salons/{id}/reviews/summary. | 
**latestReviews** | [**BuiltList&lt;SalonReviewResponse&gt;**](SalonReviewResponse.md) | The newest 5 reviews — the SalonReviewResponse rows of GET /salons/{id}/reviews. | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


