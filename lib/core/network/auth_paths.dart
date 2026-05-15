/// Shared set of auth endpoint paths used by interceptors.
///
/// Both [AuthInterceptor] and [LoggingInterceptor] reference this set
/// so additions only need to be made in one place.
///
/// Paths are matched against [RequestOptions.path], which contains only the
/// path segment (no host), as set by [BaseOptions.baseUrl].
const Set<String> kAuthPaths = {
  '/auth/login',
  '/auth/register',
  '/auth/register/independent-master',
  '/auth/refresh',
};
