// Phase 367 (9.6) — PROMOTED out of `master_avatar_upload_test.dart` (Phase
// 073) so the owner / admin / client own-avatar E2E reuses the SAME headless
// pick → crop → compress stand-in instead of copying it.

import 'dart:io';

import 'package:beautica_mobile/core/media/pick/crop_labels.dart';
import 'package:beautica_mobile/core/media/pick/image_pick_gateway.dart';
import 'package:beautica_mobile/core/media/pick/media_kind.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_backend.dart';

/// The fixture JPEG every own-avatar E2E "picks".
const String kAvatarFixturePath = 'integration_test/fixtures/avatar.jpg';

/// Headless stand-in for the native pick → crop → compress plugins: hands the
/// fixture JPEG through the REAL `MediaPickService` pipeline.
final class FixtureAvatarGateway implements ImagePickGateway {
  int picks = 0;
  bool cancelPick = false;
  CropLabels? lastCropLabels;

  @override
  Future<String?> pickImage(
    MediaPickSource source, {
    required int maxDimension,
  }) async {
    picks++;
    if (cancelPick) return null;
    return kAvatarFixturePath;
  }

  @override
  Future<String?> cropImage(
    String sourcePath, {
    required MediaSpec spec,
    required int quality,
    CropLabels? labels,
  }) async {
    lastCropLabels = labels;
    return sourcePath;
  }

  @override
  Future<String?> compress(
    String sourcePath,
    String targetPath, {
    required int maxWidth,
    required int maxHeight,
    required int quality,
    required bool keepExif,
  }) async {
    await File(sourcePath).copy(targetPath);
    return targetPath;
  }

  @override
  Future<String?> retrieveLostData() async => null;
}

/// Phase 367 QA — the locked rule "a personal avatar is set only by the person
/// themselves", asserted on the WIRE for every own-avatar request [fb] saw:
///
/// * `POST /api/v1/media/avatar` — exact path, no query, and a multipart body
///   whose ONLY part is `file` (no `userId` / `targetUserId` / `user_id`
///   form field, no second file part);
/// * `DELETE /api/v1/media/avatar` — exact path, no query, no body.
///
/// [uploads] / [deletes] pin how many requests were inspected, so a run that
/// never reached the server cannot pass vacuously.
void expectSelfOnlyAvatarRequests(
  FakeBackend fb, {
  required int uploads,
  int deletes = 0,
}) {
  expect(fb.mediaAvatarUploadUris, hasLength(uploads));
  expect(fb.mediaAvatarUploadPartNames, hasLength(uploads));
  expect(fb.mediaAvatarDeleteUris, hasLength(deletes));
  for (final Uri u in fb.mediaAvatarUploadUris) {
    expect(u.path, '/api/v1/media/avatar');
    expect(u.query, isEmpty, reason: 'POST names no target user (query)');
  }
  for (final List<String> parts in fb.mediaAvatarUploadPartNames) {
    expect(parts, <String>[
      'file',
    ], reason: 'the multipart body carries ONLY the file part — no user id');
  }
  for (final Uri u in fb.mediaAvatarDeleteUris) {
    expect(u.path, '/api/v1/media/avatar');
    expect(u.query, isEmpty, reason: 'DELETE names no target user (query)');
  }
  for (final Object? body in fb.mediaAvatarDeleteBodies) {
    expect(body, isNull, reason: 'DELETE carries no body (no user id)');
  }
}
