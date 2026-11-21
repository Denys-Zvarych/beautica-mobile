// M510 — pixel lock for the client card and «Рейтинг клієнта».
//
// NEW baselines (no existing image moved by this file):
//   • client_card_registered_360_1x         — rated, phone, next visit, history
//   • client_card_registered_no_photo_360_1x — monogram header (68 dp)
//   • client_card_guest_360_1x               — guest as owner: phone, «Ще немає оцінок»
//   • client_card_blocked_360_1x             — «Заблоковано» under the name
//   • client_card_not_found_360_1x           — «Клієнта не знайдено»
//   • client_rating_rated_360_1x             — average, bars, own ratings, note
//   • client_rating_own_empty_360_1x         — no own ratings yet
//
// Preview parity: `docs/signup-designs/ClientCardVariants/` at 360 px. The
// registered photo renders its monogram fallback here (the media loader is not
// available under `flutter test`). Dates are fixed instants; Kyiv wall-clock
// formatting is exercised.

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/network/page_response.dart';
import 'package:beautica_mobile/core/time/clock_provider.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/booking/domain/booking_status.dart';
import 'package:beautica_mobile/features/clients/data/client_repository.dart';
import 'package:beautica_mobile/features/clients/domain/client_card.dart';
import 'package:beautica_mobile/features/clients/domain/client_own_rating.dart';
import 'package:beautica_mobile/features/clients/domain/client_summary.dart';
import 'package:beautica_mobile/features/clients/domain/client_visit.dart';
import 'package:beautica_mobile/features/clients/presentation/client_card_screen.dart';
import 'package:beautica_mobile/features/clients/presentation/client_rating_screen.dart';
import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/material.dart';

import '../helpers/fakes/fake_notification_repository.dart' show FixedRoleAuth;
import 'helpers/golden_pump.dart';

DateTime _now() => DateTime.utc(2026, 11, 20, 12);

const ClientRef _reg = ClientRef.registered('u1');
const ClientRef _gst = ClientRef.guest('b1');

ClientVisit _visit(
  String key,
  DateTime at,
  BookingStatus status,
  String service,
  double price,
) => ClientVisit(
  visitKey: key,
  startsAt: at,
  items: <ClientVisitItem>[
    ClientVisitItem(
      bookingId: 'bk-$key',
      serviceName: service,
      status: status,
      startsAt: at,
      price: price,
    ),
  ],
);

final List<ClientVisit> _visits = <ClientVisit>[
  _visit(
    'next',
    DateTime.utc(2026, 11, 27, 12),
    BookingStatus.confirmed,
    'Манікюр + покриття',
    850,
  ),
  _visit(
    'v1',
    DateTime.utc(2026, 11, 7, 10),
    BookingStatus.completed,
    'Педикюр',
    700,
  ),
  _visit(
    'v2',
    DateTime.utc(2026, 10, 12, 9, 30),
    BookingStatus.completed,
    'Манікюр',
    650,
  ),
  _visit(
    'v3',
    DateTime.utc(2026, 10, 2, 14),
    BookingStatus.cancelled,
    'Нарощування',
    1400,
  ),
];

ClientCard _card(
  ClientRef ref, {
  String? name = 'Оксана Мельник',
  String? avatarUrl,
  String? phone = '+380 67 123 45 67',
  bool blocked = false,
  double? avg = 4.9,
  int count = 12,
}) => ClientCard(
  ref: ref,
  displayName: name,
  avatarUrl: avatarUrl,
  phone: phone,
  blocked: blocked,
  ratingAvg: avg,
  ratingCount: count,
  ratingDistribution: count == 0
      ? const <int>[0, 0, 0, 0, 0]
      : const <int>[9, 2, 1, 0, 0],
);

class _Repo implements ClientRepository {
  _Repo(
    this.card, {
    this.visits = const <ClientVisit>[],
    this.ratings,
    this.failure,
  });

  final ClientCard card;
  final List<ClientVisit> visits;
  final List<ClientOwnRating>? ratings;
  final Failure? failure;

  @override
  Future<ClientCard> getCard(
    ClientListScope scope,
    ClientRef client, {
    CancelToken? cancelToken,
  }) async {
    final Failure? f = failure;
    if (f != null) throw f;
    return card;
  }

