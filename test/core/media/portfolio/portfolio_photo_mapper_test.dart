// Phase 403 (9.8, D1) — PortfolioPhotoMapper: the promoted
// `SalonPortfolioMapper`. Drops entries missing id/url (one broken photo must
// not blank the rail), keeps order; `fromJson` reads an upload answer.

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/core/media/portfolio/portfolio_photo.dart';
import 'package:beautica_mobile/core/media/portfolio/portfolio_photo_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

MediaFileResponse _dto({String? id, String? url}) => MediaFileResponse(
  (MediaFileResponseBuilder b) => b
    ..id = id
    ..url = url,
);

void main() {
  group('fromDtoList', () {
    test('maps every complete entry, in order', () {
      final List<PortfolioPhoto> out =
          PortfolioPhotoMapper.fromDtoList(<MediaFileResponse>[
            _dto(id: 'a', url: 'https://m.test/a.jpg'),
            _dto(id: 'b', url: 'https://m.test/b.jpg'),
          ]);
      expect(out, const <PortfolioPhoto>[
        PortfolioPhoto(id: 'a', url: 'https://m.test/a.jpg'),
        PortfolioPhoto(id: 'b', url: 'https://m.test/b.jpg'),
      ]);
    });

    test('drops entries with a null or empty id / url, keeps the rest', () {
      final List<PortfolioPhoto> out =
          PortfolioPhotoMapper.fromDtoList(<MediaFileResponse>[
            _dto(url: 'https://m.test/no-id.jpg'),
            _dto(id: '', url: 'https://m.test/empty-id.jpg'),
            _dto(id: 'no-url'),
            _dto(id: 'empty-url', url: ''),
            _dto(id: 'ok', url: 'https://m.test/ok.jpg'),
          ]);
      expect(out, const <PortfolioPhoto>[
        PortfolioPhoto(id: 'ok', url: 'https://m.test/ok.jpg'),
      ]);
    });

    test('empty in → empty out', () {
      expect(
        PortfolioPhotoMapper.fromDtoList(const <MediaFileResponse>[]),
        isEmpty,
      );
    });
  });

  group('fromJson (upload answer `data`)', () {
    test('a complete map → the photo', () {
      expect(
        PortfolioPhotoMapper.fromJson(<String, Object?>{
          'id': 'm1',
          'url': 'https://m.test/m1.png',
          'entityType': 'SALON',
        }),
        const PortfolioPhoto(id: 'm1', url: 'https://m.test/m1.png'),
      );
    });

    test('non-map / missing / empty / wrong-typed fields → null', () {
      for (final Object? data in <Object?>[
        null,
        'x',
        <String, Object?>{'url': 'https://m.test/a.jpg'},
        <String, Object?>{'id': 'a'},
        <String, Object?>{'id': '', 'url': 'https://m.test/a.jpg'},
        <String, Object?>{'id': 'a', 'url': ''},
        <String, Object?>{'id': 1, 'url': 'https://m.test/a.jpg'},
      ]) {
        expect(PortfolioPhotoMapper.fromJson(data), isNull, reason: '$data');
      }
    });
  });

  test('toString never prints the id or the URL', () {
    const PortfolioPhoto p = PortfolioPhoto(
      id: 'secret-id',
      url: 'https://m.test/r2-key.jpg',
    );
    expect(p.toString(), isNot(contains('secret-id')));
    expect(p.toString(), isNot(contains('r2-key')));
  });
}
