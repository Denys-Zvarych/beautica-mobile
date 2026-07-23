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
**startsAt** | [**DateTime**](DateTime.md) |  | [optional] 
**endsAt** | [**DateTime**](DateTime.md) |  | [optional] 
**durationMinutesAtBooking** | **int** |  | [optional] 
**priceAtBooking** | **num** |  | [optional] 
**priceMaxAtBooking** | **num** | The frozen RANGE ceiling for this service, present only when it was a genuine range (no priceOverride) at booking time. Null = single price. | [optional] 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


