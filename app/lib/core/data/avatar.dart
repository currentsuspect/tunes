import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Storage for the profile picture.
///
/// The picker hands back a file in a cache directory that the system is free
/// to delete, and on Android it is often a copy the app has no lasting claim
/// on. So the chosen image is copied into the app's own storage immediately;
/// what gets remembered in settings is that copy, not where it came from.
class AvatarStore {
  AvatarStore({ImagePicker? picker, this.name = 'avatar', this.maxEdge = 512})
    : _picker = picker ?? ImagePicker();

  /// The same store for Glass's background photo: kept large enough to fill
  /// a phone's screen sharp, and no larger.
  AvatarStore.wallpaper({ImagePicker? picker})
    : this(picker: picker, name: 'wallpaper', maxEdge: 2000);

  final ImagePicker _picker;

  /// What the stored files are called (`<name>_<time>.jpg`).
  final String name;

  /// The avatar is shown at 38px in the header and 56px in settings. Storing a
  /// 12-megapixel photo to draw a thumbnail would cost real memory every time
  /// it decodes, so it is resized on the way in and never again.
  final double maxEdge;

  /// Opens the platform photo picker. Returns the stored path, or null if the
  /// picker was dismissed.
  Future<String?> pick() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: maxEdge,
      maxHeight: maxEdge,
      imageQuality: 90,
    );
    if (picked == null) return null;
    return store(File(picked.path));
  }

  /// Copies [source] into app storage under a fresh name.
  ///
  /// A fresh name each time, rather than a fixed avatar.jpg: Flutter caches
  /// decoded images by path, so overwriting one file leaves the previous
  /// picture on screen until the app restarts. Changing the path is what
  /// makes the new picture appear.
  Future<String> store(File source) async {
    final dir = await getApplicationSupportDirectory();
    final dest = File(
      p.join(dir.path, '${name}_${DateTime.now().millisecondsSinceEpoch}.jpg'),
    );
    await source.copy(dest.path);
    return dest.path;
  }

  /// Removes a picture that is no longer referenced.
  ///
  /// Never fatal: a picture that cannot be deleted is a stale file, whereas a
  /// throw here would leave the profile in the state the user just left.
  Future<void> discard(String? path) async {
    if (path == null || path.isEmpty) return;
    try {
      final f = File(path);
      if (f.existsSync()) await f.delete();
    } catch (_) {}
  }
}
