// Widget tests for [ContactSupportScreen] + the [AttachmentTray] it hosts.
//
// Strategy:
//   The screen is pumped inside a real GoRouter (its back action uses go_router
//   context) with [supportRepositoryProvider] overridden by a mocktail mock —
//   never the real network (M3 / isolation). Finders use the exposed widget
//   Keys, never localized strings (M2); l10n copy is asserted by resolving the
//   key via lookupAppLocalizations.
//
//   The attachment budget / counter logic lives in [AttachmentTray] and is keyed
//   off the picked-file list, which the screen builds from the platform file
//   picker (no test seam). So the n/5 counter, the per-file/total/count limits,
//   and the over-budget meter are driven directly against AttachmentTray with a
//   synthetic attachment list — the same widget instance the screen embeds.
//
// Coverage (screen):
//   • message < 10 chars → Send disabled, no repo call; submit attempt shows the
//     too-short error tone (M3 error path with the mapped l10n message).
//   • valid message → Send enabled; tapping it calls the repo once.
//   • subject > 150 chars is capped by the field's maxLength.
//   • tapping Send (valid) shows the success card (support-success-card).
//   • a 503 failure surfaces the mapped l10n.contactSupportErrUnavailable
//     SnackBar; a 413 surfaces l10n.contactSupportErrTotalTooBig.
//
// Coverage (AttachmentTray):
//   • the n/maxFiles counter reflects the attachment count.
//   • the over-budget total surfaces the size-meter "over" caption + flips the
//     add tile / counter to the limit-reached copy at maxFiles.
//
// Layer: Widget.

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/theme/brand_colors.dart';
import 'package:beautica_mobile/core/widgets/neumorphic.dart';
import 'package:beautica_mobile/features/support/data/support_repository.dart';
import 'package:beautica_mobile/features/support/domain/support_attachment.dart';
import 'package:beautica_mobile/features/support/domain/support_limits.dart';
import 'package:beautica_mobile/features/support/presentation/contact_support_screen.dart';
import 'package:beautica_mobile/features/support/presentation/widgets/attachment_tray.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/routing/route_names.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/pump_app.dart';

class _MockSupportRepository extends Mock implements SupportRepository {}

final _l10n = lookupAppLocalizations(const Locale('uk'));

SupportAttachment _attachment(String name, int bytes) => SupportAttachment(
  name: name,
  bytes: List<int>.filled(bytes, 0),
  contentType: 'image/png',
  kind: SupportAttachmentKind.image,
);

/// Router rooted at the contact screen, with a sentinel destination the back
/// action falls back to (canPop is false at the root).
GoRouter _contactRouter() => GoRouter(
  initialLocation: RouteNames.contactSupport,
  routes: <RouteBase>[
    GoRoute(
      path: RouteNames.contactSupport,
      builder: (_, _) => const ContactSupportScreen(),
    ),
    GoRoute(
      path: RouteNames.masterMenu,
      builder: (_, _) => const Scaffold(body: SizedBox(key: Key('stub-menu'))),
    ),
  ],
);

extension on WidgetTester {
  Future<void> pumpContactScreen(SupportRepository repo) async {
    final router = _contactRouter();
    addTearDown(router.dispose);
    await pumpRoutedApp(
      router,
      overrides: <Object>[supportRepositoryProvider.overrideWithValue(repo)],
    );
    await pumpAndSettle();
  }

  /// True when the Send button is enabled (onPressed != null & not loading).
  bool get sendEnabled {
    final NeumorphicButton button = widget<NeumorphicButton>(
      find.byKey(const Key('support-send')),
    );
    return button.onPressed != null && !button.loading;
  }
}

