// M510 — «Рейтинг клієнта» (CLI-60), ported from
// `docs/signup-designs/ClientCardVariants/lib/screens/rating_page.dart`.
//
// Reached only from the card's rating chip. The average, count and 5→1
// distribution are the CARD's data — the SAME cached provider the card below
// watches, so opening this page costs no refetch (D7). No «Ваші оцінки»
// section (CLI-60, CLI-D07).
//
// M545 — the anonymous comments (REV-44) follow the summary in [RatingBody]
// (its own paged read); scrolling near the end appends the next page.
//
// PII: name and photo rendered, never logged.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/clients/application/client_card_controller.dart';
import 'package:beautica_mobile/features/clients/application/client_comments_controller.dart';
import 'package:beautica_mobile/features/clients/domain/client_card.dart';
import 'package:beautica_mobile/features/clients/domain/client_summary.dart';
import 'package:beautica_mobile/core/theme/velvet_text.dart';
import 'package:beautica_mobile/features/clients/presentation/client_photo_report.dart';
import 'package:beautica_mobile/features/clients/presentation/widgets/client_avatar.dart';
import 'package:beautica_mobile/features/clients/presentation/widgets/rating_body.dart';
import 'package:beautica_mobile/features/master/presentation/widgets/profile_scaffold.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/widgets/error_state.dart';
import 'package:beautica_mobile/shared/widgets/public_profile_skeleton.dart';

class ClientRatingScreen extends ConsumerWidget {
  const ClientRatingScreen({
    super.key,
    required this.scope,
    required this.client,
  });

  final ClientListScope scope;
  final ClientRef client;

  static const Key screenKey = Key('client-rating-screen');
  static const Key backKey = Key('btn-back-client-rating');
  static const Key nameKey = Key('client-rating-name');
  static const Key notFoundKey = Key('client-rating-not-found');

  /// Distance from the end at which the next comments page is requested.
  static const double _loadMoreThreshold = 320;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<ClientCard> card = ref.watch(
      clientCardProvider(scope, client),
    );
    final UserRole? role = ref.watch(authProvider.select(authUserRoleOrNull));

    final (Widget body, List<Widget> slivers) = card.when(
      loading: () =>
          (const PublicProfileSkeleton(showTabs: false), const <Widget>[]),
      error: (Object e, StackTrace _) {
        final Failure failure = e is Failure ? e : UnknownFailure(cause: e);
        return (
          failure is NotFoundFailure
              ? ErrorState(
                  key: notFoundKey,
                  failure: failure,
                  message: l10n.clientNotFound,
                )
              : ErrorState(
                  failure: failure,
                  onRetry: () =>
                      ref.invalidate(clientCardProvider(scope, client)),
                ),
          const <Widget>[],
        );
      },
      data: (ClientCard c) => (
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                ClientAvatar(
                  size: 32,
                  imageUrl: c.avatarUrl,
                  initials: c.initials,
                  previewOnTap: true,
                  previewReport: clientPhotoReport(
                    role,
                    client,
                    name: c.displayName ?? l10n.bookingDetailGuestClient,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    c.displayName ?? l10n.bookingDetailGuestClient,
                    key: nameKey,
                    style: VelvetText.masterStripName,
                  ),
                ),
              ],
            ),
            const SizedBox(height: VelvetSpacing.md),
          ],
        ),
        <Widget>[RatingBody(card: c, scope: scope)],
      ),
    );

    return NotificationListener<ScrollNotification>(
      onNotification: (ScrollNotification n) {
        if (n.depth == 0 &&
            n.metrics.axis == Axis.vertical &&
            n.metrics.extentAfter <= _loadMoreThreshold &&
            // A failed card refresh keeps its value but unmounts the
            // comments sliver; reading the autoDispose controller then would
            // recreate it and fire a stray page-0 read.
            card.hasValue &&
            !card.hasError) {
          // The controller guards double-fetch, the last page and a failed
          // append.
          ref
              .read(clientCommentsControllerProvider(scope, client).notifier)
              .loadMore();
        }
        return false;
      },
      child: ProfileScaffold(
        key: screenKey,
        title: l10n.clientRatingTitle,
        backKey: backKey,
        backSemanticLabel: l10n.registerBackStep,
        slivers: slivers,
        child: body,
      ),
    );
  }
}
