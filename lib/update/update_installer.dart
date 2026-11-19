import 'dart:io';

import 'package:flutter/services.dart';

import 'update_service.dart';

class ApkInspection {
  const ApkInspection({
    required this.packageName,
    required this.versionName,
    required this.versionCode,
  });

  final String packageName;
  final String versionName;
  final int versionCode;
}

class UpdateInstaller {
  static const _channel = MethodChannel('povarnya/app_update');

  Future<bool> canRequestInstall() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('canRequestInstall') ?? false;
    } on PlatformException catch (error) {
      throw _platformFailure('INSTALL_PERMISSION_CHECK_FAILED', error);
    } on MissingPluginException catch (error) {
      throw UpdateFailure(
        code: 'INSTALLER_BRIDGE_MISSING',
        title: 'Нет Android-модуля обновления',
        message: 'Текущая сборка не содержит нативный мост установщика.',
        suggestion: 'Пересоберите APK обновлённым Android-сборщиком.',
        technicalDetails: '$error',
      );
    }
  }

  Future<void> openInstallPermissionSettings() async {
    try {
      await _channel.invokeMethod<void>('openInstallPermissionSettings');
    } on PlatformException catch (error) {
      throw _platformFailure('INSTALL_PERMISSION_SETTINGS_FAILED', error);
    }
  }

  Future<ApkInspection> inspect(
    File apk, {
    required String expectedVersionName,
    required int expectedVersionCode,
  }) async {
    if (!Platform.isAndroid) {
      throw const UpdateFailure(
        code: 'PLATFORM_NOT_SUPPORTED',
        title: 'Проверка APK недоступна',
        message: 'Проверка пакета предназначена только для Android.',
        suggestion: 'На Linux проверяйте APK сценарием сборки.',
      );
    }
    try {
      final result = await _channel.invokeMapMethod<String, Object?>(
        'inspectApk',
        _validationArguments(apk, expectedVersionName, expectedVersionCode),
      );
      final packageName = result?['packageName'];
      final versionName = result?['versionName'];
      final versionCode = result?['versionCode'];
      if (packageName is! String ||
          versionName is! String ||
          versionCode is! int) {
        throw const UpdateFailure(
          code: 'APK_INSPECTION_INVALID_RESULT',
          title: 'Не удалось проверить APK',
          message: 'Android не вернул метаданные пакета.',
          suggestion: 'Не устанавливайте файл; пересоберите Android-модуль.',
        );
      }
      return ApkInspection(
        packageName: packageName,
        versionName: versionName,
        versionCode: versionCode,
      );
    } on PlatformException catch (error) {
      throw _platformFailure('APK_INSPECTION_FAILED', error);
    }
  }

  Future<void> install(
    File apk, {
    required String expectedVersionName,
    required int expectedVersionCode,
  }) async {
    if (!Platform.isAndroid) {
      throw const UpdateFailure(
        code: 'PLATFORM_NOT_SUPPORTED',
        title: 'Обновление APK недоступно',
        message: 'Автоустановка предназначена только для Android.',
        suggestion: 'На Linux скачайте новую сборку вручную.',
      );
    }
    try {
      await _channel.invokeMethod<void>(
        'installApk',
        _validationArguments(apk, expectedVersionName, expectedVersionCode),
      );
    } on PlatformException catch (error) {
      throw _platformFailure('APK_INSTALLER_FAILED', error);
    }
  }

  Map<String, Object> _validationArguments(
    File apk,
    String expectedVersionName,
    int expectedVersionCode,
  ) => {
    'path': apk.path,
    'expectedVersionName': expectedVersionName,
    'expectedVersionCode': expectedVersionCode,
  };

  UpdateFailure _platformFailure(String fallbackCode, PlatformException error) {
    final code = error.code.isEmpty ? fallbackCode : error.code;
    final validationFailed =
        code.startsWith('APK_') &&
        code != 'APK_INSTALLER_FAILED' &&
        code != 'APK_INSTALLER_NOT_FOUND';
    return UpdateFailure(
      code: code,
      title: validationFailed
          ? 'Проверка APK не пройдена'
          : 'Системный установщик не запустился',
      message: error.message ?? 'Неизвестная ошибка Android.',
      suggestion: validationFailed
          ? 'Не устанавливайте файл. Пересоберите и заново опубликуйте выпуск.'
          : 'Проверьте разрешение «Установка неизвестных приложений» и свободное место.',
      technicalDetails: 'details=${error.details}\n$error',
    );
  }
}
