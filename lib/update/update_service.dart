import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'update_config.dart';

enum UpdateStage {
  checking,
  downloading,
  verifying,
  requestingPermission,
  openingInstaller,
}

class UpdateProgress {
  const UpdateProgress(this.stage, this.message, {this.fraction});

  final UpdateStage stage;
  final String message;
  final double? fraction;
}

class UpdateAsset {
  const UpdateAsset({
    required this.name,
    required this.url,
    required this.size,
    required this.sha256,
  });

  final String name;
  final Uri url;
  final int size;
  final String? sha256;
}

class UpdateRelease {
  const UpdateRelease({
    required this.tag,
    required this.name,
    required this.notes,
    required this.buildNumber,
    required this.asset,
  });

  final String tag;
  final String name;
  final String notes;
  final int buildNumber;
  final UpdateAsset asset;
}

class UpdateCheckResult {
  const UpdateCheckResult({
    required this.installedVersion,
    required this.installedBuildNumber,
    required this.release,
  });

  final String installedVersion;
  final int installedBuildNumber;
  final UpdateRelease release;

  bool get updateAvailable => release.buildNumber > installedBuildNumber;
}

/// A user-readable failure with stable code and full technical context.
class UpdateFailure implements Exception {
  const UpdateFailure({
    required this.code,
    required this.title,
    required this.message,
    required this.suggestion,
    this.technicalDetails,
  });

  final String code;
  final String title;
  final String message;
  final String suggestion;
  final String? technicalDetails;

  @override
  String toString() => '$code: $message';
}

typedef UpdateProgressCallback = void Function(UpdateProgress progress);
typedef UpdateLogCallback = void Function(String message);

