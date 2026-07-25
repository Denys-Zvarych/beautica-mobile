# beautica_api.model.AppointmentItemResponse

## Load the model package
```dart
import 'package:beautica_api/api.dart';
```

## Properties
Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**bookingId** | **String** |  | [optional] 
**masterServiceId** | **String** |  | [optional] 
**serviceName** | **String** |  | [optional] 
**status** | **String** | The per-item status. A single service line may be DECLINED independently of its siblings (per-service decline); CONFIRMED means still booked. | [optional] 
**startsAt** | [**DateTime**](DateTime.md) |  | [optional] 
**endsAt** | [**DateTime**](DateTime.md) |  | [optional] 
**durationMinutesAtBooking** | **int** |  | [optional] 
**priceAtBooking** | **num** |  | [optional] 
**priceMaxAtBooking** | **num** | The frozen RANGE ceiling for this service, present only when it was a genuine range (no priceOverride) at booking time. Null = single price. | [optional] 
**cancellationReason** | **String** | This service line's own cancellation reason — non-null only when the line is terminal (e.g. PROVIDER_UNAVAILABLE for a per-service decline). | [optional] 
**providerComment** | **String** | Provider note written on THIS line's per-service decline. Mutually visible to the client (locked booking-notes decision). Null on a CONFIRMED line and on whole-visit terminations (whose note lives on the header). | [optional] 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


