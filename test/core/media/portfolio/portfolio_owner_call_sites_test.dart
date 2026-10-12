// Phase 403 (9.8, D9) — STRUCTURAL GATE: where a `PortfolioOwner` may be
// built.
//
// LOCKED PRODUCT RULE (user, 2026-10-12): "salon photos only related to the
// salon, not owner or admin or masters". Salon portfolio photos show ONLY on
// salon screens (salon management «Про салон», the public salon profile); the
// independent master's personal portfolio is separate; owners and admins have
// NO personal portfolio (O4).
//
// Nothing at runtime can tell a salon photo rendered on a master profile from
// one rendered on a salon screen — the leak is decided by WHICH owner a screen
// constructs. So this test pins every construction site of both variants in
// `lib/` to an explicit allow-list:
//   • `PortfolioOwner.salon(...)`      — only files under `lib/features/salon/`;
//   • `PortfolioOwner.masterSelf(...)` — only files under
//     `lib/features/master/`, and only where the master is
//     `MasterType.independentMaster` (never an owner's SALON_OWNER master row,
//     never a salon master).
//
// ADDING A SITE (phases 404 / 405) is a deliberate act: add the file to the
// allow-list below with its count, and — for `masterSelf` — make sure the
// call site is gated on `MasterType.independentMaster`. A reviewer reads
// this diff; that is the point.
//
// Matches the named factories (incl. tear-offs) and direct construction of
// the generated variant classes; ignores comments, the declaring file and
// generated code. Pattern matches such as `final PortfolioOwnerSalon o =>`
// carry no `(` and are not constructions.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const String _declaringFile = 'lib/core/media/portfolio/portfolio_owner.dart';

/// Allowed `PortfolioOwner.salon` construction sites → occurrence count.
const Map<String, int> _salonSites = <String, int>{
  // D3 delegate — the public salon profile's portfolio rail.
  'lib/features/salon/application/salon_portfolio_notifier.dart': 1,
  // Phase 404 — «Про салон» in salon management (owner + bound admin).
  'lib/features/salon/presentation/salon_management_profile_screen.dart': 1,
};

/// Allowed `PortfolioOwner.masterSelf` construction sites → occurrence count.
/// Phase 404 — both sites are gated on `MasterType.independentMaster`:
///   • the master's own profile (`_AboutTab` → `_OwnPortfolioRail`);
///   • the client-facing public profile (`isIndependent` → read only; D2
///     keys the same family entry so the two share one cache).
///
/// Phase 404 audit R5 — this map pins WHICH FILES may construct the variant
/// and how many times; it cannot see the `MasterType.independentMaster` gate
/// around each construction. That gate is covered behaviourally instead: the
/// owner / admin / salon-master "no portfolio request" screen tests
/// (`owner_own_profile_screen_test.dart`, `admin_own_profile_screen_test.dart`,
/// `salon_master_profile_screen_test.dart`,
/// `public_master_profile_screen_test.dart`) and
/// `integration_test/portfolio_render_flow_test.dart`.
const Map<String, int> _masterSites = <String, int>{
  'lib/features/master/presentation/master_profile_screen.dart': 1,
  'lib/features/master/presentation/public_master_profile_screen.dart': 1,
};

final RegExp _salonRe = RegExp(
  r'\bPortfolioOwner\s*\.\s*salon\b|\bPortfolioOwnerSalon\s*\(',
);
final RegExp _masterRe = RegExp(
  r'\bPortfolioOwner\s*\.\s*masterSelf\b|\bPortfolioOwnerMasterSelf\s*\(',
);

