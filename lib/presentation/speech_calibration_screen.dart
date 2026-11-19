import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:record/record.dart';

import '../data/app_settings.dart';
import '../services/offline_speech_recognizer.dart';
import '../services/speech_calibration_prompts.dart';
import '../services/speech_diagnostics.dart';
import '../services/speech_personalization.dart';
import 'speech_input_button.dart';

class SpeechCalibrationScreen extends StatefulWidget {
  const SpeechCalibrationScreen({super.key});

  @override
  State<SpeechCalibrationScreen> createState() =>
      _SpeechCalibrationScreenState();
}

enum _CalibrationPhase {
  introduction,
  preparing,
  recording,
  recognizing,
  done,
  failed,
}

class _SpeechCalibrationScreenState extends State<SpeechCalibrationScreen> {
  AudioRecorder? _recorder;
  final List<_CalibrationPrompt> _prompts = [];
  final List<_CalibrationObservation> _observations = [];
  final Stopwatch _stopwatch = Stopwatch();
  Timer? _clockTimer;
  _CalibrationPhase _phase = _CalibrationPhase.introduction;
  String _status = '';
  String _prompt = '';
  String _recognized = '';
  String? _failure;
  int _promptIndex = 0;
  int _elapsedSeconds = 0;
  bool _cancelRequested = false;
  bool _captureActive = false;
  double _workingThreshold = 280;
  double _noiseRms = 0;

  bool get _running => switch (_phase) {
    _CalibrationPhase.preparing ||
    _CalibrationPhase.recording ||
    _CalibrationPhase.recognizing => true,
    _ => false,
  };

  AudioRecorder get _audioRecorder => _recorder ??= AudioRecorder();

  @override
  void dispose() {
    _cancelRequested = true;
    _clockTimer?.cancel();
    final recorder = _recorder;
    if (recorder != null) unawaited(recorder.dispose());
    super.dispose();
  }

