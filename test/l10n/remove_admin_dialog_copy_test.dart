// Phase 308 — pins the EXACT remove-admin confirmation copy in both locales.
//
// Backend Phase 299 (`121c4ad`) turned `DELETE /salons/{salonId}/admins
// /{userId}` from a reversible unassign (`salon_id` → null) into a HARD
// DELETE of the admin's user account, and narrowed the caller to
// `SALON_OWNER`. The pre-308 copy promised only a loss of salon access and
// used the reversible verb «вилучено» — both wrong in the direction that
// hurts (they UNDER-warn before an irreversible act). This file pins the
// corrected copy against HARD-CODED literals — never against
// `l10n.adminSettingsRemove*` itself, which would pass for every possible
// value and would not have caught the defect this phase fixes (the exact
// CRITICAL finding Phase 291 recorded for a self-referential copy pin).
//
// Shape mirrors `remove_master_dialog_copy_test.dart`: load
// [AppLocalizations] per locale, compare the resolved string against a
// literal written into THIS file.

import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const String _sampleName = 'Олена Ковальчук';

// D1 — three bullets, most-irreversible first (Phase 291 house shape).
// Deliberately NOT four: an admin has no calendar, clients or reviews, so
// removeMasterDialogBody's booking-cancellation and history-under-a-saved-
// name bullets have no admin counterpart here.
const String _ukBody =
    'Цю дію не можна скасувати:\n'
    '• акаунт Олена Ковальчук буде видалено — доступ зникне одразу;\n'
    '• адміністратор зникне з команди салону;\n'
    '• за потреби ви зможете запросити цю людину знову на ту саму пошту.';