/// Removes `//` line and `/* */` block comments, leaving string literals
/// intact (a URL's `//` inside quotes is not a comment).
String _stripComments(String src) {
  final StringBuffer out = StringBuffer();
  String? quote;
  for (var i = 0; i < src.length; i++) {
    final String c = src[i];
    final String next = i + 1 < src.length ? src[i + 1] : '';
    if (quote != null) {
      out.write(c);
      if (c == r'\') {
        if (next.isNotEmpty) out.write(next);
        i++;
      } else if (c == quote) {
        quote = null;
      }
      continue;
    }
    if (c == "'" || c == '"') {
      quote = c;
      out.write(c);
      continue;
    }
    if (c == '/' && next == '/') {
      while (i < src.length && src[i] != '\n') {
        i++;
      }
      out.write('\n');
      continue;
    }
    if (c == '/' && next == '*') {
      i += 2;
      while (i + 1 < src.length && !(src[i] == '*' && src[i + 1] == '/')) {
        i++;
      }
      i++;
      continue;
    }
    out.write(c);
  }
  return out.toString();
}

/// Phase 404 audit R4 — portfolio WRITE entry points. A public (client-facing,
/// read-only) screen builds `PortfolioOwner.masterSelf(viewedMasterId)` for a
/// master who is NOT the viewer; a write there would be JWT-resolved to the
/// VIEWER's own portfolio while the cache showed the viewed master's list.
final RegExp _portfolioWriteRe = RegExp(
  r'\bportfolioEditControllerProvider\b|\buploadPortfolioPhoto\b|'
  r'\bdeletePortfolioPhoto\b',
);

/// Phase 404 audit S2 — ALLOW-list of files in `lib/` that may reference a
/// portfolio WRITE entry point. Any other file — a public screen, a read-only
/// staff/booking/review screen, a `presentation/widgets/` helper, anything —
/// fails the gate. Today only the declaring/internal `lib/core/media/` files.
///
/// Phase 405 (add + delete) will add exactly
///   `lib/features/master/presentation/master_profile_screen.dart` and
///   `lib/features/salon/presentation/salon_management_profile_screen.dart`
/// — owner-context screens where `PortfolioOwner` names the VIEWER's own
/// portfolio (or the salon they manage). Never a client-facing screen.
const Set<String> _portfolioWriteAllowed = <String>{
  // Declares `uploadPortfolioPhoto` / `deletePortfolioPhoto`.
  'lib/core/media/upload/media_upload_repository.dart',
  // Declares `portfolioEditControllerProvider`; calls the two writes.
  'lib/core/media/portfolio/portfolio_edit_controller.dart',
};

