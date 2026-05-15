// Fake [AuthRepository] for widget and unit tests.
//
// Captures calls to login/register so tests can assert which arguments were
// passed. Configure responses via the settable fields below.
// Default behaviour: throws [UnimplementedError] for any un-configured method.

import 'package:beautica_mobile/core/errors/failures.dart';
import 'package:beautica_mobile/features/auth/data/auth_repository.dart';
import 'package:beautica_mobile/features/auth/domain/auth_tokens.dart';
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
    })
  >
  registerCalls = [];
  int logoutCallCount = 0;

  // ---------------------------------------------------------------------------
  // AuthRepository
  // ---------------------------------------------------------------------------

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
  Future<(User, AuthTokens)> registerIndependentMaster({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    UserRole role = UserRole.independentMaster,
    String? businessName,
  }) async {
    registerCalls.add((
      email: email,
      password: password,
      firstName: firstName,
      lastName: lastName,
      role: role,
      businessName: businessName,
    ));
    final result = registerResult;
    if (result is Failure) throw result;
    if (result is (User, AuthTokens)) return result;
    return (_defaultUser, _defaultTokens);
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
}
