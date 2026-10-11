import 'dart:io';

import 'package:affected_tests/cli.dart';

/// Exit codes: 64 = bad usage, 70 = unexpected selector error. Callers treat
/// ANY non-zero exit as "selector error => FULL" (phase 400 D7).
void main(List<String> args) {
  try {
    exitCode = run(args);
  } on FormatException catch (e) {
    stderr.writeln('affected_tests: ${e.message}');
    exitCode = 64;
  } catch (e) {
    stderr.writeln('affected_tests: internal error: ${e.runtimeType}');
    exitCode = 70;
  }
}
