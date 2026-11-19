import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:record/record.dart';

import '../data/app_settings.dart';
import '../services/offline_speech_recognizer.dart';
import '../services/speech_diagnostics.dart';

/// Detects the end of a spoken phrase directly from little-endian PCM16.
///
/// A short loud impulse is ignored; after actual speech, one second of silence
/// ends the recording. Waiting for speech and total recording time are bounded
/// so a forgotten microphone never records indefinitely.
class SilenceEndpointDetector {
  SilenceEndpointDetector({
    this.sampleRate = 16000,
    this.amplitudeThreshold = 280,
    this.minimumSpeech = const Duration(milliseconds: 120),
    this.trailingSilence = const Duration(milliseconds: 1000),
    this.waitForSpeech = const Duration(seconds: 7),
    this.maximumDuration = const Duration(seconds: 20),
  });

  final int sampleRate;
  final double amplitudeThreshold;
  final Duration minimumSpeech;
  final Duration trailingSilence;
  final Duration waitForSpeech;
  final Duration maximumDuration;

  var _totalSamples = 0;
  var _candidateSpeechSamples = 0;
  var _silentSamples = 0;
  var _totalSquareSum = 0.0;
  int? _speechStartSample;
  int? _pendingLowByte;
  bool hasSpeech = false;
  double maxRms = 0;

  double get overallRms =>
      _totalSamples == 0 ? 0 : math.sqrt(_totalSquareSum / _totalSamples);

  Duration? get speechStart => _speechStartSample == null
      ? null
      : Duration(
          microseconds:
              (_speechStartSample! *
                      Duration.microsecondsPerSecond /
                      sampleRate)
                  .round(),
        );

  int get totalSamples => _totalSamples;

  Duration get recordedDuration => Duration(
    microseconds: (_totalSamples * Duration.microsecondsPerSecond / sampleRate)
        .round(),
  );

  bool add(Uint8List bytes) {
    var index = 0;
    var sampleCount = 0;
    var sumSquares = 0.0;

    void addSample(int raw) {
      final sample = (raw >= 0x8000 ? raw - 0x10000 : raw).toDouble();
      sumSquares += sample * sample;
      sampleCount++;
    }

    if (_pendingLowByte case final lowByte? when bytes.isNotEmpty) {
      addSample(lowByte | (bytes[0] << 8));
      _pendingLowByte = null;
      index = 1;
    }
    while (index + 1 < bytes.length) {
      addSample(bytes[index] | (bytes[index + 1] << 8));
      index += 2;
    }
    if (index < bytes.length) _pendingLowByte = bytes[index];
    if (sampleCount == 0) return false;
    final rms = math.sqrt(sumSquares / sampleCount);
    maxRms = math.max(maxRms, rms);
    _totalSquareSum += sumSquares;
    _totalSamples += sampleCount;

    if (rms >= amplitudeThreshold) {
      _candidateSpeechSamples += sampleCount;
      _silentSamples = 0;
      if (_candidateSpeechSamples >= _samples(minimumSpeech)) {
        _speechStartSample ??= _totalSamples - _candidateSpeechSamples;
        hasSpeech = true;
      }
    } else if (hasSpeech) {
      _silentSamples += sampleCount;
    } else {
      _candidateSpeechSamples = 0;
    }

    if (hasSpeech && _silentSamples >= _samples(trailingSilence)) return true;
    if (!hasSpeech && _totalSamples >= _samples(waitForSpeech)) return true;
    return _totalSamples >= _samples(maximumDuration);
  }

  int _samples(Duration duration) =>
      (sampleRate * duration.inMicroseconds / Duration.microsecondsPerSecond)
          .round();
}

enum _SpeechInputPhase { idle, recording, recognizing }

/// One-tap, confirmation-free microphone control.
class SpeechInputButton extends StatefulWidget {
  const SpeechInputButton({
    super.key,
    required this.onRecognized,
    this.onPartialRecognized,
    this.onRecognitionStarted,
    this.onRecognitionCanceled,
    this.color,
    this.tooltip = 'Голосовой ввод',
  });

  final ValueChanged<String> onRecognized;
  final ValueChanged<String>? onPartialRecognized;
  final VoidCallback? onRecognitionStarted;
  final VoidCallback? onRecognitionCanceled;
  final Color? color;
  final String tooltip;

  @override
  State<SpeechInputButton> createState() => _SpeechInputButtonState();
}

class _SpeechInputButtonState extends State<SpeechInputButton> {
  AudioRecorder? _recorder;
  StreamSubscription<Uint8List>? _audioSubscription;
  StreamSubscription<RecordStop>? _stopSubscription;
  Completer<void>? _audioDone;
  BytesBuilder _audio = BytesBuilder(copy: false);
  SilenceEndpointDetector _endpoint = SilenceEndpointDetector();
  _SpeechInputPhase _phase = _SpeechInputPhase.idle;
  bool _starting = false;
  bool _finishing = false;
  bool _captureFailureReported = false;
  bool _recognitionSessionStarted = false;
  bool _resultCommitted = false;
  bool _partialRecognitionInFlight = false;
  int _recognitionSession = 0;
  int _lastPartialAudioLength = 0;
  String _lastPartialText = '';
  Timer? _partialRecognitionTimer;
  Future<void>? _partialRecognitionFuture;

