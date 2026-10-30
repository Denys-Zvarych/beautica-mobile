// Phase 425 D5 — BOOKING_UNAVAILABLE (backend 398) decode + copy.

import 'package:beautica_mobile/core/errors/failure_retry_policy.dart';
import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pump_app.dart';

void main() {
  group('decodeBookingUnavailable', () {
    test('decodes the typed 409 envelope with its message', () {
      final BookingUnavailableFailure? f = decodeBookingUnavailable(
        <String, dynamic>{
          'success': false,
          'data': <String, dynamic>{'code': 'BOOKING_UNAVAILABLE'},
          'message': 'Запис до цього салону зараз недоступний',
        },
      );
      expect(f, isNotNull);
      expect(f?.serverMessage, 'Запис до цього салону зараз недоступний');
    });

    test('other codes, missing data and non-map bodies → null', () {
      expect(
        decodeBookingUnavailable(<String, dynamic>{
          'data': <String, dynamic>{'code': 'CLIENT_BOOKING_CONFLICT'},
        }),
        isNull,
      );
      expect(decodeBookingUnavailable(<String, dynamic>{'data': null}), isNull);
      expect(decodeBookingUnavailable('BOOKING_UNAVAILABLE'), isNull);
      expect(decodeBookingUnavailable(null), isNull);
    });

    test('a non-string message decodes with a null serverMessage', () {
      expect(
        decodeBookingUnavailable(<String, dynamic>{
          'data': <String, dynamic>{'code': 'BOOKING_UNAVAILABLE'},
          'message': 42,
        })?.serverMessage,
        isNull,
      );
    });
  });

  testWidgets('userMessage: server text as-is, localized fallback when blank', (
    tester,
  ) async {
    await tester.pumpApp(const SizedBox());
    final BuildContext ctx = tester.element(find.byType(SizedBox));
    final AppLocalizations l10n = AppLocalizations.of(ctx);
    expect(
      const BookingUnavailableFailure(
        serverMessage: 'Текст сервера',
      ).userMessage(ctx),
      'Текст сервера', // i18n-finder-ok: passthrough fixture
    );
    expect(
      const BookingUnavailableFailure(serverMessage: '  ').userMessage(ctx),
      l10n.bookingErrUnavailable,
    );
    expect(
      const BookingUnavailableFailure().userMessage(ctx),
      'Запис до цього майстра/салону зараз недоступний', // i18n-finder-ok: verbatim D5 copy
    );
  });

  test('is never auto-retried', () {
    expect(isTransientFailure(const BookingUnavailableFailure()), isFalse);
    expect(beauticaProviderRetry(0, const BookingUnavailableFailure()), isNull);
  });
}
