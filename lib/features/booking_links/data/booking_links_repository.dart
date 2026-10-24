// Phase 413 — booking links over the generated [BookingLinksApi]
// (`GET /api/v1/booking-links/mine`, backend 375 + 376).
//
// Methods throw a typed [Failure]; the provider layer turns any error into
// "not visible" (D4). A CLIENT gets 403 — mapped by `ErrorMapperInterceptor`
// like every other status and rethrown untouched.
//
// Mapping rules:
//   * `shareEnabled == false` ⇒ links are dropped even if the wire carried
//     some — the kill-switch always wins.
//   * a `kind` this build does not know decodes to the generated
//     `unknownDefaultOpenApi` fallback (`enumUnknownDefaultCase=true`) and
//     that link is dropped; the rest of the response survives.
//   * the server-built `url` goes straight to the clipboard / share sheet
//     under the user's name, so it is never trusted blindly
//     (MASVS-CODE-4): a link is dropped unless [isTrustedBookingLinkUrl]
//     accepts it — the slug matches the backend slug format
//     (`^[a-z0-9][a-z0-9-]*[a-z0-9]$`, <= 60 chars, `BookingSlugService`) and
//     the url is EXACTLY `${AppConfig.publicWebOrigin}/book/{slug}` (MASTER)
//     or `.../book/s/{slug}` (SALON) — no query, no fragment, no port, no
//     userinfo, nothing else. The rest of the response survives.
//   * `salonId` becomes a `go_router` path segment (`/salons/{id}/shell`),
//     so it is kept only when it is a UUID ([isUuid], either case, verbatim);
//     anything else maps to `null` and the screen shows no setup link
//     (MASVS-CODE-4). The link itself survives.
//   * Phase 415 — `status`: an ACTIVE link must carry a trusted slug + url
//     (above); a REVOKED link carries neither and maps to
//     `BookingLinkStatus.revoked` with `slug`/`url` null and `bookable`
//     false. A REVOKED SALON link without a UUID salon id is dropped — it
//     could never be regenerated (the route needs the id). An unknown status
//     drops the link.
//
// Phase 415 — [BookingLinksRepository.regenerate] (backend 378). 409 / 404 /
// 429 come back as [BookingLinkMutationOutcome] values, re-mapped by HTTP
// status BEFORE deferring to the interceptor's failure (it maps 409 to a
// bare `ServerFailure(409)` and has no 429 arm for these routes). The
// response link goes through the same mapper rules as `getMine`; a response
// the mapper would drop is a `ServerFailure`. The app never revokes (415 D1,
// user decision 2026-10-23): no revoke method here even though backend 378
// still serves `DELETE`.

import 'dart:developer';

import 'package:beautica_api/beautica_api.dart' as api;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/config/app_config.dart';
import '../../../core/errors/failures.dart';
import '../../../core/network/api_client_provider.dart';
import '../../../shared/validators/uuid_validator.dart';
import '../domain/booking_link.dart';
import '../domain/booking_link_url.dart';

part 'booking_links_repository.g.dart';

const String _logName = 'feature.booking_links.repository';

abstract interface class BookingLinksRepository {
  /// The caller's booking links (`GET /booking-links/mine`).
  Future<BookingLinks> getMine();

  /// Replaces [link]'s slug with a new one (`POST .../regenerate`), sending
  /// the slug the app shows (`null` for a revoked link) as `currentSlug`.
  Future<BookingLinkMutationOutcome> regenerate(BookingLink link);
}

final class HttpBookingLinksRepository implements BookingLinksRepository {
  HttpBookingLinksRepository(this._api);

  final api.BookingLinksApi _api;

  @override
  Future<BookingLinks> getMine() async {
    try {
      final res = await _api.getMine();
      final api.BookingLinksResponse? dto = res.data?.data;
      if (dto == null) {
        if (kDebugMode) {
          log(
            'getMine: ApiResponseBookingLinksResponse.data is null',
            name: _logName,
            level: 1000,
          );
        }
        throw const ServerFailure(statusCode: null);
      }
      return mapBookingLinks(dto);
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        log(
          'getMine failed: ${e.type} ${e.response?.statusCode}',
          name: _logName,
          level: 900,
          stackTrace: st,
        );
      }
      throw _mapDioException(e);
    }
  }

  @override
  Future<BookingLinkMutationOutcome> regenerate(BookingLink link) async {
    final api.BookingLinkMutationRequest body = api.BookingLinkMutationRequest(
      (b) => b..currentSlug = link.slug,
    );
    try {
      final Response<api.ApiResponseBookingLinkResponse> res;
      switch (link.kind) {
        case BookingLinkKind.master:
          res = await _api.regenerateMaster(bookingLinkMutationRequest: body);
        case BookingLinkKind.salon:
          final String? salonId = link.salonId;
          // A salon link without a trusted id has no regenerate route; the
          // screen never offers the action for it.
          if (salonId == null) throw const UnknownFailure();
          res = await _api.regenerateSalon(
            salonId: salonId,
            bookingLinkMutationRequest: body,
          );
      }
      final api.BookingLinkResponse? dto = res.data?.data;
      final BookingLink? mapped = dto == null ? null : mapBookingLink(dto);
      // The reply must describe the SAME link: same kind and, for a salon
      // link, the same salon — never let a mismatched body replace the card.
      if (mapped == null ||
          mapped.kind != link.kind ||
          (link.kind == BookingLinkKind.salon &&
              mapped.salonId != link.salonId)) {
        if (kDebugMode) {
          log('regenerate: unusable response', name: _logName, level: 1000);
        }
        throw const ServerFailure(statusCode: null);
      }
      return BookingLinkMutationOutcome.done(mapped);
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      final int? status = e.response?.statusCode;
      if (kDebugMode) {
        log(
          'regenerate failed: ${e.type} $status',
          name: _logName,
          level: 900,
          stackTrace: st,
        );
      }
      switch (status) {
        case 409:
          return const BookingLinkMutationOutcome.stale();
        case 404:
          return const BookingLinkMutationOutcome.unavailable();
        case 429:
          return const BookingLinkMutationOutcome.rateLimited();
      }
      throw _mapDioException(e);
    }
  }

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

