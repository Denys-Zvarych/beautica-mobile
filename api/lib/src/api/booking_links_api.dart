//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

import 'dart:async';

import 'package:built_value/json_object.dart';
import 'package:built_value/serializer.dart';
import 'package:dio/dio.dart';

import 'package:beautica_api/src/api_util.dart';
import 'package:beautica_api/src/model/api_response_booking_link_response.dart';
import 'package:beautica_api/src/model/api_response_booking_links_response.dart';
import 'package:beautica_api/src/model/booking_link_mutation_request.dart';

class BookingLinksApi {
  final Dio _dio;

  final Serializers _serializers;

  const BookingLinksApi(this._dio, this._serializers);

  /// My shareable public booking links
  /// INDEPENDENT_MASTER gets its own MASTER link (https://beautica.app/book/{slug}). SALON_OWNER gets ONLY SALON links (https://beautica.app/book/s/{slug}), one per active owned salon, ordered by salon name, and no personal MASTER link; SALON_ADMIN gets the SALON link of the active salon it is bound to (the same link the owner shares). Inactive salons and inactive master rows yield no link. SALON_MASTER gets no links. A legacy master&#39;s or salon&#39;s slug is issued on the first call and never changes, not even on rename. bookable reports whether the public page can take a booking today (for a salon: at least one bookable master). When sharing is switched off server-side, shareEnabled is false and links is empty. 409 when a slug issue cannot acquire its lock in time (retry).
  ///
  /// Parameters:
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [ApiResponseBookingLinksResponse] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<ApiResponseBookingLinksResponse>> getMine({
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/api/v1/booking-links/mine';
    final _options = Options(
      method: r'GET',
      headers: <String, dynamic>{
        ...?headers,
      },
      extra: <String, dynamic>{
        'secure': <Map<String, String>>[],
        ...?extra,
      },
      validateStatus: validateStatus,
    );

    final _response = await _dio.request<Object>(
      _path,
      options: _options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );

    ApiResponseBookingLinksResponse? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null
          ? null
          : _serializers.deserialize(
              rawResponse,
              specifiedType: const FullType(ApiResponseBookingLinksResponse),
            ) as ApiResponseBookingLinksResponse;
    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<ApiResponseBookingLinksResponse>(
      data: _responseData,
      headers: _response.headers,
      isRedirect: _response.isRedirect,
      requestOptions: _response.requestOptions,
      redirects: _response.redirects,
      statusCode: _response.statusCode,
      statusMessage: _response.statusMessage,
      extra: _response.extra,
    );
  }

  /// Regenerate my master booking link
  /// INDEPENDENT_MASTER only. Retires the current slug (if any) and issues a new one; from a REVOKED link this creates a new active link. Body: {\&quot;currentSlug\&quot;: \&quot;&lt;the slug the app shows&gt;\&quot;} or {\&quot;currentSlug\&quot;: null} when the link is REVOKED (optimistic concurrency). The retired slug is never issued to anyone again. 404 when sharing is switched off server-side or the master / salon is not active; 409 when currentSlug is stale (refresh and retry) or no unique slug could be allocated; 429 after 10 regenerate/revoke calls per user per hour (all four routes share the budget).
  ///
  /// Parameters:
  /// * [bookingLinkMutationRequest]
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [ApiResponseBookingLinkResponse] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<ApiResponseBookingLinkResponse>> regenerateMaster({
    required BookingLinkMutationRequest bookingLinkMutationRequest,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/api/v1/booking-links/master/regenerate';
    final _options = Options(
      method: r'POST',
      headers: <String, dynamic>{
        ...?headers,
      },
      extra: <String, dynamic>{
        'secure': <Map<String, String>>[],
        ...?extra,
      },
      contentType: 'application/json',
      validateStatus: validateStatus,
    );

    dynamic _bodyData;

    try {
      const _type = FullType(BookingLinkMutationRequest);
      _bodyData = _serializers.serialize(bookingLinkMutationRequest,
          specifiedType: _type);
    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _options.compose(
          _dio.options,
          _path,
        ),
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    final _response = await _dio.request<Object>(
      _path,
      data: _bodyData,
      options: _options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );

    ApiResponseBookingLinkResponse? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null
          ? null
          : _serializers.deserialize(
              rawResponse,
              specifiedType: const FullType(ApiResponseBookingLinkResponse),
            ) as ApiResponseBookingLinkResponse;
    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<ApiResponseBookingLinkResponse>(
      data: _responseData,
      headers: _response.headers,
      isRedirect: _response.isRedirect,
      requestOptions: _response.requestOptions,
      redirects: _response.redirects,
      statusCode: _response.statusCode,
      statusMessage: _response.statusMessage,
      extra: _response.extra,
    );
  }

  /// Regenerate a salon booking link
  /// SALON_OWNER of the salon (any salon they own) or the SALON_ADMIN bound to it; any other salon → 403. Retires the current slug (if any) and issues a new one. Body: {\&quot;currentSlug\&quot;: \&quot;&lt;the slug the app shows&gt;\&quot;} or {\&quot;currentSlug\&quot;: null} when the link is REVOKED (optimistic concurrency). The retired slug is never issued to anyone again. 404 when sharing is switched off server-side or the master / salon is not active; 409 when currentSlug is stale (refresh and retry) or no unique slug could be allocated; 429 after 10 regenerate/revoke calls per user per hour (all four routes share the budget).
  ///
  /// Parameters:
  /// * [salonId]
  /// * [bookingLinkMutationRequest]
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [ApiResponseBookingLinkResponse] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<ApiResponseBookingLinkResponse>> regenerateSalon({
    required String salonId,
    required BookingLinkMutationRequest bookingLinkMutationRequest,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/api/v1/booking-links/salons/{salonId}/regenerate'
        .replaceAll(
            '{' r'salonId' '}',
            encodeQueryParameter(_serializers, salonId, const FullType(String))
                .toString());
    final _options = Options(
      method: r'POST',
      headers: <String, dynamic>{
        ...?headers,
      },
      extra: <String, dynamic>{
        'secure': <Map<String, String>>[],
        ...?extra,
      },
      contentType: 'application/json',
      validateStatus: validateStatus,
    );

    dynamic _bodyData;

    try {
      const _type = FullType(BookingLinkMutationRequest);
      _bodyData = _serializers.serialize(bookingLinkMutationRequest,
          specifiedType: _type);
    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _options.compose(
          _dio.options,
          _path,
        ),
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    final _response = await _dio.request<Object>(
      _path,
      data: _bodyData,
      options: _options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );

    ApiResponseBookingLinkResponse? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null
          ? null
          : _serializers.deserialize(
              rawResponse,
              specifiedType: const FullType(ApiResponseBookingLinkResponse),
            ) as ApiResponseBookingLinkResponse;
    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<ApiResponseBookingLinkResponse>(
      data: _responseData,
      headers: _response.headers,
      isRedirect: _response.isRedirect,
      requestOptions: _response.requestOptions,
      redirects: _response.redirects,
      statusCode: _response.statusCode,
      statusMessage: _response.statusMessage,
      extra: _response.extra,
    );
  }

  /// Revoke my master booking link
  /// INDEPENDENT_MASTER only. Switches the link off: the slug is retired, GET /mine shows status REVOKED and never re-issues it. Idempotent when already revoked (currentSlug null). Body: {\&quot;currentSlug\&quot;: \&quot;&lt;the slug the app shows&gt;\&quot;} or {\&quot;currentSlug\&quot;: null} when the link is REVOKED (optimistic concurrency). The retired slug is never issued to anyone again. 404 when sharing is switched off server-side or the master / salon is not active; 409 when currentSlug is stale (refresh and retry) or no unique slug could be allocated; 429 after 10 regenerate/revoke calls per user per hour (all four routes share the budget).
  ///
  /// Parameters:
  /// * [bookingLinkMutationRequest]
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [ApiResponseBookingLinkResponse] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<ApiResponseBookingLinkResponse>> revokeMaster({
    required BookingLinkMutationRequest bookingLinkMutationRequest,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/api/v1/booking-links/master';
    final _options = Options(
      method: r'DELETE',
      headers: <String, dynamic>{
        ...?headers,
      },
      extra: <String, dynamic>{
        'secure': <Map<String, String>>[],
        ...?extra,
      },
      contentType: 'application/json',
      validateStatus: validateStatus,
    );

    dynamic _bodyData;

    try {
      const _type = FullType(BookingLinkMutationRequest);
      _bodyData = _serializers.serialize(bookingLinkMutationRequest,
          specifiedType: _type);
    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _options.compose(
          _dio.options,
          _path,
        ),
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    final _response = await _dio.request<Object>(
      _path,
      data: _bodyData,
      options: _options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );

    ApiResponseBookingLinkResponse? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null
          ? null
          : _serializers.deserialize(
              rawResponse,
              specifiedType: const FullType(ApiResponseBookingLinkResponse),
            ) as ApiResponseBookingLinkResponse;
    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<ApiResponseBookingLinkResponse>(
      data: _responseData,
      headers: _response.headers,
      isRedirect: _response.isRedirect,
      requestOptions: _response.requestOptions,
      redirects: _response.redirects,
      statusCode: _response.statusCode,
      statusMessage: _response.statusMessage,
      extra: _response.extra,
    );
  }

  /// Revoke a salon booking link
  /// SALON_OWNER of the salon or the SALON_ADMIN bound to it; any other salon → 403. Switches the salon link off (status REVOKED, never re-issued by GET /mine). Idempotent when already revoked (currentSlug null). Body: {\&quot;currentSlug\&quot;: \&quot;&lt;the slug the app shows&gt;\&quot;} or {\&quot;currentSlug\&quot;: null} when the link is REVOKED (optimistic concurrency). The retired slug is never issued to anyone again. 404 when sharing is switched off server-side or the master / salon is not active; 409 when currentSlug is stale (refresh and retry) or no unique slug could be allocated; 429 after 10 regenerate/revoke calls per user per hour (all four routes share the budget).
  ///
  /// Parameters:
  /// * [salonId]
  /// * [bookingLinkMutationRequest]
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [ApiResponseBookingLinkResponse] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<ApiResponseBookingLinkResponse>> revokeSalon({
    required String salonId,
    required BookingLinkMutationRequest bookingLinkMutationRequest,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/api/v1/booking-links/salons/{salonId}'.replaceAll(
        '{' r'salonId' '}',
        encodeQueryParameter(_serializers, salonId, const FullType(String))
            .toString());
    final _options = Options(
      method: r'DELETE',
      headers: <String, dynamic>{
        ...?headers,
      },
      extra: <String, dynamic>{
        'secure': <Map<String, String>>[],
        ...?extra,
      },
      contentType: 'application/json',
      validateStatus: validateStatus,
    );

    dynamic _bodyData;

    try {
      const _type = FullType(BookingLinkMutationRequest);
      _bodyData = _serializers.serialize(bookingLinkMutationRequest,
          specifiedType: _type);
    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _options.compose(
          _dio.options,
          _path,
        ),
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    final _response = await _dio.request<Object>(
      _path,
      data: _bodyData,
      options: _options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );

    ApiResponseBookingLinkResponse? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null
          ? null
          : _serializers.deserialize(
              rawResponse,
              specifiedType: const FullType(ApiResponseBookingLinkResponse),
            ) as ApiResponseBookingLinkResponse;
    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<ApiResponseBookingLinkResponse>(
      data: _responseData,
      headers: _response.headers,
      isRedirect: _response.isRedirect,
      requestOptions: _response.requestOptions,
      redirects: _response.redirects,
      statusCode: _response.statusCode,
      statusMessage: _response.statusMessage,
      extra: _response.extra,
    );
  }
}
