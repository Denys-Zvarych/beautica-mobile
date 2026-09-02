// Phase 21.4 QA follow-up (2026-08-29) — Widget tests for InviteStaffScreen +
// the InviteStaff notifier's screen-owned guards.
//
// mobile-dev shipped this screen without its own test file (item 10 of the
// implementation plan, skipped) — `salon_management_profile_screen_test
// .dart` only proves the «+» staff tile NAVIGATES to this route via a
// trivial marker; nothing in the suite exercised this screen's own form,
// role toggle, error branching, or lifecycle guards. This file closes that
// gap.
//
// Covers:
//   1. Role toggle defaults to Майстер (SALON_MASTER) and switching to
//      Адміністратор flips the alignment + swaps the description copy.
//   2. Invalid/empty email blocks submit — never reaches the repository,
//      surfaces the inline field error + the validation-summary snack.
//   3. A valid submit sends the CORRECT (salonId, email, role) tuple to the
//      repository for BOTH roles, shows the success snack, and pops.
//   4. 403 / 429 / generic (NetworkFailure + an unmapped ServerFailure)
//      failures each surface their OWN distinct localized copy and do NOT
//      pop.
//   5. The `_submitting` re-entry guard: two taps with NO pump between them
//      (mirrors `booking_confirm_test.dart`'s proven
//      `should_submitOnce_when_ctaDoubleTapped_onWalkInPath` no-pump idiom,
//      adapted with a Completer-gated notifier override — a plain
//      `FakeSalonRepository` call has no real async gap, so the whole
//      submit→repo→pop cycle can resolve inside a SINGLE `tester.tap()`
//      await, leaving nothing for a second tap to race against) issue
//      exactly ONE `InviteStaff.submit` call.
//   6. The `PopScope` back-guard (system back) AND the explicit top-bar
//      back-icon guard both block navigation while a submit is genuinely
//      in flight (the SAME Completer-gated notifier override, this time
//      pumped once so the pending state survives a real frame — needed
//      because `PopScope.canPop` is read from the LAST BUILT frame, so the
//      no-pump trick from (5) cannot prove this on its own) and show the
//      in-progress hint; both guards clear once the request resolves, and
//      a normal (idle) back still works immediately.
//   7. mobile-perf LOW regression pin: the role-description style and the
//      selected segment-label style are the SAME static `TextStyle`
//      instance across a rebuild that leaves their inputs unchanged, not a
//      fresh `.copyWith()` allocation.
//
// mobile-perf MEDIUM `RepaintBoundary` added around `_RoleToggle`'s
// animating `Stack` — a bare `find.byType(RepaintBoundary)` presence check
// would be coverage theater (removing it changes nothing a widget test can
// observe — no rendered output or provider state changes, only frame/repaint
// cost). Instead, the 'role toggle' group's own
// 'the RepaintBoundary sits BETWEEN the shadow CustomPaint and the animating
// Stack' test pins the TOPOLOGY the fix depends on: the boundary must be a
// descendant of `NeumorphicInset`'s `CustomPaint(painter: _InsetShadowPainter
// ...)` (so the boundary isolates repaints FROM that raster) and an ancestor
// of the `AnimatedAlign` (so it actually contains the animating subtree).
// Mutation-probed 2026-08-29: hoisting the boundary to wrap `NeumorphicInset`
// itself (i.e. above the `CustomPaint`, the exact regression this guards)
// turns this test red. Still NOT covered: the actual raster-count/frame-cost
// savings — proving that needs a `mobile-perf` timeline/repaint-count
// profiling harness, out of scope for this file.
//
// Strategy mirrors `register_salon_screen_test.dart`: a real GoRouter (via
// `pumpRoutedApp`) with a source-marker route to pop back to, and
// `salonRepositoryProvider` overridden by the shared `FakeSalonRepository`.

import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/theme/velvet_geometry.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:dio/dio.dart';
import 'package:beautica_mobile/features/salon/application/invite_staff_notifier.dart';
import 'package:beautica_mobile/features/salon/data/salon_repository.dart';
import 'package:beautica_mobile/features/salon/domain/invite_status.dart';
import 'package:beautica_mobile/features/salon/domain/salon.dart';
import 'package:beautica_mobile/features/salon/domain/salon_invite.dart';
import 'package:beautica_mobile/features/salon/domain/salon_staff_member.dart';
import 'package:beautica_mobile/features/salon/presentation/invite_staff_screen.dart';
import 'package:beautica_mobile/features/salon/presentation/widgets/salon_invite_row.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:beautica_mobile/shared/feedback/velvet_snack.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../helpers/fakes/fake_salon_repository.dart';
import '../../../helpers/pump_app.dart';
import '../../../helpers/velvet_snack_matchers.dart';

