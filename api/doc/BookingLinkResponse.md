# beautica_api.model.BookingLinkResponse

## Load the model package
```dart
import 'package:beautica_api/api.dart';
```

## Properties
Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**kind** | **String** | MASTER = the caller's own master booking page; SALON = a salon booking page (phase 376) | 
**status** | **String** | Phase 378: ACTIVE, or REVOKED (slug and url null, bookable false) | 
**slug** | **String** | Public slug; null when status is REVOKED. Never changes on rename; changes only by an explicit regenerate (the old slug is retired for good) | 
**url** | **String** | Absolute https canonical URL (the app adds its own share-channel flag): MASTER https://beautica.app/book/{slug}, SALON https://beautica.app/book/s/{slug}; null when status is REVOKED | 
**displayName** | **String** | Master full name, or salon name for SALON links | 
**salonId** | **String** | Salon id for SALON links; null for MASTER links | [optional] 
**bookable** | **bool** | false = clients see the page but cannot book yet (MASTER: no active service or no schedule; SALON: no bookable master) | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


