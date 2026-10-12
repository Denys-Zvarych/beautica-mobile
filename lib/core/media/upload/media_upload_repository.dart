// Phase 070 — the ONE shared media-upload seam.
//
// Hand-written over the app `dioProvider` (Auth / Refresh / ErrorMapper
// interceptors all stay in the chain) because the generated
// `MediaControllerApi.uploadAvatar` posts JSON and cannot report progress.
// Follows the in-repo multipart precedent in `support_repository.dart`.
//
// Phase 074 adds the service-photo methods by calling the SAME private
// `_upload` — do NOT add a second upload path.
//
// Phase 369 adds the salon logo / cover methods ([uploadSalonImage] /
// [deleteSalonImage], `POST`/`DELETE /salons/{salonId}/media/{logo|cover}`,
// SALON_OWNER only) on that same `_upload`.
//
// Phase 403 (9.8, D4) adds the portfolio methods ([getMasterPortfolio],
// [uploadPortfolioPhoto], [deletePortfolioPhoto]) — salon
// (`/salons/{salonId}/portfolio[/{mediaId}]`, owner or bound admin) and
// independent master (`/media/portfolio[/{mediaId}]`, self-only) — again on
// that same `_upload`. Portfolio uploads declare the file's REAL content type
// (sniffed from its magic bytes) instead of the avatar path's fixed JPEG, and
// map 409 / 503 portfolio-specifically (see [mapUploadFailure]'s
// `portfolio:`).

import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:beautica_api/beautica_api.dart'
    show MediaControllerApi, MediaFileResponse, standardSerializers;
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/media/portfolio/portfolio_owner.dart';
import 'package:beautica_mobile/core/media/portfolio/portfolio_photo.dart';
import 'package:beautica_mobile/core/media/portfolio/portfolio_photo_mapper.dart';
import 'package:beautica_mobile/core/media/upload/upload_failure.dart';
import 'package:beautica_mobile/core/media/upload/upload_task.dart';
import 'package:beautica_mobile/core/network/dio_provider.dart';
import 'package:beautica_mobile/core/network/path_segment.dart';
import 'package:beautica_mobile/core/network/retry_on_unauthorized.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:http_parser/http_parser.dart' show MediaType;
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'media_upload_repository.g.dart';

/// Client-side size ceiling — mirrors the server's 5 MB Tomcat limit.
const int kMaxUploadBytes = 5 * 1024 * 1024;

/// Uploads are slower than the 15 s default `sendTimeout` allows on a weak LAN.
const Duration kUploadSendTimeout = Duration(seconds: 60);

/// Multipart part name the backend binds (`@RequestPart("file")`).
const String kUploadPartName = 'file';

/// Phase 403 — the `data.code` backend 362 sends with a portfolio-cap 409.
const String kPortfolioLimitReachedCode = 'PORTFOLIO_LIMIT_REACHED';

/// Minimum progress step (1 %) so listeners rebuild cheaply.
const double _kProgressStep = 0.01;

/// Phase 369 — the two salon image slots. [wire] is the EXACT lowercase path
/// segment the backend binds (`/salons/{salonId}/media/{logo|cover}`).
enum SalonImageSlot {
  /// The round salon logo (served back as `SalonResponse.avatarUrl`).
  logo('logo'),

  /// The 16:9 cover banner (served back as `SalonResponse.coverImageUrl`).
  cover('cover');

  const SalonImageSlot(this.wire);

  /// The path segment.
  final String wire;
}

/// Uploads / deletes media through the authenticated Dio.
abstract interface class MediaUploadRepository {
  /// Uploads [file] as the caller's avatar; the task resolves to the public
  /// avatar URL.
  UploadTask<String> uploadAvatar(File file);

  /// Removes the caller's avatar.
  Future<void> deleteAvatar();

  /// Phase 369 — uploads [file] as [salonId]'s [slot] image (SALON_OWNER of
  /// that salon only; anyone else gets 403 → [UploadForbiddenFailure] with
  /// `salonOwnerOnly`). The task resolves to the slot's new public URL.
  UploadTask<String> uploadSalonImage(
    String salonId,
    SalonImageSlot slot,
    File file,
  );