  Future<void> _startCalibration() async {
    if (_running) return;
    _cancelRequested = false;
    _observations.clear();
    _promptIndex = 0;
    _failure = null;
    _recognized = '';
    _stopwatch
      ..reset()
      ..start();
    _clockTimer?.cancel();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _elapsedSeconds = _stopwatch.elapsed.inSeconds);
      }
    });

    try {
      if (!await _audioRecorder.hasPermission()) {
        throw const SpeechFailure(SpeechFailureStage.microphonePermission);
      }
      if (!mounted) return;
      setState(() {
        _phase = _CalibrationPhase.preparing;
        _status = 'Подбираю различные модули и шаги рецептов';
        _prompt = '';
      });
      final texts = await createSpeechCalibrationTexts();
      if (_cancelRequested) return _finishCancellation();
      final firstModulePass = [...texts.modules]..shuffle();
      final secondModulePass = [...texts.modules]..shuffle();
      _prompts
        ..clear()
        ..addAll(
          texts.trainingSteps.map(
            (text) => _CalibrationPrompt(text, validation: false),
          ),
        )
        ..addAll(
          firstModulePass.map(
            (text) => _CalibrationPrompt(text, validation: false),
          ),
        )
        ..addAll(
          secondModulePass.map(
            (text) => _CalibrationPrompt(text, validation: false),
          ),
        )
        ..addAll(
          texts.validationSteps.map(
            (text) => _CalibrationPrompt(text, validation: true),
          ),
        );
      if (!mounted) return;
      setState(() {
        _status = 'Сохраняйте тишину — измеряю фоновый шум';
      });
      unawaited(_warmRecognizer());
      final silence = await _capture(fixedDuration: const Duration(seconds: 5));
      if (_cancelRequested) return _finishCancellation();
      _noiseRms = silence.detector.overallRms;
      _workingThreshold = (_noiseRms * 2.8).clamp(140, 800).toDouble();

      for (var index = 0; index < _prompts.length; index++) {
        if (_cancelRequested) break;
        final item = _prompts[index];
        _promptIndex = index;
        if (!mounted) return;
        setState(() {
          _phase = _CalibrationPhase.preparing;
          _status = item.validation
              ? 'Контрольная фраза — приготовьтесь'
              : 'Приготовьтесь';
          _prompt = item.text;
          _recognized = '';
        });
        await Future<void>.delayed(const Duration(milliseconds: 900));
        if (_cancelRequested) return _finishCancellation();

        setState(() {
          _phase = _CalibrationPhase.recording;
          _status = 'Говорите';
        });
        final take = await _capture(
          amplitudeThreshold: _workingThreshold,
          trailingSilence: const Duration(milliseconds: 900),
          waitForSpeech: const Duration(seconds: 6),
        );
        if (_cancelRequested) return _finishCancellation();
        if (!take.detector.hasSpeech || take.bytes.isEmpty) continue;

        setState(() {
          _phase = _CalibrationPhase.recognizing;
          _status = 'Распознаю фразу';
        });
        final recognized = await OfflineSpeechRecognizer.instance
            .recognizePcm16(take.bytes, applyPersonalization: false);
        _observations.add(
          _CalibrationObservation(
            expected: item.text,
            recognized: recognized,
            validation: item.validation,
            detector: take.detector,
          ),
        );
        if (mounted) setState(() => _recognized = recognized);
        await Future<void>.delayed(const Duration(milliseconds: 350));
      }
      if (_cancelRequested) return _finishCancellation();
      await _saveProfile();
    } catch (error, stackTrace) {
      final failure = error is SpeechFailure
          ? error
          : SpeechFailure(
              SpeechFailureStage.unknown,
              cause: error,
              technicalDetails: error.toString(),
            );
      await SpeechDiagnostics.record(
        failure,
        stackTrace: stackTrace,
        context: const <String, Object?>{'source': 'speech-calibration'},
      );
      _stopClock();
      if (mounted) {
        setState(() {
          _phase = _CalibrationPhase.failed;
          _failure = failure.userMessage;
        });
      }
    }
  }

  Future<_CalibrationTake> _capture({
    Duration? fixedDuration,
    double amplitudeThreshold = double.infinity,
    Duration trailingSilence = const Duration(milliseconds: 1000),
    Duration waitForSpeech = const Duration(seconds: 7),
  }) async {
    final detector = SilenceEndpointDetector(
      amplitudeThreshold: amplitudeThreshold,
      trailingSilence: trailingSilence,
      waitForSpeech: waitForSpeech,
      maximumDuration: const Duration(seconds: 12),
    );
    final audio = BytesBuilder(copy: false);
    final endpoint = Completer<void>();
    Object? streamError;
    StackTrace? streamStack;
    Timer? fixedTimer;
    StreamSubscription<Uint8List>? subscription;
    _captureActive = true;
    try {
      final stream = await _audioRecorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
          autoGain: true,
          echoCancel: true,
          noiseSuppress: true,
        ),
      );
      subscription = stream.listen(
        (chunk) {
          audio.add(chunk);
          if (fixedDuration == null &&
              detector.add(chunk) &&
              !endpoint.isCompleted) {
            endpoint.complete();
          } else if (fixedDuration != null) {
            detector.add(chunk);
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          streamError = error;
          streamStack = stackTrace;
          if (!endpoint.isCompleted) endpoint.complete();
        },
        onDone: () {
          if (!endpoint.isCompleted) endpoint.complete();
        },
      );
      if (fixedDuration != null) {
        fixedTimer = Timer(fixedDuration, () {
          if (!endpoint.isCompleted) endpoint.complete();
        });
      }
      await endpoint.future.timeout(const Duration(seconds: 15));
      await _audioRecorder.stop();
      await subscription.cancel();
      if (streamError != null) {
        Error.throwWithStackTrace(
          SpeechFailure(
            SpeechFailureStage.microphoneStream,
            cause: streamError,
            technicalDetails: streamError.toString(),
          ),
          streamStack ?? StackTrace.current,
        );
      }
      return _CalibrationTake(audio.takeBytes(), detector);
    } finally {
      fixedTimer?.cancel();
      _captureActive = false;
      await subscription?.cancel();
      try {
        if (await _audioRecorder.isRecording()) await _audioRecorder.stop();
      } catch (_) {
        // A simultaneous cancellation may already have stopped the recorder.
      }
    }
  }

  Future<void> _warmRecognizer() async {
    try {
      await OfflineSpeechRecognizer.instance.prepare();
    } catch (_) {
      // The first recorded phrase retries and reports the precise failure.
    }
  }

  Future<void> _saveProfile() async {
    if (_observations.length < 10) {
      throw const SpeechFailure(
        SpeechFailureStage.noSpeech,
        technicalDetails: 'Calibration collected fewer than 10 phrases',
      );
    }

    final speechPeaks =
        _observations
            .map((item) => item.detector.maxRms)
            .where((value) => value > 0)
            .toList()
          ..sort();
    final quietSpeech = speechPeaks[(speechPeaks.length * .2).floor()];
    var threshold = math.max(120.0, _noiseRms * 2.8);
    threshold = math
        .min(threshold, quietSpeech * .45)
        .clamp(120, 900)
        .toDouble();

    final startDelays =
        _observations
            .map((item) => item.detector.speechStart?.inMilliseconds ?? 0)
            .where((value) => value > 0)
            .toList()
          ..sort();
    final startDelay = startDelays.isEmpty
        ? 1000
        : startDelays[(startDelays.length * .9).floor().clamp(
            0,
            startDelays.length - 1,
          )];
    final waitForSpeechMs = (startDelay + 3000).clamp(4000, 10000);

    final millisecondsPerWord =
        _observations
            .map(
              (item) =>
                  item.detector.recordedDuration.inMilliseconds /
                  math.max(
                    1,
                    normalizeSpeechText(item.expected).split(' ').length,
                  ),
            )
            .reduce((sum, value) => sum + value) /
        _observations.length;
    final trailingSilenceMs = millisecondsPerWord > 1100
        ? 1500
        : millisecondsPerWord > 800
        ? 1200
        : millisecondsPerWord > 550
        ? 1000
        : 800;

    final learned = _learnPersonalVocabulary(_observations);
    final validation = _observations.where((item) => item.validation).toList();
    var expectedWords = 0;
    var wordErrors = 0;
    for (final item in validation) {
      expectedWords += normalizeSpeechText(item.expected).split(' ').length;
      final personalized = applySpeechPersonalization(
        item.recognized,
        personalWords: learned.words,
        corrections: learned.corrections,
      );
      wordErrors += speechWordDistance(item.expected, personalized);
    }
    final accuracy = expectedWords == 0
        ? 0
        : ((1 - wordErrors / expectedWords) * 100).round().clamp(0, 100);

    final settings = AppSettings();
    settings.speechAmplitudeThreshold = threshold;
    settings.speechTrailingSilenceMs = trailingSilenceMs;
    settings.speechWaitForSpeechMs = waitForSpeechMs;
    settings.speechPersonalWords = learned.words;
    settings.speechCorrections = learned.corrections;
    settings.speechCalibrationAccuracy = accuracy;
    settings.speechCalibrationPhraseCount = _observations.length;
    settings.speechProfileUpdatedAt = DateTime.now();
    await settings.save();
    _stopClock();
    if (!mounted) return;
    setState(() {
      _phase = _CalibrationPhase.done;
      _status = 'Настройка завершена';
      _prompt = '';
      _recognized = '';
    });
  }

  Future<void> _cancel() async {
    if (!_running) return;
    _cancelRequested = true;
    if (_captureActive) {
      try {
        await _audioRecorder.stop();
      } catch (_) {
        // The active capture will finish through its stream callback.
      }
    }
  }

  void _finishCancellation() {
    _stopClock();
    if (!mounted) return;
    setState(() {
      _phase = _CalibrationPhase.introduction;
      _status = '';
      _prompt = '';
      _recognized = '';
    });
  }

  void _stopClock() {
    _stopwatch.stop();
    _clockTimer?.cancel();
    _clockTimer = null;
    _elapsedSeconds = _stopwatch.elapsed.inSeconds;
  }

  Future<void> _resetProfile() async {
    final settings = AppSettings();
    settings.speechAmplitudeThreshold = 280;
    settings.speechTrailingSilenceMs = 1000;
    settings.speechWaitForSpeechMs = 7000;
    settings.speechPersonalWords = <String>[];
    settings.speechCorrections = <String, String>{};
    settings.speechCalibrationAccuracy = 0;
    settings.speechCalibrationPhraseCount = 0;
    settings.speechProfileUpdatedAt = null;
    await settings.save();
    if (mounted) setState(() {});
  }

  String get _elapsedLabel {
    final minutes = _elapsedSeconds ~/ 60;
    final seconds = _elapsedSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final settings = AppSettings();
    final progress = _prompts.isEmpty
        ? 0.0
        : (_promptIndex / _prompts.length).clamp(0.0, 1.0);
    return PopScope(
      canPop: !_running,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Настройка распознавания речи'),
          actions: [
            if (_running)
              TextButton(onPressed: _cancel, child: const Text('Отменить')),
          ],
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  if (_phase == _CalibrationPhase.introduction)
                    _Introduction(
                      hasProfile: settings.speechProfileUpdatedAt != null,
                      accuracy: settings.speechCalibrationAccuracy,
                      phraseCount: settings.speechCalibrationPhraseCount,
                      onStart: _startCalibration,
                      onReset: settings.speechProfileUpdatedAt == null
                          ? null
                          : _resetProfile,
                    )
                  else if (_phase == _CalibrationPhase.done)
                    _Completion(
                      settings: settings,
                      elapsed: _elapsedLabel,
                      onClose: () => Navigator.pop(context),
                      onRepeat: _startCalibration,
                    )
                  else if (_phase == _CalibrationPhase.failed)
                    _Failure(
                      message: _failure ?? 'Неизвестная ошибка',
                      onRetry: _startCalibration,
                    )
                  else ...[
                    LinearProgressIndicator(value: progress),
                    const SizedBox(height: 12),
                    Text(
                      '${math.min(_promptIndex + 1, _prompts.length)} из ${_prompts.length} · $_elapsedLabel',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    Icon(
                      _phase == _CalibrationPhase.recording
                          ? Icons.mic
                          : _phase == _CalibrationPhase.recognizing
                          ? Icons.graphic_eq
                          : Icons.hearing,
                      size: 64,
                      color: _phase == _CalibrationPhase.recording
                          ? Theme.of(context).colorScheme.error
                          : Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _status,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    if (_prompt.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            _prompt,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                        ),
                      ),
                    ],
                    if (_recognized.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Распознано: $_recognized',
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 24),
                    const Text(
                      'Фразы переключаются автоматически. Говорите обычным голосом после появления красного микрофона.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Introduction extends StatelessWidget {
  const _Introduction({
    required this.hasProfile,
    required this.accuracy,
    required this.phraseCount,
    required this.onStart,
    required this.onReset,
  });

  final bool hasProfile;
  final int accuracy;
  final int phraseCount;
  final VoidCallback onStart;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Icon(
        Icons.record_voice_over,
        size: 72,
        color: Theme.of(context).colorScheme.primary,
      ),
      const SizedBox(height: 20),
      Text(
        'Персональная настройка около 10 минут',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 16),
      const Text(
        'Сначала приложение измерит тишину, затем автоматически запишет кулинарные слова и фразы. Говорите естественно и делайте обычные паузы. Записи обрабатываются локально и после настройки не сохраняются.',
        textAlign: TextAlign.center,
      ),
      if (hasProfile) ...[
        const SizedBox(height: 16),
        Text(
          'Текущий профиль: $accuracy% на контрольных фразах, обработано $phraseCount фраз.',
          textAlign: TextAlign.center,
        ),
      ],
      const SizedBox(height: 28),
      FilledButton.icon(
        key: const ValueKey('start-speech-calibration'),
        onPressed: onStart,
        icon: const Icon(Icons.mic),
        label: Text(hasProfile ? 'Настроить заново' : 'Начать настройку'),
      ),
      if (onReset != null)
        TextButton(
          onPressed: onReset,
          child: const Text('Сбросить профиль речи'),
        ),
    ],
  );
}

class _Completion extends StatelessWidget {
  const _Completion({
    required this.settings,
    required this.elapsed,
    required this.onClose,
    required this.onRepeat,
  });

  final AppSettings settings;
  final String elapsed;
  final VoidCallback onClose;
  final VoidCallback onRepeat;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Icon(
        Icons.check_circle,
        size: 72,
        color: Theme.of(context).colorScheme.primary,
      ),
      const SizedBox(height: 16),
      Text(
        'Профиль речи готов',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 16),
      Text(
        'Контрольная точность: ${settings.speechCalibrationAccuracy}%\n'
        'Фраз обработано: ${settings.speechCalibrationPhraseCount}\n'
        'Личных слов: ${settings.speechPersonalWords.length}\n'
        'Устойчивых исправлений: ${settings.speechCorrections.length}\n'
        'Время: $elapsed',
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 24),
      FilledButton(onPressed: onClose, child: const Text('Готово')),
      TextButton(onPressed: onRepeat, child: const Text('Повторить настройку')),
    ],
  );
}