  @override
  Future<PageResponse<ClientVisit>> getVisits(
    ClientListScope scope,
    ClientRef client, {
    int page = 0,
    int size = kClientPageSize,
    CancelToken? cancelToken,
  }) async => PageResponse<ClientVisit>(
    items: visits,
    page: 0,
    totalPages: 1,
    totalElements: visits.length,
  );

  @override
  Future<PageResponse<ClientOwnRating>> getOwnRatings(
    ClientListScope scope,
    ClientRef client, {
    int page = 0,
    int size = kClientPageSize,
    CancelToken? cancelToken,
  }) async => PageResponse<ClientOwnRating>(
    items: ratings ?? const <ClientOwnRating>[],
    page: 0,
    totalPages: 1,
    totalElements: 0,
  );

  @override
  Future<PageResponse<ClientSummary>> list(
    ClientListScope scope, {
    String? q,
    int page = 0,
    int size = kClientPageSize,
    CancelToken? cancelToken,
  }) => throw UnimplementedError();
}

List<Object> _overrides(ClientRepository repo) => <Object>[
  authProvider.overrideWith(() => FixedRoleAuth(UserRole.independentMaster)),
  clientRepositoryProvider.overrideWithValue(repo),
  clockProvider.overrideWithValue(_now),
];

Widget _cardScreen(ClientRef ref) => ClientCardScreen(
  scope: const ClientListScope.me(),
  client: ref,
  cardBase: '/master/clients',
  bookingRoute: (String id) => '/master/bookings/$id',
);

Widget _ratingScreen() =>
    const ClientRatingScreen(scope: ClientListScope.me(), client: _reg);

void main() {
  const double width = 360;
  const Size screen = Size(width, 900);

  void card(String name, String file, ClientRepository repo, ClientRef ref) =>
      goldenTest(
        'client card — $name',
        fileName: file,
        constraints: BoxConstraints.tight(screen),
        textScaleFactor: 1.0,
        pumpWidget: goldenPumpWidget(width: width, overrides: _overrides(repo)),
        builder: () => _cardScreen(ref),
      );

  card(
    'registered',
    'client_card_registered_360_1x',
    _Repo(
      _card(_reg, avatarUrl: 'https://cdn.example.test/o.jpg'),
      visits: _visits,
    ),
    _reg,
  );
  card(
    'registered, no photo',
    'client_card_registered_no_photo_360_1x',
    _Repo(_card(_reg), visits: _visits),
    _reg,
  );
  card(
    'guest',
    'client_card_guest_360_1x',
    _Repo(
      _card(_gst, name: 'Ірина Коваль', avg: null, count: 0),
      visits: <ClientVisit>[_visits[2], _visits[3]],
    ),
    _gst,
  );
  card(
    'blocked',
    'client_card_blocked_360_1x',
    _Repo(_card(_reg, blocked: true), visits: <ClientVisit>[_visits[1]]),
    _reg,
  );
  card(
    'not found',
    'client_card_not_found_360_1x',
    _Repo(_card(_reg), failure: const NotFoundFailure()),
    _reg,
  );

  goldenTest(
    'client rating — rated',
    fileName: 'client_rating_rated_360_1x',
    constraints: BoxConstraints.tight(screen),
    textScaleFactor: 1.0,
    // The bars animate in on mount: settle so the golden shows the fill.
    pumpBeforeTest: onlyPumpAndSettle,
    pumpWidget: goldenPumpWidget(
      width: width,
      overrides: _overrides(
        _Repo(
          _card(_reg),
          ratings: <ClientOwnRating>[
            ClientOwnRating(
              bookingId: 'a',
              visitAt: DateTime.utc(2026, 11, 7, 10),
              serviceName: 'Педикюр',
              stars: 5,
            ),
            ClientOwnRating(
              bookingId: 'b',
              visitAt: DateTime.utc(2026, 10, 12, 9),
              serviceName: 'Манікюр',
              stars: 4,
            ),
          ],
        ),
      ),
    ),
    builder: _ratingScreen,
  );

  goldenTest(
    'client rating — no own ratings',
    fileName: 'client_rating_own_empty_360_1x',
    constraints: BoxConstraints.tight(screen),
    textScaleFactor: 1.0,
    pumpBeforeTest: onlyPumpAndSettle,
    pumpWidget: goldenPumpWidget(
      width: width,
      overrides: _overrides(_Repo(_card(_reg))),
    ),
    builder: _ratingScreen,
  );
}
