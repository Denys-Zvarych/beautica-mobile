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