  /// Phase 369 — removes [salonId]'s [slot] image (owner only, `204`).
  Future<void> deleteSalonImage(String salonId, SalonImageSlot slot);

  /// Phase 403 — the independent master [masterId]'s public portfolio
  /// (`GET /masters/{masterId}/portfolio`, newest first, at most 50). The
  /// SALON read stays on `SalonRepository.getSalonPortfolio`. Throws a
  /// [Failure].
  Future<List<PortfolioPhoto>> getMasterPortfolio(String masterId);

  /// Phase 403 (D4) — uploads [file] to [owner]'s portfolio. Master →
  /// `POST /media/portfolio` (INDEPENDENT_MASTER, self); salon →
  /// `POST /salons/{salonId}/portfolio` (owner or the admin bound to it). The
  /// task resolves to the stored photo; over the cap it errors with
  /// [PortfolioLimitReachedFailure], under lock contention with
  /// [UploadBusyFailure].
  UploadTask<PortfolioPhoto> uploadPortfolioPhoto(
    PortfolioOwner owner,
    File file,
  );

  /// Phase 403 (D4) — deletes portfolio photo [mediaId] of [owner] (`204`).
  /// Master → `DELETE /media/portfolio/{mediaId}` (own rows only; anyone
  /// else's is a 404); salon → `DELETE /salons/{salonId}/portfolio/{mediaId}`
  /// (any salon manager, whoever uploaded it).
  Future<void> deletePortfolioPhoto(PortfolioOwner owner, String mediaId);
}

/// HTTP implementation. Inject via [mediaUploadRepositoryProvider].
final class HttpMediaUploadRepository implements MediaUploadRepository {
  HttpMediaUploadRepository({
    required Dio dio,
    bool Function()? isSessionLive,
    String? Function()? currentUserId,
  }) : _dio = dio,
       _mediaApi = MediaControllerApi(dio, standardSerializers),
       _isSessionLive = isSessionLive ?? _alwaysLive,
       _currentUserId = currentUserId;

  final Dio _dio;

  /// The generated read client over the SAME [_dio] (no second Dio).
  final MediaControllerApi _mediaApi;

  /// `false` once the session has ended (e.g. `RefreshInterceptor` failed and
  /// forced a logout) — the 401 retry is then pointless and is skipped.
  final bool Function() _isSessionLive;

  /// The signed-in user's id. When set, the 401 retry additionally requires
  /// the user who STARTED the upload to still be the signed-in one (Phase 367
  /// audit, security INFO): an account switch between the 401 and the retry
  /// must never deliver one user's photo under another user's fresh token.
  /// `null` (the default) skips the identity check.
  final String? Function()? _currentUserId;

  static bool _alwaysLive() => true;

  static const _tag = 'core.media.upload';

  // Raw path MUST carry `/api/v1` — `AppConfig.baseUrl` never does.
  static const _avatarPath = '/api/v1/media/avatar';

  @override
  UploadTask<String> uploadAvatar(File file) => _upload<String>(
    _avatarPath,
    file,
    // The backend always re-validates by magic bytes, so the declared type is
    // informational; JPEG is what the picker/crop pipeline (071) emits.
    filename: 'avatar.jpg',
    contentType: MediaType('image', 'jpeg'),
    parse: (Object? body) {
      if (body is Map) {
        final data = body['data'];
        if (data is Map) {
          final url = data['avatarUrl'];
          if (url is String && url.isNotEmpty) return url;
        }
      }
      return null;
    },
  );

  @override
  Future<void> deleteAvatar() async {
    try {
      await _dio.delete<Object?>(_avatarPath);
    } on DioException catch (e) {
      _logFailure('deleteAvatar', e);
      throw mapUploadFailure(e);
    }
  }

