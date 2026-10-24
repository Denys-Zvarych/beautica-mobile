# beautica_api.model.BookingSlugInfoResponse

## Load the model package
```dart
import 'package:beautica_api/api.dart';
```

## Properties
Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**masterName** | **String** |  | 
**avatarUrl** | **String** |  | [optional] 
**bio** | **String** |  | [optional] 
**services** | [**BuiltList&lt;ServiceSummaryDto&gt;**](ServiceSummaryDto.md) |  | 
**masterId** | **String** |  | 
**masterType** | **String** |  | 
**professionalTitle** | **String** |  | [optional] 
**city** | **String** |  | [optional] 
**region** | **String** |  | [optional] 
**salon** | [**BookingSlugSalonRef**](BookingSlugSalonRef.md) | null for independent masters. | [optional] 
**avgRating** | **num** | null while the master has no reviews (never a fabricated 0). | [optional] 
**reviewCount** | **int** |  | 
**categories** | [**BuiltList&lt;CategoryRef&gt;**](CategoryRef.md) |  | 
**portfolio** | [**BuiltList&lt;MediaFileResponse&gt;**](MediaFileResponse.md) |  | 
**latestReviews** | [**BuiltList&lt;ReviewResponse&gt;**](ReviewResponse.md) |  | 
**bookable** | **bool** | false when the master has no active service or no working schedule yet; the page then renders «not accepting online bookings». | 
**updatedAt** | [**DateTime**](DateTime.md) | Profile last edited; display/JSON-LD only, never a cache validator. | 
**ratingDistribution** | [**BuiltList&lt;RatingBucket&gt;**](RatingBucket.md) | Zero-filled 5..1 histogram, the same as GET /masters/{id}/reviews/summary (phase 383). | 
**street** | **String** | Non-null only for INDEPENDENT_MASTER (the app's public-profile address rule). | [optional] 
**buildingNo** | **String** | Non-null only for INDEPENDENT_MASTER. | [optional] 
**locationNote** | **String** | Non-null only for INDEPENDENT_MASTER. | [optional] 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


