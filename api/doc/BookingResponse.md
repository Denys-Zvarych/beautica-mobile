# beautica_api.model.BookingResponse

## Load the model package
```dart
import 'package:beautica_api/api.dart';
```

## Properties
Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**id** | **String** |  | [optional] 
**clientId** | **String** |  | [optional] 
**masterId** | **String** |  | [optional] 
**masterServiceId** | **String** |  | [optional] 
**serviceName** | **String** |  | [optional] 
**status** | **String** |  | [optional] 
**startsAt** | [**DateTime**](DateTime.md) |  | [optional] 
**endsAt** | [**DateTime**](DateTime.md) |  | [optional] 
**priceAtBooking** | **num** |  | [optional] 
**priceMaxAtBooking** | **num** | The range ceiling agreed AT BOOKING TIME, present ONLY when the master left this service's price as a genuine RANGE (no priceOverride) when the booking was made. Null means a single price — render priceAtBooking alone. The client must never re-derive this from priceType/priceOverride; the decision is made server-side, once. | [optional] 
**durationMinutesAtBooking** | **int** |  | [optional] 
**createdAt** | [**DateTime**](DateTime.md) |  | [optional] 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


