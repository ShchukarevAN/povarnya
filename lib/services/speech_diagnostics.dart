import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

import '../data/data_directory.dart';

enum SpeechFailureStage {
  microphonePermission,
  microphoneStart,
  microphoneStream,
  microphoneStop,
  noSpeech,
  noResult,
  modelFiles,
  workerStart,
  nativeBindings,
  modelLoad,
  decode,
  decodeTimeout,
  unknown,
}

extension SpeechFailureStageDetails on SpeechFailureStage {
  String get code => switch (this) {
    SpeechFailureStage.microphonePermission => 'MIC_PERMISSION',
    SpeechFailureStage.microphoneStart => 'MIC_START',
    SpeechFailureStage.microphoneStream => 'MIC_STREAM',
    SpeechFailureStage.microphoneStop => 'MIC_STOP',
    SpeechFailureStage.noSpeech => 'AUDIO_NO_SPEECH',
    SpeechFailureStage.noResult => 'NO_RESULT',
    SpeechFailureStage.modelFiles => 'MODEL_FILES',
    SpeechFailureStage.workerStart => 'ENGINE_WORKER',
    SpeechFailureStage.nativeBindings => 'ENGINE_NATIVE',
    SpeechFailureStage.modelLoad => 'MODEL_LOAD',
    SpeechFailureStage.decode => 'DECODE',
    SpeechFailureStage.decodeTimeout => 'DECODE_TIMEOUT',
    SpeechFailureStage.unknown => 'UNKNOWN',
  };

  String get summary => switch (this) {
    SpeechFailureStage.microphonePermission =>
      'Нет разрешения на использование микрофона.',
    SpeechFailureStage.microphoneStart => 'Микрофон не начал запись.',
    SpeechFailureStage.microphoneStream =>
      'Аудиопоток микрофона неожиданно прервался.',
    SpeechFailureStage.microphoneStop =>
      'Не удалось корректно завершить запись с микрофона.',
    SpeechFailureStage.noSpeech =>
      'Микрофон записал тишину или слишком тихую речь.',
    SpeechFailureStage.noResult =>
      'Zipformer2 обработал запись, но не нашёл распознаваемых слов.',
    SpeechFailureStage.modelFiles =>
      'Файлы русской модели распознавания недоступны или повреждены.',
    SpeechFailureStage.workerStart =>
      'Не запустился фоновый модуль распознавания.',
    SpeechFailureStage.nativeBindings =>
      'Не загрузилась нативная библиотека Sherpa ONNX.',
    SpeechFailureStage.modelLoad =>
      'Zipformer2 не смог загрузить русскую модель.',
    SpeechFailureStage.decode => 'Zipformer2 не смог обработать запись.',
    SpeechFailureStage.decodeTimeout =>
      'Распознавание заняло слишком много времени.',
    SpeechFailureStage.unknown => 'Распознавание завершилось с ошибкой.',
  };

  String get recovery => switch (this) {
    SpeechFailureStage.microphonePermission =>
      'Разрешите доступ к микрофону в настройках системы.',
    SpeechFailureStage.microphoneStart || SpeechFailureStage.microphoneStream =>
      'Проверьте подключение микрофона и повторите попытку.',
    SpeechFailureStage.microphoneStop => 'Повторите голосовой ввод.',
    SpeechFailureStage.noSpeech =>
      'Говорите ближе к микрофону после нажатия на его значок.',
    SpeechFailureStage.noResult => 'Повторите фразу немного медленнее и чётче.',
    SpeechFailureStage.modelFiles ||
    SpeechFailureStage.workerStart ||
    SpeechFailureStage.nativeBindings ||
    SpeechFailureStage.modelLoad =>
      'Повторите попытку: модуль будет автоматически перезапущен.',
    SpeechFailureStage.decode || SpeechFailureStage.decodeTimeout =>
      'Повторите фразу немного медленнее и чётче.',
    SpeechFailureStage.unknown => 'Повторите попытку.',
  };
}

class SpeechFailure implements Exception {
  const SpeechFailure(this.stage, {this.technicalDetails, this.cause});

  final SpeechFailureStage stage;
  final String? technicalDetails;
  final Object? cause;

  String get userMessage =>
      '${stage.summary} ${stage.recovery}\nКод: ${stage.code}';

  @override
  String toString() {
    final details = technicalDetails ?? cause?.toString();
    return details == null || details.isEmpty
        ? 'SpeechFailure(${stage.code})'
        : 'SpeechFailure(${stage.code}): $details';
  }
}

class SpeechDiagnostics {
  SpeechDiagnostics._();

  static Future<void> _pendingWrite = Future<void>.value();

  static Future<String?> record(
    SpeechFailure failure, {
    StackTrace? stackTrace,
    Map<String, Object?> context = const <String, Object?>{},
  }) {
    final completer = Completer<String?>();
    _pendingWrite = _pendingWrite.then((_) async {
      try {
        final directory = await povarnyaDataDirectory();
        await directory.create(recursive: true);
        final log = File(path.join(directory.path, 'speech-recognition.log'));
        if (await log.exists() && await log.length() > 512 * 1024) {
          await log.writeAsString('');
        }
        final entry = <String, Object?>{
          'time': DateTime.now().toIso8601String(),
          'code': failure.stage.code,
          'summary': failure.stage.summary,
          'details': ?failure.technicalDetails,
          if (failure.cause case final cause?) 'cause': cause.toString(),
          if (stackTrace != null) 'stack': stackTrace.toString(),
          ...context,
        };
        await log.writeAsString(
          '${jsonEncode(entry)}\n',
          mode: FileMode.append,
          flush: true,
        );
        completer.complete(log.path);
      } catch (_) {
        completer.complete(null);
      }
    });
    return completer.future;
  }
}
