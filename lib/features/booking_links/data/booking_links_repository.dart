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
    final BookingLinkKind? kind = _kindOf(l.kind);
    if (kind == null) {
      if (kDebugMode) {
        log('dropping link of unknown kind', name: _logName, level: 900);
      }
      continue;
    }
    if (!isTrustedBookingLinkUrl(l.url, kind: kind, slug: l.slug)) {
      if (kDebugMode) {
        // The URL itself is not logged — it is server data of unknown shape.
        log(
          'dropping ${kind.name} link with an untrusted url',
          name: _logName,
          level: 900,
        );
      }
      continue;
    }
    links.add(
      BookingLink(
        kind: kind,
        slug: l.slug,
        url: l.url,
        displayName: l.displayName,
        salonId: _trustedSalonId(l.salonId),
        bookable: l.bookable,
      ),
    );
  }
  return BookingLinks(shareEnabled: true, links: links);
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
