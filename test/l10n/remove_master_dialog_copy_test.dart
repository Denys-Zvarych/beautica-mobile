// Phase 306 — pins the EXACT remove-master confirmation copy in both
// locales.
//
// This dialog is the only thing standing between a salon owner and
// irreversible destruction: backend phase 297 hard-deletes the master's
// user account, and phase 298 removed the earlier 409 refusal for a master
// with future bookings — the call now succeeds, cancels those bookings and
// notifies the clients. Phase 291 set the house shape for this situation on
// `deleteSalonBody` (a header clause + a bulleted consequence list, most-
// irreversible first, never promising more than the system guarantees).
// This file pins the same shape applied to `removeMasterDialogBody`, plus
// the two banned claims D1 forbids:
//   - the admin verb «вилучено із салону» (the master's account is DELETED,
//     not merely unassigned — reusing the admin wording here would repeat
//     Phase 291's «деактивовано» mistake);
//   - any claim that data was erased ("стерто") from the servers.
//
// Mirrors `schedule_discrete_times_window_summary_copy_test.dart`'s pattern
// (load AppLocalizations per locale, pin the resolved template against a
// hard-coded literal — never the same getter under test, which can never
// fail no matter what the ARB says).
//
// EXTENDED (mobile-security LOW fix, 2026-09-05) with `staffSettingsMasterSelfTitle`/
// `Body` — a 14th and 15th key alongside the original Phase 306 twelve — for
// the case the "owner-only" pair's "ask the owner" phrasing cannot honestly
// cover: the salon owner viewing their own master row.

import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const String _sampleName = 'Олена Ковальчук';

const String _ukBody =
    'Цю дію не можна скасувати:\n'
    '• акаунт Олена Ковальчук буде видалено — доступ зникне одразу;\n'
    '• майбутні записи до цього майстра скасуємо, а клієнтів сповістимо;\n'
    '• майстер зникне з команди салону та з пошуку;\n'
    '• історія завершених записів залишиться під збереженим імʼям.';

const String _enBody =
    'This cannot be undone:\n'
    '• Олена Ковальчук loses access immediately and their account is '
    'deleted;\n'
    '• upcoming bookings with this master will be cancelled and clients '
    'notified;\n'
    '• the master will disappear from the salon\'s team and from search;\n'
    '• completed bookings stay in history under a saved name.';

