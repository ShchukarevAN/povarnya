import 'dart:convert';
import 'dart:io';

import 'package:flutter/scheduler.dart';

/// Пишет реальные времена действий Flutter-кадра только при запуске из
/// анализатора. В обычном запуске объект ничего не делает.
class PerformanceTrace {
  PerformanceTrace._();
  static final instance = PerformanceTrace._();

  File? _file;
  Future<void> _traceWriteQueue = Future<void>.value();

  Future<void> startIfRequested() async {
    final path = Platform.environment['POVARNYA_PERF_TRACE_PATH'];
    if (path == null || path.isEmpty) return;
    _file = File(path);
    await _file!.parent.create(recursive: true);
    await _file!.writeAsString('');
    SchedulerBinding.instance.addTimingsCallback(_recordFrames);
  }

  void _recordFrames(List<FrameTiming> frames) {
    final file = _file;
    if (file == null) return;
    for (final frame in frames) {
      final event = jsonEncode({
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'buildUs': frame.buildDuration.inMicroseconds,
        'rasterUs': frame.rasterDuration.inMicroseconds,
      });
      _traceWriteQueue = _traceWriteQueue.then(
        (_) => file.writeAsString('$event\n', mode: FileMode.append),
      );
    }
  }
}
