// M517 + phone-first hardening (AUTH-D12 / AUTH-D28) — visual regression
// goldens for the blocking add-phone gate and its code step.
//
// Screens goldened:
//   • AddPhoneScreen — default                                    — 6 PNGs
//   • AddPhoneScreen — AUTH-D28 duplicate state (409, support
//     action in the shared AuthBanner, field editable, «Вийти»)   — 6 PNGs
//   • ContactVerifyScreen — phoneAdd (code only, no password)     — 6 PNGs
// Matrix: {320, 360, 414} dp × {textScale 1.0, 1.3} = 18 golden PNGs.
//
// The duplicate state is driven through the send path (the fake throws the
// 409 on `sendPhoneCode`), which renders the same state as the verify-time
// pop-back without a router. No router is mounted: nothing here navigates.

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/core/security/screen_protection.dart';
import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/domain/contact_verify_args.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';
import 'package:beautica_mobile/features/auth/presentation/add_phone_screen.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/auth/presentation/contact_verify_screen.dart';

import 'package:flutter/widgets.dart' show ValueKey;
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fakes/fake_auth_repository.dart';
import '../helpers/fakes/fake_secure_storage.dart';
import 'helpers/golden_pump.dart';

class _NoOpScreenProtection extends ScreenProtectionManager {
  @override
  void acquire() {}
  @override
  void release() {}
}

/// A legacy account that must add a phone (AUTH-D12).
class _LegacyAuth extends AuthNotifier {
  @override
  Future<AuthSession> build() async => const AuthSession.authenticated(
    user: User(
      id: 'u-legacy',
      role: UserRole.client,
      email: 'legacy@b.ua',
      phoneVerified: false,
      phoneRequiredBy: '2026-11-18',
      emailVerified: true,
    ),
    accessToken: 't',
  );
}

List<Object> _overrides({Failure? sendFailure}) => <Object>[
  screenProtectionProvider.overrideWithValue(_NoOpScreenProtection()),
  authProvider.overrideWith(_LegacyAuth.new),
  authRepositoryProvider.overrideWithValue(
    FakeAuthRepository()..sendPhoneCodeFailure = sendFailure,
  ),
  secureStorageProvider.overrideWithValue(FakeSecureStorage()),
];

void main() {
  for (final width in kGoldenWidths) {
    for (final scale in kGoldenTextScales) {
      final suffix = widthScaleSuffix(width, scale);

      goldenTest(
        'add_phone ${width.toInt()}dp text-${scale}x',
        fileName: 'add_phone_$suffix',
        constraints: BoxConstraints.tight(Size(width, kGoldenHeight)),
        textScaleFactor: scale,
        pumpWidget: goldenPumpWidget(overrides: _overrides(), width: width),
        builder: () => const AddPhoneScreen(),
      );

      goldenTest(
        'add_phone duplicate ${width.toInt()}dp text-${scale}x',
        fileName: 'add_phone_duplicate_$suffix',
        constraints: BoxConstraints.tight(Size(width, kGoldenHeight)),
        textScaleFactor: scale,
        whilePerforming: (WidgetTester tester) async {
          await tester.enterText(
            find.byKey(const ValueKey<String>('add_phone')),
            '0931112233',
          );
          await tester.tap(
            find.byKey(const ValueKey<String>('add_phone_submit')),
          );
          await tester.pumpAndSettle();
          return null;
        },
        pumpWidget: goldenPumpWidget(
          overrides: _overrides(
            sendFailure: const PhoneIdentityFailure(
              code: PhoneIdentityErrorCode.phoneAlreadyRegistered,
            ),
          ),
          width: width,
        ),
        builder: () => const AddPhoneScreen(),
      );

      goldenTest(
        'contact_verify phoneAdd ${width.toInt()}dp text-${scale}x',
        fileName: 'contact_verify_phone_add_$suffix',
        constraints: BoxConstraints.tight(Size(width, kGoldenHeight)),
        textScaleFactor: scale,
        pumpWidget: goldenPumpWidget(overrides: _overrides(), width: width),
        builder: () => const ContactVerifyScreen(
          args: ContactVerifyArgs(
            kind: ContactVerifyKind.phoneAdd,
            target: '+380931112233',
          ),
        ),
      );
    }
  }
}
