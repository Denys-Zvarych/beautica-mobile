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

  /// Return value for the next [requestPasswordReset] call.
  ///
  /// Accepted values:
  ///   - `null`     → generic success (no return value).
  ///   - `Failure`  → thrown to simulate a transport / server error.
  Object? requestPasswordResetResult;

  /// Return value for the next [confirmPasswordReset] call.
  ///
  /// Accepted values:
  ///   - `null`     → success (no return value).
  ///   - `Failure`  → thrown to simulate a backend error
  ///                  (e.g. [ResetTokenInvalidFailure]).
  Object? confirmPasswordResetResult;

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

  /// Captured arguments for each [verifyEmail] call.
  /// Tests can assert `verifyEmailCalls.first.email` / `.otp`.
  final List<({String email, String otp})> verifyEmailCalls = [];

  /// Captured arguments for each [resendVerificationCode] call.
  /// Tests can assert `resendCalls.first.email` (backlog row 164).
  final List<({String email})> resendCalls = [];

  /// Captured arguments for each [requestPasswordReset] call.
  final List<({String email})> requestPasswordResetCalls = [];

  /// Captured arguments for each [confirmPasswordReset] call.
  final List<({String token, String newPassword})> confirmPasswordResetCalls =
      [];

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
    final result = resendVerificationResult;
    if (result is Failure) throw result;
  }

  @override
  Future<void> requestPasswordReset(String email) async {
    requestPasswordResetCalls.add((email: email));
    final result = requestPasswordResetResult;
    if (result is Failure) throw result;
  }

  @override
  Future<void> confirmPasswordReset({
    required String token,
    required String newPassword,
  }) async {
    confirmPasswordResetCalls.add((token: token, newPassword: newPassword));
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
