// Phase 2.16 — Unit tests for [RegisterDraftNotifier].
//
// Verifies:
//   • Initial state is null until start(role) is called.
//   • updateStep1 / updateStep2 / updateStep3 merge correctly into the draft.
//   • Role is preserved across all three updates.
//   • reset() clears the draft back to null.
//   • updateStepN before start() is a no-op (defensive).

import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/state/register_draft_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RegisterDraftNotifier', () {
    test('initial state is null until start(role) is called', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(registerDraftProvider), isNull);
    });

    test('start(role) seeds the draft with empty step-1/2/3 fields', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container
          .read(registerDraftProvider.notifier)
          .start(UserRole.independentMaster);

      final draft = container.read(registerDraftProvider);
      expect(draft, isNotNull);
      expect(draft!.role, equals(UserRole.independentMaster));
      expect(draft.email, isEmpty);
      expect(draft.password, isEmpty);
      expect(draft.confirmPassword, isEmpty);
      expect(draft.firstName, isEmpty);
      expect(draft.lastName, isEmpty);
      expect(draft.phone, isEmpty);
      expect(draft.salonName, isEmpty);
      expect(draft.oblastCode, isNull);
      expect(draft.cityId, isNull);
      expect(draft.districtId, isNull);
      expect(draft.street, isEmpty);
      expect(draft.buildingNo, isEmpty);
      expect(draft.locationNote, isEmpty);
    });

    test('updateStep1 merges email + password + confirmPassword', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(registerDraftProvider.notifier);
      notifier.start(UserRole.client);
      notifier.updateStep1(
        email: 'anya@example.com',
        password: 'SecurePass1',
        confirmPassword: 'SecurePass1',
      );

      final draft = container.read(registerDraftProvider);
      expect(draft!.email, equals('anya@example.com'));
      expect(draft.password, equals('SecurePass1'));
      expect(draft.confirmPassword, equals('SecurePass1'));
      // Role is preserved.
      expect(draft.role, equals(UserRole.client));
      // Other slices are untouched.
      expect(draft.firstName, isEmpty);
      expect(draft.phone, isEmpty);
    });

    test('updateStep2 merges firstName + lastName + phone + salonName', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(registerDraftProvider.notifier);
      notifier.start(UserRole.salonOwner);
      notifier.updateStep1(
        email: 'olena@example.com',
        password: 'StrongPass2',
        confirmPassword: 'StrongPass2',
      );
      notifier.updateStep2(
        firstName: 'Олена',
        lastName: 'Бойко',
        phone: '+380 67 123 45 67',
        salonName: 'Краса Студія',
      );

      final draft = container.read(registerDraftProvider);
      expect(draft!.firstName, equals('Олена'));
      expect(draft.lastName, equals('Бойко'));
      expect(draft.phone, equals('+380 67 123 45 67'));
      expect(draft.salonName, equals('Краса Студія'));
      // Step 1 slice is preserved.
      expect(draft.email, equals('olena@example.com'));
      expect(draft.password, equals('StrongPass2'));
      // Role preserved.
      expect(draft.role, equals(UserRole.salonOwner));
    });

    test('updateStep3 merges address fields', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(registerDraftProvider.notifier);
      notifier.start(UserRole.salonOwner);
      notifier.updateStep1(
        email: 'a@b.com',
        password: 'p1',
        confirmPassword: 'p1',
      );
      notifier.updateStep2(firstName: 'A', lastName: 'B', phone: 'p');
      notifier.updateStep3(
        // Locality IDs are backend UUID strings (Phase 2.19) — not ints.
        oblastCode: 'oblast-uuid-32',
        cityId: 'city-uuid-100',
        districtId: 'district-uuid-5',
        street: 'вул. Хрещатик',
        buildingNo: '1',
        locationNote: '2 поверх',
      );

      final draft = container.read(registerDraftProvider);
      expect(draft!.oblastCode, equals('oblast-uuid-32'));
      expect(draft.cityId, equals('city-uuid-100'));
      expect(draft.districtId, equals('district-uuid-5'));
      expect(draft.street, equals('вул. Хрещатик'));
      expect(draft.buildingNo, equals('1'));
      expect(draft.locationNote, equals('2 поверх'));
      // All earlier slices preserved.
      expect(draft.email, equals('a@b.com'));
      expect(draft.firstName, equals('A'));
      // Role preserved through every update.
      expect(draft.role, equals(UserRole.salonOwner));
    });

    test(
      'clearCredentials() wipes password + confirmPassword, keeps the rest',
      () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final notifier = container.read(registerDraftProvider.notifier);
        notifier.start(UserRole.independentMaster);
        notifier.updateStep1(
          email: 'anya@example.com',
          password: 'SecurePass1!',
          confirmPassword: 'SecurePass1!',
        );
        notifier.updateStep2(
          firstName: 'Аня',
          lastName: 'Коваль',
          phone: '+380501112233',
        );
        notifier.updateStep3(
          oblastCode: 'o1',
          cityId: 'c1',
          districtId: 'd1',
          street: 'вул. Тестова',
          buildingNo: '12',
        );

        notifier.clearCredentials();

        final draft = container.read(registerDraftProvider);
        expect(draft, isNotNull);
        // Credentials wiped.
        expect(draft!.password, isEmpty);
        expect(draft.confirmPassword, isEmpty);
        // Everything else intact (needed by the verification step).
        expect(draft.email, equals('anya@example.com'));
        expect(draft.firstName, equals('Аня'));
        expect(draft.lastName, equals('Коваль'));
        expect(draft.phone, equals('+380501112233'));
        expect(draft.oblastCode, equals('o1'));
        expect(draft.cityId, equals('c1'));
        expect(draft.districtId, equals('d1'));
        expect(draft.street, equals('вул. Тестова'));
        expect(draft.buildingNo, equals('12'));
        expect(draft.role, equals(UserRole.independentMaster));
      },
    );

    test('clearCredentials() before start() is a no-op (defensive)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(registerDraftProvider.notifier).clearCredentials();

      expect(container.read(registerDraftProvider), isNull);
    });

    test('reset() clears the draft back to null', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(registerDraftProvider.notifier);
      notifier.start(UserRole.independentMaster);
      notifier.updateStep1(
        email: 'a@b.com',
        password: 'pw',
        confirmPassword: 'pw',
      );
      notifier.reset();

      expect(container.read(registerDraftProvider), isNull);
    });

    test('updateStep1 before start() is a no-op (defensive)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container
          .read(registerDraftProvider.notifier)
          .updateStep1(email: 'a@b.com', password: 'pw', confirmPassword: 'pw');

      expect(container.read(registerDraftProvider), isNull);
    });

    test('role survives start → updateStep1/2/3 → reset → start(new role)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(registerDraftProvider.notifier);
      notifier.start(UserRole.client);
      notifier.updateStep1(email: 'a', password: 'b', confirmPassword: 'b');
      expect(
        container.read(registerDraftProvider)!.role,
        equals(UserRole.client),
      );

      notifier.reset();
      expect(container.read(registerDraftProvider), isNull);

      // Re-start with a different role — the new draft starts fresh.
      notifier.start(UserRole.salonOwner);
      expect(
        container.read(registerDraftProvider)!.role,
        equals(UserRole.salonOwner),
      );
      // Previous step-1 data did NOT carry over.
      expect(container.read(registerDraftProvider)!.email, isEmpty);
    });
  });
}
