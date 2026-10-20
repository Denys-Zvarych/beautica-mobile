// Phase 413 — HttpBookingLinksRepository + mapBookingLinks.
//
// Mocktail-mocks the generated [api.BookingLinksApi]; failures are answered
// asynchronously (`thenAnswer(... throw ...)`), the only shape a Dio-backed
// call can produce.

import 'package:beautica_api/beautica_api.dart' as api;
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/booking_links/data/booking_links_repository.dart';
import 'package:beautica_mobile/features/booking_links/domain/booking_link.dart';
import 'package:built_collection/built_collection.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockBookingLinksApi extends Mock implements api.BookingLinksApi {}

const String _path = '/api/v1/booking-links/mine';

RequestOptions _req() => RequestOptions(path: _path);

api.BookingLinkResponse _link({
  required api.BookingLinkResponseKindEnum kind,
  required String slug,
  String? salonId,
  bool bookable = true,
  String? url,
}) => api.BookingLinkResponse(
  (b) => b
    ..kind = kind
    ..slug = slug
    ..url =
        url ??
        (kind == api.BookingLinkResponseKindEnum.SALON
            ? 'https://beautica.app/book/s/$slug'
            : 'https://beautica.app/book/$slug')
    ..displayName = 'Name $slug'
    ..salonId = salonId
    ..bookable = bookable,
);

Response<api.ApiResponseBookingLinksResponse> _ok({
  required bool shareEnabled,
  List<api.BookingLinkResponse> links = const <api.BookingLinkResponse>[],
}) => Response<api.ApiResponseBookingLinksResponse>(
  requestOptions: _req(),
  statusCode: 200,
  data: api.ApiResponseBookingLinksResponse(
    (b) => b
      ..success = true
      ..data.shareEnabled = shareEnabled
      ..data.links = ListBuilder<api.BookingLinkResponse>(links),
  ),
);

DioException _dioError(
  DioExceptionType type, {
  int? statusCode,
  Object? error,
}) => DioException(
  requestOptions: _req(),
  type: type,
  error: error,
  response: statusCode == null
      ? null
      : Response<dynamic>(requestOptions: _req(), statusCode: statusCode),
);

