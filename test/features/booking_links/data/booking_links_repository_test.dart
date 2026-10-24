// Phase 413 — HttpBookingLinksRepository + mapBookingLinks.
//
// Mocktail-mocks the generated [api.BookingLinksApi]; failures are answered
// asynchronously (`thenAnswer(... throw ...)`), the only shape a Dio-backed
// call can produce.

import 'package:beautica_api/beautica_api.dart' as api;
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/booking_links/data/booking_links_repository.dart';
import 'package:beautica_mobile/features/booking_links/domain/booking_link.dart';
import 'package:beautica_mobile/features/booking_links/domain/booking_link_url.dart';
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
    ..status = api.BookingLinkResponseStatusEnum.ACTIVE
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
              salonId: '5b1f0c8e-3a2d-4f6b-9c7e-1a2b3c4d5e6f',
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
          salonId: '5b1f0c8e-3a2d-4f6b-9c7e-1a2b3c4d5e6f',
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
              'status': 'ACTIVE',
              'slug': 'future',
              'url': 'https://beautica.app/book/x/future',
              'displayName': 'Future',
              'salonId': null,
              'bookable': true,
            },
            <String, Object?>{
              'kind': 'MASTER',
              'status': 'ACTIVE',
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

  group('mapBookingLinks — salonId must be a UUID (MASVS-CODE-4)', () {
    const String salonUuid = '5b1f0c8e-3a2d-4f6b-9c7e-1a2b3c4d5e6f';

    String? mappedSalonId(String? salonId) {
      final api.BookingLinksResponse dto = api.BookingLinksResponse(
        (b) => b
          ..shareEnabled = true
          ..links =
              ListBuilder<api.BookingLinkResponse>(<api.BookingLinkResponse>[
                _link(
                  kind: api.BookingLinkResponseKindEnum.SALON,
                  slug: 'velvet',
                  salonId: salonId,
                ),
              ]),
      );
      final BookingLinks out = mapBookingLinks(dto);
      // The link itself always survives — only the id is dropped.
      expect(out.links.map((BookingLink l) => l.slug), <String>['velvet']);
      return out.links.single.salonId;
    }

    test('a lowercase UUID is kept verbatim', () {
      expect(mappedSalonId(salonUuid), salonUuid);
    });

    test('an uppercase UUID is kept verbatim (not normalised)', () {
      const String upper = '5B1F0C8E-3A2D-4F6B-9C7E-1A2B3C4D5E6F';
      expect(mappedSalonId(upper), upper);
    });

    test('null stays null', () {
      expect(mappedSalonId(null), isNull);
    });

    for (final String bad in <String>[
      'x/../..?tab=',
      '',
      ' ',
      'salon-1',
      '$salonUuid/../home',
      ' $salonUuid',
      '$salonUuid\n',
      '5b1f0c8e3a2d4f6b9c7e1a2b3c4d5e6f',
      '5b1f0c8e-3a2d-4f6b-9c7e-1a2b3c4d5e6',
      'gb1f0c8e-3a2d-4f6b-9c7e-1a2b3c4d5e6f',
    ]) {
      test('${bad.isEmpty ? '<empty>' : bad} → null', () {
        expect(mappedSalonId(bad), isNull);
      });
    }
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

  // ── Phase 415 — status + regenerate ──────────────────────────────────────

  group('mapBookingLink — status (415 D5)', () {
    const String salonUuid = '5b1f0c8e-3a2d-4f6b-9c7e-1a2b3c4d5e6f';

    api.BookingLinkResponse revoked({
      required api.BookingLinkResponseKindEnum kind,
      String? salonId,
    }) => api.BookingLinkResponse(
      (b) => b
        ..kind = kind
        ..status = api.BookingLinkResponseStatusEnum.REVOKED
        ..displayName = 'Velvet'
        ..salonId = salonId
        ..bookable = false,
    );

    test('a REVOKED master link maps with no slug / url, not bookable', () {
      final BookingLink? out = mapBookingLink(
        revoked(kind: api.BookingLinkResponseKindEnum.MASTER),
      );
      expect(
        out,
        const BookingLink(
          kind: BookingLinkKind.master,
          slug: null,
          url: null,
          displayName: 'Velvet',
          bookable: false,
          status: BookingLinkStatus.revoked,
        ),
      );
      expect(out?.isRevoked, isTrue);
      expect(out?.keyId, 'revoked-master');
    });

    test('a REVOKED salon link keeps its UUID salon id', () {
      final BookingLink? out = mapBookingLink(
        revoked(
          kind: api.BookingLinkResponseKindEnum.SALON,
          salonId: salonUuid,
        ),
      );
      expect(out?.salonId, salonUuid);
      expect(out?.isRevoked, isTrue);
      expect(out?.keyId, 'revoked-salon-$salonUuid');
    });

    test('a REVOKED salon link without a UUID salon id is dropped', () {
      expect(
        mapBookingLink(revoked(kind: api.BookingLinkResponseKindEnum.SALON)),
        isNull,
      );
      expect(
        mapBookingLink(
          revoked(
            kind: api.BookingLinkResponseKindEnum.SALON,
            salonId: 'salon-1',
          ),
        ),
        isNull,
      );
    });

    test('an ACTIVE link with a null url or slug is dropped', () {
      final api.BookingLinkResponse noUrl = _link(
        kind: api.BookingLinkResponseKindEnum.MASTER,
        slug: 'anna',
      ).rebuild((b) => b..url = null);
      final api.BookingLinkResponse noSlug = _link(
        kind: api.BookingLinkResponseKindEnum.MASTER,
        slug: 'anna',
      ).rebuild((b) => b..slug = null);
      expect(mapBookingLink(noUrl), isNull);
      expect(mapBookingLink(noSlug), isNull);
    });

    test('an unknown wire status drops only that link', () {
      final api.BookingLinksResponse dto = api.standardSerializers
          .deserializeWith(
            api.BookingLinksResponse.serializer,
            <String, Object?>{
              'shareEnabled': true,
              'links': <Object?>[
                <String, Object?>{
                  'kind': 'MASTER',
                  'status': 'PAUSED',
                  'slug': 'anna',
                  'url': 'https://beautica.app/book/anna',
                  'displayName': 'Anna',
                  'bookable': true,
                },
                <String, Object?>{
                  'kind': 'SALON',
                  'status': 'ACTIVE',
                  'slug': 'velvet',
                  'url': 'https://beautica.app/book/s/velvet',
                  'displayName': 'Velvet',
                  'salonId': salonUuid,
                  'bookable': true,
                },
              ],
            },
          )!;
      final BookingLinks out = mapBookingLinks(dto);
      expect(out.links.map((BookingLink l) => l.slug), <String>['velvet']);
    });

    test('an ACTIVE link maps to status active', () {
      final BookingLink? out = mapBookingLink(
        _link(kind: api.BookingLinkResponseKindEnum.MASTER, slug: 'anna'),
      );
      expect(out?.status, BookingLinkStatus.active);
      expect(out?.keyId, 'anna');
    });
  });

  group('regenerate (415 D6 / D7)', () {
    const String salonUuid = '5b1f0c8e-3a2d-4f6b-9c7e-1a2b3c4d5e6f';
    const BookingLink master = BookingLink(
      kind: BookingLinkKind.master,
      slug: 'anna',
      url: 'https://beautica.app/book/anna',
      displayName: 'Anna',
      bookable: true,
    );
    const BookingLink salon = BookingLink(
      kind: BookingLinkKind.salon,
      slug: 'velvet',
      url: 'https://beautica.app/book/s/velvet',
      displayName: 'Velvet',
      salonId: salonUuid,
      bookable: true,
    );

    setUpAll(() {
      registerFallbackValue(api.BookingLinkMutationRequest());
    });

    Response<api.ApiResponseBookingLinkResponse> okLink(
      api.BookingLinkResponse link,
    ) => Response<api.ApiResponseBookingLinkResponse>(
      requestOptions: _req(),
      statusCode: 200,
      data: api.ApiResponseBookingLinkResponse(
        (b) => b
          ..success = true
          ..data.replace(link),
      ),
    );

    test('master: sends the shown slug and maps the new link', () async {
      when(
        () => bookingLinksApi.regenerateMaster(
          bookingLinkMutationRequest: any(named: 'bookingLinkMutationRequest'),
        ),
      ).thenAnswer(
        (_) async => okLink(
          _link(
            kind: api.BookingLinkResponseKindEnum.MASTER,
            slug: 'anna-x7k2',
          ),
        ),
      );

      final BookingLinkMutationOutcome out = await repository.regenerate(
        master,
      );

      expect(
        out,
        BookingLinkMutationOutcome.done(
          master.copyWith(
            slug: 'anna-x7k2',
            url: 'https://beautica.app/book/anna-x7k2',
            displayName: 'Name anna-x7k2',
          ),
        ),
      );
      final api.BookingLinkMutationRequest sent =
          verify(
                () => bookingLinksApi.regenerateMaster(
                  bookingLinkMutationRequest: captureAny(
                    named: 'bookingLinkMutationRequest',
                  ),
                ),
              ).captured.single
              as api.BookingLinkMutationRequest;
      expect(sent.currentSlug, 'anna');
    });

    test('a revoked link sends currentSlug null (D3)', () async {
      when(
        () => bookingLinksApi.regenerateMaster(
          bookingLinkMutationRequest: any(named: 'bookingLinkMutationRequest'),
        ),
      ).thenAnswer(
        (_) async => okLink(
          _link(kind: api.BookingLinkResponseKindEnum.MASTER, slug: 'anna-new'),
        ),
      );

      await repository.regenerate(
        const BookingLink(
          kind: BookingLinkKind.master,
          slug: null,
          url: null,
          displayName: 'Anna',
          bookable: false,
          status: BookingLinkStatus.revoked,
        ),
      );

      final api.BookingLinkMutationRequest sent =
          verify(
                () => bookingLinksApi.regenerateMaster(
                  bookingLinkMutationRequest: captureAny(
                    named: 'bookingLinkMutationRequest',
                  ),
                ),
              ).captured.single
              as api.BookingLinkMutationRequest;
      expect(sent.currentSlug, isNull);
      // The wire body omits the null field: `{}` (backend reads it as null).
      expect(
        api.standardSerializers.serializeWith(
          api.BookingLinkMutationRequest.serializer,
          sent,
        ),
        <String, Object?>{},
      );
    });

    test('salon: hits the salon route with its id', () async {
      when(
        () => bookingLinksApi.regenerateSalon(
          salonId: any(named: 'salonId'),
          bookingLinkMutationRequest: any(named: 'bookingLinkMutationRequest'),
        ),
      ).thenAnswer(
        (_) async => okLink(
          _link(
            kind: api.BookingLinkResponseKindEnum.SALON,
            slug: 'velvet-2',
            salonId: salonUuid,
          ),
        ),
      );

      final BookingLinkMutationOutcome out = await repository.regenerate(salon);

      expect(out, isA<BookingLinkMutationDone>());
      verify(
        () => bookingLinksApi.regenerateSalon(
          salonId: salonUuid,
          bookingLinkMutationRequest: any(named: 'bookingLinkMutationRequest'),
        ),
      ).called(1);
      verifyNever(
        () => bookingLinksApi.regenerateMaster(
          bookingLinkMutationRequest: any(named: 'bookingLinkMutationRequest'),
        ),
      );
    });

    test('a salon link without a salon id never calls the API', () async {
      await expectLater(
        repository.regenerate(salon.copyWith(salonId: null)),
        throwsA(isA<UnknownFailure>()),
      );
      verifyZeroInteractions(bookingLinksApi);
    });

    for (final (int status, Type expected) in <(int, Type)>[
      (409, BookingLinkMutationStale),
      (404, BookingLinkMutationUnavailable),
      (429, BookingLinkMutationRateLimited),
    ]) {
      test('$status → $expected, even behind an interceptor Failure', () async {
        when(
          () => bookingLinksApi.regenerateMaster(
            bookingLinkMutationRequest: any(
              named: 'bookingLinkMutationRequest',
            ),
          ),
        ).thenAnswer(
          (_) async => throw _dioError(
            DioExceptionType.badResponse,
            statusCode: status,
            error: ServerFailure(statusCode: status),
          ),
        );

        final BookingLinkMutationOutcome out = await repository.regenerate(
          master,
        );
        expect(out.runtimeType, expected);
      });
    }

    test('403 keeps the interceptor Failure', () async {
      const Failure forbidden = ServerFailure(statusCode: 403);
      when(
        () => bookingLinksApi.regenerateMaster(
          bookingLinkMutationRequest: any(named: 'bookingLinkMutationRequest'),
        ),
      ).thenAnswer(
        (_) async => throw _dioError(
          DioExceptionType.badResponse,
          statusCode: 403,
          error: forbidden,
        ),
      );

      await expectLater(
        repository.regenerate(master),
        throwsA(same(forbidden)),
      );
    });

    test('a response the mapper would drop is a ServerFailure', () async {
      when(
        () => bookingLinksApi.regenerateMaster(
          bookingLinkMutationRequest: any(named: 'bookingLinkMutationRequest'),
        ),
      ).thenAnswer(
        (_) async => okLink(
          _link(
            kind: api.BookingLinkResponseKindEnum.MASTER,
            slug: 'anna-2',
            url: 'https://evil.example/book/anna-2',
          ),
        ),
      );

      await expectLater(
        repository.regenerate(master),
        throwsA(isA<ServerFailure>()),
      );
    });

    test('a link of another kind in the response is a ServerFailure', () async {
      when(
        () => bookingLinksApi.regenerateMaster(
          bookingLinkMutationRequest: any(named: 'bookingLinkMutationRequest'),
        ),
      ).thenAnswer(
        (_) async => okLink(
          _link(
            kind: api.BookingLinkResponseKindEnum.SALON,
            slug: 'velvet',
            salonId: salonUuid,
          ),
        ),
      );

      await expectLater(
        repository.regenerate(master),
        throwsA(isA<ServerFailure>()),
      );
    });

    test('salon id mismatch in response → ServerFailure', () async {
      when(
        () => bookingLinksApi.regenerateSalon(
          salonId: any(named: 'salonId'),
          bookingLinkMutationRequest: any(named: 'bookingLinkMutationRequest'),
        ),
      ).thenAnswer(
        (_) async => okLink(
          _link(
            kind: api.BookingLinkResponseKindEnum.SALON,
            slug: 'velvet-2',
            // A valid UUID, but another salon's.
            salonId: '0d9e8f7a-6b5c-4d3e-8f2a-1b0c9d8e7f6a',
          ),
        ),
      );

      await expectLater(
        repository.regenerate(salon),
        throwsA(isA<ServerFailure>()),
      );
    });
  });
}