  static const _partialRecognitionInterval = Duration(milliseconds: 700);
  static const _minimumPartialAudioBytes = 16000;
  static const _minimumNewPartialAudioBytes = 8000;

  @override
  void dispose() {
    _partialRecognitionTimer?.cancel();
    _audioSubscription?.cancel();
    _stopSubscription?.cancel();
    final recorder = _recorder;
    if (recorder != null) unawaited(recorder.dispose());
    super.dispose();
  }

  Future<void> _handlePressed() async {
    if (_starting) return;
    if (_phase == _SpeechInputPhase.recording) {
      await _finishRecording();
    } else if (_phase == _SpeechInputPhase.idle) {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    _starting = true;
    if (mounted) setState(() {});
    try {
      final recorder = _recorder ??= AudioRecorder();
      if (!await recorder.hasPermission()) {
        await _reportFailure(
          const SpeechFailure(SpeechFailureStage.microphonePermission),
        );
        return;
      }
      _stopSubscription ??= recorder.onStopped().listen(_handleRecorderStopped);
      unawaited(_warmRecognizer());
      _audio = BytesBuilder(copy: false);
      final settings = AppSettings();
      _endpoint = SilenceEndpointDetector(
        amplitudeThreshold: settings.speechAmplitudeThreshold,
        trailingSilence: Duration(
          milliseconds: settings.speechTrailingSilenceMs,
        ),
        waitForSpeech: Duration(milliseconds: settings.speechWaitForSpeechMs),
      );
      _finishing = false;
      _captureFailureReported = false;
      _resultCommitted = false;
      _recognitionSessionStarted = false;
      _partialRecognitionInFlight = false;
      _partialRecognitionFuture = null;
      _lastPartialAudioLength = 0;
      _lastPartialText = '';
      _recognitionSession++;
      _audioDone = Completer<void>();
      final stream = await recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
          autoGain: true,
          echoCancel: true,
          noiseSuppress: true,
        ),
      );
      if (!mounted) return;
      setState(() => _phase = _SpeechInputPhase.recording);
      _recognitionSessionStarted = true;
      widget.onRecognitionStarted?.call();
      _partialRecognitionTimer?.cancel();
      _partialRecognitionTimer = Timer.periodic(
        _partialRecognitionInterval,
        (_) => _requestPartialRecognition(),
      );
      _audioSubscription = stream.listen(
        (chunk) {
          _audio.add(chunk);
          if (_endpoint.add(chunk)) unawaited(_finishRecording());
        },
        onError: (Object error) {
          unawaited(
            _reportCaptureFailure(
              SpeechFailure(
                SpeechFailureStage.microphoneStream,
                cause: error,
                technicalDetails: error.toString(),
              ),
            ),
          );
          unawaited(_finishRecording(recognize: false));
        },
        onDone: () {
          final audioDone = _audioDone;
          if (audioDone != null && !audioDone.isCompleted) audioDone.complete();
          if (!_finishing && _phase == _SpeechInputPhase.recording) {
            unawaited(
              _reportCaptureFailure(
                const SpeechFailure(
                  SpeechFailureStage.microphoneStream,
                  technicalDetails: 'Audio stream closed before stop()',
                ),
              ),
            );
            unawaited(_finishRecording(recognize: false));
          }
        },
      );
    } catch (error, stackTrace) {
      await _reportFailure(
        SpeechFailure(
          SpeechFailureStage.microphoneStart,
          cause: error,
          technicalDetails: error.toString(),
        ),
        stackTrace: stackTrace,
      );
      if (mounted) setState(() => _phase = _SpeechInputPhase.idle);
    } finally {
      _starting = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _finishRecording({bool recognize = true}) async {
    if (_finishing || _phase != _SpeechInputPhase.recording) return;
    _finishing = true;
    _partialRecognitionTimer?.cancel();
    _partialRecognitionTimer = null;
    try {
      try {
        await _recorder!.stop();
        await _audioDone?.future.timeout(const Duration(seconds: 2));
      } catch (error, stackTrace) {
        await _reportFailure(
          SpeechFailure(
            SpeechFailureStage.microphoneStop,
            cause: error,
            technicalDetails: error.toString(),
          ),
          stackTrace: stackTrace,
        );
        return;
      }
      await _audioSubscription?.cancel();
      _audioSubscription = null;
      if (!recognize) return;
      if (!_endpoint.hasSpeech) {
        await _reportFailure(const SpeechFailure(SpeechFailureStage.noSpeech));
        return;
      }
      await _partialRecognitionFuture;
      if (mounted) setState(() => _phase = _SpeechInputPhase.recognizing);
      final bytes = _audio.takeBytes();
      final text = await OfflineSpeechRecognizer.instance.recognizePcm16(bytes);
      if (text.isEmpty) {
        await _reportFailure(
          const SpeechFailure(SpeechFailureStage.noResult),
          diagnosticsContext: <String, Object?>{'audioBytes': bytes.length},
        );
      } else if (mounted) {
        _resultCommitted = true;
        widget.onRecognized(text);
      }
    } catch (error, stackTrace) {
      final failure = error is SpeechFailure
          ? error
          : SpeechFailure(
              SpeechFailureStage.unknown,
              cause: error,
              technicalDetails: error.toString(),
            );
      await _reportFailure(failure, stackTrace: stackTrace);
    } finally {
      if (_recognitionSessionStarted && !_resultCommitted) {
        widget.onRecognitionCanceled?.call();
      }
      _recognitionSessionStarted = false;
      if (mounted) setState(() => _phase = _SpeechInputPhase.idle);
      _finishing = false;
      _audioDone = null;
    }
  }

  void _requestPartialRecognition() {
    if (_finishing ||
        _phase != _SpeechInputPhase.recording ||
        !_endpoint.hasSpeech ||
        _partialRecognitionInFlight ||
        widget.onPartialRecognized == null) {
      return;
    }
    final audioLength = _audio.length;
    if (audioLength < _minimumPartialAudioBytes ||
        audioLength - _lastPartialAudioLength < _minimumNewPartialAudioBytes) {
      return;
    }
    _lastPartialAudioLength = audioLength;
    final session = _recognitionSession;
    final snapshot = _audio.toBytes();
    _partialRecognitionInFlight = true;
    final future = _recognizePartial(snapshot, session);
    _partialRecognitionFuture = future;
    unawaited(future);
  }

  Future<void> _recognizePartial(Uint8List audio, int session) async {
    try {
      final text = await OfflineSpeechRecognizer.instance.recognizePcm16(
        audio,
        timeout: const Duration(seconds: 8),
      );
      if (!mounted ||
          session != _recognitionSession ||
          _finishing ||
          _phase != _SpeechInputPhase.recording ||
          text.isEmpty ||
          text == _lastPartialText) {
        return;
      }
      _lastPartialText = text;
      widget.onPartialRecognized?.call(text);
    } catch (_) {
      // A preview is best-effort. The final pass reports a detailed error.
    } finally {
      if (session == _recognitionSession) {
        _partialRecognitionInFlight = false;
      }
    }
  }

  Future<void> _warmRecognizer() async {
    try {
      await OfflineSpeechRecognizer.instance.prepare();
    } catch (_) {
      // recognizePcm16 retries initialization and reports a precise stage.
    }
  }

  void _handleRecorderStopped(RecordStop event) {
    if (_finishing || _phase != _SpeechInputPhase.recording) return;
    if (event.reason == RecordStopReason.stop) return;
    unawaited(
      _reportCaptureFailure(
        SpeechFailure(
          SpeechFailureStage.microphoneStream,
          technicalDetails:
              'reason=${event.reason.name}; error=${event.error ?? '-'}',
        ),
      ),
    );
    unawaited(_finishRecording(recognize: false));
  }

  Future<void> _reportCaptureFailure(SpeechFailure failure) async {
    if (_captureFailureReported) return;
    _captureFailureReported = true;
    await _reportFailure(failure);
  }

  Future<void> _reportFailure(
    SpeechFailure failure, {
    StackTrace? stackTrace,
    Map<String, Object?> diagnosticsContext = const <String, Object?>{},
  }) async {
    final logPath = await SpeechDiagnostics.record(
      failure,
      stackTrace: stackTrace,
      context: <String, Object?>{
        'platform': defaultTargetPlatform.name,
        'hasSpeech': _endpoint.hasSpeech,
        'maxRms': _endpoint.maxRms.round(),
        'recordedMs': _endpoint.recordedDuration.inMilliseconds,
        ...diagnosticsContext,
      },
    );
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 8),
          content: Text(
            logPath == null
                ? failure.userMessage
                : '${failure.userMessage}\nДиагностика: $logPath',
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    return IconButton(
      constraints: Theme.of(context).inputDecorationTheme.suffixIconConstraints,
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      tooltip: _phase == _SpeechInputPhase.recording
          ? 'Идёт запись — завершится по тишине'
          : widget.tooltip,
      onPressed: _starting || _phase == _SpeechInputPhase.recognizing
          ? null
          : _handlePressed,
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 160),
        child: switch (_phase) {
          _SpeechInputPhase.idle => Icon(
            Icons.mic_none,
            key: const ValueKey('speech-idle'),
            color: color,
          ),
          _SpeechInputPhase.recording => Icon(
            Icons.mic,
            key: const ValueKey('speech-recording'),
            color: Theme.of(context).colorScheme.error,
          ),
          _SpeechInputPhase.recognizing => SizedBox(
            key: const ValueKey('speech-recognizing'),
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: color),
          ),
        },
      ),
    );
  }
}
