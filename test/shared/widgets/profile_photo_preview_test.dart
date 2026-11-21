// 2026-11-21 — tap a profile photo → the shared full-screen viewer.
//
// Pins, for every avatar widget that opts in (`previewOnTap: true`):
//   * a photo → tap opens `PortfolioPhotoViewer` on THAT url, no «n / N»
//     counter, spoken «Фото профілю»; close returns;
//   * no photo (monogram / icon well) → not tappable, no viewer;
//   * `previewOnTap` left at its default → no viewer (every list row).
// Plus the own-avatar source sheet's additive «Переглянути фото» row.

import 'package:beautica_mobile/core/media/beautica_image.dart';
import 'package:beautica_mobile/core/media/media_config.dart';
import 'package:beautica_mobile/core/media/pick/image_source_sheet.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_avatar_badge.dart';
import 'package:beautica_mobile/features/clients/presentation/widgets/client_avatar.dart';
import 'package:beautica_mobile/features/master/presentation/widgets/profile_avatar.dart';
import 'package:beautica_mobile/features/salon/presentation/widgets/salon_cover_widgets.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/widgets/portfolio_photo_viewer.dart';
import 'package:beautica_mobile/shared/widgets/profile_photo_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_media_cache.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/rendered_image_url.dart';

const String _url = 'https://media.test/avatar.webp';
const Key _host = Key('preview-host');

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byKey(_host)));

Future<void> _pump(WidgetTester tester, Widget avatar) async {
  await tester.pumpApp(
    Scaffold(
      body: Center(
        child: KeyedSubtree(key: _host, child: avatar),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  setUp(() {
    MediaConfig.debugAllowedHosts = <String>{'media.test'};
    debugMediaCacheManager = FakeMediaCacheManager(mediaLoadingForever);
  });
  tearDown(() {
    debugMediaCacheManager = null;
    MediaConfig.debugAllowedHosts = null;
  });

  final Map<String, Widget Function(String? url, bool preview)> avatars =
      <String, Widget Function(String? url, bool preview)>{
        'ClientAvatar': (String? u, bool p) => ClientAvatar(
          size: 96,
          imageUrl: u,
          initials: 'ОМ',
          previewOnTap: p,
        ),
        'ProfileAvatar': (String? u, bool p) =>
            ProfileAvatar(imageUrl: u, previewOnTap: p),
        'MasterAvatarBadge': (String? u, bool p) =>
            MasterAvatarBadge(imageUrl: u, initials: 'МІ', previewOnTap: p),
        'SalonLogo': (String? u, bool p) =>
            SalonLogo(imageUrl: u, monogram: 'В', previewOnTap: p),
      };

  for (final MapEntry<String, Widget Function(String?, bool)> a
      in avatars.entries) {
    group(a.key, () {
      testWidgets('photo + previewOnTap → tap opens the viewer on that photo, '
          'no counter; close returns', (tester) async {
        await _pump(tester, a.value(_url, true));
        final AppLocalizations l10n = _l10n(tester);
        expect(find.bySemanticsLabel(l10n.profilePhotoViewAction), findsOne);
        await tester.tap(find.byType(ProfilePhotoPreviewTap));
        await tester.pumpAndSettle();

        expect(find.byType(PortfolioPhotoViewer), findsOne);
        expect(find.byKey(PortfolioPhotoViewer.indicatorKey), findsNothing);
        expect(
          renderedImageUrls(
            tester,
            within: find.byKey(PortfolioPhotoViewer.pageKey('profile')),
          ),
          <String>[_url],
        );
        expect(
          find.bySemanticsLabel(l10n.profilePhotoViewerSemantics),
          findsOne,
        );

        await tester.tap(find.byKey(PortfolioPhotoViewer.closeKey));
        await tester.pumpAndSettle();
        expect(find.byType(PortfolioPhotoViewer), findsNothing);
      });

      testWidgets('no photo → monogram is not tappable', (tester) async {
        await _pump(tester, a.value(null, true));
        expect(find.byType(GestureDetector), findsNothing);
        await tester.tap(find.byKey(_host), warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(find.byType(PortfolioPhotoViewer), findsNothing);
      });

      testWidgets('previewOnTap default (false) → no viewer, no wrapper', (
        tester,
      ) async {
        await _pump(tester, a.value(_url, false));
        expect(find.byType(ProfilePhotoPreviewTap), findsNothing);
        await tester.tap(find.byKey(_host), warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(find.byType(PortfolioPhotoViewer), findsNothing);
      });
    });
  }

  group('ImageSourceSheet «Переглянути фото» (own avatar)', () {
    testWidgets('canView → the view row resolves to ImageSourceChoice.view', (
      tester,
    ) async {
      ImageSourceChoice? picked;
      await tester.pumpApp(
        Scaffold(
          body: Builder(
            builder: (BuildContext context) => TextButton(
              key: _host,
              onPressed: () async => picked = await showImageSourceSheet(
                context,
                canRemove: true,
                canView: true,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(_host));
      await tester.pumpAndSettle();
      expect(find.text(_l10n(tester).profilePhotoViewAction), findsOne);
      await tester.tap(find.byKey(ImageSourceSheet.viewKey));
      await tester.pumpAndSettle();
      expect(picked, ImageSourceChoice.view);
    });

    testWidgets('default → no view row', (tester) async {
      await tester.pumpApp(const Scaffold(body: ImageSourceSheet()));
      await tester.pump();
      expect(find.byKey(ImageSourceSheet.viewKey), findsNothing);
    });
  });
}
