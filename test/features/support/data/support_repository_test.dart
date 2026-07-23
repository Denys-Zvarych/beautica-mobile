// Unit tests for [HttpSupportRepository].
//
// Strategy:
//   The repository issues a raw multipart POST via the authenticated [Dio]
//   instance. We mock [Dio] with mocktail and capture the [FormData] it is
//   asked to send so we can assert the multipart SHAPE (the JSON `request`
//   part + N `attachments` parts) without a real socket — the same mock-Dio
//   pattern service_repository_test.dart uses for its transport-level checks.
//
// Coverage:
//   1.  submitContact() — success (202) resolves; the `request` JSON part is
//       present with content-type application/json and carries {message}.
//   2.  submitContact() — optional subject: trimmed + included when non-empty;
//       omitted when blank/whitespace/null.
//   3.  submitContact() — N attachments mapped to N `attachments` file parts
//       with the right filename + sniffed content type.
//   4.  status → Failure mapping: 400 → Validation, 401 → Unauthorized,
//       413 → SupportAttachmentTooLargeFailure, 503 → SupportChannelUnavailable,
//       connectionError → Network, 500 → Server.
//   5.  a pre-mapped Failure on e.error is re-thrown unchanged (interceptor
//       already mapped it) — EXCEPT 413/503, which the repo maps itself.
//
// Layer: Unit (pure Dart, no widget tree).

import 'dart:convert';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/support/data/support_repository.dart';
import 'package:beautica_mobile/features/support/domain/support_attachment.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

// ── Mocks ──────────────────────────────────────────────────────────────────

class _MockDio extends Mock implements Dio {}

// ── Helpers ──────────────────────────────────────────────────────────────────

const _path = '/api/v1/support/contact';

SupportAttachment _image(String name, {int bytes = 1024}) => SupportAttachment(
  name: name,
  bytes: List<int>.filled(bytes, 0),
  contentType: 'image/png',
  kind: SupportAttachmentKind.image,
);

SupportAttachment _pdf(String name, {int bytes = 2048}) => SupportAttachment(
  name: name,
  bytes: List<int>.filled(bytes, 0),
  contentType: 'application/pdf',
  kind: SupportAttachmentKind.pdf,
);

/// A 202 Accepted response (the backend's success contract for this endpoint).
Response<Object?> _accepted() => Response<Object?>(
  requestOptions: RequestOptions(path: _path),
  statusCode: 202,
);

/// A badResponse [DioException] carrying [status].
DioException _badResponse(int status) => DioException(
  requestOptions: RequestOptions(path: _path),
  response: Response<dynamic>(
    requestOptions: RequestOptions(path: _path),
    statusCode: status,
  ),
  type: DioExceptionType.badResponse,
);

