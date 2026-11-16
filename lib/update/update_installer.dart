import 'dart:io';

import 'package:flutter/services.dart';

import 'update_service.dart';

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

  Future<void> install(File apk) async {
    if (!Platform.isAndroid) {
      throw const UpdateFailure(
        code: 'PLATFORM_NOT_SUPPORTED',
        title: 'Обновление APK недоступно',
        message: 'Автоустановка предназначена только для Android.',
        suggestion: 'На Linux скачайте новую сборку вручную.',
      );
    }
    try {
      await _channel.invokeMethod<void>('installApk', {'path': apk.path});
    } on PlatformException catch (error) {
      throw _platformFailure('APK_INSTALLER_FAILED', error);
    }
  }

  UpdateFailure _platformFailure(String fallbackCode, PlatformException error) {
    return UpdateFailure(
      code: error.code.isEmpty ? fallbackCode : error.code,
      title: 'Системный установщик не запустился',
      message: error.message ?? 'Неизвестная ошибка Android.',
      suggestion: 'Проверьте разрешение «Установка неизвестных приложений» и свободное место.',
      technicalDetails: 'details=${error.details}\n$error',
    );
  }
}