class UpdateService {
  UpdateService({
    http.Client? client,
    this.onProgress,
    this.onLog,
    this.latestReleaseUrl = UpdateConfig.latestReleaseUrl,
    this.apkAssetName = UpdateConfig.apkAssetName,
    this.requireSha256 = UpdateConfig.requireSha256,
    this.installedInfoOverride,
    this.downloadDirectoryOverride,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;
  final UpdateProgressCallback? onProgress;
  final UpdateLogCallback? onLog;
  final String latestReleaseUrl;
  final String apkAssetName;
  final bool requireSha256;
  final ({String version, int buildNumber})? installedInfoOverride;
  final Directory? downloadDirectoryOverride;
  UpdateStage? _lastLoggedStage;

  void _progress(UpdateStage stage, String message, {double? fraction}) {
    if (_lastLoggedStage != stage) {
      _lastLoggedStage = stage;
      onLog?.call(message);
    }
    onProgress?.call(UpdateProgress(stage, message, fraction: fraction));
  }

  Future<UpdateCheckResult> check() async {
    _progress(UpdateStage.checking, 'Проверяю последний выпуск GitHub…');
    final uri = Uri.tryParse(latestReleaseUrl);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        !uri.path.endsWith('/releases/latest')) {
      throw UpdateFailure(
        code: 'CONFIG_INVALID_URL',
        title: 'Ошибка настройки сборки',
        message: 'Адрес GitHub Releases задан неверно.',
        suggestion:
            'Укажите HTTPS-адрес API, заканчивающийся на /releases/latest.',
        technicalDetails: 'POVARNYA_UPDATE_URL=$latestReleaseUrl',
      );
    }

    late http.Response response;
    try {
      response = await _client
          .get(
            uri,
            headers: const {
              'Accept': 'application/vnd.github+json',
              'X-GitHub-Api-Version': '2022-11-28',
              'User-Agent': 'Povarnya-Android-Updater',
            },
          )
          .timeout(UpdateConfig.requestTimeout);
    } on TimeoutException catch (error) {
      throw UpdateFailure(
        code: 'NETWORK_TIMEOUT',
        title: 'Истекло время ожидания',
        message:
            'GitHub не ответил за ${UpdateConfig.requestTimeout.inSeconds} с.',
        suggestion: 'Проверьте интернет и VPN, затем повторите.',
        technicalDetails: '$error\nGET $uri',
      );
    } on SocketException catch (error) {
      throw UpdateFailure(
        code: 'NETWORK_UNREACHABLE',
        title: 'Нет связи с GitHub',
        message: 'Не удалось открыть сетевое соединение.',
        suggestion: 'Проверьте Wi‑Fi, мобильную сеть, DNS и VPN.',
        technicalDetails:
            '${error.osError?.message ?? error.message}\nGET $uri',
      );
    } on HandshakeException catch (error) {
      throw UpdateFailure(
        code: 'TLS_HANDSHAKE_FAILED',
        title: 'Ошибка защищённого соединения',
        message: 'Не удалось проверить TLS-сертификат GitHub.',
        suggestion: 'Проверьте дату на телефоне, VPN и сетевой фильтр.',
        technicalDetails: '$error\nGET $uri',
      );
    } on http.ClientException catch (error) {
      throw UpdateFailure(
        code: 'HTTP_CLIENT_ERROR',
        title: 'Ошибка HTTP-клиента',
        message: error.message,
        suggestion: 'Повторите позже или проверьте адрес репозитория.',
        technicalDetails: '$error\nGET $uri',
      );
    }

    onLog?.call(
      'GitHub ответил HTTP ${response.statusCode}; '
      'request-id=${response.headers['x-github-request-id'] ?? 'нет'}',
    );
    if (response.statusCode != HttpStatus.ok) {
      final remaining = response.headers['x-ratelimit-remaining'];
      final reset = response.headers['x-ratelimit-reset'];
      final body = response.body.length > 1000
          ? '${response.body.substring(0, 1000)}…'
          : response.body;
      throw UpdateFailure(
        code: 'GITHUB_HTTP_${response.statusCode}',
        title: response.statusCode == HttpStatus.notFound
            ? 'Релиз GitHub не найден'
            : 'GitHub вернул ошибку',
        message: 'GET $uri завершился с HTTP ${response.statusCode}.',
        suggestion: 'Проверьте, что репозиторий публичный и в нём есть опубликованный Release.',
        technicalDetails:
            'HTTP ${response.statusCode}\n'
            'x-github-request-id: ${response.headers['x-github-request-id']}\n'
            'x-ratelimit-remaining: $remaining\n'
            'x-ratelimit-reset: $reset\n'
            'response: $body',
      );
    }

    late Map<String, Object?> json;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, Object?>) throw const FormatException();
      json = decoded;
    } on FormatException catch (error) {
      throw UpdateFailure(
        code: 'GITHUB_JSON_INVALID',
        title: 'Неверный ответ GitHub',
        message: 'Ответ Releases API не является ожидаемым JSON-объектом.',
        suggestion: 'Проверьте URL и повторите позже.',
        technicalDetails: '$error\n${response.body}',
      );
    }

    final tag = json['tag_name'];
    final assets = json['assets'];
    if (tag is! String || tag.isEmpty || assets is! List) {
      throw const UpdateFailure(
        code: 'RELEASE_FIELDS_MISSING',
        title: 'Релиз оформлен неверно',
        message: 'В ответе нет tag_name или списка assets.',
        suggestion: 'Переопубликуйте GitHub Release с APK-файлом.',
      );
    }

    final buildMatch = RegExp(r'\+(\d+)$').firstMatch(tag);
    final buildNumber = int.tryParse(buildMatch?.group(1) ?? '');
    if (buildNumber == null) {
      throw UpdateFailure(
        code: 'RELEASE_TAG_INVALID',
        title: 'Неверная метка релиза',
        message: 'Метка «$tag» не содержит номер сборки.',
        suggestion:
            'Используйте метку вида v0.6.0+1, где 1 — Android versionCode.',
        technicalDetails: 'tag_name=$tag',
      );
    }

