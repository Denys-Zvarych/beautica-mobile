# beautica_api.model.BookingLinkResponse

## Load the model package
```dart
import 'package:beautica_api/api.dart';
```

## Properties
Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**kind** | **String** | MASTER = the caller's own master booking page; SALON = a salon booking page (phase 376) | 
**slug** | **String** | Permanent public slug; never changes once issued | 
**url** | **String** | Absolute https URL, no UTM (the app appends UTM per share action): MASTER https://beautica.app/book/{slug}, SALON https://beautica.app/book/s/{slug} | 
**displayName** | **String** | Master full name, or salon name for SALON links | 
**salonId** | **String** | Salon id for SALON links; null for MASTER links | [optional] 
**bookable** | **bool** | false = clients see the page but cannot book yet (MASTER: no active service or no schedule; SALON: no bookable master) | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


