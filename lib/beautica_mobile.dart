// `custom_lint_builder` is a dev_dependency (it's the plugin-author SDK).
// The analyzer flags the import as a transitive reference because the
// entrypoint convention puts this file under `lib/`. Suppress the cosmetic
// lint — this file is the analyzer-plugin entrypoint, not runtime code.
// ignore_for_file: depend_on_referenced_packages

// Phase 1.3 — `custom_lint` plugin entrypoint.
//
// `custom_lint_builder` discovers a plugin by importing the package's
// `lib/<package_name>.dart` and calling its top-level `createPlugin()`
// function. For this project that file is right here:
//   beautica-mobile/lib/beautica_mobile.dart
//
// This file MUST NOT be imported by application code — it is the
// analyzer-plugin entrypoint only. Keeping it dependency-free of the
// rest of `lib/` (other than the rules under `lib/core/lints/`)
// prevents accidental coupling between runtime widgets and plugin code.
//
// To add a new lint rule:
//   1. Implement it under `lib/core/lints/<rule>_rule.dart`.
//   2. Add it to the `getLintRules` list below.
//   3. Register it in `analysis_options.yaml` under `custom_lint: rules:`.
//   4. Cover it with a test under `test/core/lints/`.

import 'package:custom_lint_builder/custom_lint_builder.dart';

import 'core/lints/no_raw_ui_strings_rule.dart';

/// Entrypoint invoked by the `custom_lint` runtime when the analyzer loads
/// the plugin. Returns the set of rules defined by `beautica_mobile`.
PluginBase createPlugin() => _BeauticaLints();

class _BeauticaLints extends PluginBase {
  @override
  List<LintRule> getLintRules(CustomLintConfigs configs) => const [
    NoRawUiStringsRule(),
  ];
}
