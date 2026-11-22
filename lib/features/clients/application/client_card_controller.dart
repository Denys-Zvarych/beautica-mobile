// M510 — the client card's data (B508 + B526 aggregate) for one client in one
// scope. A functional `@riverpod` family keyed by the freezed (scope, client)
// pair, so the card screen and the rating page share ONE fetch (D7): the
// average, count and distribution come from this card, never a second call.
//
// A 404 (unknown / out-of-scope / attached-since-the-list-loaded guest, B527)
// surfaces as a [NotFoundFailure] for the screen's «Клієнта не знайдено» state.
//
// Session boundary: the card holds a name, photo and phone, so the provider
// rebuilds on a different signed-in identity (narrowed to the user id — a
// silent token refresh must not refetch). Signed out → [UnauthorizedFailure]
// with no request, matching the visits / ratings controllers' early return.
//
// PII: never logged.

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter_riverpod/flutter_riverpod.dart'
    show ProviderListenableSelect;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/clients/data/client_repository.dart';
import 'package:beautica_mobile/features/clients/domain/client_card.dart';
import 'package:beautica_mobile/features/clients/domain/client_summary.dart';

part 'client_card_controller.g.dart';

@riverpod
Future<ClientCard> clientCard(
  Ref ref,
  ClientListScope scope,
  ClientRef client,
) {
  final String? userId = ref.watch(authProvider.select(authUserIdOrNull));
  if (userId == null) {
    return Future<ClientCard>.error(const UnauthorizedFailure());
  }
  final CancelToken token = CancelToken();
  ref.onDispose(token.cancel);
  return ref
      .watch(clientRepositoryProvider)
      .getCard(scope, client, cancelToken: token);
}
