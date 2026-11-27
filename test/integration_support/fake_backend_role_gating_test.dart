// Phase 386 (backend 355 + 356) - pure-Dart proof of the fake's role gating.
//
// `FakeBackend` is what the E2E flows trust: if its role rules drift, the
// salon_master / salon_staff client-review flows keep passing while asserting
// nothing. This file pins the rules directly:
//   * `providerCanReviewClientFor` - 5 roles x seeded flag, plus (B547) a
//     SALON_MASTER on another master's booking reads `false`;
//   * `PATCH /bookings/booking-1/complete` - 403 and NO mutation for a
//     SALON_MASTER, 200 and COMPLETED for the staff roles (positive control);
//   * `POST /client-reviews` - B547: 200 for the performing SALON_MASTER,
//     403 and the flag untouched when the booking is another master's;
//   * `GET /bookings/booking-1` - the post-356 contract: 200 for SALON_ADMIN.

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/fake_backend.dart';

/// Role -> expected `providerCanReviewClient` when the raw seed is `true`.
const Map<UserRole, bool> _expectedForSeededTrue = <UserRole, bool>{
  UserRole.client: false,
  UserRole.salonOwner: true,
  UserRole.salonAdmin: true,
  // B547 / REV-D06: the performing master (default `performedBySignedInMaster`).
  UserRole.salonMaster: true,
  UserRole.independentMaster: true,
};

/// 4xx must come back as a Response, not be mapped to a thrown Failure.
final Options _raw = Options(validateStatus: (_) => true);

void main() {
  group('providerCanReviewClientFor: role x seeded flag', () {
    for (final UserRole role in UserRole.values) {
      for (final bool seeded in <bool>[true, false]) {
        final bool expected = seeded && _expectedForSeededTrue[role]!;
        test('should_return_${expected}_when_${role.name}_seeded_$seeded', () {
          final FakeBackend fb = FakeBackend()..currentRole = role;

          expect(fb.providerCanReviewClientFor(seeded), expected);
        });
      }
    }

    test('should_return_false_when_salonMaster_not_performing', () {
      final FakeBackend fb = FakeBackend()..currentRole = UserRole.salonMaster;

      expect(
        fb.providerCanReviewClientFor(true, performedBySignedInMaster: false),
        isFalse,
      );
    });

    test('should_cover_every_role_in_the_table', () {
      expect(_expectedForSeededTrue.keys.toSet(), UserRole.values.toSet());
    });
  });

  group('PATCH /bookings/booking-1/complete', () {
    test('should_403_and_not_mutate_when_salonMaster', () async {
      final FakeBackend fb = FakeBackend()
        ..currentRole = UserRole.salonMaster
        ..bookingStatus = 'CONFIRMED';

      final Response<Map<String, dynamic>> res = await fb.dio
          .patch<Map<String, dynamic>>(
            '/api/v1/bookings/booking-1/complete',
            options: _raw,
          );

      expect(res.statusCode, 403);
      expect(res.data!['success'], false);
      expect(fb.completeBookingCalls, 1, reason: 'the call reached the server');
      expect(fb.bookingStatus, 'CONFIRMED', reason: 'a 403 mutates nothing');
    });

    for (final UserRole role in <UserRole>[
      UserRole.salonOwner,
      UserRole.salonAdmin,
    ]) {
      test('should_200_and_complete_when_${role.name}', () async {
        final FakeBackend fb = FakeBackend()
          ..currentRole = role
          ..bookingStatus = 'CONFIRMED';

        final Response<Map<String, dynamic>> res = await fb.dio
            .patch<Map<String, dynamic>>(
              '/api/v1/bookings/booking-1/complete',
              options: _raw,
            );

        expect(res.statusCode, 200);
        expect(fb.completeBookingCalls, 1);
        expect(fb.bookingStatus, 'COMPLETED');
      });
    }
  });

  group('POST /client-reviews', () {
    Future<Response<Map<String, dynamic>>> post(FakeBackend fb) =>
        fb.dio.post<Map<String, dynamic>>(
          '/api/v1/client-reviews',
          data: <String, dynamic>{'bookingId': 'booking-1', 'rating': 4},
          options: _raw,
        );

    test('should_200_and_flip_flag_when_salonMaster_performing', () async {
      final FakeBackend fb = FakeBackend()
        ..currentRole = UserRole.salonMaster
        ..bookingProviderCanReviewClient = true;

      expect(fb.bookingPerformedBySignedInMaster, isTrue);
      final Response<Map<String, dynamic>> res = await post(fb);

      expect(res.statusCode, 200);
      expect(fb.createClientReviewCalls, 1);
      expect(fb.lastClientReviewRating, 4);
      expect(fb.bookingProviderCanReviewClient, isFalse);
    });

    test('should_403_and_keep_flag_when_salonMaster_not_performing', () async {
      final FakeBackend fb = FakeBackend()
        ..currentRole = UserRole.salonMaster
        ..bookingProviderCanReviewClient = true
        ..bookingPerformedBySignedInMaster = false;

      final Response<Map<String, dynamic>> detail = await fb.dio
          .get<Map<String, dynamic>>(
            '/api/v1/bookings/booking-1',
            options: _raw,
          );
      final Map<String, dynamic> data =
          detail.data!['data'] as Map<String, dynamic>;
      expect(
        data['providerCanReviewClient'],
        false,
        reason: 'B547: not the performing master -> no CTA flag',
      );

      final Response<Map<String, dynamic>> res = await post(fb);

      expect(res.statusCode, 403);
      expect(fb.createClientReviewCalls, 1);
      expect(fb.lastClientReviewRating, isNull);
      expect(fb.bookingProviderCanReviewClient, isTrue);
    });

    test('should_200_and_flip_flag_when_salonOwner', () async {
      final FakeBackend fb = FakeBackend()
        ..currentRole = UserRole.salonOwner
        ..bookingProviderCanReviewClient = true;

      final Response<Map<String, dynamic>> res = await post(fb);

      expect(res.statusCode, 200);
      expect(fb.lastClientReviewRating, 4);
      expect(fb.bookingProviderCanReviewClient, isFalse);
    });
  });

  group('GET /bookings/booking-1 (backend 356)', () {
    for (final UserRole role in <UserRole>[
      UserRole.salonOwner,
      UserRole.salonAdmin,
    ]) {
      test('should_200_with_reviewable_flag_when_${role.name}', () async {
        final FakeBackend fb = FakeBackend()
          ..currentRole = role
          ..bookingStatus = 'COMPLETED'
          ..bookingProviderCanReviewClient = true;

        final Response<Map<String, dynamic>> res = await fb.dio
            .get<Map<String, dynamic>>(
              '/api/v1/bookings/booking-1',
              options: _raw,
            );

        expect(res.statusCode, 200);
        final Map<String, dynamic> data =
            res.data!['data'] as Map<String, dynamic>;
        expect(data['providerCanReviewClient'], true);
      });
    }
  });
}
