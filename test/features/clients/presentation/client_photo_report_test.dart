// MOD-39 / CLI-70 — `clientPhotoReport`, the ONE gate behind the client
// card / «Рейтинг клієнта» avatar «Поскаржитися» (target CLIENT_PROFILE):
//   • role matrix: every provider role → a report for a registered client;
//     signed-out (`null`) and CLIENT → none (MOD-35: a client photo is
//     reportable by providers only);
//   • a guest has no account / photo → none, for every role;
//   • the report it builds targets {CLIENT_PROFILE, userId} with the client
//     subject — never the booking id, never another target type.
// Own photo / already-reported hiding lives in `profilePhotoReport` and is
// pinned by `report_sheet_test.dart` + `profile_photo_preview_test.dart`.

import 'package:beautica_mobile/core/media/portfolio/portfolio_photo.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/clients/domain/client_summary.dart';
import 'package:beautica_mobile/features/clients/presentation/client_photo_report.dart';
import 'package:beautica_mobile/features/moderation/data/content_report_repository.dart';
import 'package:beautica_mobile/features/moderation/domain/content_report.dart';
import 'package:beautica_mobile/features/moderation/presentation/widgets/report_sheet.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/widgets/portfolio_photo_viewer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/pump_app.dart';
import '../../../helpers/velvet_snack_matchers.dart';
import '../../moderation/support/fake_content_report_repository.dart';

final AppLocalizations _l10n = lookupAppLocalizations(const Locale('uk'));

const String _kUserId = 'u-oksana';
const String _kName = 'Oksana M.';
const ClientRef _registered = ClientRef.registered(_kUserId);
const ClientRef _guest = ClientRef.guest('b-iryna');
const Key _open = Key('open-client-photo-report');

const List<UserRole> _providers = <UserRole>[
  UserRole.salonOwner,
  UserRole.salonAdmin,
  UserRole.salonMaster,
  UserRole.independentMaster,
];

/// Pumps a button that runs [report]'s `onReport` like the viewer does.
Future<FakeContentReportRepository> _pumpOpener(
  WidgetTester tester,
  PhotoViewerReport report,
) async {
  final FakeContentReportRepository repo = FakeContentReportRepository();
  await tester.pumpApp(
    Scaffold(
      body: Builder(
        builder: (BuildContext context) => Center(
          child: TextButton(
            key: _open,
            onPressed: () => report.onReport(
              context,
              const PortfolioPhoto(id: 'profile', url: 'https://x.test/a.jpg'),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
    overrides: <Object>[
      contentReportRepositoryProvider.overrideWithValue(repo),
    ],
    height: 1400,
  );
  await tester.tap(find.byKey(_open));
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  group('role gate matrix', () {
    for (final UserRole role in _providers) {
      test('${role.name} + registered client → a report', () {
        expect(clientPhotoReport(role, _registered, name: _kName), isNotNull);
      });
      test('${role.name} + guest → no report (no account, no photo)', () {
        expect(clientPhotoReport(role, _guest, name: _kName), isNull);
      });
    }

    for (final UserRole? role in <UserRole?>[null, UserRole.client]) {
      for (final ClientRef ref in <ClientRef>[_registered, _guest]) {
        test('${role?.name ?? 'signed-out'} + ${ref.runtimeType} → no '
            'report (MOD-35: providers only)', () {
          expect(clientPhotoReport(role, ref, name: _kName), isNull);
        });
      }
    }
  });

  testWidgets('the report opens the sheet with the client subject and sends '
      '{CLIENT_PROFILE, userId}', (tester) async {
    final PhotoViewerReport report = clientPhotoReport(
      UserRole.salonAdmin,
      _registered,
      name: _kName,
    )!;
    final FakeContentReportRepository repo = await _pumpOpener(tester, report);

    expect(find.byType(ReportSheet), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ReportSheet),
        matching: find.text(_l10n.reportSubjectClient(_kName)),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(ReportSheet.reasonKey(ReportReason.offensive)));
    await tester.pump();
    await tester.ensureVisible(find.byKey(ReportSheet.submitKey));
    // By label — the CTA's AnimatedScale root swallows tap-by-key.
    await tester.tap(find.text(_l10n.reportSubmit));
    await tester.pumpAndSettle();

    expect(
      repo.requests.single,
      const ContentReportRequest(
        targetType: ReportTargetType.clientProfile,
        targetId: _kUserId,
        reason: ReportReason.offensive,
      ),
    );
    expect(find.byType(ReportSheet), findsNothing);
    await pumpPastVelvetSnack(tester);
  });

  test('the report carries an isReported check (own / reported / signed-out '
      'hide the button)', () {
    expect(
      clientPhotoReport(
        UserRole.independentMaster,
        _registered,
        name: _kName,
      )!.isReported,
      isNotNull,
    );
  });
}
