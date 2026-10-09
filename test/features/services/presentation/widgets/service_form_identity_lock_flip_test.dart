// Phase 377 audit-fix 2 — `ServiceForm.identityLocked` can flip AFTER
// initState (the owner's set resolving late). didUpdateWidget must re-evaluate
// the name listener / read-only state, and when the lock flips ON mid-edit it
// must restore the loaded identity values so nothing is silently dropped.

import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';
import 'package:beautica_mobile/features/services/data/service_repository.dart';
import 'package:beautica_mobile/features/services/domain/master_service.dart';
import 'package:beautica_mobile/features/services/domain/master_service_input.dart';
import 'package:beautica_mobile/features/services/domain/service_category_option.dart';
import 'package:beautica_mobile/features/services/domain/service_type_option.dart';
import 'package:beautica_mobile/features/services/presentation/service_types_provider.dart';
import 'package:beautica_mobile/features/services/presentation/widgets/service_form.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'select_dropdown_test_helpers.dart';

class _MockServiceRepository extends Mock implements ServiceRepository {}

const MasterService _service = MasterService(
  id: 'svc-1',
  serviceDefId: 'def-1',
  name: 'Мій манікюр',
  category: 'MANICURE',
  durationMinutes: 60,
  priceType: ServicePriceType.fixed,
  priceMin: 500,
  priceDisplay: '500 ₴',
);

const List<ServiceCategoryOption> _categories = <ServiceCategoryOption>[
  ServiceCategoryOption(name: 'MANICURE', displayName: 'Манікюр'),
  ServiceCategoryOption(name: 'HAIRCUT', displayName: 'Стрижка'),
];

final Finder _nameField = find.descendant(
  of: find.byKey(const Key('field-service-name')),
  matching: find.byType(TextField),
);

void main() {
  late ValueNotifier<bool> locked;
  late List<bool> dirtyFlips;
  MasterServiceCreate? submitted;

  setUp(() {
    locked = ValueNotifier<bool>(false);
    dirtyFlips = <bool>[];
    submitted = null;
  });
  tearDown(() => locked.dispose());

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        retry: beauticaProviderRetry,
        overrides: <Object>[
          serviceRepositoryProvider.overrideWithValue(_MockServiceRepository()),
          approvedCategoriesProvider.overrideWith((ref) async => _categories),
          serviceTypesProvider.overrideWith(
            (ref, String c) async => const <ServiceTypeOption>[],
          ),
        ].cast(),
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('uk'),
          home: Scaffold(
            body: SingleChildScrollView(
              child: ValueListenableBuilder<bool>(
                valueListenable: locked,
                builder: (_, bool isLocked, _) => ServiceForm(
                  initial: _service,
                  identityLocked: isLocked,
                  onDirtyChanged: dirtyFlips.add,
                  onSubmit: (MasterServiceCreate i) async => submitted = i,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const Key('btn-submit-service')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('btn-submit-service')));
    await tester.pumpAndSettle();
  }

  testWidgets('false -> true mid-edit: name + category reset to the loaded '
      'values, name goes read-only, submit sends the ORIGINAL identity', (
    tester,
  ) async {
    await pump(tester);
    await tester.enterText(_nameField, 'Нова назва');
    await selectCategoryOption(tester, 'HAIRCUT');
    expect(dirtyFlips.isNotEmpty && dirtyFlips.last, isTrue);

    locked.value = true;
    await tester.pumpAndSettle();

    expect(_nameField, findsNothing, reason: 'name is plain text when locked');
    expect(
      find.descendant(
        of: find.byKey(const Key('field-service-name')),
        matching: find.text(_service.name),
      ),
      findsOneWidget,
    );
    expect(dirtyFlips.last, isFalse, reason: 'identity edits were discarded');

    await submit(tester);
    expect(submitted, isNotNull);
    expect(submitted?.name, _service.name);
    expect(submitted?.category, 'MANICURE');
  });

  testWidgets('true -> false: the name field is editable again and its '
      'listener is re-attached (typing flips dirty)', (tester) async {
    locked.value = true;
    await pump(tester);
    expect(_nameField, findsNothing);

    locked.value = false;
    await tester.pumpAndSettle();
    expect(_nameField, findsOneWidget);

    dirtyFlips.clear();
    await tester.enterText(_nameField, 'Інша назва');
    await tester.pump();
    expect(dirtyFlips, contains(true));
  });
}