    Map<String, Object?>? assetJson;
    final availableNames = <String>[];
    for (final item in assets) {
      if (item is! Map<String, Object?>) continue;
      final name = item['name'];
      if (name is String) availableNames.add(name);
      if (name == apkAssetName) assetJson = item;
    }
    if (assetJson == null) {
      throw UpdateFailure(
        code: 'APK_ASSET_NOT_FOUND',
        title: 'APK не прикреплён к релизу',
        message: 'Ожидался файл «$apkAssetName».',
        suggestion: 'Загрузите APK с точно таким именем или измените POVARNYA_UPDATE_ASSET.',
        technicalDetails:
            'Доступные assets: ${availableNames.isEmpty ? 'нет' : availableNames.join(', ')}',
      );
    }

    final downloadUrl = assetJson['browser_download_url'];
    final size = assetJson['size'];
    final digestValue = assetJson['digest'];
    final downloadUri = downloadUrl is String
        ? Uri.tryParse(downloadUrl)
        : null;
    if (downloadUri == null || downloadUri.scheme != 'https' || size is! int) {
      throw UpdateFailure(
        code: 'APK_ASSET_INVALID',
        title: 'Неверные данные APK',
        message: 'GitHub не вернул корректные URL и размер файла.',
        suggestion: 'Удалите повреждённый asset и загрузите APK заново.',
        technicalDetails: 'url=$downloadUrl\nsize=$size',
      );
    }
    final digest = digestValue is String && digestValue.startsWith('sha256:')
        ? digestValue.substring('sha256:'.length).toLowerCase()
        : null;
    if (requireSha256 && digest == null) {
      throw const UpdateFailure(
        code: 'SHA256_MISSING',
        title: 'Нет контрольной суммы',
        message: 'GitHub не вернул SHA‑256 для APK.',
        suggestion: 'Загрузите asset заново или временно соберите с POVARNYA_UPDATE_REQUIRE_SHA256=false.',
      );
    }

