// Phase 424 D1 — ReportSheet (ported from docs/signup-designs/UgcSafety):
//   • reason required: the CTA is disabled until one is picked;
//   • «Інше» makes the comment required (>= 5 chars) and relabels the field;
//   • submit sends {targetType, targetId, reason, comment?} through the
//     repository, closes the sheet and shows the success snack;
//   • 429 → «Забагато скарг…» banner, 404 → generic banner; the sheet stays
//     open and a reason change clears the banner;
//   • chrome: title + subject subtitle, 3-line comment well.

import 'dart:async';

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/moderation/data/content_report_repository.dart';
import 'package:beautica_mobile/features/moderation/domain/content_report.dart';
import 'package:beautica_mobile/features/moderation/presentation/widgets/report_sheet.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/shared/feedback/velvet_snack.dart';
import 'package:beautica_mobile/shared/widgets/velvet_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/pump_app.dart';
import '../../../../helpers/velvet_snack_matchers.dart';
import '../../support/fake_content_report_repository.dart';

final AppLocalizations _l10n = lookupAppLocalizations(const Locale('uk'));

/// Reviewer name fixture (ASCII so no Cyrillic literal reaches a finder).
const String _kName = 'Olena K.';

const Key _open = Key('open-report');
final Finder _sheet = find.byType(ReportSheet);
final Finder _submit = find.byKey(ReportSheet.submitKey);
final Finder _banner = find.byKey(ReportSheet.bannerKey);

/// Result of the last showReportSheet future.
bool? _result;
bool _resolved = false;

