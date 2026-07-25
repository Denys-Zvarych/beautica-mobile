// Track 7.x Wave B — ClientReviewRepository: the PROVIDER→CLIENT «ВІДГУК ПРО
// КЛІЄНТА» write path.
//
//   POST /api/v1/client-reviews
//
// A dedicated, deliberately TINY repository — mirrors `client_profile_
// repository.dart` in shape (interface + Http impl + provider + DioException
// → typed Failure mapping) rather than folding this write into the much
// larger `BookingRepository` (which owns the CLIENT-side booking lifecycle +
// the CLIENT→MASTER `POST /reviews`). The two review directions use DIFFERENT
// generated API classes (`ReviewControllerApi` vs `ClientReviewControllerApi`)
// and never share request/response shapes, so there is nothing to fold.
//
// Every method either resolves successfully or throws a [Failure] subclass
// from `core/errors/failures.dart`. Raw [DioException]s are caught here and
// never escape.

import 'dart:developer';

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

const String _tag = 'client_review.repository';

/// Contract for the PROVIDER→CLIENT feedback write path.
abstract interface class ClientReviewRepository {
  /// Leaves PRIVATE feedback about the client of a COMPLETED [bookingId] on
  /// behalf of the authenticated provider (master or salon).
  ///
  /// Wraps `POST /client-reviews`. [rating] is 1–5; [comment] is optional free
  /// text (an empty/blank string is sent as null so the backend sees no
  /// comment). The client NEVER sees this comment — only their aggregate
  /// rating number moves (`GET /users/me/rating`).
  ///
  /// The backend enforces COMPLETED + provider ownership + not-already-
  /// reviewed. Unlike the CLIENT→MASTER review flow there is no client-side
  /// `canReview`-equivalent gate to check first (see
  /// `ClientReviewAlreadyExistsFailure`'s doc). Throws
  /// [ClientReviewAlreadyExistsFailure] on HTTP 409 (feedback already left)
  /// and [ClientReviewNotAllowedFailure] on 403 (not the booking's provider) /
  /// other 4xx (e.g. the booking is not COMPLETED, or is a guest booking with
  /// no client account to rate).
  Future<void> createClientReview({
    required String bookingId,
    required int rating,
    String? comment,
  });
}

/// HTTP implementation of [ClientReviewRepository].
///
/// Inject via [clientReviewRepositoryProvider] (`booking_providers.dart`) —
/// never construct directly outside tests.
final class HttpClientReviewRepository implements ClientReviewRepository {
  HttpClientReviewRepository(this._api);

  final ClientReviewControllerApi _api;

  @override
  Future<void> createClientReview({
    required String bookingId,
    required int rating,
    String? comment,
  }) async {
    // Blank/whitespace-only comment → send no comment at all (the field is
    // optional on the wire; a null keeps the payload clean) — mirrors
    // `HttpBookingRepository.createReview`.
    final String? trimmed = comment?.trim();
    final String? effectiveComment = (trimmed == null || trimmed.isEmpty)
        ? null
        : trimmed;
    try {
      await _api.create(
        createClientReviewRequest: CreateClientReviewRequest(
          (b) => b
            ..bookingId = bookingId
            ..rating = rating
            ..comment = effectiveComment,
        ),
      );
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'createClientReview failed: ${e.type} ${e.response?.statusCode}',
          name: _tag,
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapClientReviewException(e);
    }
  }

  /// Maps a [DioException] from `POST /client-reviews` to a typed [Failure]
  /// (track 7.x Wave B).
  ///
  ///   - **409** → [ClientReviewAlreadyExistsFailure] (feedback already left
  ///     about this booking's client).
  ///   - **403** (not the booking's provider) or any other **4xx** (e.g. the
  ///     booking is not COMPLETED, or a guest booking with no client account)
  ///     → [ClientReviewNotAllowedFailure] — one friendly message; the
  ///     provider never distinguishes the two.
  ///
  /// The status-code checks run BEFORE deferring to any [Failure] the
  /// [ErrorMapperInterceptor] may have attached, mirroring
  /// `HttpBookingRepository._mapReviewException`.
  Failure _mapClientReviewException(DioException e) {
    final int? statusCode = e.response?.statusCode;
    if (statusCode == 409) return ClientReviewAlreadyExistsFailure(cause: e);
    if (statusCode == 403 || statusCode == 400 || statusCode == 422) {
      return ClientReviewNotAllowedFailure(cause: e);
    }
    return _mapDioException(e);
  }

  /// Maps a [DioException] to a typed [Failure]. If [ErrorMapperInterceptor]
  /// already attached a [Failure] as `e.error`, that value is re-thrown
  /// directly; otherwise the Dio type is inspected. Raw [DioException] never
  /// escapes.
  Failure _mapDioException(DioException e) {
    if (e.error is Failure) return e.error as Failure;
    switch (e.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return NetworkFailure(cause: e);
      case DioExceptionType.badResponse:
      case DioExceptionType.cancel:
      case DioExceptionType.badCertificate:
      case DioExceptionType.unknown:
        return ServerFailure(statusCode: e.response?.statusCode, cause: e);
    }
  }
}
