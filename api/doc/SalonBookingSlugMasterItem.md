# beautica_api.model.SalonBookingSlugMasterItem

## Load the model package
```dart
import 'package:beautica_api/api.dart';
```

## Properties
Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**masterSlug** | **String** | The master's personal booking slug (GET /api/v1/book/{slug}/info); null when the master has no live personal link (phase 391) — book them through the salon routes /api/v1/book/s/{slug}/masters/{masterId}/_*. | [optional] 
**name** | **String** | Composed \"First Last\". | 
**avatarUrl** | **String** |  | [optional] 
**professionalTitle** | **String** |  | [optional] 
**avgRating** | **num** | The master's rating as the app's salon master card shows it; null while the master has no reviews (never a fabricated 0). | [optional] 
**reviewCount** | **int** |  | 
**masterId** | **String** | Phase 391 — the master's id: the {masterId} of /api/v1/book/s/{slug}/masters/{masterId}/_* and the key serviceCoverage[].masters[].masterId refers to. | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