void main() {
  late _MockDio dio;
  late HttpSupportRepository repo;

  setUpAll(() {
    registerFallbackValue(RequestOptions(path: _path));
    registerFallbackValue(FormData());
    registerFallbackValue(Options());
  });

  setUp(() {
    dio = _MockDio();
    repo = HttpSupportRepository(dio: dio);
  });

  /// Stubs `dio.post` to succeed and returns the captured [FormData].
  Future<FormData> captureFormData(Future<void> Function() act) async {
    when(
      () => dio.post<Object?>(
        any(),
        data: any(named: 'data'),
        options: any(named: 'options'),
      ),
    ).thenAnswer((_) async => _accepted());

    await act();

    final captured = verify(
      () => dio.post<Object?>(
        _path,
        data: captureAny(named: 'data'),
        options: any(named: 'options'),
      ),
    ).captured.single;
    return captured as FormData;
  }

  // ── 1. multipart request part ────────────────────────────────────────────

  group('multipart build', () {
    test('success (202) resolves and posts a `request` JSON part with '
        'application/json content-type carrying {message}', () async {
      late FormData form;
      form = await captureFormData(
        () => repo.submitContact(message: 'A real ten-plus char message'),
      );

      // Exactly one part is the JSON `request` part.
      final requestParts = form.files.where((e) => e.key == 'request').toList();
      expect(requestParts, hasLength(1));

      final MultipartFile requestPart = requestParts.single.value;
      expect(
        requestPart.contentType.toString(),
        startsWith('application/json'),
        reason:
            'the request part must be a JSON part (mixed multipart), '
            'not a plain form field',
      );

      // The JSON payload carries the message and (here) no subject.
      final String json = await requestPart
          .finalize()
          .fold<List<int>>(<int>[], (acc, chunk) => acc..addAll(chunk))
          .then(utf8.decode);
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      expect(decoded['message'], 'A real ten-plus char message');
      expect(decoded.containsKey('subject'), isFalse);
    });

    test(
      'non-empty subject is trimmed and included in the request part',
      () async {
        final form = await captureFormData(
          () => repo.submitContact(
            message: 'A real ten-plus char message',
            subject: '  Billing question  ',
          ),
        );

        final MultipartFile requestPart = form.files
            .firstWhere((e) => e.key == 'request')
            .value;
        final json = await requestPart
            .finalize()
            .fold<List<int>>(<int>[], (acc, chunk) => acc..addAll(chunk))
            .then(utf8.decode);
        final decoded = jsonDecode(json) as Map<String, dynamic>;
        expect(decoded['subject'], 'Billing question');
      },
    );

    test(
      'blank / whitespace subject is omitted from the request part',
      () async {
        final form = await captureFormData(
          () => repo.submitContact(
            message: 'A real ten-plus char message',
            subject: '   ',
          ),
        );

        final MultipartFile requestPart = form.files
            .firstWhere((e) => e.key == 'request')
            .value;
        final json = await requestPart
            .finalize()
            .fold<List<int>>(<int>[], (acc, chunk) => acc..addAll(chunk))
            .then(utf8.decode);
        final decoded = jsonDecode(json) as Map<String, dynamic>;
        expect(
          decoded.containsKey('subject'),
          isFalse,
          reason:
              'a blank optional subject must not be sent as an empty string',
        );
      },
    );

    test('N attachments map to N `attachments` file parts with filename + '
        'sniffed content type', () async {
      final form = await captureFormData(
        () => repo.submitContact(
          message: 'A real ten-plus char message',
          attachments: <SupportAttachment>[
            _image('shot.png'),
            _pdf('invoice.pdf'),
          ],
        ),
      );

      final attachmentParts = form.files
          .where((e) => e.key == 'attachments')
          .toList();
      expect(attachmentParts, hasLength(2));

      final first = attachmentParts[0].value;
      expect(first.filename, 'shot.png');
      expect(first.contentType.toString(), 'image/png');

      final second = attachmentParts[1].value;
      expect(second.filename, 'invoice.pdf');
      expect(second.contentType.toString(), 'application/pdf');
    });

    test(
      'zero attachments produce no `attachments` parts (only `request`)',
      () async {
        final form = await captureFormData(
          () => repo.submitContact(message: 'A real ten-plus char message'),
        );

        expect(form.files.where((e) => e.key == 'attachments'), isEmpty);
        expect(form.files.where((e) => e.key == 'request'), hasLength(1));
      },
    );

    test('posts with multipart/form-data content type override', () async {
      when(
        () => dio.post<Object?>(
          any(),
          data: any(named: 'data'),
          options: any(named: 'options'),
        ),
      ).thenAnswer((_) async => _accepted());

      await repo.submitContact(message: 'A real ten-plus char message');

      final Options opts =
          verify(
                () => dio.post<Object?>(
                  _path,
                  data: any(named: 'data'),
                  options: captureAny(named: 'options'),
                ),
              ).captured.single
              as Options;
      expect(opts.contentType, 'multipart/form-data');
    });
  });

  // ── 4. status → Failure mapping ──────────────────────────────────────────

  group('status → Failure mapping', () {
    Future<void> stubThrow(DioException e) async {
      when(
        () => dio.post<Object?>(
          any(),
          data: any(named: 'data'),
          options: any(named: 'options'),
        ),
      ).thenThrow(e);
    }

    Future<void> send() =>
        repo.submitContact(message: 'A real ten-plus char message');

    test('400 → ValidationFailure', () async {
      await stubThrow(_badResponse(400));
      await expectLater(send(), throwsA(isA<ValidationFailure>()));
    });

    test('422 → ValidationFailure', () async {
      await stubThrow(_badResponse(422));
      await expectLater(send(), throwsA(isA<ValidationFailure>()));
    });

    test('401 → UnauthorizedFailure', () async {
      await stubThrow(_badResponse(401));
      await expectLater(send(), throwsA(isA<UnauthorizedFailure>()));
    });

    test('413 → SupportAttachmentTooLargeFailure', () async {
      await stubThrow(_badResponse(413));
      await expectLater(
        send(),
        throwsA(isA<SupportAttachmentTooLargeFailure>()),
      );
    });

    test('503 → SupportChannelUnavailableFailure', () async {
      await stubThrow(_badResponse(503));
      await expectLater(
        send(),
        throwsA(isA<SupportChannelUnavailableFailure>()),
      );
    });

    test('connectionError → NetworkFailure', () async {
      await stubThrow(
        DioException(
          requestOptions: RequestOptions(path: _path),
          type: DioExceptionType.connectionError,
        ),
      );
      await expectLater(send(), throwsA(isA<NetworkFailure>()));
    });

    test('500 → ServerFailure carrying the status code', () async {
      await stubThrow(_badResponse(500));
      await expectLater(
        send(),
        throwsA(
          isA<ServerFailure>().having((f) => f.statusCode, 'statusCode', 500),
        ),
      );
    });

    test('413 takes precedence even when the interceptor pre-mapped a generic '
        'Failure onto e.error', () async {
      // The error-mapper interceptor maps 413 → a generic ServerFailure; the
      // repo must still produce the support-specific too-large failure so the
      // user sees the right copy.
      await stubThrow(
        DioException(
          requestOptions: RequestOptions(path: _path),
          response: Response<dynamic>(
            requestOptions: RequestOptions(path: _path),
            statusCode: 413,
          ),
          type: DioExceptionType.badResponse,
          error: const ServerFailure(statusCode: 413),
        ),
      );
      await expectLater(
        send(),
        throwsA(isA<SupportAttachmentTooLargeFailure>()),
      );
    });

    test(
      'a pre-mapped Failure on e.error (non-413/503) is re-thrown unchanged',
      () async {
        const mapped = NetworkFailure();
        await stubThrow(
          DioException(
            requestOptions: RequestOptions(path: _path),
            type: DioExceptionType.unknown,
            error: mapped,
          ),
        );
        await expectLater(send(), throwsA(same(mapped)));
      },
    );

    test('an already-thrown Failure escapes unchanged (rethrow arm)', () async {
      const failure = ValidationFailure(fieldErrors: <String, String>{});
      when(
        () => dio.post<Object?>(
          any(),
          data: any(named: 'data'),
          options: any(named: 'options'),
        ),
      ).thenThrow(failure);
      await expectLater(send(), throwsA(same(failure)));
    });
  });
}
