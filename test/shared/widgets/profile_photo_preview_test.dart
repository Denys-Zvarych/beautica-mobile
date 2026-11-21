// 2026-11-21 — tap a profile photo → the shared full-screen viewer.
//
// Pins, for every avatar widget that opts in (`previewOnTap: true`):
//   * a photo → tap opens `PortfolioPhotoViewer` on THAT url, no «n / N»
//     counter, spoken «Фото профілю»; close returns;
//   * no photo (monogram / icon well) → not tappable, no viewer;
//   * `previewOnTap` left at its default → no viewer (every list row).
// MOD-39 — a `previewReport` target adds the viewer's SAME «Поскаржитися»
// flag → the shared report sheet → the report repository with the PROFILE
// target; hidden with no target, for the viewer's own photo, once reported,
// and signed out.
// Plus the own-avatar source sheet's additive «Переглянути фото» row.

import 'package:beautica_mobile/core/media/beautica_image.dart';
import 'package:beautica_mobile/core/media/media_config.dart';
import 'package:beautica_mobile/core/media/pick/image_source_sheet.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/booking/presentation/widgets/master_avatar_badge.dart';
import 'package:beautica_mobile/features/clients/presentation/widgets/client_avatar.dart';
import 'package:beautica_mobile/features/master/presentation/widgets/profile_avatar.dart';
import 'package:beautica_mobile/features/moderation/data/content_report_repository.dart';
import 'package:beautica_mobile/features/moderation/domain/content_report.dart';
import 'package:beautica_mobile/features/moderation/presentation/widgets/report_sheet.dart';
import 'package:beautica_mobile/features/salon/presentation/widgets/salon_cover_widgets.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/widgets/portfolio_photo_viewer.dart';
import 'package:beautica_mobile/shared/widgets/profile_photo_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../features/moderation/support/fake_content_report_repository.dart';
import '../../helpers/fake_media_cache.dart';
import '../../helpers/fakes/fake_notification_repository.dart'
    show FixedRoleAuth;
import '../../helpers/no_reported_targets.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/rendered_image_url.dart';

const String _url = 'https://media.test/avatar.webp';
const Key _host = Key('preview-host');

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byKey(_host)));

Future<void> _pump(
  WidgetTester tester,
  Widget avatar, {
  List<Object> overrides = const <Object>[],
}) async {
  await tester.pumpApp(
    Scaffold(
      body: Center(
        child: KeyedSubtree(key: _host, child: avatar),
      ),
    ),
    overrides: overrides,
  );
  await tester.pump();
}

/// Signed out — no user id.
class _SignedOut extends AuthNotifier {
  @override
  Future<AuthSession> build() async => const AuthSession.unauthenticated();
}

/// Opens the viewer from [avatar] (FixedRoleAuth signs in as `u1`).
Future<void> _openViewer(
  WidgetTester tester,
  Widget avatar, {
  required List<Object> overrides,
}) async {
  await _pump(tester, avatar, overrides: overrides);
  await tester.tap(find.byType(ProfilePhotoPreviewTap));
  await tester.pumpAndSettle();
  expect(find.byType(PortfolioPhotoViewer), findsOne);
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

  group('MOD-39 — «Поскаржитися» on a profile photo', () {
    Object provider() =>
        authProvider.overrideWith(() => FixedRoleAuth(UserRole.salonMaster));

    final Map<ReportTargetType, Widget Function(PhotoViewerReport?)> targets =
        <ReportTargetType, Widget Function(PhotoViewerReport?)>{
          ReportTargetType.clientProfile: (PhotoViewerReport? r) =>
              ClientAvatar(
                size: 96,
                imageUrl: _url,
                previewOnTap: true,
                previewReport: r,
              ),
          ReportTargetType.masterProfile: (PhotoViewerReport? r) =>
              ProfileAvatar(
                imageUrl: _url,
                previewOnTap: true,
                previewReport: r,
              ),
          ReportTargetType.salonProfile: (PhotoViewerReport? r) => SalonLogo(
            imageUrl: _url,
            monogram: 'В',
            previewOnTap: true,
            previewReport: r,
          ),
        };

    for (final MapEntry<ReportTargetType, Widget Function(PhotoViewerReport?)> t
        in targets.entries) {
      testWidgets('${t.key.wireName}: flag → report sheet → repository gets '
          'the profile target; the flag then hides', (tester) async {
        final FakeContentReportRepository repo = FakeContentReportRepository();
        await _openViewer(
          tester,
          t.value(
            profilePhotoReport(
              targetType: t.key,
              targetId: 'target-7',
              name: 'Оксана',
            ),
          ),
          overrides: <Object>[
            provider(),
            contentReportRepositoryProvider.overrideWithValue(repo),
          ],
        );
        expect(find.byKey(PortfolioPhotoViewer.reportKey), findsOne);

        await tester.tap(find.byKey(PortfolioPhotoViewer.reportKey));
        await tester.pumpAndSettle();
        expect(find.byType(ReportSheet), findsOne);
        await tester.tap(find.byKey(ReportSheet.reasonKey(ReportReason.spam)));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(ReportSheet.submitKey));
        await tester.tap(find.byKey(ReportSheet.submitKey));
        await tester.pumpAndSettle();

        final ContentReportRequest sent = repo.requests.single;
        expect(sent.targetType, t.key);
        expect(sent.targetId, 'target-7');
        expect(sent.reason, ReportReason.spam);
        expect(find.byType(ReportSheet), findsNothing);
        // Still in the viewer; reported once → no flag (MOD-06).
        expect(find.byType(PortfolioPhotoViewer), findsOne);
        expect(find.byKey(PortfolioPhotoViewer.reportKey), findsNothing);
      });
    }

    testWidgets('no report target → no flag (own-profile previews)', (
      tester,
    ) async {
      await _openViewer(
        tester,
        targets[ReportTargetType.masterProfile]!(null),
        overrides: <Object>[provider()],
      );
      expect(find.byKey(PortfolioPhotoViewer.reportKey), findsNothing);
    });

    testWidgets('the viewer\'s OWN photo → no flag', (tester) async {
      await _openViewer(
        tester,
        targets[ReportTargetType.clientProfile]!(
          profilePhotoReport(
            targetType: ReportTargetType.clientProfile,
            // FixedRoleAuth's user id.
            targetId: 'u1',
            name: 'Я',
          ),
        ),
        overrides: <Object>[provider()],
      );
      expect(find.byKey(PortfolioPhotoViewer.reportKey), findsNothing);
    });

    testWidgets('already reported (MOD-06) → no flag', (tester) async {
      await _openViewer(
        tester,
        targets[ReportTargetType.clientProfile]!(
          profilePhotoReport(
            targetType: ReportTargetType.clientProfile,
            targetId: 'c-9',
            name: 'Оксана',
          ),
        ),
        overrides: <Object>[
          provider(),
          reportedTargetsOverride(<ReportedTarget>{
            (type: ReportTargetType.clientProfile, id: 'c-9'),
          }),
        ],
      );
      expect(find.byKey(PortfolioPhotoViewer.reportKey), findsNothing);
    });

    testWidgets('signed out → no flag', (tester) async {
      await _openViewer(
        tester,
        targets[ReportTargetType.salonProfile]!(
          profilePhotoReport(
            targetType: ReportTargetType.salonProfile,
            targetId: 's-1',
            name: 'Велюр',
          ),
        ),
        overrides: <Object>[authProvider.overrideWith(_SignedOut.new)],
      );
      expect(find.byKey(PortfolioPhotoViewer.reportKey), findsNothing);
    });
  });

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
