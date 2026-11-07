// Phase 438 D5 — opening the Google Play listing from the forced-update gate.
//
// 1. `market://details?id=<id>` (the Play app, if installed), where `<id>` is
//    the listing id of the SANITIZED store URL — never the installed package
//    name (a staging build is `com.beautica.app.staging`, which has no Play
//    listing: Play would open a "not found" page and report success);
// 2. otherwise the backend's `storeUrl` — but ONLY if it is exactly
//    `https://play.google.com/store/apps/details?id=<allow-listed id>`;
//    anything else is replaced by [kPlayStoreFallbackUrl], so a tampered or
//    misconfigured response can never open an arbitrary URL or listing.
// Both go through `url_launcher` with `LaunchMode.externalApplication`.

import 'package:url_launcher/url_launcher.dart';

/// The hard-coded prod listing — the last-resort web target.
const String kPlayStoreFallbackUrl =
    'https://play.google.com/store/apps/details?id=com.beautica.app';

/// Launcher seam (`url_launcher`'s [launchUrl] in production).
typedef StoreUrlLauncher = Future<bool> Function(Uri uri, {LaunchMode mode});

/// The Play app deep link for the listing [id].
Uri marketUriFor(String id) => Uri(
  scheme: 'market',
  host: 'details',
  queryParameters: <String, String>{'id': id},
);

/// The only Play listings the gate may open.
const Set<String> kAllowedStoreListingIds = <String>{'com.beautica.app'};

const String _storeListingPath = '/store/apps/details';

/// [storeUrl] when it is an absolute
/// `https://play.google.com/store/apps/details` URL with exactly one `id` from
/// [kAllowedStoreListingIds], no user-info, explicit port or fragment;
/// otherwise [kPlayStoreFallbackUrl].
Uri sanitizedStoreUri(String? storeUrl) {
  final Uri fallback = Uri.parse(kPlayStoreFallbackUrl);
  if (storeUrl == null) return fallback;
  final Uri? uri = Uri.tryParse(storeUrl.trim());
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host != 'play.google.com' ||
      uri.userInfo.isNotEmpty ||
      uri.hasPort ||
      uri.hasFragment ||
      uri.path != _storeListingPath) {
    return fallback;
  }
  final List<String>? ids = uri.queryParametersAll['id'];
  if (ids == null ||
      ids.length != 1 ||
      !kAllowedStoreListingIds.contains(ids.single)) {
    return fallback;
  }
  return uri;
}

/// Tries [marketUriFor] (for the sanitized listing's `id`) first, then
/// [sanitizedStoreUri]. `true` when one of them launched; a throwing launch
/// counts as a failure, never an error.
Future<bool> openStoreListing({
  required String? storeUrl,
  StoreUrlLauncher launcher = launchUrl,
}) async {
  final Uri web = sanitizedStoreUri(storeUrl);
  final String? id = web.queryParameters['id'];
  final List<Uri> candidates = <Uri>[
    if (id != null && id.isNotEmpty) marketUriFor(id),
    web,
  ];
  for (final Uri uri in candidates) {
    try {
      if (await launcher(uri, mode: LaunchMode.externalApplication)) {
        return true;
      }
    } on Object {
      // Fall through to the next candidate.
    }
  }
  return false;
}
