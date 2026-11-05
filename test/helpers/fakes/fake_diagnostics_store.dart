import 'package:beautica_mobile/core/diagnostics/install_id.dart';

/// In-memory [DiagnosticsStore] (phase 410). [failReads] / [failWrites] make
/// the corresponding calls throw, to drive the storage-failure paths.
class FakeDiagnosticsStore implements DiagnosticsStore {
  final Map<String, String> values = <String, String>{};
  bool failReads = false;
  bool failWrites = false;
  int writes = 0;

  @override
  Future<String?> read(String key) async {
    if (failReads) throw StateError('read failed');
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    if (failWrites) throw StateError('write failed');
    writes++;
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}
