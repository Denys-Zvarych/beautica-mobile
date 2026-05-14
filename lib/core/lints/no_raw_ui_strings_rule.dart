// `analyzer` and `custom_lint_builder` are dev-side dependencies pulled
// in by the `custom_lint` plugin host. The `depend_on_referenced_packages`
// info is cosmetic — direct-pinning analyzer in pubspec is fragile across
// Flutter SDK bumps, and this file is plugin-side only (never imported by
// runtime app code).
// ignore_for_file: depend_on_referenced_packages

// Phase 1.3 — Custom lint: `no_raw_ui_strings`.
//
// Enforces ARCHITECTURE-mobile.md § 10.0 (Language Policy): every
// user-facing string flows through `AppLocalizations`. The rule is a
// thin `custom_lint_builder` adapter on top of the pure analyzer logic
// in `no_raw_ui_strings_checker.dart` — splitting the two layers lets
// `flutter test` exercise the checker without dragging the broken
// `analyzer_plugin` 0.12.0 transitive into the test compile graph (it
// uses analyzer's `Element` API, which Flutter 3.41+ ships as `Element2`).
//
// Severity: WARNING for Phase 1.3 (staged ramp). Promoted to ERROR at
// the start of Phase 1.5 (error-handling foundation). The promotion is
// one line in `analysis_options.yaml` — no rule-code change.
//
// Allow-list (per phase doc Step 8) lives in `isRawUiStringFileAllowListed`
// inside the checker. Same-line / preceding `// ignore: no_raw_ui_strings`
// directives are honoured by the `custom_lint` runtime (see
// custom_lint/src/client.dart#parseIgnoreForFile) — no rule-side handling.
//
// Target widget surface (narrow start — expand in later phases) lives in
// `kRawUiStringTargets` inside the checker. See the checker file for the
// full list.

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/error/error.dart' show ErrorSeverity;
import 'package:analyzer/error/listener.dart';
import 'package:custom_lint_builder/custom_lint_builder.dart';

import 'no_raw_ui_strings_checker.dart';

/// Flags raw user-visible string literals passed to Material widget args
/// that should always carry localized text via `AppLocalizations`.
class NoRawUiStringsRule extends DartLintRule {
  const NoRawUiStringsRule() : super(code: _code);

  static const LintCode _code = LintCode(
    name: 'no_raw_ui_strings',
    problemMessage:
        'Raw user-visible string literal — route this through '
        '`AppLocalizations.of(context).<key>` instead.',
    correctionMessage:
        'Add the key to `lib/l10n/app_uk.arb` (and mirror in `app_en.arb`), '
        'run `flutter gen-l10n`, then reference '
        '`AppLocalizations.of(context).<key>`.',
    errorSeverity: ErrorSeverity.WARNING,
  );

  @override
  void run(
    CustomLintResolver resolver,
    ErrorReporter reporter,
    CustomLintContext context,
  ) {
    if (isRawUiStringFileAllowListed(resolver.path)) return;

    context.registry.addInstanceCreationExpression((node) {
      final String typeName = node.constructorName.type.name2.lexeme;
      final Set<String>? args = kRawUiStringTargets[typeName];
      if (args == null) return;

      // Walk argument list, dispatching on positional/named slots we care
      // about. For widgets like `AppBar(title: Text('x'))` we descend one
      // level into a wrapping `Text(...)` to surface the inner literal.
      final NodeList<Expression> argNodes = node.argumentList.arguments;
      for (var i = 0; i < argNodes.length; i++) {
        final Expression arg = argNodes[i];
        if (arg is NamedExpression) {
          final String name = arg.name.label.name;
          if (!args.contains(name)) continue;
          _checkExpression(arg.expression, reporter);
        } else {
          // Only the first positional slot is interesting for `Text('...')`.
          if (i != 0) continue;
          if (!args.contains(positionalFirstArg)) continue;
          _checkExpression(arg, reporter);
        }
      }
    });
  }

  /// Reports a lint if [expr] is a non-empty `SimpleStringLiteral`. When
  /// [expr] is itself a `Text(...)` invocation (the common AppBar / Button
  /// child / SnackBar.content / AlertDialog.title|content pattern), we
  /// descend into its first positional argument.
  void _checkExpression(Expression expr, ErrorReporter reporter) {
    if (expr is InstanceCreationExpression) {
      final String inner = expr.constructorName.type.name2.lexeme;
      if (inner == 'Text') {
        final NodeList<Expression> args = expr.argumentList.arguments;
        if (args.isNotEmpty && args.first is! NamedExpression) {
          _reportIfRawLiteral(args.first, reporter);
        }
      }
      return;
    }
    _reportIfRawLiteral(expr, reporter);
  }

  void _reportIfRawLiteral(Expression expr, ErrorReporter reporter) {
    if (expr is! SimpleStringLiteral) return;
    if (expr.value.isEmpty) return; // explicitly allowed
    reporter.atNode(expr, code);
  }
}
