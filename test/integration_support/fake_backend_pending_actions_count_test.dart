// Phase 393 (24.7a) — fake parity: `FakeBackend`'s
// `…/pending-actions/count` answers are COMPUTED from its seeded rows with the
// backend-357 rules (CONFIRMED && ended, or COMPLETED && client present &&
// providerCanReviewClient), never a settable integer. Without this, 395's
// badge assertions could pass against a fake that disagrees with the server.

import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/fake_backend.dart';

Future<int> _meCount(FakeBackend fb, {bool asMaster = false}) async {
  final res = await fb.dio.get<Map<String, dynamic>>(
    '/api/v1/bookings/me/pending-actions/count',
    queryParameters: <String, dynamic>{'asMaster': asMaster},
  );
  return (res.data!['data'] as Map<String, dynamic>)['count'] as int;
}

Future<int> _salonCount(FakeBackend fb, String salonId) async {
  final res = await fb.dio.get<Map<String, dynamic>>(
    '/api/v1/bookings/salon/$salonId/pending-actions/count',
  );
  return (res.data!['data'] as Map<String, dynamic>)['count'] as int;
}

void main() {
  late FakeBackend fb;

  setUp(() => fb = FakeBackend());

  // 2 ended CONFIRMED + 1 COMPLETED unreviewed = 3; the rest must NOT count.
  List<Map<String, dynamic>> mix() {
    final now = fb.serverNow;
    return <Map<String, dynamic>>[
      fb.datasetBookingRow(
        id: 'ended-1',
        status: 'CONFIRMED',
        startsAt: now.subtract(const Duration(hours: 5)),
      ),
      fb.datasetBookingRow(
        id: 'ended-2',
        status: 'CONFIRMED',
        startsAt: now.subtract(const Duration(days: 2)),
      ),
      // In slot: endsAt is after now.
      fb.datasetBookingRow(
        id: 'in-slot',
        status: 'CONFIRMED',
        startsAt: now.subtract(const Duration(minutes: 10)),
      ),
      fb.datasetBookingRow(
        id: 'upcoming',
        status: 'CONFIRMED',
        startsAt: now.add(const Duration(days: 1)),
      ),
      fb.datasetBookingRow(
        id: 'completed-unreviewed',
        status: 'COMPLETED',
        startsAt: now.subtract(const Duration(days: 1)),
        providerCanReviewClient: true,
      ),
      fb.datasetBookingRow(
        id: 'completed-reviewed',
        status: 'COMPLETED',
        startsAt: now.subtract(const Duration(days: 1)),
      ),
      <String, dynamic>{
        ...fb.datasetBookingRow(
          id: 'completed-guest',
          status: 'COMPLETED',
          startsAt: now.subtract(const Duration(days: 1)),
          providerCanReviewClient: true,
        ),
        'clientId': null,
      },
      fb.datasetBookingRow(
        id: 'cancelled',
        status: 'CANCELLED',
        startsAt: now.subtract(const Duration(days: 1)),
      ),
    ];
  }

  test('/me count is computed from the seeded dataset (3-case mix)', () async {
    fb.seedManyBookingsDataset(mix());

    expect(await _meCount(fb), 3);
    expect(fb.getPendingActionsCountCalls, 1);
  });

  test('/me count changes when the seeded rows change', () async {
    fb.seedManyBookingsDataset(mix().take(3).toList());
    expect(await _meCount(fb), 2);
  });

  test('asMaster narrows to ownerMasterRowBookingIds', () async {
    fb.seedManyBookingsDataset(mix());
    fb.ownerMasterRowBookingIds = <String>{'ended-1'};

    expect(await _meCount(fb, asMaster: true), 1);
    expect(await _meCount(fb, asMaster: false), 3);
  });

  test('salon count is computed from board + archive rows', () async {
    final now = fb.serverNow;
    fb.salonBoardBookings = <Map<String, dynamic>>[
      fb.salonBoardBookingRow(
        id: 'b1',
        masterId: 'm1',
        masterFirstName: 'Софія',
        masterLastName: 'Бондар',
        startsAt: now.subtract(const Duration(hours: 4)),
      ),
      fb.salonBoardBookingRow(
        id: 'b2',
        masterId: 'm1',
        masterFirstName: 'Софія',
        masterLastName: 'Бондар',
        startsAt: now.add(const Duration(hours: 4)),
      ),
    ];
    fb.salonArchiveBookings = <Map<String, dynamic>>[
      fb.salonBoardBookingRow(
        id: 'a1',
        masterId: 'm1',
        masterFirstName: 'Софія',
        masterLastName: 'Бондар',
        startsAt: now.subtract(const Duration(days: 1)),
        status: 'COMPLETED',
        providerCanReviewClient: true,
      ),
    ];

    expect(await _salonCount(fb, FakeBackend.kAdminSalonId), 2);
  });

  test('owner salon id resolves to the same computed salon count', () async {
    final now = fb.serverNow;
    fb.salonBoardBookings = <Map<String, dynamic>>[
      fb.salonBoardBookingRow(
        id: 'o1',
        masterId: 'm1',
        masterFirstName: 'Софія',
        masterLastName: 'Бондар',
        startsAt: now.subtract(const Duration(hours: 4)),
      ),
    ];
    fb.salonArchiveBookings = <Map<String, dynamic>>[];

    expect(await _salonCount(fb, FakeBackend.kOwnerSalonId), 1);
    expect(fb.getPendingActionsCountCalls, 1);
  });
}
