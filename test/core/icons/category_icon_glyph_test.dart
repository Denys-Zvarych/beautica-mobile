// M542 — CategoryIconGlyph resolution order (SVC-04): cached remote →
// bundled asset; tint parity on the remote branch; a parse failure falls back
// and is discarded from the store; no ProviderScope / no key → bundled.

import 'dart:io';
import 'dart:typed_data';

import 'package:beautica_mobile/core/icons/app_icon.dart';
import 'package:beautica_mobile/core/icons/beautica_asset_icons.dart';
import 'package:beautica_mobile/core/icons/category_icon_glyph.dart';
import 'package:beautica_mobile/core/icons/category_icon_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

const String _url =
    'https://media.test/catalog/category-icons/NAIL_SERVICE/0123456789abcdef.svg';
const Color _tint = Color(0xFF6A4A28);

final Uint8List _fixtureSvg = File(
  'test/core/icons/fixtures/remote_category_icon.svg',
).readAsBytesSync();

class _SeededStore extends CategoryIconStore {
  _SeededStore(this._seed);

  final Map<String, CategoryIconBytes> _seed;

  @override
  Map<String, CategoryIconBytes> build() => _seed;
}

Widget _glyph({String? categoryKey = 'nail_service '}) => CategoryIconGlyph(
  BeauticaAssetIcons.categoryNailService,
  key: const Key('glyph'),
  categoryKey: categoryKey,
  size: 20,
  color: _tint,
);

Widget _app(Widget child, {Map<String, CategoryIconBytes>? seed}) {
  final Widget tree = MaterialApp(home: Center(child: child));
  if (seed == null) return tree;
  return ProviderScope(
    overrides: [
      categoryIconStoreProvider.overrideWith(() => _SeededStore(seed)),
    ],
    child: tree,
  );
}

void main() {
  testWidgets('no ProviderScope → the bundled AppIcon, unchanged', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_glyph()));

    final AppIcon icon = tester.widget<AppIcon>(find.byType(AppIcon));
    expect(icon.asset, BeauticaAssetIcons.categoryNailService);
    expect(icon.size, 20);
    expect(icon.color, _tint);
    expect(tester.getSize(find.byKey(const Key('glyph'))), const Size(20, 20));
  });

  testWidgets('scope present but nothing cached → bundled AppIcon', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_glyph(), seed: const {}));

    expect(find.byType(AppIcon), findsOneWidget);
  });

  testWidgets('cached remote icon → SvgPicture.memory with the SAME srcIn '
      'tint, same box, key normalised', (tester) async {
    await tester.pumpWidget(
      _app(
        _glyph(),
        seed: <String, CategoryIconBytes>{
          'NAIL_SERVICE': (url: _url, bytes: _fixtureSvg),
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AppIcon), findsNothing);
    final SvgPicture svg = tester.widget<SvgPicture>(find.byType(SvgPicture));
    expect(svg.bytesLoader, isA<SvgBytesLoader>());
    expect(svg.colorFilter, const ColorFilter.mode(_tint, BlendMode.srcIn));
    expect(tester.getSize(find.byKey(const Key('glyph'))), const Size(20, 20));
  });

  testWidgets('null key ignores the store → bundled', (tester) async {
    await tester.pumpWidget(
      _app(
        _glyph(categoryKey: null),
        seed: <String, CategoryIconBytes>{
          'NAIL_SERVICE': (url: _url, bytes: _fixtureSvg),
        },
      ),
    );

    expect(find.byType(AppIcon), findsOneWidget);
  });

  testWidgets('unparseable remote bytes → bundled, and the key is discarded '
      'from the store', (tester) async {
    late ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          categoryIconStoreProvider.overrideWith(
            () => _SeededStore(<String, CategoryIconBytes>{
              'NAIL_SERVICE': (
                url: _url,
                bytes: Uint8List.fromList('not an svg'.codeUnits),
              ),
            }),
          ),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            container = ProviderScope.containerOf(context, listen: false);
            return MaterialApp(home: Center(child: _glyph()));
          },
        ),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    expect(container.read(categoryIconStoreProvider), isEmpty);
    final AppIcon icon = tester.widget<AppIcon>(find.byType(AppIcon));
    expect(icon.asset, BeauticaAssetIcons.categoryNailService);
  });
}
