import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Fast, host-independent regression guard for the Android App-Link /
/// deep-link wiring (Phase 17.5, branch `feat/patrol-native`).
///
/// The end-to-end behaviour is covered by
/// `integration_test/patrol/deep_link_patrol_test.dart`, but that only runs on
/// the slow gated nightly patrol job. The whole fix hinges on three lines in
/// `android/app/src/main/AndroidManifest.xml`:
///   1. the `flutter_deeplinking_enabled=true` meta-data (forwards the
///      ACTION_VIEW intent URL to go_router via the framework),
///   2. MainActivity `launchMode="singleTop"` (so a warm-app deep link reuses
///      the existing task instead of spawning a duplicate),
///   3. the `autoVerify` App-Link intent-filter for `/invite/accept` on the
///      production Railway host.
///
/// mobile-security MEDIUM (Beautica OTP task): the `/reset-password`
/// `autoVerify` intent-filter that used to be asserted here was REMOVED from
/// the manifest. It was a stale holdover from the retired emailed-link
/// `?token=` flow — `android:pathPrefix` matches by prefix, so it also
/// claimed `/reset-password/otp` (the new unauthenticated OTP-entry screen)
/// as a live exported deep-link surface, even though that screen only ever
/// reads `GoRouterState.extra` from in-app navigation and never a URL. See
/// the regression guard below asserting it stays gone.
///
/// An accidental manifest edit would silently break deep-link routing and only
/// surface in the gated patrol job. This contract test reads the raw manifest
/// and fails fast in the normal `flutter test` job.
///
/// Assertions are deliberately tolerant to attribute ordering and whitespace —
/// they match against a whitespace-collapsed view of the file and use RegExps
/// that allow newlines/spaces between attributes — so cosmetic reformatting of
/// the manifest does not produce false failures.
void main() {
  // Relative to the package root (`beautica-mobile/`), which is `flutter test`'s
  // working directory.
  const manifestPath = 'android/app/src/main/AndroidManifest.xml';
  const productionHost = 'beautica-backend-production.up.railway.app';

  late String manifest;

  // Whitespace-collapsed view: every run of whitespace (incl. newlines) becomes
  // a single space. Lets `contains` checks ignore source-formatting choices.
  late String collapsed;

  setUpAll(() {
    final file = File(manifestPath);
    expect(
      file.existsSync(),
      isTrue,
      reason:
          'Expected AndroidManifest at "$manifestPath" relative to the package '
          'root. `flutter test` runs from beautica-mobile/; if this fails the '
          'manifest moved or the working directory is wrong.',
    );
    manifest = file.readAsStringSync();
    collapsed = manifest.replaceAll(RegExp(r'\s+'), ' ');
  });

  group('AndroidManifest deep-link contract', () {
    test('declares flutter_deeplinking_enabled=true meta-data', () {
      // <meta-data> with name + value attributes in either order, tolerant of
      // whitespace/newlines between attributes and around the `=`.
      final nameThenValue = RegExp(
        r'<meta-data\b[^>]*android:name\s*=\s*"flutter_deeplinking_enabled"'
        r'[^>]*android:value\s*=\s*"true"',
        dotAll: true,
      );
      final valueThenName = RegExp(
        r'<meta-data\b[^>]*android:value\s*=\s*"true"'
        r'[^>]*android:name\s*=\s*"flutter_deeplinking_enabled"',
        dotAll: true,
      );

      expect(
        nameThenValue.hasMatch(manifest) || valueThenName.hasMatch(manifest),
        isTrue,
        reason:
            'Missing <meta-data android:name="flutter_deeplinking_enabled" '
            'android:value="true"/>. Without it, an approved https ACTION_VIEW '
            'intent reaching MainActivity is NOT forwarded to Flutter\'s '
            'RouteInformationProvider, so go_router never navigates to '
            '/invite/accept and deep-linking silently breaks.',
      );
    });

    test('MainActivity declares launchMode="singleTop"', () {
      // Find the .MainActivity <activity ...> open tag and assert it carries
      // the singleTop launch mode. Match up to the first `>` so we stay scoped
      // to the activity element's attributes.
      final activityTag = RegExp(
        r'<activity\b[^>]*android:name\s*=\s*"\.MainActivity"[^>]*>',
        dotAll: true,
      );
      final match = activityTag.firstMatch(manifest);
      expect(
        match,
        isNotNull,
        reason:
            'Could not locate the <activity android:name=".MainActivity"> '
            'element in the manifest.',
      );

      final launchMode = RegExp(r'android:launchMode\s*=\s*"singleTop"');
      expect(
        launchMode.hasMatch(match!.group(0)!),
        isTrue,
        reason:
            'MainActivity must declare android:launchMode="singleTop" so a '
            'deep link delivered to a warm app reuses the existing task '
            '(onNewIntent) instead of launching a duplicate Activity.',
      );
    });

    test('declares an autoVerify App-Link intent-filter for /invite/accept '
        'on the production host', () {
      // Slice each <intent-filter ...> ... </intent-filter> block and find the
      // one that is autoVerify="true" AND targets the production host AND
      // references /invite/accept via pathPrefix | pathPattern | path.
      final intentFilters = RegExp(
        r'<intent-filter\b[^>]*>.*?</intent-filter>',
        dotAll: true,
      ).allMatches(manifest).map((m) => m.group(0)!).toList();

      expect(
        intentFilters,
        isNotEmpty,
        reason: 'No <intent-filter> elements found in the manifest.',
      );

      final autoVerify = RegExp(r'android:autoVerify\s*=\s*"true"');
      final host = RegExp(
        'android:host\\s*=\\s*"${RegExp.escape(productionHost)}"',
      );
      // Accept pathPrefix, pathPattern, or path attributes referencing
      // /invite/accept.
      final invitePath = RegExp(
        r'android:path(Prefix|Pattern)?\s*=\s*"[^"]*/invite/accept[^"]*"',
      );

      final matching = intentFilters.where((block) {
        final c = block.replaceAll(RegExp(r'\s+'), ' ');
        return autoVerify.hasMatch(c) &&
            host.hasMatch(c) &&
            invitePath.hasMatch(c);
      }).toList();

      expect(
        matching,
        isNotEmpty,
        reason:
            'Missing the App-Link intent-filter that handles invite-accept '
            'deep links. Expected a single <intent-filter '
            'android:autoVerify="true"> containing <data '
            'android:host="$productionHost" '
            'android:pathPrefix="/invite/accept" .../>. autoVerify prevents '
            'a competing app from intercepting the single-use invite token '
            'from the emailed link.',
      );
    });

    test('invite/accept App-Link uses the https scheme', () {
      // Defence-in-depth: the invite/accept App-Link must be https (App Links
      // are https-only; an http data element would never auto-verify).
      final inviteFilter = RegExp(
        r'<intent-filter\b[^>]*android:autoVerify\s*=\s*"true"[^>]*>'
        r'(?:(?!</intent-filter>).)*?/invite/accept'
        r'(?:(?!</intent-filter>).)*?</intent-filter>',
        dotAll: true,
      ).firstMatch(manifest);

      expect(
        inviteFilter,
        isNotNull,
        reason:
            'Could not isolate the autoVerify /invite/accept '
            'intent-filter to check its scheme.',
      );

      final httpsScheme = RegExp(r'android:scheme\s*=\s*"https"');
      expect(
        httpsScheme.hasMatch(
          inviteFilter!.group(0)!.replaceAll(RegExp(r'\s+'), ' '),
        ),
        isTrue,
        reason:
            'The /invite/accept App-Link intent-filter must use '
            'android:scheme="https". App Links are https-only; an http scheme '
            'would silently fail to auto-verify against assetlinks.json.',
      );
    });

    // mobile-security MEDIUM (Beautica OTP task) — regression guard. The
    // /reset-password autoVerify intent-filter was intentionally REMOVED: it
    // was a stale holdover from the retired emailed-link `?token=` flow, and
    // because android:pathPrefix matches by prefix it also kept
    // /reset-password/otp (the new unauthenticated OTP-entry screen) claimed
    // as a live exported deep-link surface for a flow that no longer receives
    // anything meaningful from a URL. Fails red if this filter is
    // reintroduced.
    test('does NOT declare an autoVerify App-Link intent-filter for '
        '/reset-password (retired — OTP flow uses in-app navigation only)', () {
      final intentFilters = RegExp(
        r'<intent-filter\b[^>]*>.*?</intent-filter>',
        dotAll: true,
      ).allMatches(manifest).map((m) => m.group(0)!).toList();

      final autoVerify = RegExp(r'android:autoVerify\s*=\s*"true"');
      final host = RegExp(
        'android:host\\s*=\\s*"${RegExp.escape(productionHost)}"',
      );
      final resetPath = RegExp(
        r'android:path(Prefix|Pattern)?\s*=\s*"[^"]*/reset-password[^"]*"',
      );

      final matching = intentFilters.where((block) {
        final c = block.replaceAll(RegExp(r'\s+'), ' ');
        return autoVerify.hasMatch(c) &&
            host.hasMatch(c) &&
            resetPath.hasMatch(c);
      }).toList();

      expect(
        matching,
        isEmpty,
        reason:
            'A /reset-password autoVerify App-Link intent-filter has been '
            'reintroduced. Nothing in the OTP password-reset flow needs '
            'external linkability anymore (ResetOtpVerificationScreen / '
            'ResetPasswordScreen only ever consume GoRouterState.extra), '
            'and android:pathPrefix would also re-claim '
            '/reset-password/otp as an exported surface.',
      );
    });

    test('production host is wired (sanity check on collapsed manifest)', () {
      // Guards against the host being renamed/typo\'d anywhere in the manifest,
      // which would break every App-Link filter at once.
      expect(
        collapsed.contains(productionHost),
        isTrue,
        reason:
            'Production App-Link host "$productionHost" is not present in the '
            'manifest. A renamed/typo\'d host breaks all https deep links.',
      );
    });
  });
}