Future<FakeContentReportRepository> _open_(
  WidgetTester tester, {
  FakeContentReportRepository? repo,
}) async {
  final FakeContentReportRepository r = repo ?? FakeContentReportRepository();
  _result = null;
  _resolved = false;
  await tester.pumpApp(
    Scaffold(
      body: Builder(
        builder: (BuildContext context) => Center(
          child: TextButton(
            key: _open,
            onPressed: () async {
              _result = await showReportSheet(
                context,
                targetType: ReportTargetType.review,
                targetId: 'review-42',
                subject: _l10n.reportSubjectReview(_kName),
              );
              _resolved = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
    overrides: <Object>[contentReportRepositoryProvider.overrideWithValue(r)],
    height: 1400,
  );
  await tester.tap(find.byKey(_open));
  await tester.pumpAndSettle();
  return r;
}

Future<void> _pick(WidgetTester tester, ReportReason reason) async {
  await tester.tap(find.byKey(ReportSheet.reasonKey(reason)));
  await tester.pump();
}

/// Taps the CTA by its label (an AnimatedScale root swallows tap-by-key).
Future<void> _tapSubmit(WidgetTester tester) async {
  await tester.ensureVisible(_submit);
  await tester.tap(find.text(_l10n.reportSubmit));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('chrome: title, subject subtitle, six reasons, 3-line well, '
      'optional comment label, helper', (tester) async {
    await _open_(tester);
    expect(_sheet, findsOneWidget);
    expect(find.text(_l10n.reportSheetTitle), findsOneWidget);
    expect(find.text(_l10n.reportSubjectReview(_kName)), findsOneWidget);
    for (final ReportReason r in ReportReason.values) {
      expect(find.byKey(ReportSheet.reasonKey(r)), findsOneWidget);
      expect(find.text(reportReasonLabel(_l10n, r)), findsOneWidget);
    }
    final TextField field = tester.widget<TextField>(
      find.byKey(ReportSheet.commentFieldKey),
    );
    expect(field.minLines, 3);
    expect(field.maxLines, 3);
    expect(field.maxLength, kReportCommentMaxLength);
    expect(find.text(_l10n.reportCommentLabelOptional), findsOneWidget);
    expect(find.text(_l10n.reportCommentHelper), findsOneWidget);
    expect(_banner, findsNothing);
  });

  testWidgets('reason required: tapping the CTA with no reason sends nothing', (
    tester,
  ) async {
    final FakeContentReportRepository repo = await _open_(tester);
    await _tapSubmit(tester);
    expect(repo.requests, isEmpty);
    expect(_sheet, findsOneWidget);
  });

  testWidgets('submit → request carries target + reason, comment null when '
      'empty; sheet closes true; success snack', (tester) async {
    final FakeContentReportRepository repo = await _open_(tester);
    await _pick(tester, ReportReason.offensive);
    await _tapSubmit(tester);

    expect(
      repo.requests.single,
      const ContentReportRequest(
        targetType: ReportTargetType.review,
        targetId: 'review-42',
        reason: ReportReason.offensive,
      ),
    );
    expect(_sheet, findsNothing);
    expect(_resolved, isTrue);
    expect(_result, isTrue);
    expect(find.byType(VelvetSnack), findsOneWidget);
    expect(find.text(_l10n.reportSent), findsOneWidget);
    await pumpPastVelvetSnack(tester);
  });

  testWidgets('optional comment is trimmed and sent', (tester) async {
    final FakeContentReportRepository repo = await _open_(tester);
    await _pick(tester, ReportReason.spam);
    await tester.enterText(
      find.byKey(ReportSheet.commentFieldKey),
      '  реклама  ',
    );
    await _tapSubmit(tester);
    expect(repo.requests.single.comment, 'реклама');
    await pumpPastVelvetSnack(tester);
  });

  testWidgets('«Інше» relabels the field and needs >= 5 chars before sending', (
    tester,
  ) async {
    final FakeContentReportRepository repo = await _open_(tester);
    await _pick(tester, ReportReason.other);
    expect(find.text(_l10n.reportCommentLabelRequired), findsOneWidget);

    await _tapSubmit(tester);
    expect(repo.requests, isEmpty);
    expect(find.text(_l10n.reportCommentRequiredError), findsOneWidget);

    await tester.enterText(find.byKey(ReportSheet.commentFieldKey), 'abcd');
    await tester.pump();
    // Typing clears the inline error.
    expect(find.text(_l10n.reportCommentRequiredError), findsNothing);
    await _tapSubmit(tester);
    expect(repo.requests, isEmpty);
    expect(find.text(_l10n.reportCommentRequiredError), findsOneWidget);

    await tester.enterText(
      find.byKey(ReportSheet.commentFieldKey),
      'Фейковий відгук',
    );
    await _tapSubmit(tester);
    expect(repo.requests.single.reason, ReportReason.other);
    expect(repo.requests.single.comment, 'Фейковий відгук');
    expect(_sheet, findsNothing);
    await pumpPastVelvetSnack(tester);
  });

  testWidgets('429 → rate-limit banner; sheet stays open; reason change clears '
      'it', (tester) async {
    final FakeContentReportRepository repo = await _open_(
      tester,
      repo: FakeContentReportRepository(rateLimit: 0),
    );
    await _pick(tester, ReportReason.spam);
    await _tapSubmit(tester);

    expect(_sheet, findsOneWidget);
    expect(_banner, findsOneWidget);
    expect(
      tester.widget<VelvetBanner>(_banner).message,
      _l10n.reportErrRateLimited,
    );
    expect(find.byType(VelvetSnack), findsNothing);
    expect(repo.requests, hasLength(1));

    await _pick(tester, ReportReason.harassment);
    expect(_banner, findsNothing);
  });

  testWidgets('404 → generic banner', (tester) async {
    await _open_(
      tester,
      repo: FakeContentReportRepository(hiddenTargetIds: <String>{'review-42'}),
    );
    await _pick(tester, ReportReason.falseInfo);
    await _tapSubmit(tester);
    expect(
      tester.widget<VelvetBanner>(_banner).message,
      _l10n.reportErrGeneric,
    );
    expect(_sheet, findsOneWidget);
  });

  testWidgets('any other failure → generic banner', (tester) async {
    final FakeContentReportRepository repo = FakeContentReportRepository()
      ..nextFailure = const ServerFailure(statusCode: 500);
    await _open_(tester, repo: repo);
    await _pick(tester, ReportReason.sexualContent);
    await _tapSubmit(tester);
    expect(
      tester.widget<VelvetBanner>(_banner).message,
      _l10n.reportErrGeneric,
    );
  });

  // Security LOW-3 regression: a non-`Failure` throw used to escape the
  // notifier, leaving the CTA spinning forever with no banner.
  testWidgets('non-Failure throw → spinner stops, generic banner, sheet stays '
      'open', (tester) async {
    final FakeContentReportRepository repo = FakeContentReportRepository()
      ..nextError = StateError('mapper bug');
    await _open_(tester, repo: repo);
    await _pick(tester, ReportReason.spam);
    await _tapSubmit(tester);
    expect(repo.requests, hasLength(1));
    expect(
      find.descendant(
        of: _submit,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsNothing,
    );
    expect(
      tester.widget<VelvetBanner>(_banner).message,
      _l10n.reportErrGeneric,
    );
    expect(_sheet, findsOneWidget);
  });

  // Security LOW-1 regression: the backend's `@Size(max = 500)` counts UTF-16
  // code units. 300 emoji are 300 graphemes (under a grapheme cap of 500) but
  // 600 units — the field must cap at 500 UNITS so the request never 400s.
  testWidgets('300 emoji (600 UTF-16 units) are capped at 500 units; the '
      'counter and the sent comment agree with the backend', (tester) async {
    final FakeContentReportRepository repo = await _open_(tester);
    await _pick(tester, ReportReason.spam);
    final String emoji300 = List<String>.filled(300, '\u{1F600}').join();
    expect(emoji300.length, 600);
    await tester.enterText(find.byKey(ReportSheet.commentFieldKey), emoji300);
    await tester.pump();

    final TextField field = tester.widget<TextField>(
      find.byKey(ReportSheet.commentFieldKey),
    );
    final String kept = field.controller!.text;
    expect(kept.length, kReportCommentMaxLength);
    expect(kept, List<String>.filled(250, '\u{1F600}').join());
    expect(find.text('500/$kReportCommentMaxLength'), findsOneWidget);

    await _tapSubmit(tester);
    expect(repo.requests.single.comment!.length, kReportCommentMaxLength);
    expect(_banner, findsNothing, reason: 'the fake 400s past 500 units');
    expect(_sheet, findsNothing);
    await pumpPastVelvetSnack(tester);
  });

  testWidgets('while sending: CTA spinner, a second tap and a reason change '
      'are inert; a retry after the failure still carries the FIRST reason', (
    tester,
  ) async {
    final FakeContentReportRepository repo = FakeContentReportRepository()
      ..gate = Completer<void>()
      ..nextFailure = const ServerFailure(statusCode: 503);
    await _open_(tester, repo: repo);
    await _pick(tester, ReportReason.spam);
    await tester.ensureVisible(_submit);
    await tester.tap(find.text(_l10n.reportSubmit));
    await tester.pump();

    expect(repo.requests, hasLength(1));
    expect(
      find.descendant(
        of: _submit,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    await tester.tapAt(tester.getCenter(_submit));
    await tester.pump();
    await tester.tap(
      find.byKey(ReportSheet.reasonKey(ReportReason.harassment)),
    );
    await tester.pump();
    expect(repo.requests, hasLength(1), reason: 'in-flight tap is inert');

    repo.gate!.complete();
    repo.gate = null;
    await tester.pumpAndSettle();
    expect(_banner, findsOneWidget);
    await _tapSubmit(tester);
    expect(repo.requests, hasLength(2));
    expect(
      repo.requests.last.reason,
      ReportReason.spam,
      reason: 'the reason tapped mid-flight must not have been selected',
    );
    expect(_sheet, findsNothing);
    await pumpPastVelvetSnack(tester);
  });

  testWidgets('dismissing the sheet resolves null and sends nothing', (
    tester,
  ) async {
    final FakeContentReportRepository repo = await _open_(tester);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(_sheet, findsNothing);
    expect(_resolved, isTrue);
    expect(_result, isNull);
    expect(repo.requests, isEmpty);
  });
}
