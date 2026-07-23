# beautica_api.model.DuplicateServiceResponse

## Load the model package
```dart
import 'package:beautica_api/api.dart';
```

## Properties
Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**code** | **String** | Stable machine-readable error code. Always present — the only field the client branches on. | [optional] 
**serviceName** | **String** | Human-readable label for the conflicting service, so the client can name it without a second round-trip: the service TYPE's name when the service-layer pre-check caught the conflict, the name the caller just SUBMITTED when the DB index caught a race instead. Null only on the bulk path. | [optional] 
**existingServiceDefId** | **String** | Id of the existing service definition, for a deep-link. Null when the DB index caught the conflict rather than the service-layer pre-check. | [optional] 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