void main() {
  late _MockBookingLinksApi bookingLinksApi;
  late HttpBookingLinksRepository repository;

  setUp(() {
    bookingLinksApi = _MockBookingLinksApi();
    repository = HttpBookingLinksRepository(bookingLinksApi);
  });

  group('getMine — success', () {
    test('maps MASTER + SALON links field by field', () async {
      when(() => bookingLinksApi.getMine()).thenAnswer(
        (_) async => _ok(
          shareEnabled: true,
          links: <api.BookingLinkResponse>[
            _link(kind: api.BookingLinkResponseKindEnum.MASTER, slug: 'anna'),
            _link(
              kind: api.BookingLinkResponseKindEnum.SALON,
              slug: 'velvet',
              salonId: 'salon-1',
              bookable: false,
            ),
          ],
        ),
      );

      final BookingLinks out = await repository.getMine();

      verify(() => bookingLinksApi.getMine()).called(1);
      expect(out.shareEnabled, isTrue);
      expect(out.links, const <BookingLink>[
        BookingLink(
          kind: BookingLinkKind.master,
          slug: 'anna',
          url: 'https://beautica.app/book/anna',
          displayName: 'Name anna',
          bookable: true,
        ),
        BookingLink(
          kind: BookingLinkKind.salon,
          slug: 'velvet',
          url: 'https://beautica.app/book/s/velvet',
          displayName: 'Name velvet',
          salonId: 'salon-1',
          bookable: false,
        ),
      ]);
      expect(out.isVisible, isTrue);
    });

    test('a MASTER link keeps salonId null', () async {
      when(() => bookingLinksApi.getMine()).thenAnswer(
        (_) async => _ok(
          shareEnabled: true,
          links: <api.BookingLinkResponse>[
            _link(kind: api.BookingLinkResponseKindEnum.MASTER, slug: 'anna'),
          ],
        ),
      );

      final BookingLinks out = await repository.getMine();
      expect(out.links.single.salonId, isNull);
    });

    test('shareEnabled=false → hidden, no links', () async {
      when(
        () => bookingLinksApi.getMine(),
      ).thenAnswer((_) async => _ok(shareEnabled: false));

      final BookingLinks out = await repository.getMine();
      expect(out, BookingLinks.hidden);
      expect(out.isVisible, isFalse);
    });

    test('shareEnabled=false drops links even if the wire carried some', () {
      final BookingLinks out = mapBookingLinks(
        _ok(
          shareEnabled: false,
          links: <api.BookingLinkResponse>[
            _link(kind: api.BookingLinkResponseKindEnum.MASTER, slug: 'anna'),
          ],
        ).data!.data!,
      );
      expect(out.links, isEmpty);
      expect(out.shareEnabled, isFalse);
    });

    test('shareEnabled=true with no links is not visible', () async {
      when(
        () => bookingLinksApi.getMine(),
      ).thenAnswer((_) async => _ok(shareEnabled: true));

      final BookingLinks out = await repository.getMine();
      expect(out.shareEnabled, isTrue);
      expect(out.links, isEmpty);
      expect(out.isVisible, isFalse);
    });
  });

  group('mapBookingLinks — untrusted url is dropped (MASVS-CODE-4)', () {
    const String salonId = '00000000-0000-0000-0000-000000000001';

    // Each bad link sits between a valid MASTER and a valid SALON link, so
    // every case also proves the rest of the response is unaffected.
    final List<
      ({String name, api.BookingLinkResponseKindEnum kind, String url})
    >
    bad = <({String name, api.BookingLinkResponseKindEnum kind, String url})>[
      (
        name: 'http:// scheme',
        kind: api.BookingLinkResponseKindEnum.MASTER,
        url: 'http://beautica.app/book/evil',
      ),
      (
        name: 'foreign host',
        kind: api.BookingLinkResponseKindEnum.MASTER,
        url: 'https://evil.tld/book/evil',
      ),
      (
        name: 'look-alike subdomain host',
        kind: api.BookingLinkResponseKindEnum.MASTER,
        url: 'https://beautica.app.evil.tld/book/evil',
      ),
      (
        name: 'javascript: scheme',
        kind: api.BookingLinkResponseKindEnum.MASTER,
        url: 'javascript:alert(1)//beautica.app/book/evil',
      ),
      (
        name: 'userinfo before a foreign host',
        kind: api.BookingLinkResponseKindEnum.MASTER,
        url: 'https://beautica.app@evil.tld/book/evil',
      ),
      (
        name: 'userinfo on the trusted host',
        kind: api.BookingLinkResponseKindEnum.MASTER,
        url: 'https://user@beautica.app/book/evil',
      ),
      (
        name: 'explicit port',
        kind: api.BookingLinkResponseKindEnum.MASTER,
        url: 'https://beautica.app:8443/book/evil',
      ),
      (
        name: 'explicit default port',
        kind: api.BookingLinkResponseKindEnum.MASTER,
        url: 'https://beautica.app:443/book/evil',
      ),
      (
        name: 'unparsable',
        kind: api.BookingLinkResponseKindEnum.MASTER,
        url: 'http://[::1',
      ),
      (name: 'empty', kind: api.BookingLinkResponseKindEnum.MASTER, url: ''),
      (
        name: 'MASTER kind on a salon path',
        kind: api.BookingLinkResponseKindEnum.MASTER,
        url: 'https://beautica.app/book/s/evil',
      ),
      (
        name: 'SALON kind on a master path',
        kind: api.BookingLinkResponseKindEnum.SALON,
        url: 'https://beautica.app/book/evil',
      ),
      (
        name: 'path outside /book/',
        kind: api.BookingLinkResponseKindEnum.MASTER,
        url: 'https://beautica.app/login/evil',
      ),
      (
        name: 'dot-segment escape',
        kind: api.BookingLinkResponseKindEnum.MASTER,
        url: 'https://beautica.app/book/../evil',
      ),
      (
        name: 'slug does not match the path',
        kind: api.BookingLinkResponseKindEnum.MASTER,
        url: 'https://beautica.app/book/someone-else',
      ),
    ];

    for (final c in bad) {
      test('${c.name} → dropped, siblings kept', () {
        final BookingLinks out = mapBookingLinks(
          _ok(
            shareEnabled: true,
            links: <api.BookingLinkResponse>[
              _link(kind: api.BookingLinkResponseKindEnum.MASTER, slug: 'anna'),
              _link(kind: c.kind, slug: 'evil', salonId: salonId, url: c.url),
              _link(
                kind: api.BookingLinkResponseKindEnum.SALON,
                slug: 'velvet',
                salonId: salonId,
              ),
            ],
          ).data!.data!,
        );

        expect(out.shareEnabled, isTrue);
        expect(out.links.map((BookingLink l) => l.url), <String>[
          'https://beautica.app/book/anna',
          'https://beautica.app/book/s/velvet',
        ]);
      });
    }

    test('a response whose only link is untrusted is not visible', () {
      final BookingLinks out = mapBookingLinks(
        _ok(
          shareEnabled: true,
          links: <api.BookingLinkResponse>[
            _link(
              kind: api.BookingLinkResponseKindEnum.MASTER,
              slug: 'anna',
              url: 'https://evil.tld/book/anna',
            ),
          ],
        ).data!.data!,
      );
      expect(out.links, isEmpty);
      expect(out.isVisible, isFalse);
    });

    test('valid MASTER and SALON urls are trusted', () {
      expect(
        isTrustedBookingLinkUrl(
          'https://beautica.app/book/anna-k',
          kind: BookingLinkKind.master,
          slug: 'anna-k',
        ),
        isTrue,
      );
      expect(
        isTrustedBookingLinkUrl(
          'https://beautica.app/book/s/velvet-lviv',
          kind: BookingLinkKind.salon,
          slug: 'velvet-lviv',
        ),
        isTrue,
      );
    });

    test('a 60-char and a 2-char slug are trusted (boundaries)', () {
      final String max = 'a' * 59 + '1';
      expect(isValidBookingSlug(max), isTrue);
      expect(
        isTrustedBookingLinkUrl(
          'https://beautica.app/book/$max',
          kind: BookingLinkKind.master,
          slug: max,
        ),
        isTrue,
      );
      expect(isValidBookingSlug('a1'), isTrue);
    });

    test('an empty slug is never trusted', () {
      expect(
        isTrustedBookingLinkUrl(
          'https://beautica.app/book/',
          kind: BookingLinkKind.master,
          slug: '',
        ),
        isFalse,
      );
    });
  });

  group('mapBookingLinks — slug format + exact canonical url', () {
    const String salonId = '00000000-0000-0000-0000-000000000001';
    const api.BookingLinkResponseKindEnum master =
        api.BookingLinkResponseKindEnum.MASTER;
    const api.BookingLinkResponseKindEnum salon =
        api.BookingLinkResponseKindEnum.SALON;

    String masterUrl(String slug) => 'https://beautica.app/book/$slug';
    String salonUrl(String slug) => 'https://beautica.app/book/s/$slug';

    // Slug cases: the url is the canonical url FOR THAT SLUG, so only the
    // slug-format check can reject them. URL cases: the slug is valid, so
    // only the exact-match check can reject them.
    final List<
      ({
        String name,
        api.BookingLinkResponseKindEnum kind,
        String slug,
        String url,
      })
    >
    bad =
        <
          ({
            String name,
            api.BookingLinkResponseKindEnum kind,
            String slug,
            String url,
          })
        >[
          (
            name: 'slug a%2Fb',
            kind: master,
            slug: 'a%2Fb',
            url: masterUrl('a%2Fb'),
          ),
          (
            name: 'slug x%0A',
            kind: master,
            slug: 'x%0A',
            url: masterUrl('x%0A'),
          ),
          (
            name: 'slug with a raw newline',
            kind: master,
            slug: 'anna\nevil',
            url: masterUrl('anna\nevil'),
          ),
          (
            name: 'slug with a trailing raw newline',
            kind: salon,
            slug: 'velvet\n',
            url: salonUrl('velvet\n'),
          ),
          (
            name: 'slug with an RTL override',
            kind: master,
            slug: 'anna\u202Eevil',
            url: masterUrl('anna\u202Eevil'),
          ),
          (
            name: 'slug with a space',
            kind: salon,
            slug: 'velvet lviv',
            url: salonUrl('velvet lviv'),
          ),
          (
            name: 'uppercase slug',
            kind: master,
            slug: 'Anna-k',
            url: masterUrl('Anna-k'),
          ),
          (
            name: '61-char slug',
            kind: master,
            slug: 'a' * 61,
            url: masterUrl('a' * 61),
          ),
          (
            name: 'leading-dash slug',
            kind: master,
            slug: '-anna',
            url: masterUrl('-anna'),
          ),
          (
            name: 'trailing-dash slug',
            kind: salon,
            slug: 'velvet-',
            url: salonUrl('velvet-'),
          ),
          (
            name: 'MASTER url with a ?r= query',
            kind: master,
            slug: 'evil',
            url: '${masterUrl('evil')}?r=https://evil.tld',
          ),
          (
            name: 'SALON url with a ?r= query',
            kind: salon,
            slug: 'evil',
            url: '${salonUrl('evil')}?r=https://evil.tld',
          ),
          (
            name: 'MASTER url with a #frag',
            kind: master,
            slug: 'evil',
            url: '${masterUrl('evil')}#frag',
          ),
          (
            name: 'SALON url with a #frag',
            kind: salon,
            slug: 'evil',
            url: '${salonUrl('evil')}#frag',
          ),
          (
            name: 'url with a trailing slash',
            kind: master,
            slug: 'evil',
            url: '${masterUrl('evil')}/',
          ),
          (
            name: 'valid MASTER slug not matching the url slug',
            kind: master,
            slug: 'evil',
            url: masterUrl('anna-k'),
          ),
          (
            name: 'valid SALON slug not matching the url slug',
            kind: salon,
            slug: 'evil',
            url: salonUrl('velvet-lviv'),
          ),
        ];

    for (final c in bad) {
      test('${c.name} → dropped, siblings kept', () {
        final BookingLinks out = mapBookingLinks(
          _ok(
            shareEnabled: true,
            links: <api.BookingLinkResponse>[
              _link(kind: master, slug: 'anna'),
              _link(kind: c.kind, slug: c.slug, salonId: salonId, url: c.url),
              _link(kind: salon, slug: 'velvet', salonId: salonId),
            ],
          ).data!.data!,
        );

        expect(out.shareEnabled, isTrue);
        expect(out.links.map((BookingLink l) => l.url), <String>[
          'https://beautica.app/book/anna',
          'https://beautica.app/book/s/velvet',
        ]);
      });
    }

    test('isValidBookingSlug rejects every bad slug shape', () {
      for (final String s in <String>[
        '',
        'a',
        'a%2Fb',
        'x%0A',
        'anna\nevil',
        'velvet\n',
        'anna\u202Eevil',
        'velvet lviv',
        'Anna-k',
        'a' * 61,
        '-anna',
        'anna-',
        'anna/evil',
        'anna.k',
      ]) {
        expect(isValidBookingSlug(s), isFalse, reason: s);
      }
    });
  });

  group('forward compatibility', () {
    test(
      'an unknown wire kind decodes through standardSerializers and that link '
      'alone is dropped',
      () {
        final Map<String, Object?> json = <String, Object?>{
          'shareEnabled': true,
          'links': <Object?>[
            <String, Object?>{
              'kind': 'SPA',
              'slug': 'future',
              'url': 'https://beautica.app/book/x/future',
              'displayName': 'Future',
              'salonId': null,
              'bookable': true,
            },
            <String, Object?>{
              'kind': 'MASTER',
              'slug': 'anna',
              'url': 'https://beautica.app/book/anna',
              'displayName': 'Anna',
              'salonId': null,
              'bookable': true,
            },
          ],
        };
        final api.BookingLinksResponse dto = api.standardSerializers
            .deserializeWith(api.BookingLinksResponse.serializer, json)!;
        expect(
          dto.links.first.kind,
          api.BookingLinkResponseKindEnum.unknownDefaultOpenApi,
        );

        final BookingLinks out = mapBookingLinks(dto);
        expect(out.links.map((BookingLink l) => l.slug), <String>['anna']);
        expect(out.isVisible, isTrue);
      },
    );
  });

  group('getMine — failure mapping', () {
    test('a 200 with a null data body throws ServerFailure', () async {
      when(() => bookingLinksApi.getMine()).thenAnswer(
        (_) async => Response<api.ApiResponseBookingLinksResponse>(
          requestOptions: _req(),
          statusCode: 200,
          data: api.ApiResponseBookingLinksResponse((b) => b..success = true),
        ),
      );

      await expectLater(
        repository.getMine(),
        throwsA(
          isA<ServerFailure>().having((f) => f.statusCode, 'statusCode', null),
        ),
      );
    });

    test(
      '403 (CLIENT) keeps the Failure the error-mapper interceptor set',
      () async {
        const Failure mapped = UnknownFailure(cause: Object());
        when(() => bookingLinksApi.getMine()).thenAnswer(
          (_) async => throw _dioError(
            DioExceptionType.badResponse,
            statusCode: 403,
            error: mapped,
          ),
        );

        await expectLater(repository.getMine(), throwsA(same(mapped)));
      },
    );

    test('403 without an interceptor Failure → ServerFailure(403)', () async {
      when(() => bookingLinksApi.getMine()).thenAnswer(
        (_) async =>
            throw _dioError(DioExceptionType.badResponse, statusCode: 403),
      );

      await expectLater(
        repository.getMine(),
        throwsA(
          isA<ServerFailure>().having((f) => f.statusCode, 'statusCode', 403),
        ),
      );
    });

    for (final DioExceptionType type in <DioExceptionType>[
      DioExceptionType.connectionError,
      DioExceptionType.connectionTimeout,
      DioExceptionType.receiveTimeout,
      DioExceptionType.sendTimeout,
    ]) {
      test('${type.name} → NetworkFailure', () async {
        when(
          () => bookingLinksApi.getMine(),
        ).thenAnswer((_) async => throw _dioError(type));

        await expectLater(repository.getMine(), throwsA(isA<NetworkFailure>()));
      });
    }

    test('a Failure thrown directly is rethrown untouched', () async {
      const Failure f = NotFoundFailure();
      when(() => bookingLinksApi.getMine()).thenAnswer((_) async => throw f);

      await expectLater(repository.getMine(), throwsA(same(f)));
    });
  });
}
