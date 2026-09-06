import 'dart:io';

import 'package:path_provider/path_provider.dart';

class DiagLog {
  DiagLog._();

  static File? _file;

  /// Where the log actually is, so the developer section can report its size
  /// rather than print a zero it never measured.
  static String? get path => _file?.path;

  static Future<void> init() async {
    try {
      final dir = await getApplicationCacheDirectory();
      _file = File('${dir.path}/tunes_diag.log');
      log('diag initialized at ${_file?.path}');
    } catch (e) {
      stderr.writeln('diaglog init failed: $e');
    }
  }

  static void log(String line) {
    try {
      _file?.writeAsStringSync(
        '${DateTime.now().toIso8601String()} $line\n',
        mode: FileMode.append,
      );
    } catch (e) {
      stderr.writeln('diaglog: $e — $line');
    }
  }
}