/// Every hand-written `.dart` file under `lib/` (generated code excluded).
Iterable<String> _libSources() sync* {
  for (final FileSystemEntity e in Directory('lib').listSync(recursive: true)) {
    if (e is! File) continue;
    final String path = e.path.replaceAll(r'\', '/');
    if (!path.endsWith('.dart') ||
        path.endsWith('.g.dart') ||
        path.endsWith('.freezed.dart')) {
      continue;
    }
    yield path;
  }
}

Map<String, int> _sites(RegExp re) {
  final Map<String, int> found = <String, int>{};
  for (final FileSystemEntity e in Directory('lib').listSync(recursive: true)) {
    if (e is! File) continue;
    final String path = e.path.replaceAll(r'\', '/');
    if (!path.endsWith('.dart') ||
        path.endsWith('.g.dart') ||
        path.endsWith('.freezed.dart') ||
        path == _declaringFile) {
      continue;
    }
    final int n = re.allMatches(_stripComments(e.readAsStringSync())).length;
    if (n > 0) found[path] = n;
  }
  return found;
}

void main() {
  test('the matchers catch every construction spelling and ignore '
      'comments / patterns (self-check, so the gate cannot pass '
      'vacuously)', () {
    for (final String s in <String>[
      "PortfolioOwner.salon('a')",
      "const PortfolioOwner.salon('a')",
      'PortfolioOwner.salon',
      "PortfolioOwnerSalon('a')",
    ]) {
      expect(_salonRe.hasMatch(_stripComments(s)), isTrue, reason: s);
      expect(_masterRe.hasMatch(_stripComments(s)), isFalse, reason: s);
    }
    for (final String s in <String>[
      "PortfolioOwner.masterSelf('m')",
      'PortfolioOwner.masterSelf',
      "PortfolioOwnerMasterSelf('m')",
    ]) {
      expect(_masterRe.hasMatch(_stripComments(s)), isTrue, reason: s);
    }
    for (final String s in <String>[
      "// PortfolioOwner.salon('a')",
      "/* PortfolioOwner.masterSelf('m') */",
      'final PortfolioOwnerSalon o => o.salonId,',
      "'https://x' // PortfolioOwner.salon('a')",
    ]) {
      final String code = _stripComments(s);
      expect(
        _salonRe.hasMatch(code) || _masterRe.hasMatch(code),
        isFalse,
        reason: s,
      );
    }
  });

  test(
    'PortfolioOwner.salon is built ONLY on salon screens (allow-listed)',
    () {
      final Map<String, int> found = _sites(_salonRe);
      expect(
        found,
        _salonSites,
        reason:
            'A new salon-portfolio site must be a SALON screen and be '
            'added to _salonSites deliberately (D9).',
      );
      for (final String path in found.keys) {
        expect(path, startsWith('lib/features/salon/'));
      }
    },
  );

  test('PortfolioOwner.masterSelf is built ONLY at allow-listed '
      'independent-master sites — never on a salon screen', () {
    final Map<String, int> found = _sites(_masterRe);
    expect(
      found,
      _masterSites,
      reason:
          'A new master-portfolio site must be an INDEPENDENT_MASTER '
          'screen and be added to _masterSites deliberately (D9, O4).',
    );
    for (final String path in found.keys) {
      expect(path, startsWith('lib/features/master/'));
    }
  });

  group('portfolio WRITE entry points are referenced ONLY by allow-listed '
      'files (R4 / S2)', () {
    test('positive control: the write matcher fires on real source and on '
        'every spelling, and ignores comments', () {
      // Real file on disk — proves the reader + matcher see production code.
      const String writer =
          'lib/core/media/portfolio/portfolio_edit_controller.dart';
      expect(
        _portfolioWriteRe.hasMatch(
          _stripComments(File(writer).readAsStringSync()),
        ),
        isTrue,
        reason: '$writer calls the repository write methods',
      );
      for (final String s in <String>[
        'ref.read(portfolioEditControllerProvider(owner).notifier)',
        'repo.uploadPortfolioPhoto(owner, file)',
        'repo.deletePortfolioPhoto(owner, id)',
      ]) {
        expect(
          _portfolioWriteRe.hasMatch(_stripComments(s)),
          isTrue,
          reason: s,
        );
      }
      expect(
        _portfolioWriteRe.hasMatch(
          _stripComments('// portfolioEditControllerProvider'),
        ),
        isFalse,
      );
    });

    test('the scanned set is not vacuously empty — it covers the public '
        'and other read-only screens and presentation/widgets/', () {
      final List<String> scanned = _libSources().toList();
      expect(
        scanned,
        containsAll(<String>[
          'lib/features/master/presentation/public_master_profile_screen.dart',
          'lib/features/salon/presentation/public_salon_profile_screen.dart',
          ..._portfolioWriteAllowed,
        ]),
      );
      expect(
        scanned.where((String p) => p.contains('/presentation/widgets/')),
        isNotEmpty,
      );
    });

    test('no file outside _portfolioWriteAllowed references '
        'portfolioEditControllerProvider, uploadPortfolioPhoto or '
        'deletePortfolioPhoto', () {
      final Set<String> found = <String>{
        for (final String path in _libSources())
          if (_portfolioWriteRe.hasMatch(
            _stripComments(File(path).readAsStringSync()),
          ))
            path,
      };
      expect(found, isNotEmpty, reason: 'gate would pass vacuously');
      expect(
        found.difference(_portfolioWriteAllowed),
        isEmpty,
        reason:
            'Only owner-context screens may write a portfolio (phase 405 '
            'adds them here deliberately). On a public / read-only screen '
            'PortfolioOwner.masterSelf names the VIEWED master, while the '
            'write would be JWT-resolved to the VIEWER\'s own portfolio.',
      );
    });
  });

  test('the allow-lists themselves respect the context split', () {
    for (final String path in _salonSites.keys) {
      expect(path, startsWith('lib/features/salon/'));
    }
    for (final String path in _masterSites.keys) {
      expect(path, startsWith('lib/features/master/'));
    }
  });
}
