// AppVersionLabel — the small, muted «Версія 1.3.0 (4)» caption that closes
// every settings hub (master `SettingsHubScreen`, `SalonSettingsScreen`,
// `ClientSettingsHubScreen`). One widget, three call sites (REUSE-FIRST).
//
// The version is read at runtime from the platform via `package_info_plus`
// through [appPackageInfoProvider], so tests override the provider (or call
// `PackageInfo.setMockInitialValues`) instead of touching a platform channel.
// It is NEVER hard-coded and nothing branches on it (ARCHITECTURE-mobile.md
// § 6.1 versioning policy).
//
// DEGRADATION — the line is informational chrome: while loading or on error it
// renders `SizedBox.shrink()` (no spinner, no error text), so it can never
// block or displace the rows above it.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';

part 'app_version_label.g.dart';

/// The installed app's package metadata. Kept alive: it cannot change for the
/// lifetime of the process, so one platform-channel read is enough.
///
/// Never retried ([_noRetry]): a platform read that failed once will fail
/// again, and the label degrades to nothing anyway — a retry would only leave
/// a pending backoff Timer behind (e.g. a `MissingPluginException` in a widget
/// test that pumps a hub without overriding this provider).
@Riverpod(keepAlive: true, retry: _noRetry)
Future<PackageInfo> appPackageInfo(Ref ref) => PackageInfo.fromPlatform();

Duration? _noRetry(int retryCount, Object error) => null;

/// Centred muted caption `Версія {version} ({buildNumber})`.
///
/// The rendered caption carries [labelKey], so `find.byKey(labelKey)` means
/// "the version line is on screen" — absent while loading or on error.
class AppVersionLabel extends ConsumerWidget {
  const AppVersionLabel({super.key});

  static const Key labelKey = Key('app-version-label');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PackageInfo? info = ref.watch(appPackageInfoProvider).value;
    if (info == null) return const SizedBox.shrink();
    return Padding(
      key: labelKey,
      // Own top gap (not a sibling SizedBox) so a hidden label leaves no
      // trace in the host's scroll extent.
      padding: const EdgeInsets.only(
        top: VelvetSpacing.md,
        bottom: VelvetSpacing.sm,
      ),
      child: Text(
        AppLocalizations.of(
          context,
        ).settingsHubAppVersion(info.version, info.buildNumber),
        textAlign: TextAlign.center,
        style: VelvetText.feedbackMutedSm,
      ),
    );
  }
}
