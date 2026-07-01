// SupportRepository — interface, HTTP implementation, and provider.
//
// Wraps the support-contact endpoint for the logged-in "Напишіть нам" screen:
//   - submitContact(message, subject?, attachments) →
//       POST /api/v1/support/contact   (multipart/form-data)
//
// The endpoint is NOT exposed by the generated `beautica_api` client (a mixed
// multipart with a JSON `request` part + repeated file parts is awkward to
// codegen, and regenerating the OpenAPI snapshot requires a live backend boot —
// out of scope). So this repository issues the POST via the raw authenticated
// [Dio] instance from [dioProvider] (full interceptor chain: Bearer token, error
// mapping, refresh). Identity (userId/email) is derived server-side from the
// JWT — never sent in the body.
//
// The request body is a [FormData] with two kinds of part:
//   • `request`     — a JSON part ({message, subject?}) sent as its OWN part with
//                     Content-Type: application/json (mixed multipart).
//   • `attachments` — 0..5 repeated file parts, each a [MultipartFile] carrying
//                     the picked bytes + filename + sniffed content type.
//
// All [DioException]s are mapped to typed [Failure] subclasses — no raw Dio
// types cross this boundary into the domain or presentation layers.

import 'dart:convert';
import 'dart:developer';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/dio_provider.dart';
import 'package:beautica_mobile/features/support/domain/support_attachment.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:http_parser/http_parser.dart' show MediaType;
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'support_repository.g.dart';

/// Contract for the support-contact layer.
///
/// Every method either resolves successfully or throws a [Failure] subclass
/// from `core/errors/failures.dart`. Raw [DioException]s are caught inside the
/// implementation and never escape.
abstract interface class SupportRepository {
  /// Submits a support message (+ optional subject + 0..5 attachments) to
  /// `POST /api/v1/support/contact`.
  ///
  /// Resolves on the backend's **202 Accepted**. The caller (notifier) is
  /// responsible for client-side validation BEFORE invoking this; the server
  /// re-validates as the source of truth.
  ///
  /// Throws:
  ///   - [ValidationFailure] on **400** (message length / bad attachment).
  ///   - [UnauthorizedFailure] on **401** (no/expired JWT).
  ///   - [SupportAttachmentTooLargeFailure] on **413** (over the 5 MB envelope).
  ///   - [SupportChannelUnavailableFailure] on **503** (channel not configured).
  ///   - [NetworkFailure] / [ServerFailure] on other transport errors.
  Future<void> submitContact({
    required String message,
    String? subject,
    List<SupportAttachment> attachments,
  });
}

/// HTTP implementation of [SupportRepository].
///
/// Inject via [supportRepositoryProvider] — never construct directly.
final class HttpSupportRepository implements SupportRepository {
  HttpSupportRepository({required Dio dio}) : _dio = dio;

  /// The raw authenticated [Dio] instance (full interceptor chain).
  final Dio _dio;

  static const _tag = 'feature.support.repository';

  // The generated client's relative paths all begin with `/api/v1/...`, and
  // `AppConfig.baseUrl` is normalised to NEVER carry the `/api/v1` prefix — so
  // the raw path here MUST include `/api/v1` to match (omitting it 404s; adding
  // it to the base URL too would double-prefix). See AppConfig.normalizeBaseUrl.
  static const _path = '/api/v1/support/contact';

  @override
  Future<void> submitContact({
    required String message,
    String? subject,
    List<SupportAttachment> attachments = const <SupportAttachment>[],
  }) async {
    try {
      final trimmedSubject = subject?.trim();
      final requestJson = <String, Object?>{
        'message': message,
        if (trimmedSubject != null && trimmedSubject.isNotEmpty)
          'subject': trimmedSubject,
      };

      final formData = FormData();
      // The `request` part is a JSON part with its OWN application/json content
      // type (mixed multipart) — NOT a plain form field. The backend reads it as
      // @RequestPart("request") of the JSON DTO.
      formData.files.add(
        MapEntry(
          'request',
          MultipartFile.fromString(
            jsonEncode(requestJson),
            contentType: MediaType('application', 'json'),
          ),
        ),
      );
      // 0..5 repeated `attachments` file parts.
      for (final a in attachments) {
        formData.files.add(
          MapEntry(
            'attachments',
            MultipartFile.fromBytes(
              a.bytes,
              filename: a.name,
              contentType: _mediaType(a.contentType),
            ),
          ),
        );
      }

      await _dio.post<Object?>(
        _path,
        data: formData,
        options: Options(
          // Override the Dio default `application/json` Content-Type so the
          // multipart boundary header is generated by Dio for this request.
          contentType: 'multipart/form-data',
        ),
      );
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        // Never log the message body or tokens — only transport metadata.
        log(
          'submitContact failed: ${e.type} ${e.response?.statusCode} '
          '(${attachments.length} attachments)',
          name: _tag,
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapDioException(e);
    }
  }

  /// Parses a `type/subtype` string into a [MediaType] for the multipart part.
  /// Falls back to `application/octet-stream` on a malformed value (the server
  /// re-sniffs by magic bytes regardless).
  MediaType _mediaType(String contentType) {
    final parts = contentType.split('/');
    if (parts.length == 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return MediaType(parts[0], parts[1]);
    }
    return MediaType('application', 'octet-stream');
  }

  /// Maps a [DioException] to a typed [Failure].
  ///
  /// If [ErrorMapperInterceptor] has already attached a [Failure] as `e.error`,
  /// the status-specific cases below still take precedence for 413/503 (the
  /// interceptor maps those to generic Server/Unknown failures that lack the
  /// support-specific copy); otherwise that instance is re-thrown.
  Failure _mapDioException(DioException e) {
    final statusCode = e.response?.statusCode;
    if (statusCode == 413) {
      return SupportAttachmentTooLargeFailure(cause: e);
    }
    if (statusCode == 503) {
      return SupportChannelUnavailableFailure(cause: e);
    }
    if (e.error is Failure) return e.error as Failure;
    switch (e.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return NetworkFailure(cause: e);
      case DioExceptionType.badResponse:
        if (statusCode == 400 || statusCode == 422) {
          return ValidationFailure(fieldErrors: const {}, cause: e);
        }
        if (statusCode == 401) return UnauthorizedFailure(cause: e);
        return ServerFailure(statusCode: statusCode, cause: e);
      case DioExceptionType.cancel:
      case DioExceptionType.badCertificate:
      case DioExceptionType.unknown:
        return ServerFailure(statusCode: statusCode, cause: e);
    }
  }
}

/// Provides the [SupportRepository] singleton backed by the authenticated Dio.
///
/// Override in tests with a mocktail mock — never construct
/// [HttpSupportRepository] directly in production or test code.
@Riverpod(keepAlive: true)
SupportRepository supportRepository(Ref ref) =>
    HttpSupportRepository(dio: ref.watch(dioProvider));
