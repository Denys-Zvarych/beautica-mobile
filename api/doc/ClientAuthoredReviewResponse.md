# beautica_api.model.ClientAuthoredReviewResponse

## Load the model package
```dart
import 'package:beautica_api/api.dart';
```

## Properties
Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**rating** | **int** | The client's star rating for this booking, 1-5. | [optional] 
**comment** | **String** | The client's review text, verbatim and unabridged, or null when they rated without writing anything. Already public via GET /masters/{id}/reviews — never truncated or masked here. | [optional] 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


