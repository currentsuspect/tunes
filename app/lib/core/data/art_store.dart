import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';

import '../net/tunes_client.dart';

/// On-disk cover cache, keyed by art sha.
///
/// Every sleeve in the app loads from the network; with no local copy a
/// downloaded library still shows empty frames the moment the box is
/// unreachable. Covers are content-addressed and immutable like the audio,
/// so a file on disk is never stale -- presence is the whole index.
class ArtStore extends ChangeNotifier {
  ArtStore(this.dir, {this._client});

  final Directory dir;

  /// Set at download time (see [DownloadManager]) or lazily by [fetch].
  TunesClient? _client;

  void attachClient(TunesClient client) => _client = client;

  final Map<String, String> _bySha = {};
  final Set<String> _inflight = {};

  File get _indexFile => File('${dir.path}/art.json');

  bool contains(String sha) => _bySha.containsKey(sha);

  String? pathFor(String sha) => _bySha[sha];

  Future<void> load() async {
    try {
      if (await _indexFile.exists()) {
        final raw = await _indexFile.readAsString();
        final json = jsonDecode(raw) as Map<String, dynamic>;
        _bySha
          ..clear()
          ..addAll(
            (json['files'] as Map<String, dynamic>? ?? {}).map(
              (k, v) => MapEntry(k, v as String),
            ),
          );
      }
    } catch (_) {
      _bySha.clear();
    }
    notifyListeners();
  }

  /// Fetches a cover unless it is already on disk or in flight. Best effort:
  /// a missing cover is an empty frame, never an error surface.
  Future<void> fetch(String sha) async {
    if (sha.isEmpty || contains(sha) || _inflight.contains(sha)) return;
    final client = _client;
    if (client == null) return;
    _inflight.add(sha);
    try {
      final path = '${dir.path}/$sha';
      await client.downloadArt(sha, path);
      _bySha[sha] = path;
      notifyListeners();
      await _persist();
    } catch (_) {
      // Leave no trace: a later view retries.
    } finally {
      _inflight.remove(sha);
    }
  }

  Future<void> _persist() async {
    try {
      await dir.create(recursive: true);
      await _indexFile.writeAsString(jsonEncode({'files': _bySha}));
    } catch (_) {}
  }
}

/// Makes the [ArtStore] reachable from any sleeve without threading it
/// through every screen. Sleeves repaint when the store notifies.
class ArtScope extends InheritedNotifier<ArtStore> {
  const ArtScope({super.key, required ArtStore store, required super.child})
    : super(notifier: store);

  static ArtStore? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<ArtScope>()?.notifier;
  }
}
