/// Route path constants for `go_router`.
///
/// Raw path strings must never appear elsewhere in `lib/` — always reference
/// this class so renaming a route is a single-point change.
abstract final class RouteNames {
  static const String splash = '/splash';
  static const String login = '/login';
  static const String register = '/register';
  static const String home = '/';
}
