// Phase 070 — the ONE shared media-upload seam.
//
// Hand-written over the app `dioProvider` (Auth / Refresh / ErrorMapper
// interceptors all stay in the chain) because the generated
// `MediaControllerApi.uploadAvatar` posts JSON and cannot report progress.
// Follows the in-repo multipart precedent in `support_repository.dart`.
//
// Phase 074 adds the service-photo methods by calling the SAME private
// `_upload` — do NOT add a second upload path.

import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/media/upload/upload_failure.dart';
import 'package:beautica_mobile/core/media/upload/upload_task.dart';
import 'package:beautica_mobile/core/network/dio_provider.dart';
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

/// Minimum progress step (1 %) so listeners rebuild cheaply.
const double _kProgressStep = 0.01;

/// Uploads / deletes media through the authenticated Dio.
abstract interface class MediaUploadRepository {
  /// Uploads [file] as the caller's avatar; the task resolves to the public
  /// avatar URL.
  UploadTask<String> uploadAvatar(File file);

  /// Removes the caller's avatar.
  Future<void> deleteAvatar();
}

/// HTTP implementation. Inject via [mediaUploadRepositoryProvider].
final class HttpMediaUploadRepository implements MediaUploadRepository {
  HttpMediaUploadRepository({
    required Dio dio,
    bool Function()? isSessionLive,
    String? Function()? currentUserId,
  }) : _dio = dio,
       _isSessionLive = isSessionLive ?? _alwaysLive,
       _currentUserId = currentUserId;

  final Dio _dio;

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

  /// Shared multipart upload. [parse] returns `null` for an unusable body.
  UploadTask<T> _upload<T>(
    String path,
    File file, {
    required String filename,
    required MediaType contentType,
    required T? Function(Object? body) parse,
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
                  filename: filename,
                  contentType: contentType,
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
              mapUploadFailure(e) is UploadUnauthorizedFailure,
          isSessionLive: () => _isSessionLive() && sameUser(),
          onRetry: (e) {
            _logFailure('upload(401, retrying)', e);
            last = 0.0;
            if (!controller.isClosed) controller.add(0.0);
          },
        );
      } on DioException catch (e) {
        _logFailure('upload', e);
        throw mapUploadFailure(e);
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

/// Maps a [DioException] (already passed through `ErrorMapperInterceptor`, so
/// `e.error` may be a typed [Failure]) to an [UploadFailure].
///
/// Status codes the mapper has no dedicated [Failure] for (413, 403, 503
/// semantics) are read from the retained response; transport and 401/404
/// semantics reuse the mapper's [Failure]. Exposed for tests.
@visibleForTesting
UploadFailure mapUploadFailure(DioException e) {
  if (e.type == DioExceptionType.cancel) return const UploadCancelledFailure();
  if (e.type == DioExceptionType.badCertificate) {
    return const UploadCertificateFailure();
  }
  final failure = e.error;
  if (failure is CertificateFailure) return const UploadCertificateFailure();
  if (failure is UnauthorizedFailure) return const UploadUnauthorizedFailure();

  final status = e.response?.statusCode;
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

/// App-wide [MediaUploadRepository] over the authenticated Dio.
@Riverpod(keepAlive: true)
MediaUploadRepository mediaUploadRepository(Ref ref) =>
    HttpMediaUploadRepository(
      dio: ref.watch(dioProvider),
      isSessionLive: () => isAuthSessionLive(ref),
      currentUserId: () => authUserIdOrNull(ref.read(authProvider)),
    );