    final installed = installedInfoOverride ?? await _installedInfo();
    final release = UpdateRelease(
      tag: tag,
      name: json['name'] is String ? json['name']! as String : tag,
      notes: json['body'] is String ? json['body']! as String : '',
      buildNumber: buildNumber,
      asset: UpdateAsset(
        name: apkAssetName,
        url: downloadUri,
        size: size,
        sha256: digest,
      ),
    );
    onLog?.call(
      'Установлено ${installed.version}+${installed.buildNumber}; '
      'на GitHub ${release.tag}.',
    );
    return UpdateCheckResult(
      installedVersion: installed.version,
      installedBuildNumber: installed.buildNumber,
      release: release,
    );
  }

  Future<({String version, int buildNumber})> _installedInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final buildNumber = int.tryParse(info.buildNumber);
      if (buildNumber == null) {
        throw FormatException('buildNumber=${info.buildNumber}');
      }
      return (version: info.version, buildNumber: buildNumber);
    } catch (error) {
      throw UpdateFailure(
        code: 'INSTALLED_VERSION_UNAVAILABLE',
        title: 'Не удалось определить версию',
        message: 'Платформа не вернула Android versionCode.',
        suggestion: 'Пересоберите приложение из актуального pubspec.yaml.',
        technicalDetails: '$error',
      );
    }
  }

  Future<File> download(UpdateRelease release) async {
    final asset = release.asset;
    _progress(
      UpdateStage.downloading,
      'Начинаю загрузку ${asset.name}…',
      fraction: 0,
    );
    final baseDirectory =
        downloadDirectoryOverride ?? await getTemporaryDirectory();
    final updateDirectory = Directory(path.join(baseDirectory.path, 'updates'));
    try {
      await updateDirectory.create(recursive: true);
    } on FileSystemException catch (error) {
      throw UpdateFailure(
        code: 'UPDATE_DIRECTORY_FAILED',
        title: 'Не удалось создать папку',
        message: 'Внутреннее хранилище недоступно для записи.',
        suggestion: 'Освободите место и перезапустите приложение.',
        technicalDetails: '${error.message}\n${error.path}',
      );
    }
    final target = File(
      path.join(updateDirectory.path, 'povarnya-${release.buildNumber}.apk'),
    );
    final partial = File('${target.path}.part');

    try {
      final request = http.Request('GET', asset.url)
        ..headers['Accept'] = 'application/octet-stream'
        ..headers['User-Agent'] = 'Povarnya-Android-Updater';
      final response = await _client
          .send(request)
          .timeout(UpdateConfig.requestTimeout);
      if (response.statusCode != HttpStatus.ok) {
        throw UpdateFailure(
          code: 'APK_HTTP_${response.statusCode}',
          title: 'Не удалось скачать APK',
          message: 'Сервер вернул HTTP ${response.statusCode}.',
          suggestion: 'Проверьте asset GitHub Release и повторите.',
          technicalDetails: 'GET ${asset.url}\nheaders=${response.headers}',
        );
      }
      final sink = partial.openWrite();
      var received = 0;
      try {
        await for (final chunk in response.stream.timeout(
          UpdateConfig.downloadTimeout,
        )) {
          sink.add(chunk);
          received += chunk.length;
          _progress(
            UpdateStage.downloading,
            'Загружено ${_formatBytes(received)} '
            'из ${_formatBytes(asset.size)}',
            fraction: asset.size > 0
                ? (received / asset.size).clamp(0.0, 1.0)
                : null,
          );
        }
      } finally {
        await sink.close();
      }
      if (received != asset.size) {
        throw UpdateFailure(
          code: 'APK_SIZE_MISMATCH',
          title: 'APK загружен не полностью',
          message:
              'Ожидалось ${_formatBytes(asset.size)}, '
              'получено ${_formatBytes(received)}.',
          suggestion: 'Проверьте связь и повторите загрузку.',
          technicalDetails: 'expected=${asset.size}\nactual=$received',
        );
      }

      _progress(UpdateStage.verifying, 'Проверяю SHA‑256 APK…');
      final actualDigest = (await sha256.bind(partial.openRead()).first)
          .toString()
          .toLowerCase();
      onLog?.call('SHA-256: $actualDigest');
      if (asset.sha256 != null && actualDigest != asset.sha256) {
        throw UpdateFailure(
          code: 'APK_SHA256_MISMATCH',
          title: 'Контрольная сумма не совпала',
          message: 'Скачанный APK отличается от файла GitHub.',
          suggestion: 'Не устанавливайте файл. Удалите и загрузите asset GitHub заново.',
          technicalDetails:
              'expected=${asset.sha256}\nactual=$actualDigest\nfile=${partial.path}',
        );
      }
      if (await target.exists()) await target.delete();
      return await partial.rename(target.path);
    } on UpdateFailure {
      if (await partial.exists()) await partial.delete();
      rethrow;
    } on TimeoutException catch (error) {
      if (await partial.exists()) await partial.delete();
      throw UpdateFailure(
        code: 'APK_DOWNLOAD_TIMEOUT',
        title: 'Загрузка APK прервана',
        message: 'Данные не поступали слишком долго.',
        suggestion: 'Проверьте связь и повторите.',
        technicalDetails: '$error\nGET ${asset.url}',
      );
    } on FileSystemException catch (error) {
      if (await partial.exists()) await partial.delete();
      throw UpdateFailure(
        code: 'APK_WRITE_FAILED',
        title: 'Не удалось сохранить APK',
        message: error.message,
        suggestion: 'Освободите место в памяти телефона и повторите.',
        technicalDetails: '${error.path}\n$error',
      );
    } on SocketException catch (error) {
      if (await partial.exists()) await partial.delete();
      throw UpdateFailure(
        code: 'APK_NETWORK_INTERRUPTED',
        title: 'Сеть отключилась',
        message: 'Соединение прервалось при скачивании APK.',
        suggestion: 'Восстановите сеть и повторите.',
        technicalDetails: '${error.osError}\nGET ${asset.url}',
      );
    } on http.ClientException catch (error) {
      if (await partial.exists()) await partial.delete();
      throw UpdateFailure(
        code: 'APK_HTTP_CLIENT_ERROR',
        title: 'Ошибка загрузки',
        message: error.message,
        suggestion: 'Повторите загрузку позже.',
        technicalDetails: '$error\nGET ${asset.url}',
      );
    }
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} МБ';
    }
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} КБ';
    return '$bytes байт';
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}
