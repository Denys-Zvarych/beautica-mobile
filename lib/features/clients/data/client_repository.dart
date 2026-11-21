// M509 — ClientRepository: the one seam for backend B507 (the provider's
// client list), `GET /salons/{salonId}/clients[?masterId=]` and
// `GET /masters/me/clients`.
//
// WIRE-FORMAT NOTE: the generated `ProviderClientControllerApi.list*` take a
// typed `Pageable`, whose generated encoder JSON-encodes the WHOLE object into
// one `pageable=` query value; Spring's pageable resolver expects FLAT
// `page` / `size` keys (the bug `salon/data/salon_repository.dart`'s header
// documents). So the read goes through the shared authenticated [Dio] with
// flat params and deserializes with the SAME [standardSerializers] — the rows
// are still the generated [ClientListItemResponse], never a hand-written DTO.
//
// SEC: rows carry client names and avatars. `/api/v1/salons/` and
// `/api/v1/masters/me/clients` are redacted prefixes in `LoggingInterceptor`
// (`kPiiPathPrefixes`), and only transport metadata is ever logged here.
// B507 sends no phone and no comment text.

import 'dart:developer';

import 'package:beautica_api/beautica_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:built_value/serializer.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/api_enum_names.dart';
import 'package:beautica_mobile/core/network/dio_provider.dart';
import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/core/network/path_segment.dart';
import 'package:beautica_mobile/features/clients/domain/client_summary.dart';

part 'client_repository.g.dart';

const String _tag = 'feature.clients';

/// B507 page size (the endpoint's `@PageableDefault(size = 20)`).
const int kClientPageSize = 20;

/// Shortest / longest `q` the endpoint honours (B507): a blank `q` is a 400,
/// so a shorter term must not be sent at all.
const int kClientSearchMinLength = 2;
const int kClientSearchMaxLength = 50;

/// The `q` to send for the raw search text [raw]: trimmed, capped at
/// [kClientSearchMaxLength]; `null` (parameter omitted) when blank or
/// shorter than [kClientSearchMinLength].
String? clientQueryFor(String raw) {
  final String trimmed = raw.trim();
  if (trimmed.length < kClientSearchMinLength) return null;
  return trimmed.length > kClientSearchMaxLength
      ? trimmed.substring(0, kClientSearchMaxLength).trim()
      : trimmed;
}

/// Contract for the provider's client list.
///
/// Resolves or throws a [Failure]; raw Dio types never cross this boundary.
abstract interface class ClientRepository {
  /// One page of [scope]'s clients, newest activity first (server order).
  /// [q] must already be a valid term ([clientQueryFor]) or `null`. A row the
  /// app cannot read (unknown `kind`, no id) is dropped and logged as a
  /// breadcrumb — never a crash, never the whole page.
  ///
  /// [cancelToken] (optional) aborts a superseded request; a cancelled call
  /// rethrows the Dio cancel [DioException] unmapped (never a [Failure]).
  Future<PageResponse<ClientSummary>> list(
    ClientListScope scope, {
    String? q,
    int page = 0,
    int size = kClientPageSize,
    CancelToken? cancelToken,
  });
}

/// HTTP implementation of [ClientRepository].
///
/// Inject via [clientRepositoryProvider] — never construct directly outside
/// tests.
final class HttpClientRepository implements ClientRepository {
  HttpClientRepository(this._dio);

  final Dio _dio;

  @override
  Future<PageResponse<ClientSummary>> list(
    ClientListScope scope, {
    String? q,
    int page = 0,
    int size = kClientPageSize,
    CancelToken? cancelToken,
  }) async {
    final String path = switch (scope) {
      SalonClientListScope(:final String salonId) =>
        '/api/v1/salons/${encodePathSegment(salonId, 'salonId', logTag: _tag)}/clients',
      MyClientListScope() => '/api/v1/masters/me/clients',
    };
    final String? masterId = switch (scope) {
      SalonClientListScope(:final String? masterId) => masterId,
      MyClientListScope() => null,
    };
    try {
      final Response<Object?> response = await _dio.get<Object?>(
        path,
        queryParameters: <String, dynamic>{
          'page': page,
          'size': size,
          'masterId': ?masterId,
          'q': ?q,
        },
        cancelToken: cancelToken,
      );
      return clientPageFromBody(response.data, requestedPage: page);
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      // A superseded request is not a failure: hand the cancel straight back
      // so the caller can drop it (the controller's generation check does).
      if (CancelToken.isCancel(e)) rethrow;
      if (kDebugMode) {
        // Transport metadata only — never the body (names) or the query (`q`).
        log(
          'list failed: ${e.type} ${e.response?.statusCode}',
          name: _tag,
          level: 900,
          stackTrace: st,
        );
      }
      throw mapClientDioException(e);
    }
  }
}