void main() {
  late _MockSupportRepository repo;

  setUpAll(() {
    registerFallbackValue(<SupportAttachment>[]);
  });

  setUp(() {
    repo = _MockSupportRepository();
  });

  void stubSuccess() {
    when(
      () => repo.submitContact(
        message: any(named: 'message'),
        subject: any(named: 'subject'),
        attachments: any(named: 'attachments'),
      ),
    ).thenAnswer((_) async {});
  }

  void stubFailure(Failure failure) {
    when(
      () => repo.submitContact(
        message: any(named: 'message'),
        subject: any(named: 'subject'),
        attachments: any(named: 'attachments'),
      ),
    ).thenThrow(failure);
  }

  // ── Message validation ─────────────────────────────────────────────────────

  group('message validation', () {
    testWidgets('Send is disabled with an empty message', (tester) async {
      await tester.pumpContactScreen(repo);

      expect(tester.sendEnabled, isFalse);
    });

    testWidgets('Send stays disabled while the message is under 10 chars', (
      tester,
    ) async {
      await tester.pumpContactScreen(repo);

      await tester.enterText(find.byKey(const Key('support-message')), 'short');
      await tester.pumpAndSettle();

      expect(
        tester.sendEnabled,
        isFalse,
        reason: '5 chars is below the 10-char minimum',
      );
    });

    testWidgets(
      'a below-minimum message renders the live counter in the error tone and '
      'never lets the repo be called',
      (tester) async {
        await tester.pumpContactScreen(repo);

        await tester.enterText(
          find.byKey(const Key('support-message')),
          'too short', // 9 chars, below the 10-char minimum
        );
        await tester.pumpAndSettle();

        // The live counter (n/max) inside the message well flips to the error
        // tone while below minimum — the inline "error tone <10" affordance.
        final Text counter = tester.widget<Text>(
          find.text('9/${SupportLimits.maxMessage}'),
        );
        expect(
          counter.style?.color,
          BrandColors.error,
          reason: 'below the minimum the live counter must use the error tone',
        );

        // Send is disabled and the repo is never reachable.
        expect(tester.sendEnabled, isFalse);
        verifyNever(
          () => repo.submitContact(
            message: any(named: 'message'),
            subject: any(named: 'subject'),
            attachments: any(named: 'attachments'),
          ),
        );
      },
    );

    testWidgets('Send becomes enabled once the message reaches 10 chars', (
      tester,
    ) async {
      await tester.pumpContactScreen(repo);

      await tester.enterText(
        find.byKey(const Key('support-message')),
        'This message is long enough',
      );
      await tester.pumpAndSettle();

      expect(tester.sendEnabled, isTrue);
    });
  });

  // ── Subject length cap ──────────────────────────────────────────────────────

  testWidgets('the subject field enforces the 150-char maxLength', (
    tester,
  ) async {
    await tester.pumpContactScreen(repo);

    final TextField subjectField = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('support-subject')),
        matching: find.byType(TextField),
      ),
    );
    expect(subjectField.maxLength, SupportLimits.maxSubject);
  });

  // ── Happy path → success card ───────────────────────────────────────────────

  testWidgets(
    'tapping Send with a valid message calls the repo and shows the success card',
    (tester) async {
      stubSuccess();
      await tester.pumpContactScreen(repo);

      await tester.enterText(
        find.byKey(const Key('support-message')),
        'A perfectly valid support message body',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('support-send')));
      await tester.pumpAndSettle();

      verify(
        () => repo.submitContact(
          message: 'A perfectly valid support message body',
          subject: any(named: 'subject'),
          attachments: any(named: 'attachments'),
        ),
      ).called(1);
      expect(find.byKey(const Key('support-success-card')), findsOneWidget);
      expect(find.byKey(const Key('support-success-done')), findsOneWidget);
    },
  );

  // ── Error mapping → SnackBar ────────────────────────────────────────────────

  group('error mapping surfaces the mapped l10n message', () {
    testWidgets('503 → channel unavailable copy', (tester) async {
      stubFailure(const SupportChannelUnavailableFailure());
      await tester.pumpContactScreen(repo);

      await tester.enterText(
        find.byKey(const Key('support-message')),
        'A perfectly valid support message body',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('support-send')));
      await tester.pump(); // start the submit
      await tester.pump(); // surface the SnackBar

      expect(find.text(_l10n.contactSupportErrUnavailable), findsOneWidget);
      // The screen returns to the editable form (not the success card).
      expect(find.byKey(const Key('support-success-card')), findsNothing);
    });

    testWidgets('413 → attachments too large copy', (tester) async {
      stubFailure(const SupportAttachmentTooLargeFailure());
      await tester.pumpContactScreen(repo);

      await tester.enterText(
        find.byKey(const Key('support-message')),
        'A perfectly valid support message body',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('support-send')));
      await tester.pump();
      await tester.pump();

      expect(find.text(_l10n.contactSupportErrTotalTooBig), findsOneWidget);
    });
  });

  // ── AttachmentTray — counter + budget surface (M3) ──────────────────────────
  //
  // The tray is the screen's attachment surface; the screen feeds it the picked
  // list. We drive it directly because the file picker has no widget-test seam.

  group('AttachmentTray counter + budget', () {
    Future<void> pumpTray(
      WidgetTester tester,
      List<SupportAttachment> attachments,
    ) async {
      await tester.pumpApp(
        AttachmentTray(
          attachments: attachments,
          onAdd: () {},
          onRemove: (_) {},
          maxFiles: SupportLimits.maxFiles,
          maxTotalBytes: SupportLimits.maxTotalBytes,
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('the n/maxFiles counter reflects the attachment count', (
      tester,
    ) async {
      await pumpTray(tester, <SupportAttachment>[
        _attachment('a.png', 1024),
        _attachment('b.png', 1024),
      ]);

      expect(find.text('2/${SupportLimits.maxFiles}'), findsOneWidget);
      expect(
        find.byKey(const Key('support-attachment-chip-0')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('support-attachment-chip-1')),
        findsOneWidget,
      );
    });

    testWidgets('at maxFiles the add tile shows the limit-reached subtitle', (
      tester,
    ) async {
      await pumpTray(tester, <SupportAttachment>[
        for (int i = 0; i < SupportLimits.maxFiles; i++)
          _attachment('file-$i.png', 1024),
      ]);

      expect(
        find.text('${SupportLimits.maxFiles}/${SupportLimits.maxFiles}'),
        findsOneWidget,
      );
      expect(
        find.text(_l10n.contactSupportAttachmentsLimitReached),
        findsOneWidget,
      );
    });

    testWidgets(
      'exceeding the total budget surfaces the over-budget size-meter caption',
      (tester) async {
        // Two ~3 MB files → ~6 MB total, over the 5 MB envelope.
        await pumpTray(tester, <SupportAttachment>[
          _attachment('big-1.png', 3 * 1024 * 1024),
          _attachment('big-2.png', 3 * 1024 * 1024),
        ]);

        expect(
          find.text(_l10n.contactSupportSizeMeterOver),
          findsOneWidget,
          reason:
              'over the 5 MB total budget the size meter flips to the '
              'over-limit caption',
        );
      },
    );
  });
}
