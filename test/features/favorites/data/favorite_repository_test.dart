// Phase 234 — unit tests for [HttpFavoriteRepository]'s wire-enum translation.
//
// WHY THIS FILE EXISTS
// --------------------
// `HttpFavoriteRepository._wireType` is the SINGLE point where the pure-Dart
// [FavoriteTargetType] becomes the generated `AddFavoriteRequestTargetTypeEnum`,
// and the invariant it protects — "the generated enum never escapes the data
// layer" — means no test above this layer can observe what actually goes on the
// wire. Until Phase 234 the repository had no test at all: the only favorites
// coverage was `favorite_toggle_notifier_test.dart`, which drives a FAKE
// repository and therefore cannot see the enum.
//
// That gap matters now that `SERVICE` exists. A `service` arm that mapped to
// `MASTER` (a plausible copy-paste, since the switch is exhaustive and the
// compiler only demands *an* arm, not the right one) would send a valid enum
// value the backend accepts, silently favouriting a master whose id is really a
// masterServiceId. Nothing else in the suite would go red.
//
// Strategy: mocktail-mock the generated [FavoriteControllerApi] and capture the
// argument. No real Dio, no ProviderScope, no widget tree.

import 'package:beautica_api/beautica_api.dart';
import 'package:beautica_mobile/features/favorites/data/favorite_repository.dart';
import 'package:beautica_mobile/features/favorites/domain/favorite_target.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockFavoriteControllerApi extends Mock
    implements FavoriteControllerApi {}

class _FakeAddFavoriteRequest extends Fake implements AddFavoriteRequest {}

Response<ApiResponseFavoriteResponse> _addOk() =>
    Response<ApiResponseFavoriteResponse>(
      requestOptions: RequestOptions(path: '/api/v1/favorites'),
      statusCode: 200,
    );

Response<void> _removeOk() => Response<void>(
  requestOptions: RequestOptions(path: '/api/v1/favorites'),
  statusCode: 204,
);

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeAddFavoriteRequest());
  });

  late _MockFavoriteControllerApi api;
  late HttpFavoriteRepository repository;

  setUp(() {
    api = _MockFavoriteControllerApi();
    repository = HttpFavoriteRepository(api);
    when(
      () =>
          api.addFavorite(addFavoriteRequest: any(named: 'addFavoriteRequest')),
    ).thenAnswer((_) async => _addOk());
    when(
      () => api.removeFavorite(
        targetType: any(named: 'targetType'),
        targetId: any(named: 'targetId'),
      ),
    ).thenAnswer((_) async => _removeOk());
  });

  /// The `AddFavoriteRequest` the repository actually handed to the generated
  /// API on the single captured `addFavorite` call.
  AddFavoriteRequest capturedAddRequest() =>
      verify(
            () => api.addFavorite(
              addFavoriteRequest: captureAny(named: 'addFavoriteRequest'),
            ),
          ).captured.single
          as AddFavoriteRequest;

  group('HttpFavoriteRepository.add — wire enum translation', () {
    test('sends the SERVICE wire enum when targetType is service', () async {
      await repository.add(
        const FavoriteTarget(
          type: FavoriteTargetType.service,
          id: 'master-service-1',
        ),
      );

      final AddFavoriteRequest sent = capturedAddRequest();
      expect(sent.targetType, AddFavoriteRequestTargetTypeEnum.SERVICE);
      // The id must ride along untouched — a `service` favourite keys on the
      // masterServiceId, not the master.
      expect(sent.targetId, 'master-service-1');
    });

    // NEGATIVE CONTROLS. Without these, a `_wireType` that returned SERVICE for
    // everything would satisfy the case above. Each existing arm is pinned to a
    // DIFFERENT enum value so no single collapsed mapping can pass all three.
    test('still sends MASTER for a master target', () async {
      await repository.add(
        const FavoriteTarget(type: FavoriteTargetType.master, id: 'm1'),
      );

      expect(
        capturedAddRequest().targetType,
        AddFavoriteRequestTargetTypeEnum.MASTER,
      );
    });

    test('still sends SALON for a salon target', () async {
      await repository.add(
        const FavoriteTarget(type: FavoriteTargetType.salon, id: 's1'),
      );

      expect(
        capturedAddRequest().targetType,
        AddFavoriteRequestTargetTypeEnum.SALON,
      );
    });
  });

  group('HttpFavoriteRepository.remove — wire enum translation', () {
    test(
      'sends the SERVICE wire enum when removing a service favorite',
      () async {
        await repository.remove(
          const FavoriteTarget(
            type: FavoriteTargetType.service,
            id: 'master-service-1',
          ),
        );

        // `remove` sends the enum's NAME as a query param, so the assertion is on
        // the string the backend will parse — the literal 'SERVICE', which is
        // what the regenerated `targetType` query enum now accepts.
        verify(
          () => api.removeFavorite(
            targetType: 'SERVICE',
            targetId: 'master-service-1',
          ),
        ).called(1);
      },
    );

    test(
      'still sends MASTER / SALON for the pre-existing target types',
      () async {
        await repository.remove(
          const FavoriteTarget(type: FavoriteTargetType.master, id: 'm1'),
        );
        await repository.remove(
          const FavoriteTarget(type: FavoriteTargetType.salon, id: 's1'),
        );

        verify(
          () => api.removeFavorite(targetType: 'MASTER', targetId: 'm1'),
        ).called(1);
        verify(
          () => api.removeFavorite(targetType: 'SALON', targetId: 's1'),
        ).called(1);
      },
    );
  });

  group('FavoriteTargetType — enum surface', () {
    test('declares exactly master, salon and service', () {
      // Guards the domain enum against silently gaining a member that
      // `_wireType` cannot translate. The switch there is exhaustive with no
      // default, so a new member is a COMPILE error — this test documents the
      // intended surface so a `default:` added to silence that error is caught
      // in review rather than shipping an untranslated type.
      expect(FavoriteTargetType.values, <FavoriteTargetType>[
        FavoriteTargetType.master,
        FavoriteTargetType.salon,
        FavoriteTargetType.service,
      ]);
    });
  });
}
