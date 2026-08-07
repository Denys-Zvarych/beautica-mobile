// Fake [AuthRepository] for widget and unit tests.
//
// Captures calls to login/register so tests can assert which arguments were
// passed. Configure responses via the settable fields below.
// Default behaviour: throws [UnimplementedError] for any un-configured method.

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository.dart';
import 'package:beautica_mobile/features/auth/domain/auth_tokens.dart';
import 'package:beautica_mobile/features/auth/domain/invite_details.dart';
import 'package:beautica_mobile/features/auth/domain/register_result.dart';
import 'package:beautica_mobile/features/auth/domain/user.dart';
import 'package:beautica_mobile/features/auth/domain/user_role.dart';

/// In-memory [AuthRepository] implementation for tests.
///
/// Assign [loginResult], [registerResult], etc. before the action under test.
/// Use [loginCalls] etc. to assert which arguments were passed.
final class FakeAuthRepository implements AuthRepository {
  // ---------------------------------------------------------------------------
  // Configurable responses
  // ---------------------------------------------------------------------------

  /// Return value for the next [login] call. May be a [Failure] to throw.
  Object? loginResult;

  /// Return value for the next [registerIndependentMaster] call.
  Object? registerResult;

  /// Return value for the next [refresh] call.
  Object? refreshResult;

  /// Return value for the next [me] call.
  Object? meResult;

  /// When non-null, [me] awaits this future before inspecting [meResult].
  ///
  /// Set to a non-completing Future (e.g. `Completer<void>().future`) to park
  /// `AuthNotifier.build()` inside its cold-start `repo.me()` await, holding
  /// `authProvider` in [AsyncLoading] with `coldStartAccessToken` populated —
  /// the window `interceptor_chain_test.dart` drives the stale-bearer replay
  /// regression through. Mirrors [resendDelay] / [requestPasswordResetDelay].
  Future<void>? meDelay;

  /// Whether [logout] should throw.
  bool logoutThrows = false;

  /// Return value for the next [verifyEmail] call.
  ///
  /// Accepted values:
  ///   - `null`               → success with default user + tokens.
  ///   - `(User, AuthTokens)` → success with these specific values.
  ///   - `Failure`            → thrown to simulate a backend error
  ///                            (e.g. [VerificationFailure] with INVALID_CODE).
  Object? verifyEmailResult;

  /// Return value for the next [resendVerificationCode] call.
  ///
  /// Accepted values:
  ///   - `null`     → success (no return value).
  ///   - `Failure`  → thrown to simulate a backend error
  ///                  (e.g. [ResendThrottledFailure]).
  Object? resendVerificationResult;

  /// When non-null, [resendVerificationCode] awaits this future before
  /// inspecting [resendVerificationResult]. Set to a non-completing Future
  /// (e.g. `Completer<void>().future`) to block the call indefinitely in
  /// tests that need to inspect the optimistic intermediate UI state.
  Future<void>? resendDelay;

  /// Return value for the next [requestPasswordReset] call.
  ///
  /// Accepted values:
  ///   - `null`     → generic success (no return value).
  ///   - `Failure`  → thrown to simulate a transport / server error.
  Object? requestPasswordResetResult;

  /// Return value for the next [requestChangePasswordOtp] call.
  ///
  /// Accepted values:
  ///   - `null`     → generic success (no return value).
  ///   - `Failure`  → thrown to simulate a backend error
  ///                  (e.g. [ResendThrottledFailure]).
  Object? requestChangePasswordOtpResult;

  /// When non-null, [requestChangePasswordOtp] awaits this future before
  /// inspecting [requestChangePasswordOtpResult]. Set to a non-completing
  /// Future (e.g. `Completer<void>().future`) to block the call indefinitely
  /// in tests that need to inspect the optimistic intermediate (loading) UI
  /// state — e.g. the `SettingsRow(loading: ...)` spinner.
  Future<void>? requestChangePasswordOtpDelay;

  /// Return value for the next [verifyPasswordResetOtp] call.
  ///
  /// Accepted values:
  ///   - `null`     → success with a default reset ticket.
  ///   - `String`   → success with this specific reset ticket.
  ///   - `Failure`  → thrown to simulate a backend error
  ///                  (e.g. [PasswordResetOtpFailure]).
  Object? verifyPasswordResetOtpResult;

