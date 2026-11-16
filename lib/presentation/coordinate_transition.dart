import 'package:flutter/material.dart';

/// Размещает копию элемента между двумя фактическими прямоугольниками.
/// Используется переходами между экранами и представлениями одного рецепта.
Widget coordinateFlight({
  required Rect source,
  required Rect target,
  required double progress,
  required Widget child,
  // Quartic-кривая заметнее задерживается у старта и цели, чем cubic:
  // элемент плавно разгоняется, проходит середину быстрее и тормозит у места.
  Curve curve = Curves.easeInOutQuart,
  double opacity = 1,
  // Текст одинакового кегля в двух состояниях не следует подгонять под
  // прямоугольник: иначе FittedBox незаметно меняет его размер в полёте.
  bool preserveChildSize = false,
}) {
  final rect = Rect.lerp(source, target, curve.transform(progress))!;
  if (preserveChildSize) {
    return Positioned(
      left: rect.left,
      top: rect.top,
      child: Opacity(opacity: opacity, child: child),
    );
  }
  return Positioned.fromRect(
    rect: rect,
    child: Opacity(
      opacity: opacity,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: child,
      ),
    ),
  );
}
