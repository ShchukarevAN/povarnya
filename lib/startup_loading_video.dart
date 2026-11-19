import 'dart:async';

import 'package:flutter/material.dart';

/// Единая полноэкранная анимация ожидания «Поварни».
///
/// Один и тот же WebP-ресурс и один и тот же виджет используются при
/// холодном запуске и во время проверки GitHub-обновления.
class PovarnyaLoadingVideo extends StatefulWidget {
  const PovarnyaLoadingVideo({
    super.key,
    this.onFirstCycleCompleted,
    this.showAnimation = true,
  });

  /// Вызывается после фактического первого кадра и полного цикла.
  final VoidCallback? onFirstCycleCompleted;

  /// Отключает декодирование анимации в виджет-тестах.
  final bool showAnimation;

  static const backgroundColor = Color(0xFFDCD2CC);

  @override
  State<PovarnyaLoadingVideo> createState() => _PovarnyaLoadingVideoState();
}

class _PovarnyaLoadingVideoState extends State<PovarnyaLoadingVideo> {
  static const _animationAsset = 'assets/animations/Загрузочный экран.webp';
  static const _animationCycle = Duration(milliseconds: 1350);

  Timer? _cycleTimer;
  bool _firstFrameDisplayed = false;
  bool _cycleReported = false;

  void _markFirstFrameDisplayed() {
    if (_firstFrameDisplayed) return;
    _firstFrameDisplayed = true;
    _cycleTimer = Timer(_animationCycle, _reportCompletedCycle);
  }

  void _reportCompletedCycle() {
    if (!mounted || _cycleReported) return;
    _cycleReported = true;
    widget.onFirstCycleCompleted?.call();
  }

  @override
  void dispose() {
    _cycleTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: PovarnyaLoadingVideo.backgroundColor,
    child: widget.showAnimation
        ? SizedBox.expand(
            child: Image.asset(
              _animationAsset,
              fit: BoxFit.contain,
              gaplessPlayback: true,
              frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                if (frame == 0 && !_firstFrameDisplayed) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _markFirstFrameDisplayed();
                  });
                }
                return child;
              },
              errorBuilder: (context, error, stackTrace) {
                debugPrint('LOADING_ANIMATION_ERROR: $error\n$stackTrace');
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _markFirstFrameDisplayed();
                });
                return const SizedBox.expand();
              },
            ),
          )
        : const SizedBox.expand(),
  );
}
