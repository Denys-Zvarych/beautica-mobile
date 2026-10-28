// AppVersionLabel — the muted «Версія {version} ({build})» caption at the
// bottom of every settings hub. Data → the localized line; loading / error →
// nothing (no spinner, no error text).

import 'dart:async';

import 'package:beautica_mobile/shared/widgets/app_version_label.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../helpers/fake_package_info.dart';
import '../../helpers/pump_app.dart';

void main() {
  testWidgets('renders «Версія 1.3.0 (4)» under the label key', (tester) async {
    await tester.pumpApp(
      const Scaffold(body: AppVersionLabel()),
      overrides: <Object>[appPackageInfoOverride()],
    );
    await tester.pumpAndSettle();

    expect(fakeAppVersionText(), 'Версія 1.3.0 (4)');
    expect(find.text(fakeAppVersionText()), findsOneWidget);
    expect(find.byKey(const Key('app-version-label')), findsOneWidget);
    final Text text = tester.widget<Text>(find.text(fakeAppVersionText()));
    expect(text.textAlign, TextAlign.center);
  });

  testWidgets('EN locale renders «Version 1.3.0 (4)»', (tester) async {
    await tester.pumpApp(
      const Scaffold(body: AppVersionLabel()),
      locale: const Locale('en'),
      overrides: <Object>[appPackageInfoOverride()],
    );
    await tester.pumpAndSettle();

    expect(find.text(fakeAppVersionText(const Locale('en'))), findsOneWidget);
    expect(fakeAppVersionText(const Locale('en')), 'Version 1.3.0 (4)');
  });

  testWidgets('error renders nothing', (tester) async {
    await tester.pumpApp(
      const Scaffold(body: AppVersionLabel()),
      overrides: <Object>[
        appPackageInfoProvider.overrideWith(
          (ref) async => throw StateError('no platform'),
        ),
      ],
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('app-version-label')), findsNothing);
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('loading renders nothing — no spinner', (tester) async {
    final Completer<PackageInfo> pending = Completer<PackageInfo>();
    await tester.pumpApp(
      const Scaffold(body: AppVersionLabel()),
      overrides: <Object>[
        appPackageInfoProvider.overrideWith((ref) => pending.future),
      ],
    );
    await tester.pump();

    expect(find.byKey(const Key('app-version-label')), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('unoverridden provider (no platform plugin) renders nothing', (
    tester,
  ) async {
    await tester.pumpApp(const Scaffold(body: AppVersionLabel()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('app-version-label')), findsNothing);
  });
}
