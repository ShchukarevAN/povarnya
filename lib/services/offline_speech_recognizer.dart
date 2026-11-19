import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

import '../data/app_settings.dart';
import '../data/data_directory.dart';
import 'speech_diagnostics.dart';
import 'speech_personalization.dart';

/// Persistent background recognizer backed by the bundled Russian Zipformer2.
///
/// Model files are copied out of Flutter assets once because sherpa-onnx takes
/// filesystem paths. The native recognizer remains in its own isolate between
/// requests, so the large model is loaded only once per application session.
class OfflineSpeechRecognizer {
  OfflineSpeechRecognizer._();

  static final instance = OfflineSpeechRecognizer._();

  static const _assetDirectory = 'assets/modules/zipformer2_ru';
  static const _modelFiles = <String, int>{
    'encoder.int8.onnx': 70876638,
    'decoder.int8.onnx': 1326290,
    'joiner.int8.onnx': 259417,
    'tokens.txt': 6388,
  };

  Future<Map<String, String>>? _modelPathsFuture;
  Future<SendPort>? _workerFuture;
  Isolate? _workerIsolate;
  ReceivePort? _responsePort;
  final _requests = <int, Completer<String>>{};
  var _nextRequestId = 0;

  /// Starts model extraction/loading early. Safe to call repeatedly.
  Future<void> prepare() async {
    Map<String, String> modelPaths;
    try {
      modelPaths = await (_modelPathsFuture ??= _prepareModelFiles());
    } catch (error, stackTrace) {
      _modelPathsFuture = null;
      Error.throwWithStackTrace(
        SpeechFailure(
          SpeechFailureStage.modelFiles,
          cause: error,
          technicalDetails: error.toString(),
        ),
        stackTrace,
      );
    }

    try {
      await (_workerFuture ??= _startWorker(modelPaths));
    } catch (error, stackTrace) {
      _workerFuture = null;
      if (error is SpeechFailure) rethrow;
      Error.throwWithStackTrace(
        SpeechFailure(
          SpeechFailureStage.workerStart,
          cause: error,
          technicalDetails: error.toString(),
        ),
        stackTrace,
      );
    }
  }