  @override
  UploadTask<String> uploadSalonImage(
    String salonId,
    SalonImageSlot slot,
    File file,
  ) {
    final String path;
    try {
      path = _salonImagePath(salonId, slot);
    } on Failure {
      // Unreachable for a server-issued UUID; never open a request for it.
      return UploadTask<String>(
        progress: const Stream<double>.empty(),
        result: Future<String>.error(const UploadUnknownFailure()),
        onCancel: () {},
      );
    }
    final UploadTask<String> task = _upload<String>(
      path,
      file,
      filename: '${slot.wire}.jpg',
      contentType: MediaType('image', 'jpeg'),
      parse: (Object? body) {
        if (body is Map) {
          final data = body['data'];
          if (data is Map) {
            // The answer is the whole updated salon; the slot's own field is
            // the new URL (logo → `avatarUrl`, cover → `coverImageUrl`).
            final url =
                data[switch (slot) {
                  SalonImageSlot.logo => 'avatarUrl',
                  SalonImageSlot.cover => 'coverImageUrl',
                }];
            if (url is String && url.isNotEmpty) return url;
          }
        }
        return null;
      },
    );
    return UploadTask<String>(
      progress: task.progress,
      result: task.result.catchError(
        (Object e) => throw _asSalonFailure(e as UploadFailure),
        test: (Object e) => e is UploadFailure,
      ),
      onCancel: task.cancel,
    );
  }

  @override
  Future<void> deleteSalonImage(String salonId, SalonImageSlot slot) async {
    final String path;
    try {
      path = _salonImagePath(salonId, slot);
    } on Failure {
      throw const UploadUnknownFailure();
    }
    try {
      await _dio.delete<Object?>(path);
    } on DioException catch (e) {
      _logFailure('deleteSalonImage', e);
      throw _asSalonFailure(mapUploadFailure(e));
    }
  }

  /// `/api/v1/salons/{salonId}/media/{logo|cover}` — the id is encoded as ONE
  /// path segment (throws a [Failure] for an empty / dot-segment id).
  static String _salonImagePath(String salonId, SalonImageSlot slot) =>
      '/api/v1/salons/'
      '${encodePathSegment(salonId, 'salonId', logTag: _tag)}'
      '/media/${encodePathSegment(slot.wire, 'slot', logTag: _tag)}';

  // Phase 403 — the independent master's own portfolio (self, by JWT).
  static const _masterPortfolioPath = '/api/v1/media/portfolio';

  @override
  Future<List<PortfolioPhoto>> getMasterPortfolio(String masterId) async {
    // The generated client interpolates path params RAW (`path_segment.dart`)
    // — gate the id through the encoder first (throws a [Failure]).
    final String id = encodePathSegment(masterId, 'masterId', logTag: _tag);
    try {
      final res = await _mediaApi.getMasterPortfolio(masterId: id);
      // Spring's default `Page<T>` shape: rows under `content`.
      return PortfolioPhotoMapper.fromDtoList(
        res.data?.data?.content ?? const <MediaFileResponse>[],
      );
    } on DioException catch (e) {
      _logFailure('getMasterPortfolio', e);
      final Object? mapped = e.error;
      // ErrorMapperInterceptor has already typed every transport / status
      // case; an untyped error is a bug, not a user condition.
      if (mapped is Failure) throw mapped;
      throw UnknownFailure(cause: e);
    }
  }

  @override
  UploadTask<PortfolioPhoto> uploadPortfolioPhoto(
    PortfolioOwner owner,
    File file,
  ) {
    final String path;
    try {
      path = _portfolioPath(owner);
    } on Failure {
      // Unreachable for a server-issued UUID; never open a request for it.
      return UploadTask<PortfolioPhoto>(
        progress: const Stream<double>.empty(),
        result: Future<PortfolioPhoto>.error(const UploadUnknownFailure()),
        onCancel: () {},
      );
    }
    return _upload<PortfolioPhoto>(
      path,
      file,
      // Placeholders: [part] replaces both with the sniffed real type.
      filename: 'portfolio.jpg',
      contentType: MediaType('image', 'jpeg'),
      part: () => sniffImagePart(file, 'portfolio'),
      portfolio: true,
      parse: (Object? body) =>
          body is Map ? PortfolioPhotoMapper.fromJson(body['data']) : null,
    );
  }

