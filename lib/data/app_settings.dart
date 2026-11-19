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
  double speechAmplitudeThreshold = 280;
  int speechTrailingSilenceMs = 1000;
  int speechWaitForSpeechMs = 7000;
  List<String> speechPersonalWords = <String>[];
  Map<String, String> speechCorrections = <String, String>{};
  int speechCalibrationAccuracy = 0;
  int speechCalibrationPhraseCount = 0;
  DateTime? speechProfileUpdatedAt;

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
      speechAmplitudeThreshold = _boundedDouble(
        raw['speechAmplitudeThreshold'],
        120,
        1200,
        speechAmplitudeThreshold,
      );
      speechTrailingSilenceMs = _boundedInt(
        raw['speechTrailingSilenceMs'],
        650,
        1800,
        speechTrailingSilenceMs,
      );
      speechWaitForSpeechMs = _boundedInt(
        raw['speechWaitForSpeechMs'],
        4000,
        12000,
        speechWaitForSpeechMs,
      );
      speechPersonalWords = _stringList(raw['speechPersonalWords']);
      speechCorrections = _stringMap(raw['speechCorrections']);
      speechCalibrationAccuracy = _boundedInt(
        raw['speechCalibrationAccuracy'],
        0,
        100,
        speechCalibrationAccuracy,
      );
      speechCalibrationPhraseCount = _boundedInt(
        raw['speechCalibrationPhraseCount'],
        0,
        500,
        speechCalibrationPhraseCount,
      );
      final profileDate = raw['speechProfileUpdatedAt'];
      speechProfileUpdatedAt = profileDate is String
          ? DateTime.tryParse(profileDate)
          : null;
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
        'speechAmplitudeThreshold': speechAmplitudeThreshold,
        'speechTrailingSilenceMs': speechTrailingSilenceMs,
        'speechWaitForSpeechMs': speechWaitForSpeechMs,
        'speechPersonalWords': speechPersonalWords,
        'speechCorrections': speechCorrections,
        'speechCalibrationAccuracy': speechCalibrationAccuracy,
        'speechCalibrationPhraseCount': speechCalibrationPhraseCount,
        'speechProfileUpdatedAt': speechProfileUpdatedAt?.toIso8601String(),
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
    speechAmplitudeThreshold = 280;
    speechTrailingSilenceMs = 1000;
    speechWaitForSpeechMs = 7000;
    speechPersonalWords = <String>[];
    speechCorrections = <String, String>{};
    speechCalibrationAccuracy = 0;
    speechCalibrationPhraseCount = 0;
    speechProfileUpdatedAt = null;
  }

  List<String> _stringList(Object? value) {
    if (value is! List) return <String>[];
    return value
        .whereType<String>()
        .map((item) => item.trim().toLowerCase())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList();
  }

  Map<String, String> _stringMap(Object? value) {
    if (value is! Map) return <String, String>{};
    final result = <String, String>{};
    for (final entry in value.entries) {
      if (entry.key is! String || entry.value is! String) continue;
      final key = (entry.key as String).trim().toLowerCase();
      final replacement = (entry.value as String).trim().toLowerCase();
      if (key.isNotEmpty && replacement.isNotEmpty && key != replacement) {
        result[key] = replacement;
      }
    }
    return result;
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
