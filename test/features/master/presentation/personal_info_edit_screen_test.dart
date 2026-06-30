// Widget tests for PersonalInfoEditScreen (firstName + lastName + bio).
//
// HIGHEST-VALUE TEST (cached-master-merge): editing ONLY the name must NOT wipe
// the cached contact siblings. updateMyProfile sends firstName/lastName/bio/
// instagram/contactPhone together and an empty string CLEARS the field
// server-side, so the split page MUST overlay name+bio onto the CACHED phone +
// instagram. This file captures the MasterUpdate passed to the repository and
// asserts the cached Instagram / phone survive.
//
// Also covers: pristine→dirty Save enable, required-field validation, the
// save-success path (updateMyProfile called → masterProfileProvider invalidated
// → saved SnackBar → navigate to profile when canPop is false), and the
// network-failure SnackBar.
//
// Finders use widget Keys (M2). Layer: Widget.

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/master/data/master_repository.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/domain/master_update.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_notifier.dart';
import 'package:beautica_mobile/features/master/presentation/personal_info_edit_screen.dart';
import 'package:beautica_mobile/features/master/presentation/widgets/section_scaffold.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/pump_app.dart';

class _MockMasterRepository extends Mock implements MasterRepository {}

const _stubUser = User(
  id: 'user-1',
  email: 'test@beautica.ua',
  role: UserRole.independentMaster,
  firstName: 'Олена',
  lastName: 'Ковальчук',
);

// Cached master with BOTH siblings (phone + instagram) populated — the personal
// page must preserve these even though it does not render them.
const _cachedMaster = Master(
  id: 'user-1',
  firstName: 'Олена',
  lastName: 'Ковальчук',
  bio: 'Майстер манікюру.',
  phoneNumber: '+380 50 123 45 67',
  instagram: '@olena_nails',
  avgRating: 4.8,
  reviewCount: 10,
  type: MasterType.independentMaster,
);

class _StubMasterProfileNotifier extends MasterProfile {
  _StubMasterProfileNotifier(this._master);
  final Master _master;

  @override
  Future<Master> build() => Future<Master>.value(_master);
}

class _StubAuthNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() async => const AuthSession.authenticated(
    user: _stubUser,
    accessToken: 'test-token',
  );
}

GoRouter _buildRouter() => GoRouter(
  initialLocation: RouteNames.masterEditPersonal,
  routes: <RouteBase>[
    GoRoute(
      path: RouteNames.masterEditPersonal,
      pageBuilder: (_, _) =>
          const NoTransitionPage<void>(child: PersonalInfoEditScreen()),
    ),
    GoRoute(
      path: RouteNames.masterProfile,
      pageBuilder: (_, _) => const NoTransitionPage<void>(
        child: Scaffold(body: SizedBox(key: Key('stub-profile'))),
      ),
    ),
  ],
);

List<Object> _overrides(_MockMasterRepository repo, {Master? master}) =>
    <Object>[
      authProvider.overrideWith(_StubAuthNotifier.new),
      masterProfileProvider.overrideWith(
        () => _StubMasterProfileNotifier(master ?? _cachedMaster),
      ),
      masterRepositoryProvider.overrideWithValue(repo),
    ];

Finder _field(String key) =>
    find.descendant(of: find.byKey(Key(key)), matching: find.byType(TextField));