const String _kSalonId = 'salon-1';
const Salon _kSalon = Salon(id: _kSalonId, name: 'Салон «Вельвет»');

/// Notifier override that BLOCKS `submit()` on a caller-controlled
/// [Completer] — the only way to get a genuinely pending `_submitting`
/// state that survives a real `pump()` (a plain [FakeSalonRepository] call
/// resolves on the next microtask, too fast to observe mid-flight after a
/// frame). Mirrors `settings_hub_screen_test.dart`'s `_TrackingAuthNotifier`
/// (`await Completer<void>().future` block-forever precedent), but keeps
/// the gate open to completion so the guard-clears-after path is provable
/// too.
class _BlockingInviteStaff extends InviteStaff {
  final Completer<Failure?> gate = Completer<Failure?>();
  int calls = 0;

  @override
  Future<Failure?> submit({
    required String salonId,
    required String email,
    required UserRole role,
  }) {
    calls++;
    return gate.future;
  }
}

GoRouter _router() => GoRouter(
  initialLocation: '/manage-marker',
  routes: <RouteBase>[
    GoRoute(
      path: '/manage-marker',
      builder: (context, state) => const Scaffold(key: Key('manage-marker')),
    ),
    GoRoute(
      path: RouteNames.salonInviteStaff(_kSalonId),
      builder: (context, state) => const InviteStaffScreen(salonId: _kSalonId),
    ),
  ],
);

Future<AppLocalizations> _l10n() =>
    AppLocalizations.delegate.load(const Locale('uk'));

Future<GoRouter> _pumpInvite(
  WidgetTester tester, {
  required List<Object> overrides,
}) async {
  final GoRouter router = _router();
  addTearDown(router.dispose);
  await tester.pumpRoutedApp(router, overrides: overrides);
  await tester.pumpAndSettle();
  unawaited(router.push(RouteNames.salonInviteStaff(_kSalonId)));
  await tester.pumpAndSettle();
  return router;
}

Finder get _emailField => find.byKey(const ValueKey<String>('invite_email'));
Finder get _submitCta => find.byKey(const Key('send_invite'));
Finder get _adminIcon => find.byIcon(Icons.admin_panel_settings_outlined);
Finder get _masterIcon => find.byIcon(Icons.brush_outlined);
Finder get _backIcon => find.byIcon(Icons.arrow_back_ios_new_rounded);

/// A MIXED-status invite history — the salon's WHOLE outbound record, exactly
/// as `GET /salons/{salonId}/invites` returns it.
///
/// Deliberately mixed and deliberately NOT pending-first: this file had NO
/// `SalonInvite` fixture at all before 2026-09-02, so the invite FORM's
/// pending-only filter (`SalonInvitesState.pending`, derived in
/// `salon_invites_notifier.dart` and consumed by `invite_staff_screen.dart`)
/// was unguarded at every layer. Dropping that filter dumps the salon's
/// entire history — accepted, expired and revoked invitations included —
/// underneath a form whose whole point is "who is still waiting for an
/// answer".
List<SalonInvite> _mixedInvites() => <SalonInvite>[
  _inviteFixture('inv-accepted', InviteStatus.accepted),
  _inviteFixture('inv-pending-1', InviteStatus.pending),
  _inviteFixture('inv-expired', InviteStatus.expired),
  _inviteFixture('inv-cancelled', InviteStatus.cancelled),
  _inviteFixture('inv-pending-2', InviteStatus.pending),
  _inviteFixture('inv-unknown', InviteStatus.unknown),
];

/// The two ids the form's block must show, and the four it must not.
const List<String> _kPendingIds = <String>['inv-pending-1', 'inv-pending-2'];
const List<String> _kTerminalIds = <String>[
  'inv-accepted',
  'inv-expired',
  'inv-cancelled',
  'inv-unknown',
];

/// `createdAt` reads the HOST clock, and so does the row's «надіслано …»
/// caption via `formatRelativeDate` — both live, never mixed (clock-coherence
/// invariant).
final DateTime _kInviteSentAt = DateTime.now().subtract(
  const Duration(days: 2),
);