  /// Return value for the next [confirmPasswordReset] call.
  ///
  /// Accepted values:
  ///   - `null`     → success (no return value).
  ///   - `Failure`  → thrown to simulate a backend error
  ///                  (e.g. [ResetTokenInvalidFailure]).
  Object? confirmPasswordResetResult;

  /// When non-null, [confirmPasswordReset] awaits this future before
  /// inspecting [confirmPasswordResetResult]. Set to a non-completing Future
  /// (e.g. `Completer<void>().future`) to block the call indefinitely in
  /// tests that need to inspect the optimistic intermediate (loading) state.
  Future<void>? confirmPasswordResetDelay;

  /// When non-null, [requestPasswordReset] awaits this future before
  /// inspecting [requestPasswordResetResult]. Set to a non-completing Future
  /// (e.g. `Completer<void>().future`) to block the call indefinitely in
  /// tests that need to inspect the optimistic intermediate (loading) state.
  Future<void>? requestPasswordResetDelay;

  /// Return value for the next [validateInvite] call.
  ///
  /// Accepted values:
  ///   - `null`          → success with [_defaultInvite].
  ///   - [InviteDetails] → success with these specific values.
  ///   - [Failure]       → thrown to simulate an invalid/expired token.
  Object? validateInviteResult;

  /// Return value for the next [acceptInvite] call.
  ///
  /// Accepted values:
  ///   - `null`               → success with default user + tokens.
  ///   - `(User, AuthTokens)` → success with these specific values.
  ///   - [Failure]            → thrown to simulate a backend error.
  Object? acceptInviteResult;

  // ---------------------------------------------------------------------------
  // Captured calls (for assertion in tests)
  // ---------------------------------------------------------------------------

  final List<({String email, String password})> loginCalls = [];
  final List<
    ({
      String email,
      String password,
      String firstName,
      String lastName,
      UserRole role,
      String? businessName,
      String? address,
      String? phone,
    })
  >
  registerCalls = [];
  int logoutCallCount = 0;

  /// Captured call count for [me] (cold-start profile load + [refreshUser]).
  int meCallCount = 0;

  /// Captured arguments for each [verifyEmail] call.
  /// Tests can assert `verifyEmailCalls.first.email` / `.otp`.
  final List<({String email, String otp})> verifyEmailCalls = [];

  /// Captured arguments for each [resendVerificationCode] call.
  /// Tests can assert `resendCalls.first.email` (backlog row 164).
  final List<({String email})> resendCalls = [];

  /// Captured arguments for each [requestPasswordReset] call.
  final List<({String email})> requestPasswordResetCalls = [];

  /// Captured call count for [requestChangePasswordOtp].
  int requestChangePasswordOtpCallCount = 0;

  /// Captured arguments for each [verifyPasswordResetOtp] call.
  final List<({String email, String code})> verifyPasswordResetOtpCalls = [];

  /// Captured arguments for each [confirmPasswordReset] call.
  final List<({String resetTicket, String newPassword})>
  confirmPasswordResetCalls = [];

  /// Captured [token] values for each [validateInvite] call.
  final List<String> validateInviteCalls = [];

  /// Captured arguments for each [acceptInvite] call.
  final List<
    ({
      String token,
      String password,
      String firstName,
      String lastName,
      String? phoneNumber,
    })
  >
  acceptInviteCalls = [];

  // ---------------------------------------------------------------------------
  // AuthRepository
  // ---------------------------------------------------------------------------

  static final _defaultInvite = InviteDetails(
    email: 'invited@salon.ua',
    role: UserRole.salonMaster,
    expiresAt: DateTime.now().add(const Duration(hours: 48)),
  );

  static const _defaultUser = User(
    id: 'u1',
    email: 'test@example.com',
    role: UserRole.independentMaster,
    firstName: 'Test',
    lastName: 'User',
  );

  static const _defaultTokens = AuthTokens(
    accessToken: 'access-token',
    refreshToken: 'refresh-token',
  );

  @override
  Future<(User, AuthTokens)> login({
    required String email,
    required String password,
  }) async {
    loginCalls.add((email: email, password: password));
    final result = loginResult;
    if (result is Failure) throw result;
    if (result is (User, AuthTokens)) return result;
    return (_defaultUser, _defaultTokens);
  }