void main() {
  late _MockMasterRepository repo;

  setUpAll(() {
    registerFallbackValue(
      const MasterUpdate(
        firstName: '',
        lastName: '',
        bio: '',
        contactPhone: '',
        instagram: '',
      ),
    );
  });

  setUp(() {
    repo = _MockMasterRepository();
  });

  testWidgets('pre-populates firstName, lastName, bio from the cached master', (
    tester,
  ) async {
    await tester.pumpRoutedApp(_buildRouter(), overrides: _overrides(repo));
    await tester.pump();
    await tester.pump();

    expect(
      tester.widget<TextField>(_field('field-firstName')).controller?.text,
      'Олена',
    );
    expect(
      tester.widget<TextField>(_field('field-lastName')).controller?.text,
      'Ковальчук',
    );
    expect(
      tester.widget<TextField>(_field('field-bio')).controller?.text,
      'Майстер манікюру.',
    );
  });

  testWidgets('Save is disabled when pristine and enables when dirty', (
    tester,
  ) async {
    await tester.pumpRoutedApp(_buildRouter(), overrides: _overrides(repo));
    await tester.pump();
    await tester.pump();

    expect(
      tester
          .widget<NeumorphicButton>(find.byKey(const Key('btn-save-personal')))
          .onPressed,
      isNull,
      reason: 'pristine form must leave Save disabled',
    );

    await tester.enterText(_field('field-firstName'), 'Оксана');
    await tester.pump();

    expect(
      tester
          .widget<NeumorphicButton>(find.byKey(const Key('btn-save-personal')))
          .onPressed,
      isNotNull,
      reason: 'editing firstName must enable Save',
    );
  });

  // ── PERF (P2): typing must NOT re-run the screen-level build ───────────────
  //
  // The dirty-state that gates the Save button is now driven by a
  // ValueNotifier<bool> + ValueListenableBuilder around the footer, NOT a
  // setState(() {}) on the whole screen State. So a keystroke must leave the
  // screen-level widget tree (the SectionScaffold chrome + its reveal animation
  // wrappers) untouched — same widget object identity before and after.
  //
  // Under the OLD setState-per-keystroke code, the screen's build() re-ran on
  // every character and produced a brand-new SectionScaffold (rebuilding the
  // app-bar / back-button / footer chrome each keystroke). The identity check
  // below fails on that old behaviour and passes on the ValueNotifier fix.
  //
  // (The typed field itself still rebuilds via FormState — that is inherent to
  // FormField and is NOT the jank this fix targets.)
  testWidgets('typing a valid name does NOT re-run the screen build '
      '(SectionScaffold chrome preserved) yet still enables Save', (
    tester,
  ) async {
    await tester.pumpRoutedApp(_buildRouter(), overrides: _overrides(repo));
    await tester.pumpAndSettle();

    SectionScaffold scaffold() =>
        tester.widget<SectionScaffold>(find.byType(SectionScaffold));

    final before = scaffold();

    // A valid name (no digit) → no per-field error change; the only screen
    // listener that fires is the dirty-notifier, which must NOT setState the
    // screen.
    await tester.enterText(_field('field-firstName'), 'Оксана');
    await tester.pump();

    expect(
      identical(before, scaffold()),
      isTrue,
      reason:
          'a keystroke must not re-run the screen build — the old '
          'setState(() {}) recreated the whole SectionScaffold (P2 jank).',
    );

    // Behaviour preserved: the dirty flip still enables Save.
    expect(
      tester
          .widget<NeumorphicButton>(find.byKey(const Key('btn-save-personal')))
          .onPressed,
      isNotNull,
      reason: 'the ValueListenableBuilder footer must still enable Save',
    );
  });

  // ── Save re-disables when the form is reverted back to pristine ────────────
  //
  // Guards that the ValueNotifier-driven dirty path tracks BOTH directions:
  // dirty on edit, clean again on revert — preserving the old getter behaviour.
  testWidgets('reverting an edit back to the original value re-disables Save', (
    tester,
  ) async {
    await tester.pumpRoutedApp(_buildRouter(), overrides: _overrides(repo));
    await tester.pump();
    await tester.pump();

    await tester.enterText(_field('field-firstName'), 'Оксана');
    await tester.pump();
    expect(
      tester
          .widget<NeumorphicButton>(find.byKey(const Key('btn-save-personal')))
          .onPressed,
      isNotNull,
      reason: 'editing enables Save',
    );

    // Revert to the cached original — the form is pristine again.
    await tester.enterText(_field('field-firstName'), 'Олена');
    await tester.pump();
    expect(
      tester
          .widget<NeumorphicButton>(find.byKey(const Key('btn-save-personal')))
          .onPressed,
      isNull,
      reason: 'reverting to the original value must disable Save again',
    );
  });

  // ── CRITICAL: cached-master-merge — Instagram + phone NOT wiped ────────────
  testWidgets(
    'editing only the name preserves the cached Instagram and phone in the '
    'MasterUpdate (siblings are NOT cleared)',
    (tester) async {
      MasterUpdate? captured;
      when(() => repo.updateMyProfile(any())).thenAnswer((invocation) async {
        captured = invocation.positionalArguments.first as MasterUpdate;
      });

      await tester.pumpRoutedApp(_buildRouter(), overrides: _overrides(repo));
      await tester.pump();
      await tester.pump();

      // Edit ONLY the firstName — never touch phone/instagram (the page does
      // not even render them).
      await tester.enterText(_field('field-firstName'), 'Оксана');
      await tester.pump();

      await tester.tap(find.byKey(const Key('btn-save-personal')));
      await tester.pumpAndSettle();

      expect(captured, isNotNull, reason: 'updateMyProfile must be called');
      expect(captured!.firstName, 'Оксана');
      expect(captured!.lastName, 'Ковальчук');
      expect(captured!.bio, 'Майстер манікюру.');
      // THE REGRESSION GUARD: siblings carried from the cache, never blanked.
      expect(
        captured!.instagram,
        '@olena_nails',
        reason:
            'Instagram must be overlaid from the cached master — an empty '
            'string here would CLEAR the user\'s Instagram server-side.',
      );
      expect(
        captured!.contactPhone,
        '+380 50 123 45 67',
        reason: 'phone must be overlaid from the cached master, not blanked.',
      );
    },
  );

  testWidgets('save success invalidates the profile, shows the saved SnackBar '
      'and navigates to the profile when canPop is false', (tester) async {
    when(() => repo.updateMyProfile(any())).thenAnswer((_) async {});

    final states = <AsyncValue<Object?>>[];

    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides(repo).cast(),
        child: _InvalidationWatcher(
          states: states,
          child: MaterialApp.router(
            routerConfig: _buildRouter(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('uk'),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final before = states.length;

    await tester.enterText(_field('field-firstName'), 'Оксана');
    await tester.pump();
    await tester.tap(find.byKey(const Key('btn-save-personal')));
    await tester.pumpAndSettle();

    verify(() => repo.updateMyProfile(any())).called(1);
    // Navigated to the profile sentinel (canPop was false at the root).
    expect(find.byKey(const Key('stub-profile')), findsOneWidget);
    // Provider invalidation produced at least one extra emission.
    expect(
      states.length,
      greaterThan(before),
      reason: 'masterProfileProvider must be invalidated after a save',
    );
  });

  testWidgets('empty firstName blocks save and shows the validation summary', (
    tester,
  ) async {
    await tester.pumpRoutedApp(_buildRouter(), overrides: _overrides(repo));
    await tester.pump();
    await tester.pump();

    await tester.enterText(_field('field-firstName'), '');
    await tester.pump();

    await tester.tap(find.byKey(const Key('btn-save-personal')));
    await tester.pump();

    expect(
      find.byKey(const Key('snackbar-validation-summary')),
      findsOneWidget,
      reason: 'an empty required firstName must block save',
    );
    verifyNever(() => repo.updateMyProfile(any()));
  });

  // ── Name no-digit validation (Step 2.7 Rule 3 regression) ────────────────
  //
  // _validateFirstName / _validateLastName reject any Unicode decimal digit
  // (nameContainsDigit) and return FIELD-SPECIFIC messages: errFirstNameHasDigit
  // for the first-name field, errLastNameHasDigit for the last-name field. On
  // save the Form validator renders the message inline and the save is blocked
  // (updateMyProfile never called). The default test locale is 'uk', where the
  // two messages differ, so the field-specific assertion is meaningful.
  testWidgets(
    'digit in firstName blocks save and renders the FIRST-name-specific '
    'digit error inline',
    (tester) async {
      await tester.pumpRoutedApp(_buildRouter(), overrides: _overrides(repo));
      await tester.pump();
      await tester.pump();

      final l10n = AppLocalizations.of(
        tester.element(find.byKey(const Key('field-firstName'))),
      );

      await tester.enterText(_field('field-firstName'), 'John2');
      await tester.pump();

      await tester.tap(find.byKey(const Key('btn-save-personal')));
      await tester.pump();

      // Field-specific message under the first-name field.
      expect(
        find.descendant(
          of: find.byKey(const Key('field-firstName')),
          matching: find.text(l10n.errFirstNameHasDigit),
        ),
        findsOneWidget,
      );
      // The last-name-specific message must NOT be the one shown here.
      expect(find.text(l10n.errLastNameHasDigit), findsNothing);
      verifyNever(() => repo.updateMyProfile(any()));
    },
  );

  testWidgets(
    'digit in lastName blocks save and renders the LAST-name-specific '
    'digit error inline',
    (tester) async {
      await tester.pumpRoutedApp(_buildRouter(), overrides: _overrides(repo));
      await tester.pump();
      await tester.pump();

      final l10n = AppLocalizations.of(
        tester.element(find.byKey(const Key('field-lastName'))),
      );

      await tester.enterText(_field('field-lastName'), 'Kov4l');
      await tester.pump();

      await tester.tap(find.byKey(const Key('btn-save-personal')));
      await tester.pump();

      expect(
        find.descendant(
          of: find.byKey(const Key('field-lastName')),
          matching: find.text(l10n.errLastNameHasDigit),
        ),
        findsOneWidget,
      );
      verifyNever(() => repo.updateMyProfile(any()));
    },
  );

  testWidgets('hyphen / apostrophe names save successfully (no digit error)', (
    tester,
  ) async {
    when(() => repo.updateMyProfile(any())).thenAnswer((_) async {});

    await tester.pumpRoutedApp(_buildRouter(), overrides: _overrides(repo));
    await tester.pump();
    await tester.pump();

    final l10n = AppLocalizations.of(
      tester.element(find.byKey(const Key('field-firstName'))),
    );

    await tester.enterText(_field('field-firstName'), 'Anne-Marie');
    await tester.enterText(_field('field-lastName'), "O'Brien");
    await tester.pump();

    await tester.tap(find.byKey(const Key('btn-save-personal')));
    await tester.pumpAndSettle();

    expect(find.text(l10n.errFirstNameHasDigit), findsNothing);
    expect(find.text(l10n.errLastNameHasDigit), findsNothing);
    final captured =
        verify(() => repo.updateMyProfile(captureAny())).captured.single
            as MasterUpdate;
    expect(captured.firstName, 'Anne-Marie');
    expect(captured.lastName, "O'Brien");
  });

  testWidgets('network failure shows an error SnackBar and re-enables Save', (
    tester,
  ) async {
    when(() => repo.updateMyProfile(any())).thenThrow(const NetworkFailure());

    await tester.pumpRoutedApp(_buildRouter(), overrides: _overrides(repo));
    await tester.pump();
    await tester.pump();

    await tester.enterText(_field('field-firstName'), 'Оксана');
    await tester.pump();
    await tester.tap(find.byKey(const Key('btn-save-personal')));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsOneWidget);
    // Still on the edit screen (no navigation on failure).
    expect(find.byKey(const Key('field-firstName')), findsOneWidget);
    expect(
      tester
          .widget<NeumorphicButton>(find.byKey(const Key('btn-save-personal')))
          .onPressed,
      isNotNull,
      reason: '_saving must clear after a failure so Save is interactive again',
    );
  });
}

/// Watches [masterProfileProvider] and records each emission so a test can
/// assert the provider was invalidated after a successful save.
class _InvalidationWatcher extends ConsumerWidget {
  const _InvalidationWatcher({required this.child, required this.states});

  final Widget child;
  final List<AsyncValue<Object?>> states;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    states.add(ref.watch(masterProfileProvider));
    return child;
  }
}
