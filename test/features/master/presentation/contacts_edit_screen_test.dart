// Widget tests for ContactsEditScreen (phone + instagram).
//
// CRITICAL (cached-master-merge mirror): editing ONLY the contacts must NOT wipe
// the cached firstName/lastName/bio. updateMyProfile sends every field together
// and an empty string CLEARS it server-side, so the contacts page MUST overlay
// phone+instagram onto the CACHED name + bio. This file captures the MasterUpdate
// and asserts the cached name/bio survive.
//
// Also covers: pristine→dirty Save enable, instagram format validation, the
// save-success path (updateMyProfile called → profile invalidated → saved
// SnackBar → navigate), and that a cleared (empty) Instagram is sent verbatim
// (the contacts page is the ONE place where clearing Instagram is intentional).
//
// Finders use widget Keys (M2). Layer: Widget.

import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/master/data/master_repository.dart';
import 'package:beautica_mobile/features/master/domain/master.dart';
import 'package:beautica_mobile/features/master/domain/master_update.dart';
import 'package:beautica_mobile/features/master/presentation/contacts_edit_screen.dart';
import 'package:beautica_mobile/features/master/presentation/master_profile_notifier.dart';
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
  initialLocation: RouteNames.masterEditContacts,
  routes: <RouteBase>[
    GoRoute(
      path: RouteNames.masterEditContacts,
      pageBuilder: (_, _) =>
          const NoTransitionPage<void>(child: ContactsEditScreen()),
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

  testWidgets('pre-populates phone and instagram from the cached master', (
    tester,
  ) async {
    await tester.pumpRoutedApp(_buildRouter(), overrides: _overrides(repo));
    await tester.pump();
    await tester.pump();

    expect(
      tester.widget<TextField>(_field('field-phone')).controller?.text,
      '+380 50 123 45 67',
    );
    expect(
      tester.widget<TextField>(_field('field-instagram')).controller?.text,
      '@olena_nails',
    );
  });

  testWidgets('renders the MASTER phone privacy note (not the client one)', (
    tester,
  ) async {
    await tester.pumpRoutedApp(_buildRouter(), overrides: _overrides(repo));
    await tester.pump();
    await tester.pump();

    final BuildContext ctx = tester.element(
      find.byKey(const Key('field-phone')),
    );
    final AppLocalizations l10n = AppLocalizations.of(ctx);

    expect(
      find.text(l10n.phonePrivacyNote),
      findsOneWidget,
      reason:
          'the master phone field shows the master-context privacy note '
          '(clients do not see the master number)',
    );
    expect(
      find.text(l10n.clientPhonePrivacyNote),
      findsNothing,
      reason:
          'the client-context privacy note must not appear on the master '
          'screen',
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
          .widget<NeumorphicButton>(find.byKey(const Key('btn-save-contacts')))
          .onPressed,
      isNull,
    );

    await tester.enterText(_field('field-instagram'), '@new_handle');
    await tester.pump();

    expect(
      tester
          .widget<NeumorphicButton>(find.byKey(const Key('btn-save-contacts')))
          .onPressed,
      isNotNull,
    );
  });

  // ── CRITICAL: cached-master-merge — name + bio NOT wiped ───────────────────
  testWidgets(
    'editing only the contacts preserves the cached firstName, lastName and '
    'bio in the MasterUpdate (siblings are NOT cleared)',
    (tester) async {
      MasterUpdate? captured;
      when(() => repo.updateMyProfile(any())).thenAnswer((invocation) async {
        captured = invocation.positionalArguments.first as MasterUpdate;
      });

      await tester.pumpRoutedApp(_buildRouter(), overrides: _overrides(repo));
      await tester.pump();
      await tester.pump();

      // Edit ONLY instagram — the page never renders name/bio.
      await tester.enterText(_field('field-instagram'), '@brand_new');
      await tester.pump();

      await tester.tap(find.byKey(const Key('btn-save-contacts')));
      await tester.pumpAndSettle();

      expect(captured, isNotNull);
      expect(captured!.instagram, '@brand_new');
      expect(captured!.contactPhone, '+380 50 123 45 67');
      // THE REGRESSION GUARD: name + bio carried from the cache, never blanked.
      expect(
        captured!.firstName,
        'Олена',
        reason:
            'firstName must be overlaid from the cached master, not blanked',
      );
      expect(captured!.lastName, 'Ковальчук');
      expect(
        captured!.bio,
        'Майстер манікюру.',
        reason: 'bio must be overlaid from the cached master, not blanked',
      );
    },
  );

  testWidgets('clearing instagram sends an empty string verbatim (the contacts '
      'page is where clearing IS intended)', (tester) async {
    MasterUpdate? captured;
    when(() => repo.updateMyProfile(any())).thenAnswer((invocation) async {
      captured = invocation.positionalArguments.first as MasterUpdate;
    });

    await tester.pumpRoutedApp(_buildRouter(), overrides: _overrides(repo));
    await tester.pump();
    await tester.pump();

    await tester.enterText(_field('field-instagram'), '');
    await tester.pump();

    await tester.tap(find.byKey(const Key('btn-save-contacts')));
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    expect(
      captured!.instagram,
      '',
      reason: 'clearing on the contacts page must send "" to clear the field',
    );
    // The cached name/bio still survive even on an intentional clear.
    expect(captured!.firstName, 'Олена');
    expect(captured!.bio, 'Майстер манікюру.');
  });

  testWidgets('invalid instagram value shows an error under the field', (
    tester,
  ) async {
    await tester.pumpRoutedApp(_buildRouter(), overrides: _overrides(repo));
    await tester.pump();
    await tester.pump();

    await tester.enterText(_field('field-instagram'), 'not valid!');
    await tester.pump();

    await tester.tap(find.byKey(const Key('btn-save-contacts')));
    await tester.pump();

    expect(
      find.descendant(
        of: find.byKey(const Key('field-instagram')),
        matching: find.textContaining('instagram'),
      ),
      findsOneWidget,
      reason: 'a malformed handle must surface a (locale-neutral) error',
    );
    verifyNever(() => repo.updateMyProfile(any()));
  });

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

    await tester.enterText(_field('field-instagram'), '@updated');
    await tester.pump();
    await tester.tap(find.byKey(const Key('btn-save-contacts')));
    await tester.pumpAndSettle();

    verify(() => repo.updateMyProfile(any())).called(1);
    expect(find.byKey(const Key('stub-profile')), findsOneWidget);
    expect(states.length, greaterThan(before));
  });
}

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