Future<AppLocalizations> _loadL10n(WidgetTester tester, Locale locale) async {
  late AppLocalizations l10n;
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (ctx) {
          l10n = AppLocalizations.of(ctx);
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return l10n;
}

void main() {
  testWidgets('removeMasterDialogTitle is pinned in uk and en', (
    WidgetTester tester,
  ) async {
    final AppLocalizations uk = await _loadL10n(tester, const Locale('uk'));
    expect(uk.removeMasterDialogTitle, 'Видалити майстра?');

    final AppLocalizations en = await _loadL10n(tester, const Locale('en'));
    expect(en.removeMasterDialogTitle, 'Remove master?');
  });

  testWidgets(
    'removeMasterDialogBody renders the four bullets in order with the '
    'name interpolated',
    (WidgetTester tester) async {
      final AppLocalizations uk = await _loadL10n(tester, const Locale('uk'));
      final String ukResolved = uk.removeMasterDialogBody(_sampleName);
      expect(ukResolved, _ukBody);
      expect(
        ukResolved.split('\n• '),
        hasLength(5),
        reason:
            'splitting on \'\\n• \' yields the header line PLUS the four '
            'bullets (5 elements total) — a truncated body would fail this '
            'count even if a substring check on the first bullet still '
            'passed',
      );

      final AppLocalizations en = await _loadL10n(tester, const Locale('en'));
      final String enResolved = en.removeMasterDialogBody(_sampleName);
      expect(enResolved, _enBody);
      expect(enResolved.split('\n• '), hasLength(5));
    },
  );

  testWidgets(
    'removeMasterDialogBody never says «вилучено із салону» and never '
    'says «стерто»',
    (WidgetTester tester) async {
      final AppLocalizations uk = await _loadL10n(tester, const Locale('uk'));
      final String body = uk.removeMasterDialogBody(_sampleName);

      expect(
        body,
        isNot(contains('вилучено із салону')),
        reason:
            'the admin verb implies unassignment, not account deletion — '
            'reusing it here would repeat the Phase 291 «деактивовано» '
            'mistake for a call that actually deletes the account',
      );
      expect(
        body,
        isNot(contains('стерто')),
        reason: 'Phase 291 rule: never claim data was erased from our servers',
      );
    },
  );

  testWidgets('the four error strings are pinned in uk and en', (
    WidgetTester tester,
  ) async {
    final AppLocalizations uk = await _loadL10n(tester, const Locale('uk'));
    expect(
      uk.removeMasterErrorForbidden,
      'Не вдалося видалити цього майстра. Ви не можете видалити самого '
      'себе, і потрібні права власника цього салону.',
    );
    expect(
      uk.removeMasterErrorConflict,
      'Цього майстра зараз не можна видалити — можливо, це ваш власний '
      'профіль майстра, він уже не працює в цьому салоні, або з ним '
      'пов’язані записи, де він виступає клієнтом.',
    );
    expect(
      uk.removeMasterErrorNotFound,
      'Майстра не знайдено — можливо, його вже видалили.',
    );
    expect(
      uk.removeMasterErrorGeneric,
      'Не вдалося видалити майстра. Спробуйте ще раз.',
    );

    final AppLocalizations en = await _loadL10n(tester, const Locale('en'));
    expect(
      en.removeMasterErrorForbidden,
      'This master could not be removed. You cannot remove yourself, '
      'and you need owner access to this salon.',
    );
    expect(
      en.removeMasterErrorConflict,
      'This master cannot be removed right now — it may be your own '
      'master profile, they may no longer be part of this salon, or '
      'they may also be linked to bookings as a client.',
    );
    expect(
      en.removeMasterErrorNotFound,
      'Master not found — they may already have been removed.',
    );
    expect(
      en.removeMasterErrorGeneric,
      'The master could not be removed. Please try again.',
    );
  });

  // The remaining 5 of the 12 Phase 306 keys have no call site yet either
  // (phase 307 wires the settings row, the success snack and the
  // owner-only notice card) — same status as the four error strings above,
  // which the original Phase 306 author DID pin. Pinning these too keeps
  // that decision consistent: this phase's stated deliverable is the copy
  // itself, not just the wired subset of it.
  testWidgets('the settings-row label, success snack, semantic label and '
      'owner-only notice are pinned in uk and en', (WidgetTester tester) async {
    final AppLocalizations uk = await _loadL10n(tester, const Locale('uk'));
    expect(uk.staffSettingsRemoveMaster, 'Видалити майстра');
    expect(uk.removeMasterSuccess, 'Майстра видалено із салону.');
    expect(uk.staffSettingsManageMasterSemanticLabel, 'Налаштування майстра');
    expect(uk.staffSettingsMasterOwnerOnlyTitle, 'Лише власник салону');
    expect(
      uk.staffSettingsMasterOwnerOnlyBody,
      'Керувати майстрами може лише власник салону. Зверніться до '
      'власника, якщо потрібно вилучити цього майстра.',
    );

    final AppLocalizations en = await _loadL10n(tester, const Locale('en'));
    expect(en.staffSettingsRemoveMaster, 'Remove master');
    expect(en.removeMasterSuccess, 'The master was removed from the salon.');
    expect(en.staffSettingsManageMasterSemanticLabel, 'Master settings');
    expect(en.staffSettingsMasterOwnerOnlyTitle, 'Owner only');
    expect(
      en.staffSettingsMasterOwnerOnlyBody,
      'Only the salon owner can manage masters. Ask the owner if this '
      'master needs to be removed.',
    );
  });

  // mobile-security LOW fix (2026-09-05) — a 14th and 15th key added to the
  // Phase 306 set: `staffSettingsMasterOwnerOnlyBody`'s "ask the owner"
  // phrasing is wrong for the one case where the viewer IS the owner
  // looking at their own master row (there is nobody else to ask). This
  // pins the distinct copy against a hard-coded literal, and separately
  // pins that the two bodies are not the same string — a regression that
  // collapsed the switch in `StaffSettingsScreen.build()` back onto one
  // getter would still pass a same-getter comparison but must fail here.
  testWidgets(
    'staffSettingsMasterSelfTitle/Body are pinned and DIFFER from the '
    'owner-only pair, in both uk and en',
    (WidgetTester tester) async {
      final AppLocalizations uk = await _loadL10n(tester, const Locale('uk'));
      expect(uk.staffSettingsMasterSelfTitle, 'Власний профіль майстра');
      expect(
        uk.staffSettingsMasterSelfBody,
        'Ви не можете видалити власний профіль майстра з цього екрана. '
        'Зверніться до служби підтримки, якщо потрібно це змінити.',
      );
      expect(
        uk.staffSettingsMasterSelfTitle,
        isNot(uk.staffSettingsMasterOwnerOnlyTitle),
      );
      expect(
        uk.staffSettingsMasterSelfBody,
        isNot(uk.staffSettingsMasterOwnerOnlyBody),
      );

      final AppLocalizations en = await _loadL10n(tester, const Locale('en'));
      expect(en.staffSettingsMasterSelfTitle, 'Your own master profile');
      expect(
        en.staffSettingsMasterSelfBody,
        "You can't remove your own master profile from this screen. "
        'Contact support if you need this changed.',
      );
      expect(
        en.staffSettingsMasterSelfTitle,
        isNot(en.staffSettingsMasterOwnerOnlyTitle),
      );
      expect(
        en.staffSettingsMasterSelfBody,
        isNot(en.staffSettingsMasterOwnerOnlyBody),
      );
    },
  );
}