class _Failure extends StatelessWidget {
  const _Failure({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Icon(
        Icons.error_outline,
        size: 72,
        color: Theme.of(context).colorScheme.error,
      ),
      const SizedBox(height: 16),
      Text(message, textAlign: TextAlign.center),
      const SizedBox(height: 24),
      FilledButton(onPressed: onRetry, child: const Text('Повторить')),
    ],
  );
}

class _CalibrationPrompt {
  const _CalibrationPrompt(this.text, {required this.validation});
  final String text;
  final bool validation;
}

class _CalibrationTake {
  const _CalibrationTake(this.bytes, this.detector);
  final Uint8List bytes;
  final SilenceEndpointDetector detector;
}

class _CalibrationObservation {
  const _CalibrationObservation({
    required this.expected,
    required this.recognized,
    required this.validation,
    required this.detector,
  });
  final String expected;
  final String recognized;
  final bool validation;
  final SilenceEndpointDetector detector;
}

({List<String> words, Map<String, String> corrections})
_learnPersonalVocabulary(Iterable<_CalibrationObservation> observations) {
  final missedWords = <String, int>{};
  final correctionCounts = <String, Map<String, int>>{};
  for (final item in observations.where((item) => !item.validation)) {
    final expected = normalizeSpeechText(item.expected);
    final recognized = normalizeSpeechText(item.recognized);
    if (expected.isEmpty || recognized.isEmpty || expected == recognized) {
      continue;
    }
    final expectedWords = expected.split(' ');
    final recognizedWords = recognized.split(' ');
    for (final word in expectedWords) {
      if (word.length >= 4 && !recognizedWords.contains(word)) {
        missedWords[word] = (missedWords[word] ?? 0) + 1;
      }
    }
    if (expectedWords.length == recognizedWords.length) {
      for (var index = 0; index < expectedWords.length; index++) {
        final source = recognizedWords[index];
        final replacement = expectedWords[index];
        if (source == replacement || source.length < 3) continue;
        final replacements = correctionCounts.putIfAbsent(
          source,
          () => <String, int>{},
        );
        replacements[replacement] = (replacements[replacement] ?? 0) + 1;
      }
    }
  }

  final corrections = <String, String>{};
  for (final entry in correctionCounts.entries) {
    final ranked = entry.value.entries.toList()
      ..sort((left, right) => right.value.compareTo(left.value));
    if (ranked.isNotEmpty && ranked.first.value >= 2) {
      corrections[entry.key] = ranked.first.key;
    }
  }
  final words =
      missedWords.entries
          .where((entry) => entry.value >= 2)
          .map((entry) => entry.key)
          .toList()
        ..sort();
  return (words: words, corrections: corrections);
}
