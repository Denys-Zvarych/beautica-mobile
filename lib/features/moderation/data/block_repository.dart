// Phase 425 — ClientBlockRepository: the one seam for backend 397
// `/api/v1/blocks` (provider → client blocks).
//
// Implemented over the generated `beautica_api` [BlockControllerApi]. DTOs are
// never hand-written: [HttpClientBlockRepository] maps the generated
// [CreateBlockRequest] / [BlockResponse] to [ClientBlock]. Responses carry the
// blocked client's name, avatar and masked phone, so only transport metadata
// is ever logged, and `/api/v1/blocks` is a redacted path in
// `LoggingInterceptor` (`kPiiPathPrefixes`).

import 'dart:developer';

import 'package:beautica_api/beautica_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/api_enum_names.dart';
import 'package:beautica_mobile/core/network/dio_provider.dart';
import 'package:beautica_mobile/features/moderation/domain/client_block.dart';

part 'block_repository.g.dart';

const String _tag = 'feature.moderation.blocks';

/// Contract for provider → client blocks (backend 397).
///
/// Every method either resolves or throws a [Failure]; raw Dio types never
/// cross this boundary.
abstract interface class ClientBlockRepository {
  /// `POST /api/v1/blocks { bookingId }`. The server derives the target from
  /// the booking (account and/or phone hash) — the app never sends a phone.
  /// Idempotent: a repeat resolves with the EXISTING block (200).
  ///
  /// Throws [ValidationFailure] (400, STAFF walk-in / erased guest),
  /// [ServerFailure] 403 (client / salon master), [NotFoundFailure] (404,
  /// booking not in scope), [ClientBlockRateLimitedFailure] (429),
  /// [ResponseUnusableFailure] (2xx without a usable block), or the usual
  /// transport failures.
  Future<ClientBlock> block(String bookingId);

  /// `DELETE /api/v1/blocks/{blockId}` — 204, also when already gone.
  Future<void> unblock(String blockId);

  /// `GET /api/v1/blocks` — the caller's list (salon owner/admin: the
  /// salon's), newest first.
  Future<List<ClientBlock>> list();
}

/// HTTP implementation of [ClientBlockRepository].
///
/// Inject via [clientBlockRepositoryProvider] — never construct directly
/// outside tests.
final class HttpClientBlockRepository implements ClientBlockRepository {
  HttpClientBlockRepository(this._api);

  final BlockControllerApi _api;

  @override
  Future<ClientBlock> block(String bookingId) async {
    final Response<ApiResponseBlockResponse> response = await _guard(
      'block',
      () => _api.block(
        createBlockRequest: CreateBlockRequest((b) => b..bookingId = bookingId),
      ),
    );
    final ClientBlock? block = clientBlockFromDto(response.data?.data);
    if (block == null) throw const ResponseUnusableFailure();
    return block;
  }

  @override
  Future<void> unblock(String blockId) async {
    await _guard('unblock', () => _api.unblock(blockId: blockId));
  }

  @override
  Future<List<ClientBlock>> list() async {
    final Response<ApiResponseListBlockResponse> response = await _guard(
      'list',
      () => _api.list(),
    );
    final Iterable<BlockResponse>? rows = response.data?.data;
    if (rows == null) throw const ResponseUnusableFailure();
    final List<ClientBlock> blocks = <ClientBlock>[];
    for (final BlockResponse row in rows) {
      final ClientBlock? block = clientBlockFromDto(row);
      if (block != null) {
        blocks.add(block);
      } else if (kDebugMode) {
        // A malformed row is dropped, never the whole list. No row content
        // is logged (names / phones).
        log('list: dropped an unusable block row', name: _tag, level: 900);
      }
    }
    return List<ClientBlock>.unmodifiable(blocks);
  }

  Future<T> _guard<T>(String op, Future<T> Function() call) async {
    try {
      return await call();
    } on Failure {
      rethrow;
    } on DioException catch (e, st) {
      if (kDebugMode) {
        // Transport metadata only — never the body (names, masked phones).
        log(
          '$op failed: ${e.type} ${e.response?.statusCode}',
          name: _tag,
          level: 900,
          stackTrace: st,
        );
      }
      throw mapClientBlockDioException(e);
    }
  }
}

/// Maps a generated [BlockResponse] to a [ClientBlock], or `null` when a
/// required field (id, known kind, display name, createdAt) is missing.
@visibleForTesting
ClientBlock? clientBlockFromDto(BlockResponse? dto) {
  if (dto == null) return null;
  final String? id = dto.id;
  final String? displayName = dto.displayName;
  final DateTime? createdAt = dto.createdAt;
  final ClientBlockKind? kind = switch (knownEnumName(dto.kind)) {
    'CLIENT' => ClientBlockKind.client,
    'GUEST' => ClientBlockKind.guest,
    _ => null,
  };
  if (id == null || displayName == null || createdAt == null || kind == null) {
    return null;
  }
  // Kind-scoped fields: a guest has no account photo and a registered client's
  // phone is never shown, so a field the backend sends for the other kind is
  // dropped rather than trusted.
  final String? avatarUrl = kind == ClientBlockKind.client
      ? dto.avatarUrl
      : null;
  final String? maskedPhone = kind == ClientBlockKind.guest
      ? dto.maskedPhone
      : null;
  return ClientBlock(
    id: id,
    kind: kind,
    displayName: displayName,
    avatarUrl: (avatarUrl == null || avatarUrl.isEmpty) ? null : avatarUrl,
    maskedPhone: (maskedPhone == null || maskedPhone.isEmpty)
        ? null
        : maskedPhone,
    createdAt: createdAt,
  );
}

/// Maps a `/blocks` [DioException] to a typed [Failure].
///
/// The status arms run BEFORE the interceptor-attached failure: the shared
/// `ErrorMapperInterceptor` has no generic 429 arm, and the block UI keys its
/// own «Забагато змін блокувань» copy on [ClientBlockRateLimitedFailure].
@visibleForTesting
Failure mapClientBlockDioException(DioException e) {
  final int? statusCode = e.response?.statusCode;
  if (statusCode == 429) return ClientBlockRateLimitedFailure(cause: e);
  if (statusCode == 404) return NotFoundFailure(cause: e);
  if (statusCode == 403) return ServerFailure(statusCode: 403, cause: e);
  final Object? attached = e.error;
  if (attached is Failure) return attached;
  if (statusCode == 400 || statusCode == 422) {
    return ValidationFailure(fieldErrors: const {}, cause: e);
  }
  switch (e.type) {
    case DioExceptionType.connectionError:
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
      return NetworkFailure(cause: e);
    case DioExceptionType.badResponse:
      if (statusCode == 401) return UnauthorizedFailure(cause: e);
      return ServerFailure(statusCode: statusCode, cause: e);
    case DioExceptionType.cancel:
    case DioExceptionType.badCertificate:
    case DioExceptionType.unknown:
      return UnknownFailure(cause: e);
  }
}

/// The generated [BlockControllerApi] on the authenticated Dio (full
/// interceptor chain). Feature-local, mirroring `reportApiProvider`.
@Riverpod(keepAlive: true)
BlockControllerApi blockApi(Ref ref) =>
    BlockControllerApi(ref.watch(dioProvider), standardSerializers);

/// The app-wide [ClientBlockRepository].
@Riverpod(keepAlive: true)
ClientBlockRepository clientBlockRepository(Ref ref) =>
    HttpClientBlockRepository(ref.watch(blockApiProvider));
