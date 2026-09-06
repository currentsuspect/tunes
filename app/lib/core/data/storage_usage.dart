import 'dart:io';

import 'package:flutter/painting.dart';

import 'download_store.dart';

/// What the app is actually using on this device.
///
/// Measured rather than estimated, and only the things that genuinely exist.
/// There is no artwork cache on disk to report: covers are fetched through
/// `Image.network`, which keeps decoded frames in memory and leaves any
/// on-disk caching to the platform's HTTP layer, where the app cannot see or
/// clear it. Reporting a number for it would be inventing one.
class StorageUsage {
  const StorageUsage({
    required this.downloadBytes,
    required this.downloadCount,
    required this.missingDownloads,
    required this.manifestBytes,
    required this.logBytes,
    required this.imageBytes,
    required this.imageCount,
  });

  /// Tracks kept on the device for offline playback.
  final int downloadBytes;
  final int downloadCount;

  /// Downloads the index claims but whose files have gone -- storage cleared
  /// by the system, most likely. Worth surfacing: the app would otherwise
  /// count them as held and fall back to streaming without saying why.
  final int missingDownloads;

  /// The cached copy of the library, so it opens offline.
  final int manifestBytes;

  final int logBytes;

  /// Decoded artwork held in memory. Not storage, but it is the number
  /// people mean when they ask why a gallery-heavy app is large in the
  /// running-apps list, and it is the only artwork figure that is real.
  final int imageBytes;
  final int imageCount;

  int get totalOnDisk => downloadBytes + manifestBytes + logBytes;

  static Future<int> _sizeOf(String? path) async {
    if (path == null) return 0;
    try {
      final f = File(path);
      return await f.exists() ? await f.length() : 0;
    } catch (_) {
      return 0;
    }
  }

  /// Walks the download index rather than the directory: the index is the
  /// app's own record of what it fetched, and anything else in that folder
  /// belongs to something other than downloads.
  static Future<StorageUsage> measure({
    required DownloadStore store,
    String? manifestPath,
    String? logPath,
  }) async {
    var bytes = 0;
    var count = 0;
    var missing = 0;
    for (final sha in store.shas) {
      final size = await _sizeOf(store.pathFor(sha));
      if (size == 0) {
        missing += 1;
        continue;
      }
      bytes += size;
      count += 1;
    }
    final images = PaintingBinding.instance.imageCache;
    return StorageUsage(
      downloadBytes: bytes,
      downloadCount: count,
      missingDownloads: missing,
      manifestBytes: await _sizeOf(manifestPath),
      logBytes: await _sizeOf(logPath),
      imageBytes: images.currentSizeBytes,
      imageCount: images.currentSize,
    );
  }
}

/// Bytes as something a person reads.
///
/// Rounds up to one decimal at MB and above and drops the decimal at KB: a
/// storage figure accurate to the byte is a figure nobody can compare.
String formatBytes(int bytes) {
  if (bytes <= 0) return '0 MB';
  const mb = 1024 * 1024;
  if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(1)} MB';
  return '${(bytes / 1024).round()} KB';
}
