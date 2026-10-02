import 'package:beautica_mobile/core/push/push_available_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

ProviderContainer _container(Future<bool> Function() init) {
  final ProviderContainer c = ProviderContainer(
    overrides: [firebaseInitializerProvider.overrideWithValue(init)],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('resolves to the init result (true)', () async {
    final ProviderContainer container = _container(() async => true);
    expect(await container.read(pushAvailableProvider.future), isTrue);
  });

  test('resolves to false when init is unavailable', () async {
    final ProviderContainer container = _container(() async => false);
    expect(await container.read(pushAvailableProvider.future), isFalse);
  });

  test('default (no Firebase on the test host) resolves to false', () async {
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);
    expect(await container.read(pushAvailableProvider.future), isFalse);
  });

  test('is keep-alive: init runs once across listeners', () async {
    int runs = 0;
    final ProviderContainer container = _container(() async {
      runs++;
      return true;
    });
    await container.read(pushAvailableProvider.future);
    await Future<void>.delayed(Duration.zero);
    await container.read(pushAvailableProvider.future);
    expect(runs, 1);
  });
}
