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
//
// M510 adds the card reads (B508 `…/clients/{users|guests}/{id}` + `/visits`)
// on the SAME seam, with the same flat-paging wire format.
// The card carries the client's PHONE (B518) — the redacted prefixes above
// cover these paths, and nothing here ever logs a body or a path id.
//
// M544 adds the list removal writes (B564, CLI-82) through the GENERATED
// `ProviderClientControllerApi` (`remove|restore` `SalonClient` / `MyClient`)
// with the generated `ClientListRemovalRequest`; 204. Both sit under the same
// redacted prefixes. The owner/admin `masterId` view is salon-scoped
// server-side, so `masterId` is never sent on a write.
//
// M545 adds the anonymous comments read (B565 `…/{users|guests}/{id}/comments`,
// REV-44) on the SAME seam and wire format as `/visits`, behind its own
// [ClientCommentsRepository] interface so the many [ClientRepository] test
// fakes stay untouched. The rows carry provider-written TEXT about a person:
// same redacted prefixes, nothing but transport metadata is logged.

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
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/clients/domain/client_card.dart';
import 'package:beautica_mobile/features/clients/domain/client_review_comment.dart';
import 'package:beautica_mobile/features/clients/domain/client_summary.dart';
import 'package:beautica_mobile/features/clients/domain/client_visit.dart';
import 'package:beautica_mobile/shared/validators/uuid_validator.dart';

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

  /// The card of [client] within [scope]. Throws [NotFoundFailure] for an
  /// unknown or out-of-scope client (the uniform 404, CLI-48).
  Future<ClientCard> getCard(
    ClientListScope scope,
    ClientRef client, {
    CancelToken? cancelToken,
  });

  /// One page of [client]'s visits, newest first (B508, size 20).
  Future<PageResponse<ClientVisit>> getVisits(
    ClientListScope scope,
    ClientRef client, {
    int page = 0,
    int size = kClientPageSize,
    CancelToken? cancelToken,
  });

  /// M544 (B564, CLI-82) — removes [client] from [scope]'s list. Bookings,
  /// history, ratings and blocks are untouched server-side. Throws a
  /// [Failure] ([NotFoundFailure] for an out-of-scope client).
  Future<void> removeFromList(ClientListScope scope, ClientRef client);

  /// M544 (B564) — undoes [removeFromList] (the undo snack). Idempotent
  /// server-side (204 even when nothing was removed).
  Future<void> restoreToList(ClientListScope scope, ClientRef client);
}

/// M545 — the anonymous comments about a client (B565, REV-44).
///
/// Resolves or throws a [Failure]; raw Dio types never cross this boundary.
abstract interface class ClientCommentsRepository {
  /// One page of the visible comments about [client], newest first (server
  /// order, size 20). A row the app cannot read (no id, bad month, no stars,
  /// blank text) is dropped — never a crash, never the whole page.
  Future<PageResponse<ClientReviewComment>> getComments(
    ClientListScope scope,
    ClientRef client, {
    int page = 0,
    int size = kClientPageSize,
    CancelToken? cancelToken,
  });

  /// M572 (B570, REV-45) — deletes the viewer's OWN client review: the whole
  /// rating goes, comment included (`DELETE /client-reviews/{reviewId}`).
  /// Throws a [Failure] ([NotFoundFailure] when it is already gone).
  Future<void> deleteOwnReview(String reviewId);
}

