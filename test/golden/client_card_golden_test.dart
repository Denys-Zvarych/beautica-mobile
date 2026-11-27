// M510 — pixel lock for the client card and «Рейтинг клієнта».
//
// NEW baselines (no existing image moved by this file):
//   • client_card_registered_360_1x         — rated, phone, next visit, history
//   • client_card_registered_no_photo_360_1x — monogram header (68 dp)
//   • client_card_guest_360_1x               — guest as owner: phone, «Ще немає оцінок»
//   • client_card_blocked_360_1x             — «Заблоковано» under the name
//   • client_card_not_found_360_1x           — «Клієнта не знайдено»
//   • client_card_long_service_name_360_1x   — one booking row with a long
//     service name: wraps by word beside the price, own status pill
//   • client_rating_rated_360_1x             — average, bars, note (CLI-60:
//     no «Ваші оцінки» section, 2026-11-21)
//   • client_rating_unrated_360_1x           — «—», «Ще немає оцінок», empty
//     bars (replaces the removed client_rating_own_empty_360_1x)
//   • client_card_owner_master_chips_360_1x  — SALON_OWNER salon card with the
//     CLI-73 master chip row («Усі майстри» selected) above the timeline
//   • client_card_owner_master_mode_no_chips_360_1x — client-profile audit
//     (2026-11-22): owner master mode (route masterId = the owner's own row,
//     servedByMasters salon-wide INCLUDING that row) → NO chip row
//   • client_rating_comments_360_1x        — M545: the «Коментарі» section
//     (own «Ваш коментар» row without «⋮», an anonymous row with «⋮», visit
//     month in the date slot, no avatar / author)
// M545 moves client_rating_rated_360_1x / client_rating_unrated_360_1x: the
// note text changed (CLI-60) — confined to the note line.
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
import 'package:beautica_mobile/features/clients/domain/client_prefill.dart';
import 'package:beautica_mobile/features/clients/domain/client_review_comment.dart';
import 'package:beautica_mobile/features/clients/domain/client_summary.dart';
import 'package:beautica_mobile/features/clients/domain/client_visit.dart';
import 'package:beautica_mobile/features/clients/presentation/client_card_screen.dart';
import 'package:beautica_mobile/features/clients/presentation/client_rating_screen.dart';
import 'package:beautica_mobile/features/moderation/data/content_report_repository.dart';
import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/material.dart';

import '../features/moderation/support/fake_content_report_repository.dart';
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
  List<ClientServedMaster> served = const <ClientServedMaster>[],
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
  servedByMasters: served,
);

class _Repo implements ClientRepository {
  _Repo(this.card, {this.visits = const <ClientVisit>[], this.failure});

  final ClientCard card;
  final List<ClientVisit> visits;
  final Failure? failure;

  @override
  Future<ClientCard> getCard(
    ClientListScope scope,
    ClientRef client, {
    CancelToken? cancelToken,
  }) async {
    final Failure? f = failure;
    if (f != null) throw f;
    // CLI-89 (B530): the server's next visit, derived from the served visits.
    return card.nextVisit != null
        ? card
        : card.copyWith(nextVisit: pickNextVisit(visits, _now()));
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
  Future<PageResponse<ClientSummary>> list(
    ClientListScope scope, {
    String? q,
    int page = 0,
    int size = kClientPageSize,
    CancelToken? cancelToken,
  }) => throw UnimplementedError();

  @override
  Future<void> removeFromList(ClientListScope scope, ClientRef client) =>
      throw UnimplementedError();

  @override
  Future<void> restoreToList(ClientListScope scope, ClientRef client) =>
      throw UnimplementedError();
}

/// M545 — one fixed page of comments.
class _Comments implements ClientCommentsRepository {
  const _Comments(this.items);

  final List<ClientReviewComment> items;

  @override
  Future<PageResponse<ClientReviewComment>> getComments(
    ClientListScope scope,
    ClientRef client, {
    int page = 0,
    int size = kClientPageSize,
    CancelToken? cancelToken,
  }) async => PageResponse<ClientReviewComment>(
    items: items,
    page: 0,
    totalPages: 1,
    totalElements: items.length,
  );
}

List<Object> _overrides(
  ClientRepository repo, {
  UserRole role = UserRole.independentMaster,
  List<ClientReviewComment> comments = const <ClientReviewComment>[],
}) => <Object>[
  authProvider.overrideWith(() => FixedRoleAuth(role)),
  clientRepositoryProvider.overrideWithValue(repo),
  clientCommentsRepositoryProvider.overrideWithValue(_Comments(comments)),
  contentReportRepositoryProvider.overrideWithValue(
    FakeContentReportRepository(),
  ),
  clockProvider.overrideWithValue(_now),
];

Widget _cardScreen(
  ClientRef ref, {
  ClientListScope scope = const ClientListScope.me(),
  void Function(BuildContext, ClientPrefill)? onBook,
}) => ClientCardScreen(
  scope: scope,
  client: ref,
  cardBase: '/master/clients',
  bookingRoute: (String id) => '/master/bookings/$id',
  onBookClient: onBook,
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
    'long service name',
    'client_card_long_service_name_360_1x',
    _Repo(
      _card(_reg),
      visits: <ClientVisit>[
        _visit(
          'long',
          DateTime.utc(2026, 11, 17, 9),
          BookingStatus.completed,
          'Пілінг шкіри голови та комплексний догляд',
          950,
        ),
      ],
    ),
    _reg,
  );
  card(
    'not found',
    'client_card_not_found_360_1x',
    _Repo(_card(_reg), failure: const NotFoundFailure()),
    _reg,
  );

