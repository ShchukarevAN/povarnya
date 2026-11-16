import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

import '../app_theme.dart';
import 'data_directory.dart';

/// Небольшой файл пользовательских настроек, независимый от базы рецептов.
///
/// Значения меняются сразу в памяти, а запись сериализуется, чтобы быстрые
/// последовательные изменения масштаба или ширины панели не перезаписывали
/// друг друга устаревшими данными.
class AppSettings {
  factory AppSettings() => _instance;
  AppSettings._();

  static final AppSettings _instance = AppSettings._();
  Future<void> _writeQueue = Future<void>.value();
  File? _file;
  String themeName = defaultAppThemeName;
  double scale = 1;
  double rightPanelFraction = .6;
  double bottomPanelFraction = .45;
  bool windowMaximized = false;
  bool compactSandboxModules = false;
  bool compactFilterIngredients = false;
  bool randomRecipeOrder = false;

  Future<void> load() async {
    final dataDirectory = await povarnyaDataDirectory();
    await dataDirectory.create(recursive: true);
    _file = File(path.join(dataDirectory.path, 'settings.json'));
    if (!await _file!.exists()) return;
    try {
      final raw = jsonDecode(await _file!.readAsString());
      if (raw is! Map<String, dynamic>) return;
      final savedThemeName = raw['themeName'];
      if (savedThemeName is String && isKnownAppThemeName(savedThemeName)) {
        themeName = savedThemeName;
      }
      scale = _boundedDouble(raw['scale'], .7, 1.6, scale);
      rightPanelFraction = _boundedDouble(
        raw['rightPanelFraction'],
        .25,
        .72,
        rightPanelFraction,
      );
      bottomPanelFraction = _boundedDouble(
        raw['bottomPanelFraction'],
        .2,
        .75,
        bottomPanelFraction,
      );
      windowMaximized = raw['windowMaximized'] is bool
          ? raw['windowMaximized'] as bool
          : windowMaximized;
      compactSandboxModules = raw['compactSandboxModules'] is bool
          ? raw['compactSandboxModules'] as bool
          : compactSandboxModules;
      compactFilterIngredients = raw['compactFilterIngredients'] is bool
          ? raw['compactFilterIngredients'] as bool
          : compactFilterIngredients;
      randomRecipeOrder = raw['randomRecipeOrder'] is bool
          ? raw['randomRecipeOrder'] as bool
          : randomRecipeOrder;
    } on FormatException {
      // Некорректный файл не мешает запуску: используются значения по умолчанию.
    }
  }

  Future<void> save() {
    final file = _file;
    if (file == null) return Future<void>.value();
    _writeQueue = _writeQueue.then((_) async {
      final serialized = jsonEncode({
        'themeName': themeName,
        'scale': scale,
        'rightPanelFraction': rightPanelFraction,
        'bottomPanelFraction': bottomPanelFraction,
        'windowMaximized': windowMaximized,
        'compactSandboxModules': compactSandboxModules,
        'compactFilterIngredients': compactFilterIngredients,
        'randomRecipeOrder': randomRecipeOrder,
      });
      await file.writeAsString(serialized);
    });
    return _writeQueue;
  }

  /// Сбрасывает только настройки интерфейса после подтверждённого удаления
  /// всех локальных данных. Значения в памяти тоже возвращаются к исходным,
  /// чтобы последующее сохранение не восстановило старый файл.
  Future<void> resetLocalSettings() async {
    final dataDirectory = await povarnyaDataDirectory();
    await dataDirectory.create(recursive: true);
    _file = File(path.join(dataDirectory.path, 'settings.json'));
    if (await _file!.exists()) await _file!.delete();
    themeName = defaultAppThemeName;
    scale = 1;
    rightPanelFraction = .6;
    bottomPanelFraction = .45;
    windowMaximized = false;
    compactSandboxModules = false;
    compactFilterIngredients = false;
    randomRecipeOrder = false;
  }

  int _boundedInt(Object? value, int min, int max, int fallback) {
    if (value is! num) return fallback;
    return value.toInt().clamp(min, max);
  }

  double _boundedDouble(
    Object? value,
    double min,
    double max,
    double fallback,
  ) {
    if (value is! num) return fallback;
    return value.toDouble().clamp(min, max);
  }
}