SalonInvite _inviteFixture(String id, InviteStatus status) => SalonInvite(
  inviteId: id,
  recipientEmail: '$id@beautica.ua',
  role: SalonStaffRole.master,
  status: status,
  createdAt: _kInviteSentAt,
  expiresAt: _kInviteSentAt.add(const Duration(hours: 48)),
);

void main() {
  group('role toggle', () {
    testWidgets(
      'defaults to Майстер (SALON_MASTER) — right-aligned pillow + master '
      'description',
      (tester) async {
        final repo = FakeSalonRepository(salon: _kSalon);
        await _pumpInvite(
          tester,
          overrides: <Object>[salonRepositoryProvider.overrideWithValue(repo)],
        );
        final l10n = await _l10n();

        expect(
          tester.widget<AnimatedAlign>(find.byType(AnimatedAlign)).alignment,
          Alignment.centerRight,
          reason:
              'SALON_MASTER is the default role — pillow starts on the '
              'right (master) segment',
        );
        expect(
          find.text(l10n.inviteStaffRoleMasterDescription),
          findsOneWidget,
        );
        expect(find.text(l10n.inviteStaffRoleAdminDescription), findsNothing);
      },
    );

    testWidgets('tapping Адміністратор flips the pillow left and swaps the '
        'description', (tester) async {
      final repo = FakeSalonRepository(salon: _kSalon);
      await _pumpInvite(
        tester,
        overrides: <Object>[salonRepositoryProvider.overrideWithValue(repo)],
      );
      final l10n = await _l10n();

      await tester.tap(_adminIcon);
      await tester.pumpAndSettle();

      expect(
        tester.widget<AnimatedAlign>(find.byType(AnimatedAlign)).alignment,
        Alignment.centerLeft,
      );
      expect(find.text(l10n.inviteStaffRoleAdminDescription), findsOneWidget);
      expect(find.text(l10n.inviteStaffRoleMasterDescription), findsNothing);

      // Tapping Майстер again flips it back.
      await tester.tap(_masterIcon);
      await tester.pumpAndSettle();
      expect(
        tester.widget<AnimatedAlign>(find.byType(AnimatedAlign)).alignment,
        Alignment.centerRight,
      );
    });

    // mobile-perf LOW fix (2026-08-29) — pins the hoisted static TextStyle
    // instances (`_roleDescriptionStyle` in `_InviteStaffScreenState`,
    // `_selectedLabelStyle`/`_unselectedLabelStyle` in `_RoleSegment`).
    // Both classes are file-private, so this cannot read the static fields
    // directly — instead it captures the RENDERED `Text.style` before and
    // after a rebuild that leaves the selection state UNCHANGED and asserts
    // `identical()`. This is load-bearing, not vacuous: `.copyWith()`
    // unconditionally allocates a NEW `TextStyle` even when called with
    // values equal to the original, so a regression back to an inline
    // `.copyWith()` call would make `identical()` false here (verified by
    // mutation probe — reverting the hoist turns this test red).
    testWidgets(
      'the role-description style and the selected segment-label style are '
      'STATIC instances, not re-allocated via .copyWith() on every rebuild',
      (tester) async {
        final repo = FakeSalonRepository(salon: _kSalon);
        await _pumpInvite(
          tester,
          overrides: <Object>[salonRepositoryProvider.overrideWithValue(repo)],
        );
        final l10n = await _l10n();

        final TextStyle? descStyleBefore = tester
            .widget<Text>(find.text(l10n.inviteStaffRoleMasterDescription))
            .style;
        final TextStyle? masterLabelStyleBefore = tester
            .widget<Text>(find.text(l10n.inviteStaffRoleMaster))
            .style;

        // Tapping the ALREADY-selected Майстер segment still calls
        // `setState(() => _role = r)` even though `r == _role` — Dart does
        // not skip a setState just because the new value equals the old
        // one — so the whole subtree (including `_RoleToggle`/
        // `_RoleSegment`) rebuilds with the SAME selection state, isolating
        // "did this rebuild re-allocate the style" from "did the SELECTION
        // change".
        await tester.tap(_masterIcon);
        await tester.pumpAndSettle();

        final TextStyle? descStyleAfter = tester
            .widget<Text>(find.text(l10n.inviteStaffRoleMasterDescription))
            .style;
        final TextStyle? masterLabelStyleAfter = tester
            .widget<Text>(find.text(l10n.inviteStaffRoleMaster))
            .style;

        expect(
          identical(descStyleBefore, descStyleAfter),
          isTrue,
          reason:
              '_roleDescriptionStyle must be the SAME static instance '
              'across rebuilds, not a fresh .copyWith() allocation',
        );
        expect(
          identical(masterLabelStyleBefore, masterLabelStyleAfter),
          isTrue,
          reason:
              '_selectedLabelStyle must be the SAME static instance across '
              'rebuilds for an UNCHANGED selection state',
        );
      },
    );

    // mobile-perf MEDIUM regression pin (topology, not presence) — see the
    // file-header doc above for why a bare `find.byType(RepaintBoundary)`
    // check is coverage theater. This asserts the two edges the fix
    // actually depends on:
    //   1. the `RepaintBoundary` is a DESCENDANT of `NeumorphicInset`'s own
    //      shadow-painting `CustomPaint(painter: _InsetShadowPainter...)` —
    //      if a future edit hoists the boundary above that `CustomPaint`
    //      (e.g. wrapping `NeumorphicInset` itself instead of the inner
    //      `Stack`), the boundary no longer isolates the `AnimatedAlign`'s
    //      per-frame repaint from the shadow raster, silently reintroducing
    //      the original finding.
    //   2. the animating `AnimatedAlign` is a DESCENDANT of that SAME
    //      `RepaintBoundary` — proves the boundary actually contains the
    //      animating subtree, not some unrelated boundary elsewhere in the
    //      tree.
    // Both finders are scoped off `find.byType(AnimatedAlign)` (proven
    // unique on this screen by the two tests above) rather than `.first`,
    // because the screen also renders a SECOND `NeumorphicInset` (inside
    // `NeumorphicTextField` for the email field) with its own matching
    // `CustomPaint` — an unscoped predicate would be ambiguous, and an
    // ambiguous finder that happens to resolve correctly today is exactly
    // the kind of assertion that rots.
    testWidgets(
      'the RepaintBoundary sits BETWEEN the shadow CustomPaint and the '
      'animating Stack (topology, not mere presence)',
      (tester) async {
        final repo = FakeSalonRepository(salon: _kSalon);
        await _pumpInvite(
          tester,
          overrides: <Object>[salonRepositoryProvider.overrideWithValue(repo)],
        );

        // `NeumorphicInset`'s own shadow `CustomPaint` — the one that is an
        // ANCESTOR of `_RoleToggle`'s `AnimatedAlign` (excludes the email
        // field's own matching `CustomPaint`, which is not on that path).
        final Finder shadowCustomPaint = find.ancestor(
          of: find.byType(AnimatedAlign),
          matching: find.byWidgetPredicate(
            (Widget w) =>
                w is CustomPaint &&
                w.painter.runtimeType.toString() == '_InsetShadowPainter',
          ),
        );
        expect(
          shadowCustomPaint,
          findsOneWidget,
          reason:
              'expected exactly one _InsetShadowPainter CustomPaint on the '
              'AnimatedAlign ancestor path',
        );

        // The RepaintBoundary under test is a DESCENDANT of that CustomPaint
        // — `NeumorphicInset`'s own PRE-EXISTING outer RepaintBoundary is an
        // ANCESTOR of the CustomPaint instead, so it is excluded here by
        // construction, not by `.first`/ordering luck.
        final Finder targetBoundary = find.descendant(
          of: shadowCustomPaint,
          matching: find.byType(RepaintBoundary),
        );
        expect(
          targetBoundary,
          findsOneWidget,
          reason:
              'the RepaintBoundary must sit BELOW the shadow CustomPaint so '
              "the AnimatedAlign's per-frame repaint never reaches "
              '_InsetShadowPainter',
        );

        // And the animating Stack/AnimatedAlign must be INSIDE that same
        // boundary, not merely somewhere below the CustomPaint.
        expect(
          find.descendant(of: targetBoundary, matching: find.byType(Stack)),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: targetBoundary,
            matching: find.byType(AnimatedAlign),
          ),
          findsOneWidget,
          reason:
              'the animating AnimatedAlign must be a descendant of the '
              'RepaintBoundary under test, so its repaints are actually '
              'contained by it',
        );
      },
    );
  });

  group('email validation', () {
    testWidgets(
      'an empty submit blocks — never reaches the repository, surfaces the '
      'inline error + the validation-summary snack',
      (tester) async {
        final repo = FakeSalonRepository(salon: _kSalon);
        await _pumpInvite(
          tester,
          overrides: <Object>[salonRepositoryProvider.overrideWithValue(repo)],
        );
        final l10n = await _l10n();

        await tester.tap(_submitCta);
        await pumpVelvetSnackIn(tester);

        expect(repo.inviteRequests, isEmpty);
        expect(find.text(l10n.errEmailRequired), findsOneWidget);
        expectVelvetSnack(
          l10n.editValidationSummary,
          variant: VelvetSnackVariant.error,
        );
        await pumpPastVelvetSnack(tester);
      },
    );

    testWidgets(
      'a malformed email blocks submit with the format-specific inline '
      'error',
      (tester) async {
        final repo = FakeSalonRepository(salon: _kSalon);
        await _pumpInvite(
          tester,
          overrides: <Object>[salonRepositoryProvider.overrideWithValue(repo)],
        );
        final l10n = await _l10n();

        await tester.enterText(_emailField, 'not-an-email');
        await tester.pump();
        await tester.tap(_submitCta);
        await pumpVelvetSnackIn(tester);

        expect(repo.inviteRequests, isEmpty);
        expect(find.text(l10n.errEmailInvalid), findsOneWidget);
        await pumpPastVelvetSnack(tester);
      },
    );
  });

  group('submit — success', () {
    testWidgets(
      'a valid email with the DEFAULT (Майстер) role sends the correct '
      'tuple, shows the success snack, and pops back to the caller',
      (tester) async {
        final repo = FakeSalonRepository(salon: _kSalon);
        await _pumpInvite(
          tester,
          overrides: <Object>[salonRepositoryProvider.overrideWithValue(repo)],
        );
        final l10n = await _l10n();

        await tester.enterText(_emailField, 'master@beautica.ua');
        await tester.pump();
        await tester.tap(_submitCta);
        await tester.pump();
        await pumpVelvetSnackIn(tester);

        expect(repo.inviteRequests, hasLength(1));
        final sent = repo.inviteRequests.single;
        expect(sent.salonId, _kSalonId);
        expect(sent.email, 'master@beautica.ua');
        expect(sent.role, UserRole.salonMaster);

        expectVelvetSnack(
          l10n.inviteStaffSuccess,
          variant: VelvetSnackVariant.success,
        );
        // Popped back — mirrors `register_salon_screen_test.dart`'s own
        // pop-confirmation shape (asserting the marker is back, not that
        // the popped screen is instantly gone — the MaterialPage exit
        // transition can still be animating at this pump depth).
        expect(find.byKey(const Key('manage-marker')), findsOneWidget);
        await pumpPastVelvetSnack(tester);
      },
    );

    testWidgets(
      'switching to Адміністратор before submit sends role=SALON_ADMIN',
      (tester) async {
        final repo = FakeSalonRepository(salon: _kSalon);
        await _pumpInvite(
          tester,
          overrides: <Object>[salonRepositoryProvider.overrideWithValue(repo)],
        );

        await tester.tap(_adminIcon);
        await tester.pumpAndSettle();
        await tester.enterText(_emailField, 'admin@beautica.ua');
        await tester.pump();
        await tester.tap(_submitCta);
        await tester.pump();
        await pumpVelvetSnackIn(tester);

        expect(repo.inviteRequests, hasLength(1));
        final sent = repo.inviteRequests.single;
        expect(sent.email, 'admin@beautica.ua');
        expect(sent.role, UserRole.salonAdmin);
        await pumpPastVelvetSnack(tester);
      },
    );
  });

  group('submit — failure copy', () {
    Future<void> submitAndExpectError(
      WidgetTester tester,
      Failure error,
      String Function(AppLocalizations) expected,
    ) async {
      final repo = FakeSalonRepository(salon: _kSalon)..inviteError = error;
      await _pumpInvite(
        tester,
        overrides: <Object>[salonRepositoryProvider.overrideWithValue(repo)],
      );
      final l10n = await _l10n();

      await tester.enterText(_emailField, 'someone@beautica.ua');
      await tester.pump();
      await tester.tap(_submitCta);
      await tester.pump();
      await pumpVelvetSnackIn(tester);

      expect(repo.inviteRequests, hasLength(1));
      expectVelvetSnack(expected(l10n), variant: VelvetSnackVariant.error);
      // Never popped on failure.
      expect(find.byKey(const Key('manage-marker')), findsNothing);
      expect(find.byType(InviteStaffScreen), findsOneWidget);
      await pumpPastVelvetSnack(tester);
    }

    testWidgets('403 shows the forbidden-specific copy', (tester) async {
      await submitAndExpectError(
        tester,
        const ServerFailure(statusCode: 403),
        (l10n) => l10n.inviteStaffErrorForbidden,
      );
    });

    testWidgets('429 shows the rate-limited-specific copy', (tester) async {
      await submitAndExpectError(
        tester,
        const ServerFailure(statusCode: 429),
        (l10n) => l10n.inviteStaffErrorRateLimited,
      );
    });

    // mobile-qa CRITICAL regression pin (2026-08-29) — the REAL
    // `ErrorMapperInterceptor` never actually produces a `ServerFailure` for
    // 403 or a bare 429 (only 401/404/409/5xx and two hard-coded-path 429s
    // are mapped that way — see `error_mapper_interceptor_test.dart`'s own
    // `'HTTP 403 (unmapped status) → UnknownFailure'` test). It produces
    // `UnknownFailure(cause: <the DioException>)` instead. The two tests
    // above (`ServerFailure(statusCode: 403/429)` injected directly) would
    // have stayed GREEN even if `_errorMessage` only ever checked
    // `is ServerFailure` — they do not exercise the shape the interceptor
    // ACTUALLY produces. These two do, and are what actually caught the bug
    // (found via `integration_test/salon_management_profile_flow_test
    // .dart`'s real end-to-end 403 case, then reproduced here so CI itself
    // — which does not run `integration_test/` — also guards it).
    testWidgets('an UnknownFailure wrapping a REAL 403 DioException shows the '
        'forbidden-specific copy (the shape the real interceptor produces)', (
      tester,
    ) async {
      await submitAndExpectError(
        tester,
        UnknownFailure(
          cause: DioException(
            requestOptions: RequestOptions(path: '/api/v1/salons/x/invite'),
            response: Response<dynamic>(
              requestOptions: RequestOptions(path: '/api/v1/salons/x/invite'),
              statusCode: 403,
            ),
          ),
        ),
        (l10n) => l10n.inviteStaffErrorForbidden,
      );
    });

    testWidgets(
      'an UnknownFailure wrapping a REAL 429 DioException shows the '
      'rate-limited-specific copy (the shape the real interceptor produces)',
      (tester) async {
        await submitAndExpectError(
          tester,
          UnknownFailure(
            cause: DioException(
              requestOptions: RequestOptions(path: '/api/v1/salons/x/invite'),
              response: Response<dynamic>(
                requestOptions: RequestOptions(path: '/api/v1/salons/x/invite'),
                statusCode: 429,
              ),
            ),
          ),
          (l10n) => l10n.inviteStaffErrorRateLimited,
        );
      },
    );

    testWidgets('a NetworkFailure falls back to the generic copy', (
      tester,
    ) async {
      await submitAndExpectError(
        tester,
        const NetworkFailure(),
        (l10n) => l10n.inviteStaffErrorGeneric,
      );
    });

    testWidgets(
      'an unmapped ServerFailure status (500) falls back to the generic '
      'copy — NOT the 403/429 branches',
      (tester) async {
        await submitAndExpectError(
          tester,
          const ServerFailure(statusCode: 500),
          (l10n) => l10n.inviteStaffErrorGeneric,
        );
      },
    );
  });

  group('re-entry guard (screen-owned _submitting field)', () {
    testWidgets('two taps with NO pump between them issue exactly ONE '
        '`InviteStaff.submit` call — a Completer-gated notifier proves the '
        'window deterministically, rather than racing a fast fake repository '
        '(a plain FakeSalonRepository call has no real async gap, so the '
        'ENTIRE submit→repo→pop cycle can resolve inside a single '
        'tester.tap() await and there is nothing left for a second tap to '
        'race against)', (tester) async {
      final blocking = _BlockingInviteStaff();
      await _pumpInvite(
        tester,
        overrides: <Object>[
          salonRepositoryProvider.overrideWithValue(
            FakeSalonRepository(salon: _kSalon),
          ),
          inviteStaffProvider.overrideWith(() => blocking),
        ],
      );

      await tester.enterText(_emailField, 'guard@beautica.ua');
      await tester.pump();

      // NO pump between the two taps: the first tap's onTapUp runs
      // `_submit()`'s synchronous prefix (validation + `setState(() =>
      // _submitting = true)`) and then genuinely suspends on
      // `blocking.gate.future` — it can never resolve underneath us. The
      // widget has NOT rebuilt yet (no pump), so the second tap still
      // hits the OLD (pre-rebuild, not-yet-disabled) button and fires
      // `onTapUp` → `_submit()` again — this time hitting the
      // `if (_submitting) return;` guard at its very top.
      await tester.tap(_submitCta);
      await tester.tap(_submitCta);
      await tester.pump();

      expect(
        blocking.calls,
        1,
        reason:
            'the internal `if (_submitting) return;` guard in _submit() '
            'must block the SECOND onTapUp invocation, which fires before '
            'the first setState-triggered rebuild disables the button',
      );

      // Clean up the pending future so the test does not leak it.
      blocking.gate.complete(null);
      await tester.pumpAndSettle();
    });
  });

  group('PopScope / back-icon guard while genuinely in flight', () {
    testWidgets('system back and the top-bar back icon are BOTH blocked while '
        'submitting, show the in-progress hint, and both clear once the '
        'request resolves', (tester) async {
      final blocking = _BlockingInviteStaff();
      await _pumpInvite(
        tester,
        overrides: <Object>[
          salonRepositoryProvider.overrideWithValue(
            FakeSalonRepository(salon: _kSalon),
          ),
          inviteStaffProvider.overrideWith(() => blocking),
        ],
      );
      final l10n = await _l10n();

      await tester.enterText(_emailField, 'pending@beautica.ua');
      await tester.pump();
      await tester.tap(_submitCta);
      await tester.pump();

      expect(blocking.calls, 1);
      expect(
        tester.widget<NeumorphicButton>(_submitCta).loading,
        isTrue,
        reason:
            'the CTA must show its loading state while genuinely '
            'in flight',
      );
      expect(
        tester.widget<NeumorphicTextField>(_emailField).enabled,
        isFalse,
        reason: 'the email field must be disabled while submitting',
      );

      // System back (PopScope.canPop reads the ALREADY-REBUILT frame from
      // the `pump()` above, so this genuinely exercises canPop:false).
      final bool handled = await tester.binding.handlePopRoute();
      await pumpVelvetSnackIn(tester);

      expect(
        handled,
        isTrue,
        reason: 'PopScope must intercept the system back while submitting',
      );
      expectVelvetSnack(
        l10n.inviteStaffSubmitInProgressHint,
        variant: VelvetSnackVariant.info,
      );
      expect(find.byType(InviteStaffScreen), findsOneWidget);
      expect(find.byKey(const Key('manage-marker')), findsNothing);
      // NOT `pumpPastVelvetSnack` — its trailing `pumpAndSettle()` can never
      // terminate here: the CTA's indeterminate `CircularProgressIndicator`
      // (`NeumorphicButton(loading: true)`) is STILL genuinely animating
      // (the gate is not completed yet), and an indeterminate spinner's
      // repeating Ticker means SOME frame is always pending. Drain just the
      // snack's own fixed lifecycle instead.
      await tester.pump(
        VelvetSnackMotion.enter +
            VelvetSnackMotion.dwell +
            VelvetSnackMotion.exit,
      );

      // The explicit top-bar back-icon guard (_onBack) — PopScope.canPop
      // does not cover this imperative context.pop() path, so it needs
      // its own proof.
      await tester.tap(_backIcon);
      await pumpVelvetSnackIn(tester);
      expectVelvetSnack(
        l10n.inviteStaffSubmitInProgressHint,
        variant: VelvetSnackVariant.info,
      );
      expect(find.byType(InviteStaffScreen), findsOneWidget);
      // Same reason as above — the CTA is still genuinely loading.
      await tester.pump(
        VelvetSnackMotion.enter +
            VelvetSnackMotion.dwell +
            VelvetSnackMotion.exit,
      );

      // Resolve the request — both guards must clear.
      blocking.gate.complete(null);
      await tester.pump();
      await pumpVelvetSnackIn(tester);

      expectVelvetSnack(
        l10n.inviteStaffSuccess,
        variant: VelvetSnackVariant.success,
      );
      expect(find.byKey(const Key('manage-marker')), findsOneWidget);
      await pumpPastVelvetSnack(tester);
    });

    testWidgets(
      'an IDLE (not submitting) back tap navigates immediately — the guard '
      'is not overly restrictive',
      (tester) async {
        final repo = FakeSalonRepository(salon: _kSalon);
        await _pumpInvite(
          tester,
          overrides: <Object>[salonRepositoryProvider.overrideWithValue(repo)],
        );

        await tester.tap(_backIcon);
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('manage-marker')), findsOneWidget);
      },
    );
  });

  // ── The pending-only filter on the invite FORM ───────────────────────────
  //
  // MUTATION-PROBED 2026-09-02: swapping `history.pending` for
  // `history.invites` in `invite_staff_screen.dart` (i.e. dropping the
  // filter, the exact regression this guards) turns every test in this group
  // RED. The observed failures are in the QA report.
  group('inline pending block renders ONLY pending rows', () {
    testWidgets('a MIXED history yields exactly the two pending rows — the '
        'accepted / expired / cancelled / unknown rows are absent', (
      tester,
    ) async {
      final repo = FakeSalonRepository(
        salon: _kSalon,
        salonInvites: _mixedInvites(),
      );
      await _pumpInvite(
        tester,
        overrides: <Object>[salonRepositoryProvider.overrideWithValue(repo)],
      );

      expect(find.byType(SalonInviteRow), findsNWidgets(2));
      for (final String id in _kPendingIds) {
        expect(
          find.byKey(salonInviteRowKey(id)),
          findsOneWidget,
          reason: '$id is still waiting for an answer — it belongs here',
        );
      }
      for (final String id in _kTerminalIds) {
        expect(
          find.byKey(salonInviteRowKey(id)),
          findsNothing,
          reason:
              '$id is HISTORY — it belongs on «Надіслані запрошення», never '
              'under the invite form',
        );
      }
    });

    testWidgets('the block header counts the PENDING rows, not the whole '
        'history', (tester) async {
      final repo = FakeSalonRepository(
        salon: _kSalon,
        salonInvites: _mixedInvites(),
      );
      await _pumpInvite(
        tester,
        overrides: <Object>[salonRepositoryProvider.overrideWithValue(repo)],
      );

      expect(
        find.descendant(
          of: find.byKey(const Key('invite-pending-header')),
          matching: find.text('2'),
        ),
        findsOneWidget,
        reason:
            'a 6 here would mean the header is counting the history the '
            'block below is not showing',
      );
      // The fixture genuinely MOVES this assertion: 6 rows in, 2 expected.
      expect(_mixedInvites(), hasLength(6));
    });

    testWidgets('a history with NO pending rows renders no block at all — not '
        'an empty header over the terminal rows', (tester) async {
      final repo = FakeSalonRepository(
        salon: _kSalon,
        salonInvites: <SalonInvite>[
          _inviteFixture('inv-accepted', InviteStatus.accepted),
          _inviteFixture('inv-expired', InviteStatus.expired),
          _inviteFixture('inv-cancelled', InviteStatus.cancelled),
        ],
      );
      await _pumpInvite(
        tester,
        overrides: <Object>[salonRepositoryProvider.overrideWithValue(repo)],
      );

      expect(find.byType(SalonInviteRow), findsNothing);
      expect(find.byKey(const Key('invite-pending-header')), findsNothing);
    });

    testWidgets('cancelling a pending row DROPS it from this block while the '
        'other pending row stays', (tester) async {
      final repo = FakeSalonRepository(
        salon: _kSalon,
        salonInvites: _mixedInvites(),
      );
      await _pumpInvite(
        tester,
        overrides: <Object>[salonRepositoryProvider.overrideWithValue(repo)],
      );

      await tester.tap(find.byKey(salonInviteCancelKey('inv-pending-1')));
      await tester.pumpAndSettle();

      expect(repo.cancelInviteRequests.single.inviteId, 'inv-pending-1');
      // The row flipped to CANCELLED, so it leaves the PENDING subset — this
      // block shrinks even though the history screen would still show it.
      expect(find.byKey(salonInviteRowKey('inv-pending-1')), findsNothing);
      expect(find.byKey(salonInviteRowKey('inv-pending-2')), findsOneWidget);
      expect(find.byType(SalonInviteRow), findsOneWidget);
    });
  });
}
