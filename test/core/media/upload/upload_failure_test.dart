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
}
