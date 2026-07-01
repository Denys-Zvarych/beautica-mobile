// tool/openapi/fetch_spec.dart
//
// Downloads the Beautica backend OpenAPI spec and writes it to
// tool/openapi/api-spec.json.  Commit the snapshot so CI can run codegen
// offline without a live backend.
//
// Usage (run from beautica-mobile/ root):
//   dart run tool/openapi/fetch_spec.dart           # local backend (default)
//   dart run tool/openapi/fetch_spec.dart --source=local
//
// NOTE: --source=prod is intentionally NOT supported.  The production backend
// has springdoc.api-docs.enabled=false for security reasons.  Always fetch
// from the local dev backend.
//
// Exit codes:
//   0 — spec written successfully
//   1 — local backend unreachable or returned a non-200 status

import 'dart:async';
import 'dart:io';

/// Hard ceiling on the whole request/response round-trip.  Guards against a
/// backend that accepts the TCP connection but never sends (or never finishes
/// sending) the response body — `HttpClient.connectionTimeout` only covers the
/// initial connect, not a mid-stream hang.
const Duration _requestTimeout = Duration(seconds: 30);

Future<void> main(List<String> args) async {
  // Reject any --source=prod attempt early with a helpful message.
  if (args.any((a) => a.contains('prod'))) {
    stderr.writeln(
      'ERROR: --source=prod is not supported.\n'
      '  The production backend has api-docs disabled (springdoc.api-docs.enabled=false).\n'
      '  Run the local backend and use the default --source=local instead.',
    );
    exit(1);
  }

  const url = 'http://localhost:8080/api-docs';
  const outPath = 'tool/openapi/api-spec.json';

  stdout.writeln('Fetching OpenAPI spec from $url …');

  final HttpClient client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10)
    ..idleTimeout = const Duration(seconds: 10);

  // Read the full response body BEFORE closing the client.  The client is
  // closed exactly once in `finally`, after the body is consumed (or on error).
  final List<int> bytes;
  try {
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close().timeout(_requestTimeout);

    if (response.statusCode != 200) {
      // Drain the body so the connection can be released cleanly.
      await response.drain<void>();
      stderr.writeln(
        'ERROR: Backend returned HTTP ${response.statusCode} for $url.\n'
        '  Expected 200.  Check that the backend is healthy and api-docs is enabled.',
      );
      exit(1);
    }

    bytes = await response
        .fold<List<int>>(<int>[], (acc, chunk) => acc..addAll(chunk))
        .timeout(_requestTimeout);
  } on TimeoutException catch (e) {
    stderr.writeln(
      'ERROR: Timed out after ${_requestTimeout.inSeconds}s waiting for $url.\n'
      '  The backend accepted the connection but did not respond in time.\n'
      '  Check that the backend is healthy and not hung.\n'
      '  Original error: $e',
    );
    exit(1);
  } on SocketException catch (e) {
    stderr.writeln(
      'ERROR: Cannot reach local backend at $url.\n'
      '  Make sure the backend is running:\n'
      '    cd beautica-backend\n'
      '    ./gradlew bootRun --args=\'--spring.profiles.active=local\'\n'
      '  Original error: $e',
    );
    exit(1);
  } on HttpException catch (e) {
    stderr.writeln('ERROR: HTTP error while fetching spec: $e');
    exit(1);
  } finally {
    client.close();
  }

  await File(outPath).writeAsBytes(bytes);

  final kb = (bytes.length / 1024).toStringAsFixed(1);
  stdout.writeln('Spec saved to $outPath ($kb KB).');
}
