import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/scheduler.dart';

/// Пишет реальные времена действий Flutter-кадра только при запуске из
/// анализатора. В обычном запуске объект ничего не делает.
class PerformanceTrace {
  PerformanceTrace._();
  static final instance = PerformanceTrace._();

  File? _file;
  StringBuffer _pendingFrames = StringBuffer();
  Future<void> _traceWriteQueue = Future<void>.value();

  Future<void> startIfRequested() async {
    final path = Platform.environment['POVARNYA_PERF_TRACE_PATH'];
    if (path == null || path.isEmpty) return;
    _file = File(path);
    await _file!.parent.create(recursive: true);
    await _file!.writeAsString('');
    SchedulerBinding.instance.addTimingsCallback(_recordFrames);
    Timer.periodic(const Duration(seconds: 1), (_) => _flushPendingFrames());
  }

  void _recordFrames(List<FrameTiming> frames) {
    if (_file == null) return;
    for (final frame in frames) {
      final event = jsonEncode({
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'buildUs': frame.buildDuration.inMicroseconds,
        'rasterUs': frame.rasterDuration.inMicroseconds,
      });
      _pendingFrames.writeln(event);
    }
  }

  void _flushPendingFrames() {
    final file = _file;
    if (file == null || _pendingFrames.length == 0) return;
    final batch = _pendingFrames.toString();
    _pendingFrames = StringBuffer();
    _traceWriteQueue = _traceWriteQueue.then(
      (_) => file.writeAsString(batch, mode: FileMode.append),
    );
  }
}