  @override
  Future<void> deletePortfolioPhoto(
    PortfolioOwner owner,
    String mediaId,
  ) async {
    final String path;
    try {
      path =
          '${_portfolioPath(owner)}/'
          '${encodePathSegment(mediaId, 'mediaId', logTag: _tag)}';
    } on Failure {
      throw const UploadUnknownFailure();
    }
    try {
      await _dio.delete<Object?>(
        path,
        // Like the uploads: a redirect on an authenticated write must never
        // re-send the Bearer token elsewhere.
        options: Options(followRedirects: false),
      );
    } on DioException catch (e) {
      _logFailure('deletePortfolioPhoto', e);
      throw mapUploadFailure(e, portfolio: true);
    }
  }

  /// The portfolio collection path of [owner] — ids encoded as ONE path
  /// segment each (throws a [Failure] for an empty / dot-segment id).
  static String _portfolioPath(PortfolioOwner owner) => switch (owner) {
    // Self-only: the backend resolves the master from the JWT.
    final PortfolioOwnerMasterSelf _ => _masterPortfolioPath,
    final PortfolioOwnerSalon o =>
      '/api/v1/salons/'
          '${encodePathSegment(o.salonId, 'salonId', logTag: _tag)}'
          '/portfolio',
  };

  /// A salon-image 403 always means "not the owner" (D6).
  static UploadFailure _asSalonFailure(UploadFailure f) =>
      f is UploadForbiddenFailure
      ? const UploadForbiddenFailure(salonOwnerOnly: true)
      : f;

  /// Shared multipart upload. [parse] returns `null` for an unusable body.
  UploadTask<T> _upload<T>(
    String path,
    File file, {
    required String filename,
    required MediaType contentType,
    required T? Function(Object? body) parse,
    Future<ImagePart> Function()? part,
    bool portfolio = false,
  }) {
    final cancelToken = CancelToken();
    final controller = StreamController<double>.broadcast();
    // Captured synchronously, before any await: the user this upload is FOR.
    final String? Function()? currentUserId = _currentUserId;
    final String? startedBy = currentUserId?.call();
    bool sameUser() {
      if (currentUserId == null) return true;
      return startedBy != null && currentUserId() == startedBy;
    }

    // Reset on every retry so progress restarts from 0 instead of freezing at
    // the first attempt's high-water mark. Within an attempt it is strictly
    // increasing; across the retry the UI sees a deliberate restart.
    var last = 0.0;

    void emit(double fraction) {
      if (controller.isClosed) return;
      if (fraction - last >= _kProgressStep ||
          (fraction >= 1.0 && last < 1.0)) {
        last = fraction;
        controller.add(fraction);
      }
    }

    Future<T> run() async {
      final int size;
      try {
        size = await file.length();
      } on FileSystemException {
        throw const UploadUnknownFailure();
      }
      if (size > kMaxUploadBytes) throw const UploadTooLargeFailure();
      // Phase 403 — the real filename / content type, when the caller sniffs.
      final ImagePart resolved =
          await part?.call() ??
          ImagePart(filename: filename, contentType: contentType);
      if (cancelToken.isCancelled) throw const UploadCancelledFailure();

      // FormData is single-use (finalised on send), so every attempt builds a
      // fresh one. A 401 gets exactly ONE re-attempt: RefreshInterceptor
      // refreshes the token but cannot replay a finalised multipart body, so
      // the retry is what actually delivers the file with the new token.
      try {
        return await retryOnceOnUnauthorized<T>(
          () async {
            final response = await _dio.post<Object?>(
              path,
              data: FormData.fromMap(<String, Object>{
                kUploadPartName: await MultipartFile.fromFile(
                  file.path,
                  filename: resolved.filename,
                  contentType: resolved.contentType,
                ),
              }),
              options: Options(
                // Override the JSON default so Dio writes the boundary header.
                contentType: 'multipart/form-data',
                sendTimeout: kUploadSendTimeout,
                // A redirect on an authenticated upload must never re-send the
                // Bearer token / body elsewhere.
                followRedirects: false,
              ),
              cancelToken: cancelToken,
              onSendProgress: (int sent, int total) {
                if (total > 0) emit((sent / total).clamp(0.0, 1.0));
              },
            );
            final parsed = parse(response.data);
            if (parsed == null) {
              throw UploadUnknownFailure(response.statusCode);
            }
            emit(1.0);
            return parsed;
          },
          isUnauthorized: (e) =>
              mapUploadFailure(e, portfolio: portfolio)
                  is UploadUnauthorizedFailure,
          isSessionLive: () => _isSessionLive() && sameUser(),
          onRetry: (e) {
            _logFailure('upload(401, retrying)', e);
            last = 0.0;
            if (!controller.isClosed) controller.add(0.0);
          },
        );
      } on DioException catch (e) {
        _logFailure('upload', e);
        throw mapUploadFailure(e, portfolio: portfolio);
      }
    }

    final result = run().whenComplete(controller.close);
    return UploadTask<T>(
      progress: controller.stream,
      result: result,
      onCancel: () {
        if (!cancelToken.isCancelled) cancelToken.cancel();
      },
    );
  }

