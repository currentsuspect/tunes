import 'dart:convert';
import 'dart:io';

import '../../domain/manifest.dart';

class TunesClient {
  TunesClient(this.baseUrl);

  final String baseUrl;

  static const _timeout = Duration(seconds: 8);

  Future<List<ManifestTrack>> fetchManifest() async {
    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      final req = await client.getUrl(Uri.parse('$baseUrl/manifest'));
      final res = await req.close().timeout(_timeout);
      if (res.statusCode != 200) {
        throw TunesFetchException('manifest ${res.statusCode}');
      }
      final body = await res.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final tracks = (json['tracks'] as List<dynamic>? ?? const [])
          .map((t) => ManifestTrack.fromJson(t as Map<String, dynamic>))
          .toList();
      return tracks;
    } on SocketException catch (e) {
      throw TunesFetchException('tunesd unreachable: ${e.message}');
    } finally {
      client.close(force: true);
    }
  }
}

class TunesFetchException implements Exception {
  TunesFetchException(this.message);

  final String message;

  @override
  String toString() => message;
}
