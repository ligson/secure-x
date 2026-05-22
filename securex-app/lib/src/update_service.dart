import 'dart:io';

import 'package:dio/dio.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

class ReleaseAsset {
  const ReleaseAsset({
    required this.name,
    required this.downloadUrl,
    required this.size,
  });

  final String name;
  final String downloadUrl;
  final int size;
}

class ReleaseInfo {
  const ReleaseInfo({
    required this.tagName,
    required this.name,
    required this.body,
    required this.htmlUrl,
    required this.assets,
  });

  final String tagName;
  final String name;
  final String body;
  final String htmlUrl;
  final List<ReleaseAsset> assets;
}

class AppVersionInfo {
  const AppVersionInfo({
    required this.version,
    required this.buildNumber,
  });

  final String version;
  final String buildNumber;

  String get display => buildNumber.isEmpty ? version : '$version+$buildNumber';
}

class UpdateService {
  UpdateService({Dio? dio}) : _dio = dio ?? Dio();

  static const repository = 'ligson/secure-x';
  static const releasesUrl = 'https://github.com/$repository/releases';

  final Dio _dio;

  Future<AppVersionInfo> currentVersion() async {
    final info = await PackageInfo.fromPlatform();
    return AppVersionInfo(
      version: info.version,
      buildNumber: info.buildNumber,
    );
  }

  Future<ReleaseInfo> fetchLatestRelease() async {
    final response = await _dio.get<Map<String, dynamic>>(
      'https://api.github.com/repos/$repository/releases/latest',
      options: Options(headers: {'Accept': 'application/vnd.github+json'}),
    );
    final data = response.data ?? <String, dynamic>{};
    final rawAssets = data['assets'];
    return ReleaseInfo(
      tagName: (data['tag_name'] ?? '').toString(),
      name: (data['name'] ?? '').toString(),
      body: (data['body'] ?? '').toString(),
      htmlUrl: (data['html_url'] ?? releasesUrl).toString(),
      assets: rawAssets is List
          ? rawAssets
                .whereType<Map<String, dynamic>>()
                .map(
                  (asset) => ReleaseAsset(
                    name: (asset['name'] ?? '').toString(),
                    downloadUrl: (asset['browser_download_url'] ?? '')
                        .toString(),
                    size: (asset['size'] as num?)?.toInt() ?? 0,
                  ),
                )
                .where((asset) => asset.name.isNotEmpty)
                .toList()
          : const [],
    );
  }

  Future<bool> hasNewVersion(ReleaseInfo latest) async {
    final current = await currentVersion();
    return compareVersions(latest.tagName, current.version) > 0;
  }

  Future<ReleaseAsset?> pickAssetForCurrentPlatform(ReleaseInfo release) async {
    final assets = release.assets;
    if (Platform.isAndroid) {
      return _firstAsset(assets, (name) => name.endsWith('-android.apk'));
    }
    if (Platform.isIOS) {
      return null;
    }
    if (Platform.isMacOS) {
      final arch = await _runtimeArch();
      final key = arch.contains('arm64') || arch.contains('aarch64')
          ? 'macos-arm64'
          : 'macos-x64';
      return _firstAsset(assets, (name) => name.contains(key));
    }
    if (Platform.isWindows) {
      return _firstAsset(assets, (name) => name.contains('windows-x64'));
    }
    if (Platform.isLinux) {
      return _firstAsset(assets, (name) => name.contains('linux'));
    }
    return null;
  }

  Future<File> downloadAsset(
    ReleaseAsset asset, {
    required void Function(int received, int total) onProgress,
  }) async {
    final directory = await getTemporaryDirectory();
    final safeName = asset.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '-');
    final file = File('${directory.path}/secure-x-updates/$safeName');
    await file.parent.create(recursive: true);

    await _dio.download(
      asset.downloadUrl,
      file.path,
      onReceiveProgress: onProgress,
      options: Options(responseType: ResponseType.bytes),
    );
    return file;
  }

  Future<void> openDownloadedFile(File file) async {
    final result = await OpenFilex.open(file.path);
    if (result.type != ResultType.done) {
      throw StateError(result.message);
    }
  }

  Future<void> openReleasePage(String url) async {
    final uri = Uri.parse(url.isEmpty ? releasesUrl : url);
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) {
      throw StateError('无法打开版本发布页面');
    }
  }

  static int compareVersions(String left, String right) {
    final leftParts = _versionParts(left);
    final rightParts = _versionParts(right);
    final length = leftParts.length > rightParts.length
        ? leftParts.length
        : rightParts.length;
    for (var i = 0; i < length; i++) {
      final leftValue = i < leftParts.length ? leftParts[i] : 0;
      final rightValue = i < rightParts.length ? rightParts[i] : 0;
      if (leftValue != rightValue) {
        return leftValue.compareTo(rightValue);
      }
    }
    return 0;
  }

  static List<int> _versionParts(String value) {
    final clean = value
        .trim()
        .replaceFirst(RegExp(r'^[vV]'), '')
        .split('+')
        .first
        .split('-')
        .first;
    return clean
        .split('.')
        .map((part) => int.tryParse(part) ?? 0)
        .toList(growable: false);
  }

  ReleaseAsset? _firstAsset(
    List<ReleaseAsset> assets,
    bool Function(String name) test,
  ) {
    for (final asset in assets) {
      if (test(asset.name.toLowerCase()) && asset.downloadUrl.isNotEmpty) {
        return asset;
      }
    }
    return null;
  }

  Future<String> _runtimeArch() async {
    if (!Platform.isMacOS && !Platform.isLinux) {
      return Platform.version.toLowerCase();
    }
    try {
      final result = await Process.run('uname', ['-m']);
      return result.stdout.toString().trim().toLowerCase();
    } catch (_) {
      return Platform.version.toLowerCase();
    }
  }
}
