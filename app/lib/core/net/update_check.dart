/// What the daemon says the newest app build is.
class AvailableUpdate {
  const AvailableUpdate({
    required this.build,
    required this.name,
    required this.notes,
    required this.size,
  });

  /// CI run number, the same value a build carries as BUILD_NUMBER.
  final int build;
  final String name;
  final String notes;

  /// Bytes. Shown before downloading, because this is ~100 MB and the person
  /// tapping may be on mobile data.
  final int size;

  static AvailableUpdate? fromJson(Map<String, dynamic> json) {
    final build = json['build'];
    if (build is! int || build <= 0) return null;
    return AvailableUpdate(
      build: build,
      name: (json['name'] as String?) ?? 'build-$build',
      notes: (json['notes'] as String?) ?? '',
      size: (json['size'] as int?) ?? 0,
    );
  }

  String get readableSize {
    if (size <= 0) return '';
    final mb = size / (1024 * 1024);
    return '${mb.toStringAsFixed(mb >= 100 ? 0 : 1)} MB';
  }
}

/// Whether [available] is worth telling the listener about.
///
/// [currentBuild] is what this build was compiled with. A local or sideloaded
/// build carries something that is not a number, and in that case the honest
/// answer is no: an update prompt against an unknown baseline is a prompt that
/// fires forever, and the person running a hand-built APK is the last person
/// who wants to be told to replace it.
bool shouldOfferUpdate(String currentBuild, AvailableUpdate? available) {
  if (available == null) return false;
  final mine = int.tryParse(currentBuild.trim());
  if (mine == null) return false;
  return available.build > mine;
}
