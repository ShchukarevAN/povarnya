import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

import '../data/app_settings.dart';
import '../presentation/speech_input_button.dart';
import 'offline_speech_recognizer.dart';
import 'silero_tts_service.dart';

enum RecipeVoiceCommand { next, repeat, previous, finish, unknown }

RecipeVoiceCommand parseRecipeVoiceCommand(String source) {
  final text = source
      .toLowerCase()
      .replaceAll('ё', 'е')
      .replaceAll(RegExp(r'[^а-яa-z\s-]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (text.isEmpty) return RecipeVoiceCommand.unknown;

  bool says(Iterable<String> variants) => variants.any((variant) {
    final normalized = variant.replaceAll('ё', 'е');
    return text == normalized ||
        text.startsWith('$normalized ') ||
        text.endsWith(' $normalized') ||
        text.contains(' $normalized ');
  });

  if (says(const <String>[
    'закончили',
    'закончить',
    'конец',
    'завершить',
    'заверши',
    'стоп',
    'хватит',
    'готово',
    'заканчиваем',
  ])) {
    return RecipeVoiceCommand.finish;
  }
  if (says(const <String>[
    'вернись',
    'возврат',
    'назад',
    'обратно',
    'предыдущий',
    'предыдущий шаг',
    'шаг назад',
  ])) {
    return RecipeVoiceCommand.previous;
  }
  if (says(const <String>[
    'повтори',
    'повторить',
    'еще раз',
    'напомни',
    'снова',
    'повтори шаг',
  ])) {
    return RecipeVoiceCommand.repeat;
  }
  if (says(const <String>[
    'продолжить',
    'продолжай',
    'дальше',
    'далее',
    'следующий',
    'следующий шаг',
    'переход',
    'вперед',
  ])) {
    return RecipeVoiceCommand.next;
  }
  return RecipeVoiceCommand.unknown;
}

/// Hands-free recipe guide: Silero speaks a step, then Zipformer2 listens for
/// one navigation command. There are no confirmation dialogs between turns.
class RecipeVoiceGuide {
  RecipeVoiceGuide({this.onActiveChanged, this.onError});

  final ValueChanged<bool>? onActiveChanged;
  final ValueChanged<String>? onError;

  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _audioSubscription;
  Completer<void>? _captureDone;
  bool _active = false;
  bool _disposed = false;
  int _session = 0;

  bool get isActive => _active;

  Future<void> start(List<String> steps) async {
    if (_active || steps.isEmpty || _disposed) return;
    final session = ++_session;
    _setActive(true);
    try {
      await OfflineSpeechRecognizer.instance.prepare();
      await SileroTtsService.instance.prepare();
      if (!_isCurrent(session)) return;
      await SileroTtsService.instance.speak('Приступаем к готовке.');
      if (!_isCurrent(session)) return;

      var stepIndex = 0;
      await SileroTtsService.instance.speak(steps[stepIndex]);
      while (_isCurrent(session)) {
        final phrase = await _captureCommand();
        if (!_isCurrent(session)) return;
        switch (parseRecipeVoiceCommand(phrase)) {
          case RecipeVoiceCommand.next:
            if (stepIndex + 1 >= steps.length) {
              await _finish(session);
              return;
            }
            stepIndex++;
            await SileroTtsService.instance.speak(steps[stepIndex]);
            break;
          case RecipeVoiceCommand.repeat:
            await SileroTtsService.instance.speak(steps[stepIndex]);
            break;
          case RecipeVoiceCommand.previous:
            if (stepIndex > 0) stepIndex--;
            await SileroTtsService.instance.speak(steps[stepIndex]);
            break;
          case RecipeVoiceCommand.finish:
            await _finish(session);
            return;
          case RecipeVoiceCommand.unknown:
            // Keep listening without interrupting cooking with confirmations.
            break;
        }
      }
    } catch (error) {
      if (_isCurrent(session)) {
        onError?.call(_messageFor(error));
      }
    } finally {
      if (_session == session) _setActive(false);
    }
  }

  Future<void> _finish(int session) async {
    if (!_isCurrent(session)) return;
    await SileroTtsService.instance.speak('Заканчиваем готовку.');
    if (_session == session) {
      _session++;
      _setActive(false);
    }
  }

  Future<String> _captureCommand() async {
    if (!await _recorder.hasPermission()) {
      throw StateError('Нет разрешения на использование микрофона.');
    }
    final settings = AppSettings();
    final endpoint = SilenceEndpointDetector(
      amplitudeThreshold: settings.speechAmplitudeThreshold,
      trailingSilence: Duration(milliseconds: settings.speechTrailingSilenceMs),
      waitForSpeech: Duration(milliseconds: settings.speechWaitForSpeechMs),
    );
    final audio = BytesBuilder(copy: false);
    final done = _captureDone = Completer<void>();
    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
        autoGain: true,
        echoCancel: true,
        noiseSuppress: true,
      ),
    );
    _audioSubscription = stream.listen(
      (chunk) {
        audio.add(chunk);
        if (endpoint.add(chunk) && !done.isCompleted) done.complete();
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!done.isCompleted) done.completeError(error, stackTrace);
      },
      onDone: () {
        if (!done.isCompleted) done.complete();
      },
    );
    try {
      await done.future;
    } finally {
      await _recorder.stop();
      await _audioSubscription?.cancel();
      _audioSubscription = null;
      _captureDone = null;
    }
    if (!endpoint.hasSpeech || audio.length == 0) return '';
    return OfflineSpeechRecognizer.instance.recognizePcm16(audio.takeBytes());
  }

  Future<void> stop() async {
    if (!_active) return;
    _session++;
    _setActive(false);
    final done = _captureDone;
    if (done != null && !done.isCompleted) done.complete();
    await _recorder.stop();
    await SileroTtsService.instance.stop();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    await stop();
    _disposed = true;
    await _audioSubscription?.cancel();
    await _recorder.dispose();
  }

  bool _isCurrent(int session) => !_disposed && _active && _session == session;

  void _setActive(bool value) {
    if (_active == value) return;
    _active = value;
    onActiveChanged?.call(value);
  }

  static String _messageFor(Object error) {
    if (error is SileroTtsException) return error.message;
    final message = error.toString().replaceFirst('Bad state: ', '');
    return 'Голосовое ведение остановлено: $message';
  }
}
