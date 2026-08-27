//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

import 'dart:async';

import 'package:built_value/json_object.dart';
import 'package:built_value/serializer.dart';
import 'package:dio/dio.dart';

import 'package:beautica_api/src/api_util.dart';
import 'package:beautica_api/src/model/api_response_appointment_detail_response.dart';
import 'package:beautica_api/src/model/create_staff_booking_request.dart';

class StaffBookingsApi {
  final Dio _dio;

  final Serializers _serializers;

  const StaffBookingsApi(this._dio, this._serializers);

  /// Create a walk-in visit on a master&#39;s calendar
  /// Salon owners and admins may book any master of the salon they manage; an independent master may book only themselves. The salon the booking is scoped to is derived from the caller, never from the request. The visit is created as ONE appointment header plus ONE booking per selected service, all CONFIRMED, source STAFF, no cancel token, and created_by_user_id set to the caller on the header AND every booking. Each service is cancelled, rescheduled, declined and reviewed INDEPENDENTLY of its siblings — creating a visit never implies a whole-visit cascade for any later transition. The guest phone is normalised to E.164 server-side; non-Ukrainian numbers are rejected.  Exactly ONE confirmation SMS is dispatched to that phone number after the visit is committed, regardless of how many services it contains, subject to the platform-wide app.booking.sms.enabled switch. Delivery is best-effort: it never changes the response, and no field here reports whether a message was sent. No push or email notification is sent by this endpoint.
  ///
  /// Parameters:
  /// * [masterId]
  /// * [createStaffBookingRequest]
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [ApiResponseAppointmentDetailResponse] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<ApiResponseAppointmentDetailResponse>> createStaffBooking({
    required String masterId,
    required CreateStaffBookingRequest createStaffBookingRequest,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/api/v1/masters/{masterId}/bookings'.replaceAll(
        '{' r'masterId' '}',
        encodeQueryParameter(_serializers, masterId, const FullType(String))
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
      const _type = FullType(CreateStaffBookingRequest);
      _bodyData = _serializers.serialize(createStaffBookingRequest,
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

    ApiResponseAppointmentDetailResponse? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null
          ? null
          : _serializers.deserialize(
              rawResponse,
              specifiedType:
                  const FullType(ApiResponseAppointmentDetailResponse),
            ) as ApiResponseAppointmentDetailResponse;
    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<ApiResponseAppointmentDetailResponse>(
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
