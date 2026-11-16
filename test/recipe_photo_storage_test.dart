import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:povarnya/data/recipe_photo_storage.dart';

Uint8List _solidPng(int side) {
  final source = image.Image(width: side, height: side);
  source.clear(image.ColorRgba8(24, 96, 180, 255));
  return Uint8List.fromList(image.encodePng(source));
}

void main() {
  const fullImage = Rect.fromLTWH(0, 0, 1, 1);

  test('большая фотография уменьшается до 1024 на 1024', () {
    final stored = RecipePhotoStorage.cropAndEncodeForStorage(
      sourceBytes: _solidPng(1100),
      normalizedCrop: fullImage,
    );
    final decoded = image.decodePng(stored)!;

    expect(decoded.width, RecipePhotoStorage.maxStoredSide);
    expect(decoded.height, RecipePhotoStorage.maxStoredSide);
  });

  test('небольшая фотография сохраняет исходный размер', () {
    final stored = RecipePhotoStorage.cropAndEncodeForStorage(
      sourceBytes: _solidPng(640),
      normalizedCrop: fullImage,
    );
    final decoded = image.decodePng(stored)!;
    final pixel = decoded.getPixel(320, 320);

    expect(decoded.width, 640);
    expect(decoded.height, 640);
    expect(pixel.r, 24);
    expect(pixel.g, 96);
    expect(pixel.b, 180);
    expect(pixel.a, 255);
  });
}
