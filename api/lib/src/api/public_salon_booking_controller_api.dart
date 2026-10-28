//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

import 'dart:async';

import 'package:built_value/json_object.dart';
import 'package:built_value/serializer.dart';
import 'package:dio/dio.dart';

import 'package:beautica_api/src/api_util.dart';
import 'package:beautica_api/src/model/available_slot_response.dart';
import 'package:beautica_api/src/model/date.dart';
import 'package:beautica_api/src/model/guest_booking_request.dart';
import 'package:beautica_api/src/model/guest_booking_response.dart';
import 'package:beautica_api/src/model/master_working_day_response.dart';
import 'package:built_collection/built_collection.dart';

class PublicSalonBookingControllerApi {
  final Dio _dio;

  final Serializers _serializers;

  const PublicSalonBookingControllerApi(this._dio, this._serializers);

  /// availability1
  ///
  ///
  /// Parameters:
  /// * [slug]
  /// * [masterId]
  /// * [date]
  /// * [serviceId]
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [BuiltList<AvailableSlotResponse>] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<BuiltList<AvailableSlotResponse>>> availability1({
    required String slug,
    required String masterId,
    required Date date,
    required BuiltList<String> serviceId,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/api/v1/book/s/{slug}/masters/{masterId}/availability'
        .replaceAll(
            '{' r'slug' '}',
            encodeQueryParameter(_serializers, slug, const FullType(String))
                .toString())
        .replaceAll(
            '{' r'masterId' '}',
            encodeQueryParameter(_serializers, masterId, const FullType(String))
                .toString());
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

    final _queryParameters = <String, dynamic>{
      r'date': encodeQueryParameter(_serializers, date, const FullType(Date)),
      r'serviceId': encodeCollectionQueryParameter<String>(
        _serializers,
        serviceId,
        const FullType(BuiltList, [FullType(String)]),
        format: ListFormat.multi,
      ),
    };

    final _response = await _dio.request<Object>(
      _path,
      options: _options,
      queryParameters: _queryParameters,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );

    BuiltList<AvailableSlotResponse>? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null
          ? null
          : _serializers.deserialize(
              rawResponse,
              specifiedType:
                  const FullType(BuiltList, [FullType(AvailableSlotResponse)]),
            ) as BuiltList<AvailableSlotResponse>;
    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<BuiltList<AvailableSlotResponse>>(
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

  /// book1
  ///
  ///
  /// Parameters:
  /// * [slug]
  /// * [masterId]
  /// * [guestBookingRequest]
  /// * [authorization]
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [GuestBookingResponse] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<GuestBookingResponse>> book1({
    required String slug,
    required String masterId,
    required GuestBookingRequest guestBookingRequest,
    String? authorization,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/api/v1/book/s/{slug}/masters/{masterId}/booking'
        .replaceAll(
            '{' r'slug' '}',
            encodeQueryParameter(_serializers, slug, const FullType(String))
                .toString())
        .replaceAll(
            '{' r'masterId' '}',
            encodeQueryParameter(_serializers, masterId, const FullType(String))
                .toString());
    final _options = Options(
      method: r'POST',
      headers: <String, dynamic>{
        if (authorization != null) r'Authorization': authorization,
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
      const _type = FullType(GuestBookingRequest);
      _bodyData =
          _serializers.serialize(guestBookingRequest, specifiedType: _type);
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

    GuestBookingResponse? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null
          ? null
          : _serializers.deserialize(
              rawResponse,
              specifiedType: const FullType(GuestBookingResponse),
            ) as GuestBookingResponse;
    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<GuestBookingResponse>(
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

  /// bookableDays1
  ///
  ///
  /// Parameters:
  /// * [slug]
  /// * [masterId]
  /// * [from]
  /// * [to]
  /// * [serviceId]
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [BuiltList<MasterWorkingDayResponse>] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<BuiltList<MasterWorkingDayResponse>>> bookableDays1({
    required String slug,
    required String masterId,
    required Date from,
    required Date to,
    required BuiltList<String> serviceId,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/api/v1/book/s/{slug}/masters/{masterId}/bookable-days'
        .replaceAll(
            '{' r'slug' '}',
            encodeQueryParameter(_serializers, slug, const FullType(String))
                .toString())
        .replaceAll(
            '{' r'masterId' '}',
            encodeQueryParameter(_serializers, masterId, const FullType(String))
                .toString());
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

    final _queryParameters = <String, dynamic>{
      r'from': encodeQueryParameter(_serializers, from, const FullType(Date)),
      r'to': encodeQueryParameter(_serializers, to, const FullType(Date)),
      r'serviceId': encodeCollectionQueryParameter<String>(
        _serializers,
        serviceId,
        const FullType(BuiltList, [FullType(String)]),
        format: ListFormat.multi,
      ),
    };

    final _response = await _dio.request<Object>(
      _path,
      options: _options,
      queryParameters: _queryParameters,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );

    BuiltList<MasterWorkingDayResponse>? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null
          ? null
          : _serializers.deserialize(
              rawResponse,
              specifiedType: const FullType(
                  BuiltList, [FullType(MasterWorkingDayResponse)]),
            ) as BuiltList<MasterWorkingDayResponse>;
    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<BuiltList<MasterWorkingDayResponse>>(
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
