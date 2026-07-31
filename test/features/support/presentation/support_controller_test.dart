// Unit tests for [SupportController] — the submit-state notifier.
//
// Strategy:
//   A fresh [ProviderContainer] per test with [supportRepositoryProvider]
//   overridden by a mocktail mock. We drive submit()/reset() and assert the
//   exposed [SupportSubmitState] transitions (idle → sending → success | error).
//   The container is disposed in addTearDown (M1).
//
// Coverage:
//   1.  initial state is SupportSubmitIdle.
//   2.  submit() success: passes through to SupportSubmitSuccess, forwarding
//       message/subject/attachments to the repo verbatim.
//   3.  submit() failure: a typed Failure maps to SupportSubmitError carrying it.
//   4.  double-submit guard: a second submit() while one is in flight is a no-op
//       (the repo is called exactly once).
//   5.  reset(): clears an error back to idle; is a no-op from any other state.
//
// Layer: Unit (no widget tree).

import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/support/data/support_repository.dart';
import 'package:beautica_mobile/features/support/domain/support_attachment.dart';
import 'package:beautica_mobile/features/support/presentation/support_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';

class _MockSupportRepository extends Mock implements SupportRepository {}

SupportAttachment _png(String name) => SupportAttachment(
  name: name,
  bytes: const <int>[1, 2, 3],
  contentType: 'image/png',
  kind: SupportAttachmentKind.image,
);

void main() {
  late _MockSupportRepository repo;

  setUpAll(() {
    registerFallbackValue(<SupportAttachment>[]);
  });

  setUp(() {
    repo = _MockSupportRepository();
  });

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      retry: beauticaProviderRetry,
      overrides: [supportRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('initial state is SupportSubmitIdle', () {
    final container = makeContainer();

    expect(container.read(supportControllerProvider), isA<SupportSubmitIdle>());
  });

  test('submit() success transitions to SupportSubmitSuccess and forwards '
      'message/subject/attachments to the repository', () async {
    when(
      () => repo.submitContact(
        message: any(named: 'message'),
        subject: any(named: 'subject'),
        attachments: any(named: 'attachments'),
      ),
    ).thenAnswer((_) async {});

    final container = makeContainer();
    final attachments = <SupportAttachment>[_png('shot.png')];

    await container
        .read(supportControllerProvider.notifier)
        .submit(
          message: 'A valid ten-plus message',
          subject: 'Subject here',
          attachments: attachments,
        );

    expect(
      container.read(supportControllerProvider),
      isA<SupportSubmitSuccess>(),
    );

    // A single verify consumes the recorded call; assert the captured values
    // by membership so the test does not couple to mocktail's flatten order.
    final captured = verify(
      () => repo.submitContact(
        message: captureAny(named: 'message'),
        subject: captureAny(named: 'subject'),
        attachments: captureAny(named: 'attachments'),
      ),
    ).captured;
    expect(captured, contains('A valid ten-plus message'));
    expect(captured, contains('Subject here'));
    expect(captured, contains(same(attachments)));
  });

  test('observes the sending transition before settling on success', () async {
    // Block the repo so we can observe the intermediate sending state.
    final completer = Completer<void>();
    when(
      () => repo.submitContact(
        message: any(named: 'message'),
        subject: any(named: 'subject'),
        attachments: any(named: 'attachments'),
      ),
    ).thenAnswer((_) => completer.future);

    final container = makeContainer();
    final states = <SupportSubmitState>[];
    container.listen(
      supportControllerProvider,
      (_, next) => states.add(next),
      fireImmediately: false,
    );

    final future = container
        .read(supportControllerProvider.notifier)
        .submit(message: 'A valid ten-plus message');

    expect(
      container.read(supportControllerProvider),
      isA<SupportSubmitSending>(),
      reason: 'submit() must flip to sending synchronously before awaiting',
    );

    completer.complete();
    await future;

    expect(states.first, isA<SupportSubmitSending>());
    expect(states.last, isA<SupportSubmitSuccess>());
  });

  test(
    'submit() failure maps a typed Failure to SupportSubmitError carrying it',
    () async {
      const failure = SupportChannelUnavailableFailure();
      when(
        () => repo.submitContact(
          message: any(named: 'message'),
          subject: any(named: 'subject'),
          attachments: any(named: 'attachments'),
        ),
      ).thenThrow(failure);

      final container = makeContainer();

      await container
          .read(supportControllerProvider.notifier)
          .submit(message: 'A valid ten-plus message');

      final state = container.read(supportControllerProvider);
      expect(state, isA<SupportSubmitError>());
      expect((state as SupportSubmitError).failure, same(failure));
    },
  );

  test(
    'double-submit guard: a second submit() while one is in flight is a no-op',
    () async {
      final completer = Completer<void>();
      when(
        () => repo.submitContact(
          message: any(named: 'message'),
          subject: any(named: 'subject'),
          attachments: any(named: 'attachments'),
        ),
      ).thenAnswer((_) => completer.future);

      final container = makeContainer();
      final notifier = container.read(supportControllerProvider.notifier);

      final first = notifier.submit(message: 'A valid ten-plus message');
      // Second call while sending — must short-circuit.
      await notifier.submit(message: 'A second concurrent message');

      completer.complete();
      await first;

      verify(
        () => repo.submitContact(
          message: any(named: 'message'),
          subject: any(named: 'subject'),
          attachments: any(named: 'attachments'),
        ),
      ).called(1);
    },
  );

  group('reset', () {
    test('clears an error back to idle', () async {
      when(
        () => repo.submitContact(
          message: any(named: 'message'),
          subject: any(named: 'subject'),
          attachments: any(named: 'attachments'),
        ),
      ).thenThrow(const NetworkFailure());

      final container = makeContainer();
      final notifier = container.read(supportControllerProvider.notifier);

      await notifier.submit(message: 'A valid ten-plus message');
      expect(
        container.read(supportControllerProvider),
        isA<SupportSubmitError>(),
      );

      notifier.reset();
      expect(
        container.read(supportControllerProvider),
        isA<SupportSubmitIdle>(),
      );
    });

    test('is a no-op from a non-error state (idle stays idle)', () {
      final container = makeContainer();
      final notifier = container.read(supportControllerProvider.notifier);

      notifier.reset();

      expect(
        container.read(supportControllerProvider),
        isA<SupportSubmitIdle>(),
      );
    });
  });
}
