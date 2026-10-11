import 'package:beautica_mobile/core/media/upload/upload_failure.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:beautica_mobile/l10n/app_localizations_en.dart';
import 'package:beautica_mobile/l10n/app_localizations_uk.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const failures = <UploadFailure>[
    UploadTooLargeFailure(),
    UploadUnsupportedFormatFailure(),
    UploadStorageUnavailableFailure(),
    UploadNetworkFailure(),
    UploadCertificateFailure(),
    UploadUnauthorizedFailure(),
    UploadForbiddenFailure(),
    UploadNotFoundFailure(),
    UploadCancelledFailure(),
    UploadUnknownFailure(500),
    // Phase 369.
    UploadForbiddenFailure(salonOwnerOnly: true),
    UploadConflictFailure(),
    UploadRateLimitedFailure(),
    UploadRateLimitedFailure(retryAfterSeconds: 42),
  ];

  for (final AppLocalizations l10n in <AppLocalizations>[
    AppLocalizationsUk(),
    AppLocalizationsEn(),
  ]) {
    test(
      '${l10n.localeName}: every variant has a distinct non-empty message',
      () {
        final messages = failures.map((f) => f.message(l10n)).toList();
        expect(messages.every((m) => m.trim().isNotEmpty), isTrue);
        expect(messages.toSet(), hasLength(failures.length));
      },
    );
  }

  test('uk copy matches the spec for the five core variants', () {
    final l10n = AppLocalizationsUk();
    expect(
      const UploadTooLargeFailure().message(l10n),
      'Фото завелике (макс. 5 МБ)',
    );
    expect(
      const UploadUnsupportedFormatFailure().message(l10n),
      'Підтримуються лише JPEG, PNG або WebP',
    );
    expect(
      const UploadStorageUnavailableFailure().message(l10n),
      'Завантаження фото тимчасово недоступне',
    );
    expect(
      const UploadNetworkFailure().message(l10n),
      "Не вдалося завантажити фото. Перевірте з'єднання",
    );
    expect(
      const UploadUnknownFailure().message(l10n),
      'Не вдалося завантажити фото',
    );
  });

  test('Phase 369 uk copy: owner-only 403, 409, 429 (with / without wait)', () {
    final l10n = AppLocalizationsUk();
    expect(
      const UploadForbiddenFailure(salonOwnerOnly: true).message(l10n),
      'Змінювати фото салону може лише власник',
    );
    expect(
      const UploadForbiddenFailure().message(l10n),
      'Немає прав для цієї дії',
    );
    expect(
      const UploadConflictFailure().message(l10n),
      'Не вдалося зберегти фото. Спробуйте ще раз',
    );
    expect(
      const UploadRateLimitedFailure().message(l10n),
      'Забагато завантажень. Спробуйте трохи згодом',
    );
    expect(
      const UploadRateLimitedFailure(retryAfterSeconds: 42).message(l10n),
      'Забагато завантажень. Спробуйте за 42 с',
    );
    expect(
      const UploadRateLimitedFailure(retryAfterSeconds: 0).message(l10n),
      'Забагато завантажень. Спробуйте трохи згодом',
    );
  });
}
