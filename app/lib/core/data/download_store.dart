import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

class DownloadStore extends ChangeNotifier {
  DownloadStore(this.dir);

  final Directory dir;

  Map<String, String> _bySha = {};

  File get _indexFile => File('${dir.path}/downloads.json');

  bool contains(String sha) => _bySha.containsKey(sha);

  String? pathFor(String sha) => _bySha[sha];

  List<String> get shas => _bySha.keys.toList();

  bool get isEmpty => _bySha.isEmpty;

  Future<void> load() async {
    try {
      if (await _indexFile.exists()) {
        final raw = await _indexFile.readAsString();
        final json = jsonDecode(raw) as Map<String, dynamic>;
        _bySha = (json['files'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, v as String),
        );
      }
    } catch (_) {
      _bySha = {};
    }
    notifyListeners();
  }

  Future<void> add(String sha, String path) async {
    _bySha[sha] = path;
    notifyListeners();
    await _persist();
  }

  Future<void> remove(String sha) async {
    final path = _bySha.remove(sha);
    notifyListeners();
    if (path != null) {
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    await _persist();
  }

  String newPathFor(String sha) => '${dir.path}/$sha';

  Future<void> _persist() async {
    try {
      await dir.create(recursive: true);
      await _indexFile.writeAsString(jsonEncode({'files': _bySha}));
    } catch (_) {}
  }
}
