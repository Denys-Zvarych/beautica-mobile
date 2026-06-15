// Phase 17.4 — Visual regression goldens for LoginScreen.
//
// Matrix: {320, 360, 414} dp × {textScale 1.0, 1.3} = 6 golden PNGs.
// File names: login_<width>_<scale>.png  (e.g. login_360_1x.png)
//
// Clock: LoginScreen renders no date-bearing UI — no clock override needed.
//
// Strategy:
//   • Override [authProvider] with a stub returning the unauthenticated idle
//     state — the blank screen the user sees on first open.
//   • Override [authRepositoryProvider] with [FakeAuthRepository] (no-op).
//   • Override [secureStorageProvider] with [FakeSecureStorage] (no tokens).
//   • One [goldenTest] per (width × scale) cell.
//   • [pumpWidget] is overridden via [goldenPumpWidget] to wrap the scene in
//     [ProviderScope] + [MaterialApp] with UK l10n.

import 'dart:async';

import 'package:beautica_mobile/core/storage/secure_storage_provider.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:beautica_mobile/features/auth/domain/auth_session.dart';
import 'package:beautica_mobile/features/auth/presentation/auth_notifier.dart';
import 'package:beautica_mobile/features/auth/presentation/login_screen.dart';

import '../helpers/fakes/fake_auth_repository.dart';
import '../helpers/fakes/fake_secure_storage.dart';
import 'helpers/golden_pump.dart';

// ---------------------------------------------------------------------------
// Stub notifier — idle unauthenticated state, no network touch.
// ---------------------------------------------------------------------------

class _IdleAuthNotifier extends AuthNotifier {
  @override
  Future<AuthSession> build() async => const AuthSession.unauthenticated();
}

// ---------------------------------------------------------------------------
// Override factory
// ---------------------------------------------------------------------------

List<Object> _overrides() => <Object>[
  authProvider.overrideWith(_IdleAuthNotifier.new),
  authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
  secureStorageProvider.overrideWithValue(FakeSecureStorage()),
];

// ---------------------------------------------------------------------------
// Goldens — one per matrix cell
// ---------------------------------------------------------------------------

void main() {
  for (final width in kGoldenWidths) {
    for (final scale in kGoldenTextScales) {
      final suffix = widthScaleSuffix(width, scale);

      goldenTest(
        'login ${width.toInt()}dp text-${scale}x',
        fileName: 'login_$suffix',
        constraints: BoxConstraints.tight(Size(width, kGoldenHeight)),
        textScaleFactor: scale,
        pumpWidget: goldenPumpWidget(overrides: _overrides(), width: width),
        builder: () => const LoginScreen(),
      );
    }
  }
}
