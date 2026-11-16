import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// Единая полноэкранная анимация ожидания «Рецептур».
///
/// Один и тот же MP4-файл и один и тот же виджет используются при
/// холодном запуске и во время проверки GitHub-обновления.
class PovarnyaLoadingVideo extends StatefulWidget {
  const PovarnyaLoadingVideo({
    super.key,
    this.loop = false,
    this.onFirstCycleCompleted,
    this.initializePlayer = true,
  });

  /// Повторять ролик, пока внешняя операция не завершится.
  final bool loop;

  /// Вызывается после фактического первого кадра и полного цикла.
  final VoidCallback? onFirstCycleCompleted;

  /// Отключает нативный плеер только в изуальных виджет-тестах.
  final bool initializePlayer;

  static const backgroundColor = Color(0xFFDCD2CC);

  @override
  State<PovarnyaLoadingVideo> createState() => _PovarnyaLoadingVideoState();
}

class _PovarnyaLoadingVideoState extends State<PovarnyaLoadingVideo> {
  static const _videoAsset = 'asset://assets/animations/Загрузочный экран.mp4';
  static const _videoCycle = Duration(milliseconds: 1345);
  static const _firstFrameTimeout = Duration(seconds: 5);

  Player? _player;
  VideoController? _videoController;
  bool _cycleReported = false;

  @override
  void initState() {
    super.initState();
    // Сначала показываем лёгкий цветной кадр, а после него грузим
    // нативные библиотеки видеодекодера.
    if (widget.initializePlayer) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _initializePlayer());
    }
  }

  void _initializePlayer() {
    if (!mounted) return;
    try {
      final player = Player();
      final videoController = VideoController(player);
      if (!mounted) {
        player.dispose();
        return;
      }
      setState(() {
        _player = player;
        _videoController = videoController;
      });
      unawaited(_play(player, videoController));
    } catch (error, stackTrace) {
      unawaited(_handleVideoFailure(error, stackTrace));
    }
  }

  Future<void> _play(Player player, VideoController videoController) async {
    try {
      await player.setPlaylistMode(
        widget.loop ? PlaylistMode.single : PlaylistMode.none,
      );
      await player.setVolume(0);
      await player.open(Media(_videoAsset)).timeout(_firstFrameTimeout);
      await videoController.waitUntilFirstFrameRendered.timeout(
        _firstFrameTimeout,
      );
      if (widget.onFirstCycleCompleted != null) {
        await Future<void>.delayed(_videoCycle);
        _reportCompletedCycle();
      }
    } catch (error, stackTrace) {
      await _handleVideoFailure(error, stackTrace);
    }
  }

  Future<void> _handleVideoFailure(Object error, StackTrace stackTrace) async {
    debugPrint('LOADING_VIDEO_ERROR: $error\n$stackTrace');
    if (widget.onFirstCycleCompleted != null) {
      await Future<void>.delayed(_videoCycle);
      _reportCompletedCycle();
    }
  }

  void _reportCompletedCycle() {
    if (!mounted || _cycleReported) return;
    _cycleReported = true;
    widget.onFirstCycleCompleted?.call();
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final videoController = _videoController;
    return ColoredBox(
      color: PovarnyaLoadingVideo.backgroundColor,
      child: videoController == null
          ? const SizedBox.expand()
          : SizedBox.expand(
              child: Video(
                controller: videoController,
                fit: BoxFit.contain,
                fill: PovarnyaLoadingVideo.backgroundColor,
                controls: null,
                wakelock: false,
              ),
            ),
    );
  }
}