  Future<String> recognizePcm16(
    Uint8List pcmBytes, {
    bool applyPersonalization = true,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (pcmBytes.isEmpty) return '';
    await prepare();

    final id = _nextRequestId++;
    final completer = Completer<String>();
    _requests[id] = completer;
    final worker = await _workerFuture!;
    worker.send(<Object?>[
      id,
      TransferableTypedData.fromList(<Uint8List>[pcmBytes]),
    ]);
    try {
      final rawText = await completer.future.timeout(timeout);
      if (!applyPersonalization || rawText.isEmpty) return rawText;
      final settings = AppSettings();
      return applySpeechPersonalization(
        rawText,
        personalWords: settings.speechPersonalWords,
        corrections: settings.speechCorrections,
      );
    } on TimeoutException catch (error, stackTrace) {
      _requests.remove(id);
      _discardWorker();
      Error.throwWithStackTrace(
        SpeechFailure(
          SpeechFailureStage.decodeTimeout,
          cause: error,
          technicalDetails: 'request=$id, bytes=${pcmBytes.length}',
        ),
        stackTrace,
      );
    }
  }

  Future<Map<String, String>> _prepareModelFiles() async {
    final supportDirectory = await povarnyaDataDirectory();
    final modelDirectory = Directory(
      path.join(supportDirectory.path, 'models', 'zipformer2_ru_v0_54'),
    );
    await modelDirectory.create(recursive: true);

    final result = <String, String>{};
    for (final entry in _modelFiles.entries) {
      final output = File(path.join(modelDirectory.path, entry.key));
      final isCurrent =
          await output.exists() && await output.length() == entry.value;
      if (!isCurrent) {
        final asset = await rootBundle.load('$_assetDirectory/${entry.key}');
        await output.writeAsBytes(
          asset.buffer.asUint8List(asset.offsetInBytes, asset.lengthInBytes),
          flush: true,
        );
      }
      result[entry.key] = output.path;
    }
    return result;
  }

  Future<SendPort> _startWorker(Map<String, String> modelPaths) async {
    _responsePort = ReceivePort();
    final ready = Completer<SendPort>();
    _responsePort!.listen((dynamic message) {
      if (message is SendPort) {
        if (!ready.isCompleted) ready.complete(message);
        return;
      }
      if (message is! List || message.length < 3) return;
      final id = message[0] as int;
      final success = message[1] as bool;
      final request = _requests.remove(id);
      if (request == null) return;
      if (success) {
        request.complete(message[2] as String);
      } else {
        final payload = (message[2] as Map).cast<String, Object?>();
        final stage = SpeechFailureStage.values.firstWhere(
          (candidate) => candidate.name == payload['stage'],
          orElse: () => SpeechFailureStage.unknown,
        );
        request.completeError(
          SpeechFailure(stage, technicalDetails: payload['error']?.toString()),
          StackTrace.fromString(payload['stack']?.toString() ?? ''),
        );
      }
    });
    try {
      _workerIsolate = await Isolate.spawn<List<Object?>>(
        _speechWorkerMain,
        <Object?>[_responsePort!.sendPort, modelPaths],
        debugName: 'zipformer2-ru',
      );
      return await ready.future.timeout(const Duration(seconds: 10));
    } catch (_) {
      _discardWorker();
      rethrow;
    }
  }

  void _discardWorker() {
    _workerIsolate?.kill(priority: Isolate.immediate);
    _workerIsolate = null;
    _responsePort?.close();
    _responsePort = null;
    _workerFuture = null;
  }
}

@pragma('vm:entry-point')
Future<void> _speechWorkerMain(List<Object?> startup) async {
  final mainPort = startup[0] as SendPort;
  final modelPaths = (startup[1] as Map).cast<String, String>();
  final commands = ReceivePort();
  mainPort.send(commands.sendPort);

  sherpa_onnx.OfflineRecognizer? recognizer;

  Future<void> ensureRecognizer() async {
    if (recognizer != null) return;
    try {
      await sherpa_onnx.initBindingsAsync();
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        _WorkerSpeechError(
          SpeechFailureStage.nativeBindings,
          error,
          stackTrace,
        ),
        stackTrace,
      );
    }
    try {
      recognizer = sherpa_onnx.OfflineRecognizer(
        sherpa_onnx.OfflineRecognizerConfig(
          feat: const sherpa_onnx.FeatureConfig(
            sampleRate: 16000,
            featureDim: 80,
          ),
          model: sherpa_onnx.OfflineModelConfig(
            transducer: sherpa_onnx.OfflineTransducerModelConfig(
              encoder: modelPaths['encoder.int8.onnx']!,
              decoder: modelPaths['decoder.int8.onnx']!,
              joiner: modelPaths['joiner.int8.onnx']!,
            ),
            tokens: modelPaths['tokens.txt']!,
            numThreads: 2,
            debug: false,
            provider: 'cpu',
          ),
          decodingMethod: 'greedy_search',
        ),
      );
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        _WorkerSpeechError(SpeechFailureStage.modelLoad, error, stackTrace),
        stackTrace,
      );
    }
  }

  await for (final dynamic message in commands) {
    if (message is! List || message.length < 2) continue;
    final id = message[0] as int;
    try {
      await ensureRecognizer();
      final bytes = (message[1] as TransferableTypedData)
          .materialize()
          .asUint8List();
      final sampleCount = bytes.length ~/ 2;
      final samples = Float32List(sampleCount);
      final data = ByteData.sublistView(bytes);
      for (var index = 0; index < sampleCount; index++) {
        samples[index] = data.getInt16(index * 2, Endian.little) / 32768.0;
      }

      try {
        final stream = recognizer!.createStream();
        try {
          stream.acceptWaveform(samples: samples, sampleRate: 16000);
          recognizer!.decode(stream);
          final text = recognizer!.getResult(stream).text.trim();
          mainPort.send(<Object?>[id, true, text]);
        } finally {
          stream.free();
        }
      } catch (error, stackTrace) {
        Error.throwWithStackTrace(
          _WorkerSpeechError(SpeechFailureStage.decode, error, stackTrace),
          stackTrace,
        );
      }
    } catch (error, stackTrace) {
      final workerError = error is _WorkerSpeechError
          ? error
          : _WorkerSpeechError(SpeechFailureStage.unknown, error, stackTrace);
      mainPort.send(<Object?>[
        id,
        false,
        <String, Object?>{
          'stage': workerError.stage.name,
          'error': workerError.error.toString(),
          'stack': workerError.stackTrace.toString(),
        },
      ]);
    }
  }
  recognizer?.free();
}

class _WorkerSpeechError implements Exception {
  const _WorkerSpeechError(this.stage, this.error, this.stackTrace);

  final SpeechFailureStage stage;
  final Object error;
  final StackTrace stackTrace;
}
