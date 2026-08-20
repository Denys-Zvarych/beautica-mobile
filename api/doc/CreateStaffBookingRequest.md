# beautica_api.model.CreateStaffBookingRequest

## Load the model package
```dart
import 'package:beautica_api/api.dart';
```

## Properties
Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**masterServiceIds** | **BuiltList&lt;String&gt;** | Ordered services performed back-to-back by this master, in the order they are performed. Duplicates are permitted — the same service twice is a valid visit. The chain starts at startsAt; each subsequent service begins when the previous one's effective duration plus its own after-buffer has elapsed. | 
**startsAt** | [**DateTime**](DateTime.md) | ISO-8601 start instant; must land on the master's real slot grid. | 
**guest** | [**GuestClientDto**](GuestClientDto.md) |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


