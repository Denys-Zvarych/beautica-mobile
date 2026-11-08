# beautica_api.model.PhoneOtpSendRequest

## Load the model package
```dart
import 'package:beautica_api/api.dart';
```

## Properties
Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**phone** | **String** |  | 
**privacyAccepted** | **bool** |  | 
**privacyPolicyVersion** | **String** |  | 
**turnstileToken** | **String** | Required when Turnstile is enabled (prod, staging). | [optional] 
**smsFormat** | **String** | Optional OTP SMS text. PLAIN = human line only; anything else (missing, null, unknown) = DOMAIN_BOUND (adds the origin-bound `@host #code` line). | [optional] 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


