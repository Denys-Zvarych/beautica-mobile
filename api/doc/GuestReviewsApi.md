# beautica_api.api.GuestReviewsApi

## Load the API package
```dart
import 'package:beautica_api/api.dart';
```

All URIs are relative to *http://localhost:8080*

Method | HTTP request | Description
------------- | ------------- | -------------
[**getInvite**](GuestReviewsApi.md#getinvite) | **GET** /api/v1/public/review-invites/{token} | Read a review invite
[**optOut**](GuestReviewsApi.md#optout) | **POST** /api/v1/public/review-invites/{token}/opt-out | Stop review-invite SMS for this phone
[**submit**](GuestReviewsApi.md#submit) | **POST** /api/v1/public/review-invites/{token}/reviews | Submit the guest&#39;s review(s)


# **getInvite**
> ReviewInviteResponse getInvite(token)

Read a review invite

The visit to rate, or state=ALREADY_REVIEWED once the token was used. Unknown, expired and malformed tokens are one identical 404.

### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getGuestReviewsApi();
final String token = token_example; // String | 

try {
    final response = api.getInvite(token);
    print(response);
} catch on DioException (e) {
    print('Exception when calling GuestReviewsApi->getInvite: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **token** | **String**|  | 

### Return type

[**ReviewInviteResponse**](ReviewInviteResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: Not defined
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **optOut**
> optOut(token, reviewInviteOptOutRequest)

Stop review-invite SMS for this phone

Idempotent; valid for 30 days after the invite was sent, also after reviewing.

### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getGuestReviewsApi();
final String token = token_example; // String | 
final ReviewInviteOptOutRequest reviewInviteOptOutRequest = ; // ReviewInviteOptOutRequest | 

try {
    api.optOut(token, reviewInviteOptOutRequest);
} catch on DioException (e) {
    print('Exception when calling GuestReviewsApi->optOut: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **token** | **String**|  | 
 **reviewInviteOptOutRequest** | [**ReviewInviteOptOutRequest**](ReviewInviteOptOutRequest.md)|  | [optional] 

### Return type

void (empty response body)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: Not defined

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

# **submit**
> GuestReviewSubmitResponse submit(token, guestReviewSubmitRequest)

Submit the guest's review(s)

Rates any subset of the visit's services, once per token.

### Example
```dart
import 'package:beautica_api/api.dart';

final api = BeauticaApi().getGuestReviewsApi();
final String token = token_example; // String | 
final GuestReviewSubmitRequest guestReviewSubmitRequest = ; // GuestReviewSubmitRequest | 

try {
    final response = api.submit(token, guestReviewSubmitRequest);
    print(response);
} catch on DioException (e) {
    print('Exception when calling GuestReviewsApi->submit: $e\n');
}
```

### Parameters

Name | Type | Description  | Notes
------------- | ------------- | ------------- | -------------
 **token** | **String**|  | 
 **guestReviewSubmitRequest** | [**GuestReviewSubmitRequest**](GuestReviewSubmitRequest.md)|  | 

### Return type

[**GuestReviewSubmitResponse**](GuestReviewSubmitResponse.md)

### Authorization

No authorization required

### HTTP request headers

 - **Content-Type**: application/json
 - **Accept**: */*

[[Back to top]](#) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to Model list]](../README.md#documentation-for-models) [[Back to README]](../README.md)

