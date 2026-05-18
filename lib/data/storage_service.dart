import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

class StorageService {
  StorageService(this._client);
  final SupabaseClient _client;

  static const String bucket = 'profile_photos';

  /// Upload pliku obrazu do `profile_photos/<profileId>/<timestamp>.<ext>`.
  /// Zwraca publiczny URL.
  Future<String> uploadProfilePhoto({
    required String profileId,
    required File source,
  }) async {
    final ext = _extOf(source.path);
    final ts = DateTime.now().toUtc().microsecondsSinceEpoch;
    final path = '$profileId/$ts$ext';
    await _client.storage.from(bucket).upload(
          path,
          source,
          fileOptions: FileOptions(
            cacheControl: '3600',
            upsert: false,
            contentType: _mimeFor(ext),
          ),
        );
    return _client.storage.from(bucket).getPublicUrl(path);
  }

  /// Usuwa wszystkie zdjęcia danego profilu (np. przy usuwaniu profilu).
  Future<void> deleteAllForProfile(String profileId) async {
    try {
      final list = await _client.storage.from(bucket).list(path: profileId);
      if (list.isEmpty) return;
      final paths = list.map((f) => '$profileId/${f.name}').toList();
      await _client.storage.from(bucket).remove(paths);
    } catch (_) {
      // ignorujemy — sprzątanie best-effort
    }
  }

  /// Usuwa konkretny obraz po URL (wyciągamy path z URL-a).
  Future<void> deleteByUrl(String publicUrl) async {
    final path = _pathFromPublicUrl(publicUrl);
    if (path == null) return;
    try {
      await _client.storage.from(bucket).remove([path]);
    } catch (_) {
      // ignorujemy
    }
  }

  String? _pathFromPublicUrl(String url) {
    final marker = '/object/public/$bucket/';
    final idx = url.indexOf(marker);
    if (idx < 0) return null;
    return url.substring(idx + marker.length);
  }

  String _extOf(String path) {
    final i = path.lastIndexOf('.');
    if (i < 0) return '.jpg';
    final sep = path.lastIndexOf(RegExp(r'[\\/]'));
    if (i <= sep) return '.jpg';
    final ext = path.substring(i).toLowerCase();
    return ext.length <= 6 ? ext : '.jpg';
  }

  String _mimeFor(String ext) {
    switch (ext.toLowerCase()) {
      case '.png':
        return 'image/png';
      case '.gif':
        return 'image/gif';
      case '.webp':
        return 'image/webp';
      case '.bmp':
        return 'image/bmp';
      case '.heic':
      case '.heif':
        return 'image/heic';
      case '.jpg':
      case '.jpeg':
      default:
        return 'image/jpeg';
    }
  }
}
