// Phase 1.3 — Pure-analyzer checker for the `no_raw_ui_strings` rule.
//
// This file contains the AST-inspection logic for the lint rule WITHOUT
// any `custom_lint_builder` / `analyzer_plugin` imports. Splitting the
// rule into two layers — a pure checker (this file) and a thin
// `DartLintRule` adapter (`no_raw_ui_strings_rule.dart`) — lets us
// unit-test the checker via `flutter test` without dragging the analyzer
// plugin SDK (which has a known Element/Element2 incompatibility with
// the analyzer 7.x shipped in Flutter 3.41+) into the test compile graph.
//
// The checker is also reusable as a standalone CLI gate (Phase 2.x might
// run it from a `grep`-style git hook before custom_lint daemon spinup).
//
// Public API: [findRawUiStringLiterals] takes a parsed [CompilationUnit]
// + file path and returns a list of `SimpleStringLiteral` AST nodes that
// the rule would flag.

// ignore_for_file: depend_on_referenced_packages

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

/// Widget class names → set of arg keys that should never carry a raw
/// string literal. The sentinel `_positional0` marks the first positional
/// argument (used by `Text('...')`).
const String positionalFirstArg = '_positional0';

const Map<String, Set<String>> kRawUiStringTargets = {
  'Text': {positionalFirstArg},
  'AppBar': {'title'},
  'InputDecoration': {'labelText', 'hintText', 'errorText', 'helperText'},
  'ElevatedButton': {'child'},
  'TextButton': {'child'},
  'OutlinedButton': {'child'},
  'FilledButton': {'child'},
  'Tooltip': {'message'},
  'Semantics': {'label'},
  'SnackBar': {'content'},
  'AlertDialog': {'title', 'content'},
};

/// Returns `true` when [path] should be exempt from the rule entirely.
///
/// Exemptions (per Phase 1.3 § 10.0 Language Policy):
///   - Generated codegen output (`*.g.dart`, `*.freezed.dart`).
///   - The generated OpenAPI client (`lib/api/**`).
///   - Tests (`test/**`) — literals are part of the fixture surface.
///   - Debug scratch files (`_debug_*.dart`) and dev scratch folders
///     (`**/dev/**`).
bool isRawUiStringFileAllowListed(String path) {
  if (path.endsWith('.g.dart')) return true;
  if (path.endsWith('.freezed.dart')) return true;
  if (path.contains('/lib/api/')) return true;
  if (path.contains('/test/')) return true;
  if (path.contains('/dev/')) return true;
  final int lastSlash = path.lastIndexOf('/');
  final String fileName = lastSlash >= 0 ? path.substring(lastSlash + 1) : path;
  if (fileName.startsWith('_debug_')) return true;
  return false;
}

/// Walks [unit] and returns every `SimpleStringLiteral` that the
/// `no_raw_ui_strings` rule would flag. Empty literals (`''`) are filtered
/// out — they're explicitly allow-listed.
///
/// [path] is checked against [isRawUiStringFileAllowListed]; if the file
/// is allow-listed, the returned list is empty.
List<SimpleStringLiteral> findRawUiStringLiterals(
  CompilationUnit unit, {
  required String path,
}) {
  if (isRawUiStringFileAllowListed(path)) {
    return const <SimpleStringLiteral>[];
  }
  final visitor = _RawUiStringVisitor();
  unit.accept(visitor);
  return visitor.findings;
}

class _RawUiStringVisitor extends RecursiveAstVisitor<void> {
  final List<SimpleStringLiteral> findings = <SimpleStringLiteral>[];

  // `Widget(...)` calls show up as `InstanceCreationExpression` in
  // fully-resolved ASTs (custom_lint runtime path) and as
  // `MethodInvocation` in the bare `parseString` path used by unit tests
  // — we handle both.

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final String typeName = node.constructorName.type.name2.lexeme;
    _inspect(typeName, node.argumentList);
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    // Only treat unprefixed identifier invocations as candidate widget
    // constructions — `obj.foo('bar')` is never a widget call.
    if (node.target == null) {
      _inspect(node.methodName.name, node.argumentList);
    }
    super.visitMethodInvocation(node);
  }

  void _inspect(String typeName, ArgumentList argumentList) {
    final Set<String>? args = kRawUiStringTargets[typeName];
    if (args == null) return;
    final NodeList<Expression> argNodes = argumentList.arguments;
    for (var i = 0; i < argNodes.length; i++) {
      final Expression arg = argNodes[i];
      if (arg is NamedExpression) {
        final String name = arg.name.label.name;
        if (!args.contains(name)) continue;
        _checkExpression(arg.expression);
      } else {
        if (i != 0) continue;
        if (!args.contains(positionalFirstArg)) continue;
        _checkExpression(arg);
      }
    }
  }

  /// If [expr] is a non-empty `SimpleStringLiteral`, record it. If [expr]
  /// is itself a `Text(...)` invocation (the common
  /// AppBar/Button/SnackBar/AlertDialog wrapping pattern), descend into
  /// its first positional argument.
  void _checkExpression(Expression expr) {
    if (expr is InstanceCreationExpression) {
      final String inner = expr.constructorName.type.name2.lexeme;
      if (inner == 'Text') {
        _descendIntoTextFirstArg(expr.argumentList);
      }
      return;
    }
    if (expr is MethodInvocation && expr.target == null) {
      if (expr.methodName.name == 'Text') {
        _descendIntoTextFirstArg(expr.argumentList);
      }
      return;
    }
    _addIfRawLiteral(expr);
  }

  void _descendIntoTextFirstArg(ArgumentList args) {
    final NodeList<Expression> inner = args.arguments;
    if (inner.isEmpty) return;
    final Expression first = inner.first;
    if (first is NamedExpression) return;
    _addIfRawLiteral(first);
  }

  void _addIfRawLiteral(Expression expr) {
    if (expr is! SimpleStringLiteral) return;
    if (expr.value.isEmpty) return; // explicitly allowed
    // De-duplicate by source offset — the visitor can reach the same
    // literal twice for the `AppBar(title: Text('x'))` family of patterns
    // (once when descending from `AppBar.title`, once when the recursive
    // walker hits the nested `Text` directly). The `custom_lint` runtime
    // collapses overlapping ranges; we mirror that here so unit tests
    // assert clean findings without source-range matching boilerplate.
    final int offset = expr.offset;
    final bool alreadyFound = findings.any((e) => e.offset == offset);
    if (alreadyFound) return;
    findings.add(expr);
  }
}
