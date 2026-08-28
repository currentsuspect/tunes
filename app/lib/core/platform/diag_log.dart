import 'dart:io';

class DiagLog {
  DiagLog._();

  static File? _file;

  static void init() {
    _file ??= File('${Directory.systemTemp.path}/tunes_diag.log');
  }

  static void log(String line) {
    try {
      _file?.writeAsStringSync(
        '${DateTime.now().toIso8601String()} $line\n',
        mode: FileMode.append,
      );
    } catch (_) {}
  }
}
