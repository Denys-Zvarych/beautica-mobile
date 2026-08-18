// Unit tests for `salonServiceFilterProvider` — the tiny per-salon
// `@riverpod` family holding the ONE service the client has tapped in the
// "Послуги" tab to narrow the "Майстри" grid. Null = no filter (every master
// shows). See `lib/features/salon/application/salon_service_filter_notifier.dart`.
//
// Pure state-machine coverage (no widget tree, no network): the four
// mutators — select / toggle / clear — plus family keying independence. The
// screen itself drives select + explicit clear (re-tapping the active row),
// but `toggle` is part of the notifier's public contract and is pinned here
// directly, including its "matches by id, not by name" invariant.
//
// A live listener is opened per test so the autoDispose family instance is
// pinned for the test's duration — without it a `read` after a mutator could
// observe a freshly rebuilt (state-reset) instance.

import 'package:beautica_mobile/features/salon/application/salon_service_filter_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';

const String _kSalonId = 'salon-1';

const SalonServiceSelection _svcA = (id: 'svc-a', name: 'Манікюр з покриттям');
const SalonServiceSelection _svcB = (id: 'svc-b', name: 'Педикюр класичний');

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer(retry: beauticaProviderRetry);
    addTearDown(container.dispose);
  });

  /// Reads the current selection for [_kSalonId], keeping the autoDispose
  /// family instance pinned for the rest of the test via a live listener.
  SalonServiceSelection? selectionOf(String salonId) {
    final sub = container.listen(
      salonServiceFilterProvider(salonId),
      (_, _) {},
    );
    addTearDown(sub.close);
    return container.read(salonServiceFilterProvider(salonId));
  }

  SalonServiceFilter notifierOf(String salonId) =>
      container.read(salonServiceFilterProvider(salonId).notifier);

  group('SalonServiceFilter', () {
    test('initial state is null — no filter, every master shows', () {
      expect(selectionOf(_kSalonId), isNull);
    });

    test('select sets the active selection', () {
      selectionOf(_kSalonId); // pin the instance
      notifierOf(_kSalonId).select(_svcA);

      expect(container.read(salonServiceFilterProvider(_kSalonId)), _svcA);
    });

    test('select replaces a previously-selected different service', () {
      selectionOf(_kSalonId);
      notifierOf(_kSalonId)
        ..select(_svcA)
        ..select(_svcB);

      expect(
        container.read(salonServiceFilterProvider(_kSalonId)),
        _svcB,
        reason: 'selecting a new service must replace the old selection',
      );
    });

    test('toggle selects when no filter is active', () {
      selectionOf(_kSalonId);
      notifierOf(_kSalonId).toggle(_svcA);

      expect(container.read(salonServiceFilterProvider(_kSalonId)), _svcA);
    });

    test('re-toggling the SAME service clears the filter', () {
      selectionOf(_kSalonId);
      notifierOf(_kSalonId)
        ..select(_svcA)
        ..toggle(_svcA);

      expect(
        container.read(salonServiceFilterProvider(_kSalonId)),
        isNull,
        reason: 'toggling the already-active service must clear it',
      );
    });

    test('toggling a DIFFERENT service replaces, never clears', () {
      selectionOf(_kSalonId);
      notifierOf(_kSalonId)
        ..select(_svcA)
        ..toggle(_svcB);

      expect(
        container.read(salonServiceFilterProvider(_kSalonId)),
        _svcB,
        reason: 'toggling a non-active service selects it (does not clear)',
      );
    });

    test('toggle keys off id, not name — a same-id/different-name toggle '
        'still clears', () {
      selectionOf(_kSalonId);
      notifierOf(_kSalonId)
        ..select(_svcA)
        ..toggle((id: 'svc-a', name: 'Стороння назва'));

      expect(
        container.read(salonServiceFilterProvider(_kSalonId)),
        isNull,
        reason:
            'toggle compares by service id — a stale/different display name '
            'carrying the same id must still count as the active service and '
            'clear the filter',
      );
    });

    test('clear nulls an active selection', () {
      selectionOf(_kSalonId);
      notifierOf(_kSalonId)
        ..select(_svcA)
        ..clear();

      expect(container.read(salonServiceFilterProvider(_kSalonId)), isNull);
    });

    test('clear on an already-empty filter is a no-op (stays null)', () {
      selectionOf(_kSalonId);
      notifierOf(_kSalonId).clear();

      expect(container.read(salonServiceFilterProvider(_kSalonId)), isNull);
    });

    test('selections for different salons are independent (family keying)', () {
      selectionOf('salon-A');
      selectionOf('salon-B');
      notifierOf('salon-A').select(_svcA);
      notifierOf('salon-B').select(_svcB);

      expect(
        container.read(salonServiceFilterProvider('salon-A')),
        _svcA,
        reason: 'salon-A keeps its own selection',
      );
      expect(
        container.read(salonServiceFilterProvider('salon-B')),
        _svcB,
        reason: "salon-B's selection must not leak into salon-A and vice versa",
      );
    });
  });
}
