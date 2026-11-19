import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:povarnya/update/update_service.dart';

void main() {
  const latestUrl =
      'https://api.github.com/repos/ShchukarevAN/povarnya/releases/latest';
  const apkUrl =
      'https://github.com/ShchukarevAN/povarnya/releases/download/v0.6.0/povarnya-android.apk';
  final apkBytes = utf8.encode('test apk payload');
  final apkDigest = sha256.convert(apkBytes).toString();

  http.Response jsonResponse(Object body, int statusCode) => http.Response(
    jsonEncode(body),
    statusCode,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  Map<String, Object?> releaseJson({String tag = 'v0.6.0'}) => {
    'tag_name': tag,
    'name': 'Тестовый релиз',
    'body': 'Проверка обновления',
    'assets': [
      {
        'name': 'povarnya-android.apk',
        'browser_download_url': apkUrl,
        'size': apkBytes.length,
        'digest': 'sha256:$apkDigest',
      },
    ],
  };

  http.Response sourceResponse(String version) => jsonResponse({
    'encoding': 'base64',
    'content': base64.encode(
      utf8.encode('name: povarnya\nversion: $version\n'),
    ),
  }, 200);

  MockClient githubClient({
    String tag = 'v0.6.0',
    String sourceVersion = '0.6.0',
  }) => MockClient((request) async {
    if (request.url.toString() == latestUrl) {
      return jsonResponse(releaseJson(tag: tag), 200);
    }
    if (request.url.path.endsWith('/contents/pubspec.yaml')) {
      return sourceResponse(sourceVersion);
    }
    throw StateError('Unexpected request: ${request.url}');
  });

  test('читает обычную версию и APK из GitHub Release', () async {
    final client = githubClient();
    final service = UpdateService(
      client: client,
      latestReleaseUrl: latestUrl,
      apkAssetName: 'povarnya-android.apk',
      installedVersionOverride: '0.5.0',
    );

    final result = await service.check();

    expect(result.updateAvailable, isTrue);
    expect(result.release.version, '0.6.0');
    expect(result.release.versionCode, 6000);
    expect(result.release.asset.sha256, apkDigest);
    service.close();
  });

  test('скачивает APK и проверяет SHA-256', () async {
    final directory = await Directory.systemTemp.createTemp(
      'povarnya-update-test.',
    );
    addTearDown(() => directory.delete(recursive: true));
    final client = MockClient((request) async {
      if (request.url.toString() == latestUrl) {
        return jsonResponse(releaseJson(), 200);
      }
      if (request.url.path.endsWith('/contents/pubspec.yaml')) {
        return sourceResponse('0.6.0');
      }
      return http.Response.bytes(apkBytes, 200);
    });
    final service = UpdateService(
      client: client,
      latestReleaseUrl: latestUrl,
      apkAssetName: 'povarnya-android.apk',
      installedVersionOverride: '0.5.0',
      downloadDirectoryOverride: directory,
    );

    final check = await service.check();
    final apk = await service.download(check.release);

    expect(await apk.readAsBytes(), apkBytes);
    expect(apk.path, endsWith('povarnya-0.6.0.apk'));
    service.close();
  });

  test('выводит точный код HTTP-ошибки GitHub', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({'message': 'Not Found'}),
        404,
        headers: {'x-github-request-id': 'TEST-REQUEST-ID'},
      ),
    );
    final service = UpdateService(
      client: client,
      latestReleaseUrl: latestUrl,
      installedVersionOverride: '0.5.0',
    );

    await expectLater(
      service.check(),
      throwsA(
        isA<UpdateFailure>()
            .having((failure) => failure.code, 'code', 'GITHUB_HTTP_404')
            .having(
              (failure) => failure.technicalDetails,
              'technicalDetails',
              contains('TEST-REQUEST-ID'),
            ),
      ),
    );
    service.close();
  });

  test('объясняет неверный тег релиза', () async {
    final client = MockClient(
      (_) async => jsonResponse(releaseJson(tag: 'v0.6'), 200),
    );
    final service = UpdateService(
      client: client,
      latestReleaseUrl: latestUrl,
      installedVersionOverride: '0.5.0',
    );

    await expectLater(
      service.check(),
      throwsA(
        isA<UpdateFailure>().having(
          (failure) => failure.code,
          'code',
          'RELEASE_TAG_INVALID',
        ),
      ),
    );
    service.close();
  });

  test('сравнивает компоненты версии как числа', () async {
    final client = githubClient(tag: 'v0.10.0', sourceVersion: '0.10.0');
    final service = UpdateService(
      client: client,
      latestReleaseUrl: latestUrl,
      installedVersionOverride: '0.9.99',
    );

    final result = await service.check();

    expect(result.updateAvailable, isTrue);
    service.close();
  });

  test('не предлагает уже установленную версию', () async {
    final client = githubClient();
    final service = UpdateService(
      client: client,
      latestReleaseUrl: latestUrl,
      installedVersionOverride: '0.6.0',
    );

    final result = await service.check();

    expect(result.updateAvailable, isFalse);
    service.close();
  });

  test('блокирует релиз, чей тег указывает на другую версию', () async {
    final client = githubClient(sourceVersion: '0.7.8');
    final service = UpdateService(
      client: client,
      latestReleaseUrl: latestUrl,
      installedVersionOverride: '0.5.0',
    );

    await expectLater(
      service.check(),
      throwsA(
        isA<UpdateFailure>()
            .having(
              (failure) => failure.code,
              'code',
              'RELEASE_SOURCE_VERSION_MISMATCH',
            )
            .having(
              (failure) => failure.message,
              'message',
              allOf(contains('0.6.0'), contains('0.7.8')),
            ),
      ),
    );
    service.close();
  });

  test('отвергает суффикс build metadata в pubspec выпуска', () async {
    final invalidVersion = <String>['0.6.0', '10'].join('+');
    final client = githubClient(sourceVersion: invalidVersion);
    final service = UpdateService(
      client: client,
      latestReleaseUrl: latestUrl,
      installedVersionOverride: '0.5.0',
    );

    await expectLater(
      service.check(),
      throwsA(
        isA<UpdateFailure>().having(
          (failure) => failure.code,
          'code',
          'RELEASE_SOURCE_VERSION_INVALID',
        ),
      ),
    );
    service.close();
  });
}