/// HTTP implementation of [ClientRepository] and [ClientCommentsRepository].
///
/// Inject via [clientRepositoryProvider] / [clientCommentsRepositoryProvider]
/// — never construct directly outside tests.
final class HttpClientRepository
    implements ClientRepository, ClientCommentsRepository {
  HttpClientRepository(this._dio)
    : _api = ProviderClientControllerApi(_dio, standardSerializers),
      _reviewApi = ClientReviewControllerApi(_dio, standardSerializers);

  final Dio _dio;

  /// The generated client — used for the B564 removal writes. The reads stay
  /// on [_dio] (flat paging, see the file header).
  final ProviderClientControllerApi _api;

  /// The generated client for the B570 own-review delete.
  final ClientReviewControllerApi _reviewApi;

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

  @override
  Future<ClientCard> getCard(
    ClientListScope scope,
    ClientRef client, {
    CancelToken? cancelToken,
  }) async => clientCardFromBody(
    await _read(
      _cardPath(scope, client, ''),
      scope: scope,
      cancelToken: cancelToken,
    ),
    client: client,
  );

  @override
  Future<PageResponse<ClientVisit>> getVisits(
    ClientListScope scope,
    ClientRef client, {
    int page = 0,
    int size = kClientPageSize,
    CancelToken? cancelToken,
  }) async => clientVisitsFromBody(
    await _read(
      _cardPath(scope, client, '/visits'),
      scope: scope,
      page: page,
      size: size,
      cancelToken: cancelToken,
    ),
    requestedPage: page,
  );

  @override
  Future<PageResponse<ClientReviewComment>> getComments(
    ClientListScope scope,
    ClientRef client, {
    int page = 0,
    int size = kClientPageSize,
    CancelToken? cancelToken,
  }) async => clientCommentsFromBody(
    await _read(
      _cardPath(scope, client, '/comments'),
      scope: scope,
      page: page,
      size: size,
      cancelToken: cancelToken,
    ),
    requestedPage: page,
  );

  @override
  Future<void> removeFromList(ClientListScope scope, ClientRef client) =>
      _removal(scope, client, restore: false);

  @override
  Future<void> restoreToList(ClientListScope scope, ClientRef client) =>
      _removal(scope, client, restore: true);

  @override
  Future<void> deleteOwnReview(String reviewId) async {
    // The generated client puts the id in the path unencoded: a non-UUID never
    // reaches the network — it is the same outcome as an unknown review.
    if (!isUuid(reviewId)) throw const NotFoundFailure();
    try {
      await _reviewApi.deleteOwn(reviewId: reviewId);
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        // Transport metadata only — never the body, the path or an id.
        log(
          'deleteOwnReview failed: ${e.type} ${e.response?.statusCode}',
          name: _tag,
          level: 900,
          stackTrace: st,
        );
      }
      throw mapClientDioException(e);
    }
  }

  /// B564 — the generated removal operations with the generated
  /// [ClientListRemovalRequest] (exactly one of `clientId` /
  /// `guestBookingId`). A salon scope always writes the salon removal (its
  /// `masterId` view is covered server-side), a master scope its own list.
  Future<void> _removal(
    ClientListScope scope,
    ClientRef client, {
    required bool restore,
  }) async {
    final ClientListRemovalRequest body = ClientListRemovalRequest(
      (ClientListRemovalRequestBuilder b) => switch (client) {
        RegisteredClientRef(:final String userId) => b.clientId = userId,
        GuestClientRef(:final String bookingId) => b.guestBookingId = bookingId,
      },
    );
    try {
      await switch ((scope, restore)) {
        (SalonClientListScope(:final String salonId), false) =>
          _api.removeSalonClient(
            salonId: salonId,
            clientListRemovalRequest: body,
          ),
        (SalonClientListScope(:final String salonId), true) =>
          _api.restoreSalonClient(
            salonId: salonId,
            clientListRemovalRequest: body,
          ),
        (MyClientListScope(), false) => _api.removeMyClient(
          clientListRemovalRequest: body,
        ),
        (MyClientListScope(), true) => _api.restoreMyClient(
          clientListRemovalRequest: body,
        ),
      };
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        // Transport metadata only — never the body, the path or an id.
        log(
          '${restore ? 'restore' : 'remove'} failed: '
          '${e.type} ${e.response?.statusCode}',
          name: _tag,
          level: 900,
          stackTrace: st,
        );
      }
      throw mapClientDioException(e);
    }
  }

  /// `…/clients/{users|guests}/{id}{suffix}` below [scope]'s base.
  String _cardPath(ClientListScope scope, ClientRef client, String suffix) {
    final String base = switch (scope) {
      SalonClientListScope(:final String salonId) =>
        '/api/v1/salons/${encodePathSegment(salonId, 'salonId', logTag: _tag)}/clients',
      MyClientListScope() => '/api/v1/masters/me/clients',
    };
    final String tail = switch (client) {
      RegisteredClientRef(:final String userId) =>
        'users/${encodePathSegment(userId, 'userId', logTag: _tag)}',
      GuestClientRef(:final String bookingId) =>
        'guests/${encodePathSegment(bookingId, 'bookingId', logTag: _tag)}',
    };
    return '$base/$tail$suffix';
  }

  Future<Object?> _read(
    String path, {
    required ClientListScope scope,
    int? page,
    int? size,
    CancelToken? cancelToken,
  }) async {
    final String? masterId = switch (scope) {
      SalonClientListScope(:final String? masterId) => masterId,
      MyClientListScope() => null,
    };
    try {
      final Response<Object?> response = await _dio.get<Object?>(
        path,
        queryParameters: <String, dynamic>{
          'page': ?page,
          'size': ?size,
          'masterId': ?masterId,
        },
        cancelToken: cancelToken,
      );
      return response.data;
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      if (CancelToken.isCancel(e)) rethrow;
      if (kDebugMode) {
        // Transport metadata only — never the body, the path or an id.
        log(
          'card read failed: ${e.type} ${e.response?.statusCode}',
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
/// missing. A guest has no account photo, so a guest `avatarUrl` is not
/// trusted. Ratings are mapped for BOTH kinds (M548 / REV-D10): a guest's
/// `ratingAvg` / `ratingCount` are the backend's values, never forced unrated.
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
    ratingAvg: dto.ratingAvg?.toDouble(),
    ratingCount: switch (dto.ratingCount) {
      final int n when n > 0 => n,
      _ => 0,
    },
    blocked: dto.blocked ?? false,
  );
}

/// Deserializes a card body into a [ClientCard] for the REQUESTED [client].
/// Throws [ResponseUnusableFailure] when the envelope is unreadable.
@visibleForTesting
ClientCard clientCardFromBody(Object? body, {required ClientRef client}) {
  final ApiResponseClientCardResponse? envelope;
  try {
    envelope = body == null
        ? null
        : standardSerializers.deserialize(
                body,
                specifiedType: const FullType(ApiResponseClientCardResponse),
              )
              as ApiResponseClientCardResponse?;
  } catch (_) {
    throw const ResponseUnusableFailure();
  }
  final ClientCardResponse? dto = envelope?.data;
  if (dto == null) throw const ResponseUnusableFailure();
  return clientCardFromDto(dto, client: client);
}

/// Maps a generated [ClientCardResponse]. No `kind` branch (CLI-D07): the
/// server decides what a guest or registered client has. `stats` /
/// `firstVisitAt` are ignored (D3).
@visibleForTesting
ClientCard clientCardFromDto(
  ClientCardResponse dto, {
  required ClientRef client,
}) {
  final List<int> distribution = List<int>.filled(kClientRatingBuckets, 0);
  for (final RatingBucket b in dto.ratingDistribution ?? <RatingBucket>[]) {
    final int? stars = b.rating;
    if (stars == null || stars < 1 || stars > kClientRatingBuckets) continue;
    final int count = b.count ?? 0;
    distribution[kClientRatingBuckets - stars] = count > 0 ? count : 0;
  }
  final int ratingCount = switch (dto.ratingCount) {
    final int n when n > 0 => n,
    _ => 0,
  };
  final String? displayName = _nonBlank(dto.displayName)?.trim();
  final String? firstName = _nonBlank(dto.firstName)?.trim();
  final String? lastName = _nonBlank(dto.lastName)?.trim();
  // B550 name parts. Both absent (a pre-B550 backend) → fall back to
  // `firstName = displayName`; one part present → the other stays null.
  final bool noParts = firstName == null && lastName == null;
  return ClientCard(
    ref: client,
    displayName: displayName,
    firstName: noParts ? displayName : firstName,
    lastName: lastName,
    avatarUrl: _nonBlank(dto.avatarUrl),
    phone: _nonBlank(dto.phone)?.trim(),
    blocked: dto.blocked ?? false,
    ratingAvg: dto.ratingAvg?.toDouble(),
    ratingCount: ratingCount,
    ratingDistribution: List<int>.unmodifiable(distribution),
    nextVisitAt: dto.nextVisitAt,
    nextVisit: clientVisitFromDto(dto.nextVisit),
    servedByMasters: List<ClientServedMaster>.unmodifiable(
      _servedMastersOf(dto.servedByMasters),
    ),
  );
}

/// CLI-73 — the salon masters who served the client, server order (most
/// recent first). An entry without an id or a name is dropped (a chip needs
/// both); a repeated id keeps its first (most recent) entry.
Iterable<ClientServedMaster> _servedMastersOf(
  Iterable<ServedMaster>? rows,
) sync* {
  final Set<String> seen = <String>{};
  for (final ServedMaster m in rows ?? const <ServedMaster>[]) {
    final String? id = _nonBlank(m.masterId);
    final String? name = _nonBlank(m.name)?.trim();
    if (id == null || name == null || !seen.add(id)) continue;
    yield ClientServedMaster(
      masterId: id,
      name: name,
      avatarUrl: _nonBlank(m.avatarUrl),
    );
  }
}

/// Deserializes a `…/visits` page, dropping visits / items the app cannot use.
@visibleForTesting
PageResponse<ClientVisit> clientVisitsFromBody(
  Object? body, {
  required int requestedPage,
}) {
  final ApiResponsePageResponseClientVisitResponse? envelope;
  try {
    envelope = body == null
        ? null
        : standardSerializers.deserialize(
                body,
                specifiedType: const FullType(
                  ApiResponsePageResponseClientVisitResponse,
                ),
              )
              as ApiResponsePageResponseClientVisitResponse?;
  } catch (_) {
    throw const ResponseUnusableFailure();
  }
  final PageResponseClientVisitResponse? dto = envelope?.data;
  final Iterable<ClientVisitResponse>? rows = dto?.data;
  if (dto == null || rows == null) throw const ResponseUnusableFailure();
  final List<ClientVisit> items = <ClientVisit>[];
  for (final ClientVisitResponse row in rows) {
    final ClientVisit? visit = clientVisitFromDto(row);
    if (visit != null) items.add(visit);
  }
  return PageResponse<ClientVisit>(
    items: List<ClientVisit>.unmodifiable(items),
    page: dto.page ?? requestedPage,
    totalPages: dto.totalPages ?? 0,
    totalElements: dto.totalElements ?? items.length,
  );
}

/// Maps one visit; `null` when it has no key / start or no usable item.
/// `masterId` / `masterDisplayName` are not mapped (D2).
@visibleForTesting
ClientVisit? clientVisitFromDto(ClientVisitResponse? dto) {
  if (dto == null) return null;
  final String? key = _nonBlank(dto.visitKey);
  final DateTime? startsAt = dto.startsAt;
  if (key == null || startsAt == null) return null;
  final List<ClientVisitItem> items = <ClientVisitItem>[];
  for (final Item i in dto.items ?? <Item>[]) {
    final String? bookingId = _nonBlank(i.bookingId);
    final DateTime? at = i.startsAt;
    if (bookingId == null || at == null) continue;
    final String? wire = knownEnumName(i.status);
    items.add(
      ClientVisitItem(
        bookingId: bookingId,
        serviceName: _nonBlank(i.serviceName)?.trim() ?? '',
        status: wire == null
            ? BookingStatus.unknown
            : BookingStatus.fromWire(wire),
        startsAt: at,
        price: i.priceAtBooking?.toDouble(),
        priceMax: i.priceMaxAtBooking?.toDouble(),
      ),
    );
  }
  if (items.isEmpty) return null;
  return ClientVisit(
    visitKey: key,
    startsAt: startsAt,
    items: List<ClientVisitItem>.unmodifiable(items),
  );
}

/// Deserializes a `…/comments` page (B565), dropping unusable rows.
@visibleForTesting
PageResponse<ClientReviewComment> clientCommentsFromBody(
  Object? body, {
  required int requestedPage,
}) {
  final ApiResponsePageResponseClientReviewCommentResponse? envelope;
  try {
    envelope = body == null
        ? null
        : standardSerializers.deserialize(
                body,
                specifiedType: const FullType(
                  ApiResponsePageResponseClientReviewCommentResponse,
                ),
              )
              as ApiResponsePageResponseClientReviewCommentResponse?;
  } catch (_) {
    throw const ResponseUnusableFailure();
  }
  final PageResponseClientReviewCommentResponse? dto = envelope?.data;
  final Iterable<ClientReviewCommentResponse>? rows = dto?.data;
  if (dto == null || rows == null) throw const ResponseUnusableFailure();
  final List<ClientReviewComment> items = <ClientReviewComment>[];
  for (final ClientReviewCommentResponse row in rows) {
    final ClientReviewComment? comment = clientCommentFromDto(row);
    if (comment != null) {
      items.add(comment);
    } else if (kDebugMode) {
      // No row content is logged (provider-written text).
      log('comments: dropped an unusable row', name: _tag, level: 900);
    }
  }
  return PageResponse<ClientReviewComment>(
    items: List<ClientReviewComment>.unmodifiable(items),
    page: dto.page ?? requestedPage,
    totalPages: dto.totalPages ?? 0,
    totalElements: dto.totalElements ?? items.length,
  );
}

/// Maps one comment; `null` when it has no id, no `YYYY-MM` month, stars
/// outside 1..5 or blank text.
@visibleForTesting
ClientReviewComment? clientCommentFromDto(ClientReviewCommentResponse? dto) {
  if (dto == null) return null;
  final String? id = _nonBlank(dto.reviewId);
  final ({int year, int month})? month = parseVisitMonth(dto.visitMonth);
  final int? stars = dto.stars;
  final String? text = _nonBlank(dto.comment)?.trim();
  if (id == null || month == null || text == null) return null;
  if (stars == null || stars < 1 || stars > kClientRatingBuckets) return null;
  return ClientReviewComment(
    reviewId: id,
    visitYear: month.year,
    visitMonth: month.month,
    stars: stars,
    comment: text,
    own: dto.own ?? false,
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

/// M545 — the app-wide [ClientCommentsRepository] on the authenticated Dio.
@Riverpod(keepAlive: true)
ClientCommentsRepository clientCommentsRepository(Ref ref) =>
    HttpClientRepository(ref.watch(dioProvider));

/// The app-wide [ClientRepository] on the authenticated Dio.
@Riverpod(keepAlive: true)
ClientRepository clientRepository(Ref ref) =>
    HttpClientRepository(ref.watch(dioProvider));
