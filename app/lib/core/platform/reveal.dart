import 'dart:io';

/// Opens the folder holding [file] in the computer's file manager, for a
/// saved moment or month card ("Show"). Never throws: a missing xdg-open
/// leaves the path in the message, which is still where the file is.
Future<void> revealFile(File file) async {
  if (!Platform.isLinux) return;
  try {
    await Process.start('xdg-open', [
      file.parent.path,
    ], mode: ProcessStartMode.detached);
  } catch (_) {}
}
