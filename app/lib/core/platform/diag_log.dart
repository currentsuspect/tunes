import 'dart:io';

import 'package:path_provider/path_provider.dart';

class DiagLog {
  DiagLog._();

  static File? _file;

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
