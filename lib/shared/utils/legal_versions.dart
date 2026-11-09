// Phase 443 — versions of the legal documents the user accepts at sign-up.
//
// BUMP THESE TOGETHER WITH THE WEBSITE LEGAL DOCS. Each value equals the
// `updated:` frontmatter date of the matching website document:
//   - [kTermsVersion]         = beautica-website/src/content/legal/uk/terms.md
//   - [kPrivacyPolicyVersion] = beautica-website/src/content/legal/uk/privacy.md
//                               (also the website `PRIVACY_POLICY_VERSION`,
//                               beautica-website/src/config/legal.mjs)
//
// Format: `YYYY-MM-DD` with an optional `.N` same-day suffix (1-3 digits) —
// the backend validates `^\d{4}-\d{2}-\d{2}(\.\d{1,3})?$` and rejects a date
// in the future. Sent only as the full triple
// (`termsAccepted: true` + both versions) — never partially.

/// Version of «Умови використання» accepted at registration / invite accept.
const String kTermsVersion = '2026-10-29';

/// Version of «Політика конфіденційності» accepted at registration / invite
/// accept.
const String kPrivacyPolicyVersion = '2026-11-07';