  goldenTest(
    'client card — owner with master chips',
    fileName: 'client_card_owner_master_chips_360_1x',
    constraints: BoxConstraints.tight(screen),
    textScaleFactor: 1.0,
    pumpWidget: goldenPumpWidget(
      width: width,
      overrides: _overrides(
        _Repo(
          _card(
            _reg,
            served: const <ClientServedMaster>[
              ClientServedMaster(masterId: 'm2', name: 'Ірина Коваль'),
              ClientServedMaster(masterId: 'm1', name: 'Олена Шевчук'),
              ClientServedMaster(masterId: 'm3', name: 'Марта Бондар'),
            ],
          ),
          visits: _visits,
        ),
        role: UserRole.salonOwner,
      ),
    ),
    builder: () =>
        _cardScreen(_reg, scope: const ClientListScope.salon(salonId: 's1')),
  );

  // Client-profile audit — owner master mode: the route carries the owner's
  // own master row and the (salon-wide) servedByMasters lists it beside the
  // others; the card must show NO chip row (phase 510).
  const String ownRow = 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11';
  goldenTest(
    'client card — owner master mode, no chips',
    fileName: 'client_card_owner_master_mode_no_chips_360_1x',
    constraints: BoxConstraints.tight(screen),
    textScaleFactor: 1.0,
    pumpWidget: goldenPumpWidget(
      width: width,
      overrides: _overrides(
        _Repo(
          _card(
            _reg,
            served: const <ClientServedMaster>[
              ClientServedMaster(
                masterId: 'b1eebc99-9c0b-4ef8-bb6d-6bb9bd380a11',
                name: 'Ірина Коваль',
              ),
              ClientServedMaster(masterId: ownRow, name: 'Власниця Салону'),
              ClientServedMaster(
                masterId: 'c2eebc99-9c0b-4ef8-bb6d-6bb9bd380a11',
                name: 'Марта Бондар',
              ),
            ],
          ),
          visits: _visits,
        ),
        role: UserRole.salonOwner,
      ),
    ),
    builder: () => _cardScreen(
      _reg,
      scope: const ClientListScope.salon(salonId: 's1', masterId: ownRow),
    ),
  );

  // M543 (CLI-80) — «Записати» under the phone / rating chips. A separate
  // variant: every scenario above passes no launcher and stays unchanged.
  goldenTest(
    'client card — with Записати',
    fileName: 'client_card_with_book_cta_360_1x',
    constraints: BoxConstraints.tight(screen),
    textScaleFactor: 1.0,
    pumpWidget: goldenPumpWidget(
      width: width,
      overrides: _overrides(
        _Repo(_card(_reg, phone: '+380671234567'), visits: _visits),
      ),
    ),
    builder: () => _cardScreen(_reg, onBook: (_, _) {}),
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
      overrides: _overrides(_Repo(_card(_reg))),
    ),
    builder: _ratingScreen,
  );

  goldenTest(
    'client rating — unrated',
    fileName: 'client_rating_unrated_360_1x',
    constraints: BoxConstraints.tight(screen),
    textScaleFactor: 1.0,
    pumpBeforeTest: onlyPumpAndSettle,
    pumpWidget: goldenPumpWidget(
      width: width,
      overrides: _overrides(_Repo(_card(_reg, avg: null, count: 0))),
    ),
    builder: _ratingScreen,
  );

  goldenTest(
    'client rating — comments',
    fileName: 'client_rating_comments_360_1x',
    constraints: BoxConstraints.tight(screen),
    textScaleFactor: 1.0,
    pumpBeforeTest: onlyPumpAndSettle,
    pumpWidget: goldenPumpWidget(
      width: width,
      overrides: _overrides(
        _Repo(_card(_reg)),
        comments: const <ClientReviewComment>[
          ClientReviewComment(
            reviewId: 'r1',
            visitYear: 2026,
            visitMonth: 11,
            stars: 5,
            comment: 'Приходить вчасно, приємна в спілкуванні.',
            own: true,
          ),
          ClientReviewComment(
            reviewId: 'r2',
            visitYear: 2026,
            visitMonth: 9,
            stars: 2,
            comment:
                'Двічі скасувала запис за годину до візиту, '
                'попереджайте про передоплату.',
          ),
        ],
      ),
    ),
    builder: _ratingScreen,
  );
}