  /// Transport metadata only — never the path, URL, headers or `$e`.
  void _logFailure(String op, DioException e) {
    if (!kDebugMode) return;
    log(
      '$op failed: ${e.type} ${e.response?.statusCode}',
      name: _tag,
      level: 900,
    );
  }
}

/// The multipart file part's declared name and type.
final class ImagePart {
  const ImagePart({required this.filename, required this.contentType});

  final String filename;
  final MediaType contentType;
}

/// Phase 403 — the declared type of [file], sniffed from its magic bytes (the
/// same JPEG / PNG / WebP set the backend accepts — it re-validates by magic
/// bytes regardless). [stem] names the part (`portfolio.png`). Anything else
/// is rejected client-side with [UploadUnsupportedFormatFailure] instead of
/// being sent under a false type; an unreadable file is
/// [UploadUnknownFailure]. Exposed for tests.
@visibleForTesting
Future<ImagePart> sniffImagePart(File file, String stem) async {
  final List<int> head = <int>[];
  try {
    await for (final List<int> chunk in file.openRead(0, 12)) {
      head.addAll(chunk);
    }
  } on FileSystemException {
    throw const UploadUnknownFailure();
  }
  bool at(int offset, List<int> magic) {
    if (head.length < offset + magic.length) return false;
    for (var i = 0; i < magic.length; i++) {
      if (head[offset + i] != magic[i]) return false;
    }
    return true;
  }

  if (at(0, const <int>[0xFF, 0xD8, 0xFF])) {
    return ImagePart(
      filename: '$stem.jpg',
      contentType: MediaType('image', 'jpeg'),
    );
  }
  if (at(0, const <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) {
    return ImagePart(
      filename: '$stem.png',
      contentType: MediaType('image', 'png'),
    );
  }
  // RIFF....WEBP
  if (at(0, const <int>[0x52, 0x49, 0x46, 0x46]) &&
      at(8, const <int>[0x57, 0x45, 0x42, 0x50])) {
    return ImagePart(
      filename: '$stem.webp',
      contentType: MediaType('image', 'webp'),
    );
  }
  throw const UploadUnsupportedFormatFailure();
}

/// Maps a [DioException] (already passed through `ErrorMapperInterceptor`, so
/// `e.error` may be a typed [Failure]) to an [UploadFailure].
///
/// Status codes the mapper has no dedicated [Failure] for (413, 403, 503
/// semantics) are read from the retained response; transport and 401/404
/// semantics reuse the mapper's [Failure]. Exposed for tests.
///
/// Phase 403 — [portfolio] (the portfolio upload / delete paths only, D5)
/// adds two mappings and changes nothing else:
///   • 409 whose `data.code` is [kPortfolioLimitReachedCode] →
///     [PortfolioLimitReachedFailure] (any other 409 stays
///     [UploadConflictFailure] — never "limit reached" on the bare status);
///   • 503 carrying a `Retry-After` header → [UploadBusyFailure] (the
///     portfolio lock timed out); a 503 without one stays
///     [UploadStorageUnavailableFailure].
@visibleForTesting
UploadFailure mapUploadFailure(DioException e, {bool portfolio = false}) {
  if (e.type == DioExceptionType.cancel) return const UploadCancelledFailure();
  if (e.type == DioExceptionType.badCertificate) {
    return const UploadCertificateFailure();
  }
  final failure = e.error;
  if (failure is CertificateFailure) return const UploadCertificateFailure();
  if (failure is UnauthorizedFailure) return const UploadUnauthorizedFailure();

  final status = e.response?.statusCode;
  if (portfolio) {
    if (status == 409 && _errorCode(e) == kPortfolioLimitReachedCode) {
      return const PortfolioLimitReachedFailure();
    }
    // Presence of the header is the signal — its VALUE may be unusable, which
    // only drops the number ([uploadRetryAfterSeconds] → null, never 0).
    if (status == 503 && e.response?.headers.value('retry-after') != null) {
      return UploadBusyFailure(retryAfterSeconds: uploadRetryAfterSeconds(e));
    }
  }
  switch (status) {
    case 413:
      return const UploadTooLargeFailure();
    case 400:
      return const UploadUnsupportedFormatFailure();
    case 503:
      return const UploadStorageUnavailableFailure();
    case 401:
      return const UploadUnauthorizedFailure();
    case 403:
      return const UploadForbiddenFailure();
    case 404:
      return const UploadNotFoundFailure();
    // Phase 369 — the per-record write lock timed out: retryable.
    case 409:
      return const UploadConflictFailure();
    // Phase 369 — the shared 10/min photo-upload bucket is empty.
    case 429:
      return UploadRateLimitedFailure(
        retryAfterSeconds: uploadRetryAfterSeconds(e),
      );
  }

  if (failure is NetworkFailure) return const UploadNetworkFailure();
  if (failure is NotFoundFailure) return const UploadNotFoundFailure();

  switch (e.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.connectionError:
      return const UploadNetworkFailure();
    case DioExceptionType.cancel:
    case DioExceptionType.badCertificate:
    case DioExceptionType.badResponse:
    case DioExceptionType.unknown:
      return UploadUnknownFailure(status);
  }
}

/// `data.code` of an error envelope, or `null`.
String? _errorCode(DioException e) {
  final Object? body = e.response?.data;
  if (body is! Map) return null;
  final Object? data = body['data'];
  if (data is! Map) return null;
  final Object? code = data['code'];
  return code is String ? code : null;
}

/// The `Retry-After` of a 429 (integer seconds — the backend never sends the
/// HTTP-date form), then the `data.retryAfterSeconds` envelope field; `null`
/// when absent, unparsable, non-positive or above [kMaxUxCooldownSeconds] (a
/// rogue value never reaches the UI as a number). Exposed for tests.
@visibleForTesting
int? uploadRetryAfterSeconds(DioException e) {
  int? raw;
  final String? header = e.response?.headers.value('retry-after');
  if (header != null) raw = int.tryParse(header.trim());
  if (raw == null) {
    final Object? body = e.response?.data;
    if (body is Map) {
      final Object? data = body['data'];
      if (data is Map) {
        final Object? v = data['retryAfterSeconds'];
        // `double.infinity.toInt()` throws (a `1e999` body decodes to ±∞) —
        // only a finite number is converted; anything else = no hint.
        if (v is int) {
          raw = v;
        } else if (v is double && v.isFinite) {
          raw = v.toInt();
        }
      }
    }
  }
  if (raw == null || raw <= 0 || raw > kMaxUxCooldownSeconds) return null;
  return raw;
}

/// App-wide [MediaUploadRepository] over the authenticated Dio.
@Riverpod(keepAlive: true)
MediaUploadRepository mediaUploadRepository(Ref ref) =>
    HttpMediaUploadRepository(
      dio: ref.watch(dioProvider),
      isSessionLive: () => isAuthSessionLive(ref),
      currentUserId: () => authUserIdOrNull(ref.read(authProvider)),
    );
