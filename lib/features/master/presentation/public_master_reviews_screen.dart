// Phase 4.x — Public master reviews screen (CLIENT-facing, read-only).
//
// The CLIENT-facing reviews list for the master identified by [masterId],
// reached by tapping the «Відгуки» stat tile on [PublicMasterProfileScreen].
//
// Deliberately NOT [MasterReceivedReviewsScreen]: that screen is param-less
// and resolves its master strictly from the AUTHENTICATED session
// (`masterProfileProvider` → `GET /masters/me`) — pointing a CLIENT there
// would 403, and pointing a different master's viewer there would silently
// show the VIEWER's own reviews. This screen instead receives [masterId]
// directly from the route param and threads it straight into
// [MasterReviewsBody] — no profile-loading step, no session dependency.
//
// Shares [MasterReviewsBody] (rating-summary card + sortable review list)
// with [MasterReceivedReviewsScreen] so the two surfaces stay visually
// identical — no new styling introduced here.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';

import 'widgets/master_reviews_body.dart';
import 'widgets/profile_scaffold.dart';

/// CLIENT-facing read-only reviews list for the master identified by
/// [masterId].
class PublicMasterReviewsScreen extends ConsumerStatefulWidget {
  const PublicMasterReviewsScreen({super.key, required this.masterId});

  /// Backend Master-row UUID whose reviews are being viewed.
  final String masterId;

  @override
  ConsumerState<PublicMasterReviewsScreen> createState() =>
      _PublicMasterReviewsScreenState();
}

class _PublicMasterReviewsScreenState
    extends ConsumerState<PublicMasterReviewsScreen> {
  // Captured in initState so dispose() never touches `ref` (Riverpod 3.x
  // throws when `ref` is used after the widget is unmounted).
  late final ScreenProtectionManager _screenProtection;

  @override
  void initState() {
    super.initState();
    // SEC: this screen renders another master's review comments (PII) —
    // guard against screenshots / app-switcher snapshots while it is mounted,
    // mirroring [PublicMasterProfileScreen] and [MasterReceivedReviewsScreen].
    // The manager is ref-counted and !kDebugMode-guarded internally.
    _screenProtection = ref.read(screenProtectionProvider)..acquire();
  }

  @override
  void dispose() {
    _screenProtection.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ProfileScaffold(
      title: l10n.publicMasterReviewsTitle,
      child: MasterReviewsBody(masterId: widget.masterId),
    );
  }
}
