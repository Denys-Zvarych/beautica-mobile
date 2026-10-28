// Shared fake for [appPackageInfoProvider] — the source of the settings hubs'
// «Версія {version} ({build})» caption ([AppVersionLabel]).

import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/widgets/app_version_label.dart';
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// A fixed `1.3.0 (4)` package-info value.
final PackageInfo fakePackageInfo = PackageInfo(
  appName: 'Beautica',
  packageName: 'com.beautica.app',
  version: '1.3.0',
  buildNumber: '4',
);

/// The rendered caption for [fakePackageInfo] in [locale] (default `uk`),
/// resolved through AppLocalizations — never a hard-coded literal.
String fakeAppVersionText([Locale locale = const Locale('uk')]) =>
    lookupAppLocalizations(locale).settingsHubAppVersion(
      fakePackageInfo.version,
      fakePackageInfo.buildNumber,
    );

/// Override list entry resolving [appPackageInfoProvider] to [fakePackageInfo].
Object appPackageInfoOverride() =>
    appPackageInfoProvider.overrideWith((ref) async => fakePackageInfo);
