// M510 — «Рейтинг клієнта» (CLI-60), ported from
// `docs/signup-designs/ClientCardVariants/lib/screens/rating_page.dart`.
//
// Reached only from the card's rating chip. The average, count and 5→1
// distribution are the CARD's data — the SAME cached provider the card below
// watches, so opening this page costs no refetch (D7); only «Ваші оцінки» is
// its own paged read. NO comment text, ever (REV-D10).
//
// PII: name and photo rendered, never logged.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/features/clients/application/client_card_controller.dart';
import 'package:beautica_mobile/features/clients/application/client_own_ratings_controller.dart';
import 'package:beautica_mobile/features/clients/domain/client_card.dart';
import 'package:beautica_mobile/features/clients/domain/client_summary.dart';
import 'package:beautica_mobile/features/clients/presentation/widgets/client_avatar.dart';
import 'package:beautica_mobile/features/clients/presentation/widgets/client_card_text.dart';
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

  /// `my_bookings_screen`'s load-more threshold.
  static const double _loadMoreThreshold = 320;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<ClientCard> card = ref.watch(
      clientCardProvider(scope, client),
    );
    final ClientOwnRatingsControllerProvider ownProvider =
        clientOwnRatingsControllerProvider(scope, client);
    // Start the own-ratings fetch alongside the card (not after it loads) so a
    // cold open runs both requests in parallel; the body still WATCHES it.
    ref.listen<AsyncValue<ClientOwnRatingsState>>(ownProvider, (_, _) {});

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
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    c.displayName ?? l10n.bookingDetailGuestClient,
                    key: nameKey,
                    style: clientBody(15, weight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: VelvetSpacing.md),
          ],
        ),
        <Widget>[
          RatingBody(
            card: c,
            own: ref.watch(ownProvider),
            onRetryOwn: () => ref.invalidate(ownProvider),
            onRetryMore: () => ref.read(ownProvider.notifier).retryLoadMore(),
          ),
        ],
      ),
    );

    return NotificationListener<ScrollNotification>(
      onNotification: (ScrollNotification n) {
        if (n.depth == 0 &&
            n.metrics.axis == Axis.vertical &&
            n.metrics.extentAfter <= _loadMoreThreshold) {
          ref.read(ownProvider.notifier).loadMore();
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