/// Deserializes a `GET …/clients` body into a [PageResponse], dropping rows
/// the app cannot use. Throws [ResponseUnusableFailure] when the envelope
/// itself is unreadable.
@visibleForTesting
PageResponse<ClientSummary> clientPageFromBody(
  Object? body, {
  required int requestedPage,
}) {
  final ApiResponsePageResponseClientListItemResponse? envelope;
  try {
    envelope = body == null
        ? null
        : standardSerializers.deserialize(
                body,
                specifiedType: const FullType(
                  ApiResponsePageResponseClientListItemResponse,
                ),
              )
              as ApiResponsePageResponseClientListItemResponse?;
  } catch (_) {
    throw const ResponseUnusableFailure();
  }
  final PageResponseClientListItemResponse? dto = envelope?.data;
  final Iterable<ClientListItemResponse>? rows = dto?.data;
  if (dto == null || rows == null) throw const ResponseUnusableFailure();

  final List<ClientSummary> items = <ClientSummary>[];
  for (final ClientListItemResponse row in rows) {
    final ClientSummary? summary = clientSummaryFromDto(row);
    if (summary != null) {
      items.add(summary);
    } else if (kDebugMode) {
      // No row content is logged (names).
      log('list: dropped an unusable client row', name: _tag, level: 900);
    }
  }
  return PageResponse<ClientSummary>(
    items: List<ClientSummary>.unmodifiable(items),
    page: dto.page ?? requestedPage,
    totalPages: dto.totalPages ?? 0,
    totalElements: dto.totalElements ?? items.length,
  );
}

/// Maps a generated [ClientListItemResponse] to a [ClientSummary], or `null`
/// when `kind` is unknown or the kind's id (`userId` / `guestBookingId`) is
/// missing. A field the API sends for the other kind is not trusted: a guest
/// has no account photo and no rating.
@visibleForTesting
ClientSummary? clientSummaryFromDto(ClientListItemResponse? dto) {
  if (dto == null) return null;
  final ClientRef? ref = switch (knownEnumName(dto.kind)) {
    'REGISTERED' =>
      _nonBlank(dto.userId) == null ? null : ClientRef.registered(dto.userId!),
    'GUEST' =>
      _nonBlank(dto.guestBookingId) == null
          ? null
          : ClientRef.guest(dto.guestBookingId!),
    _ => null,
  };
  if (ref == null) return null;
  final bool registered = ref is RegisteredClientRef;
  return ClientSummary(
    ref: ref,
    displayName: _nonBlank(dto.displayName)?.trim(),
    avatarUrl: registered ? _nonBlank(dto.avatarUrl) : null,
    lastVisitAt: dto.lastVisitAt,
    nextVisitAt: dto.nextVisitAt,
    completedVisits: switch (dto.completedVisits) {
      final int n when n > 0 => n,
      _ => 0,
    },
    ratingAvg: registered ? dto.ratingAvg?.toDouble() : null,
    ratingCount: registered
        ? switch (dto.ratingCount) {
            final int n when n > 0 => n,
            _ => 0,
          }
        : 0,
    blocked: dto.blocked ?? false,
  );
}

String? _nonBlank(String? value) =>
    (value == null || value.trim().isEmpty) ? null : value;

/// Maps a `…/clients` [DioException] to a typed [Failure]. The interceptor
/// chain attaches a [Failure] to most errors; the arms below cover the rest.
@visibleForTesting
Failure mapClientDioException(DioException e) {
  final Object? attached = e.error;
  if (attached is Failure) return attached;
  final int? statusCode = e.response?.statusCode;
  switch (e.type) {
    case DioExceptionType.connectionError:
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
      return NetworkFailure(cause: e);
    case DioExceptionType.badResponse:
      if (statusCode == 401) return UnauthorizedFailure(cause: e);
      if (statusCode == 404) return NotFoundFailure(cause: e);
      return ServerFailure(statusCode: statusCode, cause: e);
    case DioExceptionType.badCertificate:
    case DioExceptionType.cancel:
    case DioExceptionType.unknown:
      return UnknownFailure(cause: e);
  }
}

/// The app-wide [ClientRepository] on the authenticated Dio.
@Riverpod(keepAlive: true)
ClientRepository clientRepository(Ref ref) =>
    HttpClientRepository(ref.watch(dioProvider));
