import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

class UpdateInfo {
  UpdateInfo({
    required this.tag,
    required this.version,
    required this.notes,
    required this.apkUrl,
    required this.apkSize,
  });

  final String tag;
  final String version;
  final String notes;
  final String apkUrl;
  final int apkSize;
}

class UpdateChecker {
  /// Repo GitHuba które trzyma release'y APK. Zmień jeśli kiedyś zmienisz nazwę.
  static const String _owner = 'grekot';
  static const String _repo = 'kalendarzyk-app';
  static const String _latestUrl =
      'https://api.github.com/repos/$_owner/$_repo/releases/latest';

  /// Sprawdza GitHub Releases. Zwraca info o nowej wersji albo null gdy
  /// jesteśmy aktualni / coś poszło nie tak (offline, brak release'a, itp.).
  /// Działa tylko na Androidzie — na innych platformach zwraca null.
  Future<UpdateInfo?> checkForUpdate() async {
    if (!Platform.isAndroid) return null;
    try {
      final pkg = await PackageInfo.fromPlatform();
      final current = '${pkg.version}+${pkg.buildNumber}';

      final res = await http
          .get(Uri.parse(_latestUrl))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;

      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final tag = (json['tag_name'] as String?) ?? '';
      if (tag.isEmpty) return null;
      final version = tag.startsWith('v') ? tag.substring(1) : tag;

      if (compareVersions(version, current) <= 0) return null;

      final assets = (json['assets'] as List?) ?? const [];
      Map<String, dynamic>? arm64Asset;
      for (final raw in assets) {
        final asset = raw as Map<String, dynamic>;
        final name = (asset['name'] as String?) ?? '';
        if (name.contains('arm64-v8a') && name.endsWith('.apk')) {
          arm64Asset = asset;
          break;
        }
      }
      if (arm64Asset == null) return null;

      return UpdateInfo(
        tag: tag,
        version: version,
        notes: (json['body'] as String?) ?? '',
        apkUrl: arm64Asset['browser_download_url'] as String,
        apkSize: (arm64Asset['size'] as int?) ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  /// Pobiera APK do tmp i otwiera systemowym instalatorem (Intent.ACTION_VIEW).
  /// User akceptuje instalację w systemowym dialogu Androida.
  Future<void> downloadAndInstall(
    UpdateInfo info, {
    void Function(double progress)? onProgress,
  }) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/kalendarzyk_${info.version}.apk');

    // Streamed download z progress callback'iem.
    final client = http.Client();
    try {
      final req = http.Request('GET', Uri.parse(info.apkUrl));
      final res = await client.send(req);
      if (res.statusCode != 200) {
        throw Exception('Pobieranie nie powiodło się (HTTP ${res.statusCode})');
      }
      final total = res.contentLength ?? info.apkSize;
      final sink = file.openWrite();
      var received = 0;
      await for (final chunk in res.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0 && onProgress != null) {
          onProgress(received / total);
        }
      }
      await sink.flush();
      await sink.close();
    } finally {
      client.close();
    }

    final openResult = await OpenFilex.open(file.path);
    if (openResult.type != ResultType.done) {
      throw Exception('Nie udało się otworzyć instalatora: ${openResult.message}');
    }
  }

  /// Porównuje wersje typu "1.2.3+4" — zwraca -1/0/1.
  static int compareVersions(String a, String b) {
    final pa = _parse(a);
    final pb = _parse(b);
    final len = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < len; i++) {
      final ai = i < pa.length ? pa[i] : 0;
      final bi = i < pb.length ? pb[i] : 0;
      if (ai != bi) return ai.compareTo(bi);
    }
    return 0;
  }

  static List<int> _parse(String v) {
    final parts = v.split('+');
    final out = <int>[];
    out.addAll(parts[0].split('.').map((s) => int.tryParse(s) ?? 0));
    while (out.length < 3) {
      out.add(0);
    }
    out.add(parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0);
    return out;
  }
}
