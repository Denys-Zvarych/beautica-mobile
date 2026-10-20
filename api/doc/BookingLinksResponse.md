# beautica_api.model.BookingLinksResponse

## Load the model package
```dart
import 'package:beautica_api/api.dart';
```

## Properties
Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**shareEnabled** | **bool** | Server kill-switch; false = sharing is hidden and links is empty | 
**links** | [**BuiltList&lt;BookingLinkResponse&gt;**](BookingLinkResponse.md) | MASTER link first, then SALON links by salon name | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


