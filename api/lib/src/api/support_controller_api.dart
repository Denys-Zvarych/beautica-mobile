//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

import 'dart:async';

import 'package:built_value/json_object.dart';
import 'package:built_value/serializer.dart';
import 'package:dio/dio.dart';

import 'package:beautica_api/src/api_util.dart';
import 'package:beautica_api/src/model/api_response_contact_support_response.dart';
import 'package:beautica_api/src/model/contact_support_request.dart';
import 'package:built_collection/built_collection.dart';

class SupportControllerApi {
  final Dio _dio;

  final Serializers _serializers;

  const SupportControllerApi(this._dio, this._serializers);

  /// Send a Help / Contact-us message to support
  /// Accepts a free-text message plus optional file attachments and emails the whole thing to the support inbox. Authenticated users only; the sender&#39;s identity is taken from the JWT, never from the request body.  Constraints: up to 5 attachments, each ≤ 5 MB, total ≤ 5 MB; allowed types JPEG, PNG, WebP, PDF (validated by content, not the declared header).
  ///
  /// Parameters:
  /// * [request]
  /// * [attachments] - Optional file attachments (≤5 files, ≤5 MB each, ≤5 MB total)
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [ApiResponseContactSupportResponse] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<ApiResponseContactSupportResponse>> contact({
    ContactSupportRequest? request,
    BuiltList<MultipartFile>? attachments,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/api/v1/support/contact';
    final _options = Options(
      method: r'POST',
      headers: <String, dynamic>{
        ...?headers,
      },
      extra: <String, dynamic>{
        'secure': <Map<String, String>>[],
        ...?extra,
      },
      contentType: 'multipart/form-data',
      validateStatus: validateStatus,
    );

    dynamic _bodyData;

    try {
      _bodyData = FormData.fromMap(<String, dynamic>{
        if (request != null)
          r'request': encodeFormParameter(
              _serializers, request, const FullType(ContactSupportRequest)),
        if (attachments != null) r'attachments': attachments.toList(),
      });
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

    ApiResponseContactSupportResponse? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null
          ? null
          : _serializers.deserialize(
              rawResponse,
              specifiedType: const FullType(ApiResponseContactSupportResponse),
            ) as ApiResponseContactSupportResponse;
    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<ApiResponseContactSupportResponse>(
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