const String _enBody =
    'This cannot be undone:\n'
    '• Олена Ковальчук loses access immediately and their account is '
    'deleted;\n'
    '• they will disappear from the salon\'s team;\n'
    '• you can invite the same person again later, using the same email.';

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
  // Test cases 1, 2, 4, 5 — the dialog body, byte for byte, in both
  // locales, plus the bullet count and the Phase 291 header clause.
  testWidgets(
    'adminSettingsRemoveDialogBody is pinned in uk and en, three bullets, '
    'Phase 291 header clause',
    (WidgetTester tester) async {
      final AppLocalizations uk = await _loadL10n(tester, const Locale('uk'));
      final String ukResolved = uk.adminSettingsRemoveDialogBody(_sampleName);
      expect(ukResolved, _ukBody);
      expect(
        ukResolved.startsWith('Цю дію не можна скасувати:'),
        isTrue,
        reason: 'Phase 291 house shape: header clause first',
      );
      expect(
        '•'.allMatches(ukResolved).length,
        3,
        reason:
            'exactly THREE bullets — an admin has no calendar, clients or '
            "reviews, so inventing a fourth to match removeMasterDialogBody "
            'would be a false claim, not a symmetry win',
      );

      final AppLocalizations en = await _loadL10n(tester, const Locale('en'));
      final String enResolved = en.adminSettingsRemoveDialogBody(_sampleName);
      expect(enResolved, _enBody);
      expect('•'.allMatches(enResolved).length, 3);
    },
  );

  // Test case 3 — the word whose ABSENCE was the pre-308 defect: the old
  // body never said an account was being touched at all.
  testWidgets('adminSettingsRemoveDialogBody names the account, uk', (
    WidgetTester tester,
  ) async {
    final AppLocalizations uk = await _loadL10n(tester, const Locale('uk'));
    expect(uk.adminSettingsRemoveDialogBody(_sampleName), contains('акаунт'));
  });

  // Test case 6 — the success snack swaps the reversible verb («вилучено»,
  // withdrawn) for the correct one («видалено», deleted), keeping the
  // trailing «із салону» frame `removeMasterSuccess` already shipped.
  testWidgets(
    'adminSettingsRemoveSuccess is pinned in uk, uses «видалено» never '
    '«вилучено»',
    (WidgetTester tester) async {
      final AppLocalizations uk = await _loadL10n(tester, const Locale('uk'));
      expect(
        uk.adminSettingsRemoveSuccess,
        'Адміністратора видалено із салону.',
      );
      expect(uk.adminSettingsRemoveSuccess, isNot(contains('вилучен')));

      // D2 — the English value is UNCHANGED: "removed" carries none of
      // «вилучено»'s reversible connotation, so only the uk verb needed
      // the swap.
      final AppLocalizations en = await _loadL10n(tester, const Locale('en'));
      expect(
        en.adminSettingsRemoveSuccess,
        'The administrator was removed from the salon.',
      );
    },
  );

  // Test case 7 — D7: the 403 copy names OWNER access, never "management
  // access" (an admin HAS management access and is still refused as of
  // Phase 299's narrowing).
  testWidgets('adminSettingsRemoveErrorForbidden names owner access, never '
      'management access, uk and en', (WidgetTester tester) async {
    final AppLocalizations uk = await _loadL10n(tester, const Locale('uk'));
    expect(
      uk.adminSettingsRemoveErrorForbidden,
      'Не вдалося видалити цього адміністратора. Ви не можете видалити '
      'самого себе, і потрібні права власника цього салону.',
    );
    expect(uk.adminSettingsRemoveErrorForbidden, contains('власника'));
    expect(uk.adminSettingsRemoveErrorForbidden, isNot(contains('керування')));

    final AppLocalizations en = await _loadL10n(tester, const Locale('en'));
    expect(
      en.adminSettingsRemoveErrorForbidden,
      'This administrator could not be removed. You cannot remove '
      'yourself, and you need owner access to this salon.',
    );
  });

  // Test case 8 — D6: the 409 (Phase 299's new failure mode) and the 404
  // each get their OWN copy, hard-coded, in both locales.
  testWidgets(
    'adminSettingsRemoveErrorConflict and …ErrorNotFound are pinned in uk '
    'and en',
    (WidgetTester tester) async {
      final AppLocalizations uk = await _loadL10n(tester, const Locale('uk'));
      expect(
        uk.adminSettingsRemoveErrorConflict,
        "Цього адміністратора зараз не можна видалити — з ним пов'язані "
        'записи, де він виступає клієнтом.',
      );
      expect(
        uk.adminSettingsRemoveErrorNotFound,
        'Адміністратора не знайдено — можливо, його вже видалили.',
      );
      // adminSettingsRemoveErrorGeneric — pinned here too: it uses «видалити»,
      // matching removeMasterErrorGeneric's sibling verb, never the old
      // reversible-sounding «вилучити».
      expect(
        uk.adminSettingsRemoveErrorGeneric,
        'Не вдалося видалити адміністратора. Спробуйте ще раз.',
      );

      final AppLocalizations en = await _loadL10n(tester, const Locale('en'));
      expect(
        en.adminSettingsRemoveErrorConflict,
        'This administrator cannot be removed right now — they are also '
        'linked to bookings as a client.',
      );
      expect(
        en.adminSettingsRemoveErrorNotFound,
        'Administrator not found — they may already have been removed.',
      );
    },
  );

  // Test case 9 — sweep: NOTHING under this key family still promises the
  // old reversible verb, `adminSettingsRemoveErrorGeneric` included — it now
  // uses «видалити» like every other key here, so the stem check below
  // applies uniformly with no carved-out exception.
  testWidgets('no adminSettingsRemove* uk value contains the stem «вилучен»', (
    WidgetTester tester,
  ) async {
    final AppLocalizations uk = await _loadL10n(tester, const Locale('uk'));
    final Map<String, String> values = <String, String>{
      'adminSettingsRemove': uk.adminSettingsRemove,
      'adminSettingsRemoveDialogTitle': uk.adminSettingsRemoveDialogTitle,
      'adminSettingsRemoveDialogBody': uk.adminSettingsRemoveDialogBody(
        _sampleName,
      ),
      'adminSettingsRemoveConfirmCta': uk.adminSettingsRemoveConfirmCta,
      'adminSettingsRemoveSuccess': uk.adminSettingsRemoveSuccess,
      'adminSettingsRemoveErrorForbidden': uk.adminSettingsRemoveErrorForbidden,
      'adminSettingsRemoveErrorGeneric': uk.adminSettingsRemoveErrorGeneric,
      'adminSettingsRemoveErrorConflict': uk.adminSettingsRemoveErrorConflict,
      'adminSettingsRemoveErrorNotFound': uk.adminSettingsRemoveErrorNotFound,
    };

    for (final MapEntry<String, String> entry in values.entries) {
      expect(
        entry.value,
        isNot(contains('вилучен')),
        reason: '${entry.key} still contains the reversible «вилучен» stem',
      );
    }
  });
}
