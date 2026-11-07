// Phase 438 — the installed app's version, read once from the platform.
//
// PROMOTED (REUSE-FIRST): [appPackageInfo] used to live in
// `shared/widgets/app_version_label.dart`, where only the settings-hub caption
// read it. The forced-update gate and the `X-App-Version` interceptor (both
// in `core/`) need the same value, and `core/` must not import `shared/`, so
// the provider moved here. `app_version_label.dart` re-exports it, so every
// existing import and test override keeps working unchanged.
//
// The version is NEVER hard-coded and no product logic branches on the semver
// string (ARCHITECTURE-mobile.md § 6.1). The ONLY comparison is the gate's
// integer build number (pubspec `+N` = Android versionCode) against the
// backend's `minVersionCode`.

import 'package:package_info_plus/package_info_plus.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'app_version_info.g.dart';

/// The installed app's package metadata. Kept alive: it cannot change for the
/// lifetime of the process, so one platform-channel read is enough.
///
/// Never retried ([_noRetry]): a platform read that failed once will fail
/// again, and every consumer degrades without it — a retry would only leave
/// a pending backoff Timer behind (e.g. a `MissingPluginException` in a widget
/// test that does not override this provider).
@Riverpod(keepAlive: true, retry: _noRetry)
Future<PackageInfo> appPackageInfo(Ref ref) => PackageInfo.fromPlatform();

Duration? _noRetry(int retryCount, Object error) => null;

/// The pubspec `+N` build number as an `int`, or `null` when it is not a
/// plain non-negative integer (the gate then never blocks — decision 1).
int? parseBuildNumber(String raw) {
  final String trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  final int? value = int.tryParse(trimmed);
  if (value == null || value < 0) return null;
  return value;
}

/// The `X-App-Version` header value: `<version>+<buildNumber>`
/// (e.g. `1.5.0+7`), matching the pubspec `version:` line.
String appVersionHeaderValue(PackageInfo info) =>
    '${info.version}+${info.buildNumber}';