  @override
  Future<RegisterResult> registerIndependentMaster({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    UserRole role = UserRole.independentMaster,
    String? businessName,
    String? address,
    String? phone,
  }) async {
    registerCalls.add((
      email: email,
      password: password,
      firstName: firstName,
      lastName: lastName,
      role: role,
      businessName: businessName,
      address: address,
      phone: phone,
    ));
    final result = registerResult;
    if (result is Failure) throw result;
    if (result is RegisterResult) return result;
    // Legacy convenience: tests that set registerResult to a (User, AuthTokens)
    // tuple keep their existing semantics — treated as auto-login.
    if (result is (User, AuthTokens)) {
      final (user, tokens) = result;
      return RegisterResult.authenticated(user: user, tokens: tokens);
    }
    // Default: verification-required (matches the current backend default).
    return RegisterResult.verificationRequired(email: email);
  }

  @override
  Future<AuthTokens> refresh(String refreshToken) async {
    final result = refreshResult;
    if (result is Failure) throw result;
    if (result is AuthTokens) return result;
    return _defaultTokens;
  }

  @override
  Future<User> me() async {
    meCallCount++;
    if (meDelay != null) await meDelay!;
    final result = meResult;
    if (result is Failure) throw result;
    if (result is User) return result;
    return _defaultUser;
  }

  @override
  Future<void> logout() async {
    logoutCallCount++;
    if (logoutThrows) throw const UnauthorizedFailure();
  }

  @override
  Future<(User, AuthTokens)> verifyEmail({
    required String email,
    required String otp,
  }) async {
    verifyEmailCalls.add((email: email, otp: otp));
    final result = verifyEmailResult;
    if (result is Failure) throw result;
    if (result is (User, AuthTokens)) return result;
    return (_defaultUser, _defaultTokens);
  }

  @override
  Future<void> resendVerificationCode({required String email}) async {
    resendCalls.add((email: email));
    if (resendDelay != null) await resendDelay!;
    final result = resendVerificationResult;
    if (result is Failure) throw result;
  }

  @override
  Future<void> requestPasswordReset(String email) async {
    requestPasswordResetCalls.add((email: email));
    if (requestPasswordResetDelay != null) await requestPasswordResetDelay!;
    final result = requestPasswordResetResult;
    if (result is Failure) throw result;
  }

  @override
  Future<void> requestChangePasswordOtp() async {
    requestChangePasswordOtpCallCount++;
    if (requestChangePasswordOtpDelay != null) {
      await requestChangePasswordOtpDelay!;
    }
    final result = requestChangePasswordOtpResult;
    if (result is Failure) throw result;
  }

  @override
  Future<String> verifyPasswordResetOtp({
    required String email,
    required String code,
  }) async {
    verifyPasswordResetOtpCalls.add((email: email, code: code));
    final result = verifyPasswordResetOtpResult;
    if (result is Failure) throw result;
    if (result is String) return result;
    return 'default-reset-ticket';
  }

  @override
  Future<void> confirmPasswordReset({
    required String resetTicket,
    required String newPassword,
  }) async {
    confirmPasswordResetCalls.add((
      resetTicket: resetTicket,
      newPassword: newPassword,
    ));
    if (confirmPasswordResetDelay != null) await confirmPasswordResetDelay!;
    final result = confirmPasswordResetResult;
    if (result is Failure) throw result;
  }

  @override
  Future<InviteDetails> validateInvite({required String token}) async {
    validateInviteCalls.add(token);
    final result = validateInviteResult;
    if (result is Failure) throw result;
    if (result is InviteDetails) return result;
    return _defaultInvite;
  }

  @override
  Future<(User, AuthTokens)> acceptInvite({
    required String token,
    required String password,
    required String firstName,
    required String lastName,
    String? phoneNumber,
  }) async {
    acceptInviteCalls.add((
      token: token,
      password: password,
      firstName: firstName,
      lastName: lastName,
      phoneNumber: phoneNumber,
    ));
    final result = acceptInviteResult;
    if (result is Failure) throw result;
    if (result is (User, AuthTokens)) return result;
    return (_defaultUser, _defaultTokens);
  }
}