/// Maps the generated DTO to the domain model (see the file header rules).
@visibleForTesting
BookingLinks mapBookingLinks(api.BookingLinksResponse dto) {
  if (!dto.shareEnabled) return BookingLinks.hidden;
  final List<BookingLink> links = <BookingLink>[];
  for (final api.BookingLinkResponse l in dto.links) {
    final BookingLink? link = mapBookingLink(l);
    if (link != null) links.add(link);
  }
  return BookingLinks(shareEnabled: true, links: links);
}

/// One wire link → domain, or `null` when it must be dropped (see the file
/// header rules).
@visibleForTesting
BookingLink? mapBookingLink(api.BookingLinkResponse l) {
  final BookingLinkKind? kind = _kindOf(l.kind);
  if (kind == null) {
    if (kDebugMode) {
      log('dropping link of unknown kind', name: _logName, level: 900);
    }
    return null;
  }
  final String? salonId = _trustedSalonId(l.salonId);
  if (l.status == api.BookingLinkResponseStatusEnum.REVOKED) {
    if (kind == BookingLinkKind.salon && salonId == null) {
      if (kDebugMode) {
        log(
          'dropping revoked salon link without a salon id',
          name: _logName,
          level: 900,
        );
      }
      return null;
    }
    return BookingLink(
      kind: kind,
      slug: null,
      url: null,
      displayName: l.displayName,
      salonId: salonId,
      bookable: false,
      status: BookingLinkStatus.revoked,
    );
  }
  if (l.status != api.BookingLinkResponseStatusEnum.ACTIVE) {
    if (kDebugMode) {
      log('dropping link of unknown status', name: _logName, level: 900);
    }
    return null;
  }
  final String? slug = l.slug;
  final String? url = l.url;
  if (slug == null ||
      url == null ||
      !isTrustedBookingLinkUrl(url, kind: kind, slug: slug)) {
    if (kDebugMode) {
      // The URL itself is not logged — it is server data of unknown shape.
      log(
        'dropping ${kind.name} link with an untrusted url',
        name: _logName,
        level: 900,
      );
    }
    return null;
  }
  return BookingLink(
    kind: kind,
    slug: slug,
    url: url,
    displayName: l.displayName,
    salonId: salonId,
    bookable: l.bookable,
  );
}

/// [raw] when it is a UUID, otherwise `null` (see the file header rules).
String? _trustedSalonId(String? raw) {
  if (raw == null || isUuid(raw)) return raw;
  if (kDebugMode) {
    // The value itself is not logged — it is server data of unknown shape.
    log('dropping a non-UUID salonId', name: _logName, level: 900);
  }
  return null;
}

/// Whether [url] is exactly the canonical public booking page for [kind] +
/// [slug] on [AppConfig.publicWebOrigin] (see the file header rules).
///
/// Delegates to the domain's [isCanonicalBookingLinkUrl] — the same check
/// `BookingLinkUrl.forSharing` re-runs at share time. An exact string match,
/// not a parse: any query (`?r=...`), fragment, port, userinfo, dot-segment
/// or casing difference fails it, and nothing the server adds beyond the
/// canonical URL can reach the share sheet.
@visibleForTesting
bool isTrustedBookingLinkUrl(
  String url, {
  required BookingLinkKind kind,
  required String slug,
}) => isCanonicalBookingLinkUrl(
  url,
  origin: AppConfig.publicWebOrigin,
  kind: kind,
  slug: slug,
);

BookingLinkKind? _kindOf(api.BookingLinkResponseKindEnum kind) {
  if (kind == api.BookingLinkResponseKindEnum.MASTER) {
    return BookingLinkKind.master;
  }
  if (kind == api.BookingLinkResponseKindEnum.SALON) {
    return BookingLinkKind.salon;
  }
  return null;
}

@Riverpod(keepAlive: true)
BookingLinksRepository bookingLinksRepository(Ref ref) =>
    HttpBookingLinksRepository(ref.watch(bookingLinksApiProvider));
