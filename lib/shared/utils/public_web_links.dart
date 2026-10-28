// Public website pages the app links out to (legal documents).
//
// Built ONLY from [AppConfig.publicWebOrigin] — the single allow-listed
// website origin. Never hard-code another host here.

import '../../core/config/app_config.dart';

/// Absolute URLs of the public website's legal pages.
abstract final class PublicWebLinks {
  /// «Умови використання» — `https://beautica.app/terms`.
  static final Uri terms = Uri.parse('${AppConfig.publicWebOrigin}/terms');

  /// «Політика конфіденційності» — `https://beautica.app/privacy`.
  static final Uri privacy = Uri.parse('${AppConfig.publicWebOrigin}/privacy');
}
