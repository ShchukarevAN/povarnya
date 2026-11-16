import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:file_selector/file_selector.dart';
import 'package:image/image.dart' as image;
import 'package:path/path.dart' as path;

import 'data_directory.dart';
import 'recipe_database.dart';

/// Выбор, квадратная обрезка и локальное сохранение фотографий рецептов.
/// PNG с максимальным уровнем сжатия не меняет пиксели после обрезки.
class StoredRecipePhoto {
  const StoredRecipePhoto({this.path, this.bytes});
  final String? path;
  final Uint8List? bytes;
}

class RecipePhotoStorage {
  const RecipePhotoStorage._();

  static const maxStoredSide = 1024;

  static const _imageTypes = XTypeGroup(
    label: 'Изображения',
    extensions: ['jpg', 'jpeg', 'png', 'webp', 'bmp', 'gif', 'tif', 'tiff'],
    mimeTypes: ['image/*'],
    uniformTypeIdentifiers: ['public.image'],
  );

  static Future<Uint8List?> selectImageBytes() async {
    final file = await openFile(acceptedTypeGroups: const [_imageTypes]);
    return file?.readAsBytes();
  }

  static image.Image? decode(Uint8List bytes) {
    final decoded = image.decodeImage(bytes);
    return decoded == null ? null : image.bakeOrientation(decoded);
  }

  static Future<StoredRecipePhoto> cropAndStore({
    required String recipeId,
    required Uint8List sourceBytes,
    required Rect normalizedCrop,
  }) async {
    final pngBytes = cropAndEncodeForStorage(
      sourceBytes: sourceBytes,
      normalizedCrop: normalizedCrop,
    );
    if (!Platform.isAndroid && !Platform.isIOS) {
      await RecipeDatabase().saveRecipePhotoBytes(recipeId, pngBytes);
      return StoredRecipePhoto(bytes: pngBytes);
    }
    final directory = await povarnyaRecipePhotoDirectory();
    await directory.create(recursive: true);
    final fileName = '$recipeId.png';
    final output = File(path.join(directory.path, fileName));
    await output.writeAsBytes(pngBytes, flush: true);
    await RecipeDatabase().saveRecipePhotoFileName(recipeId, fileName);
    return StoredRecipePhoto(path: output.path);
  }

  /// Обрезает снимок и уменьшает только изображения крупнее 1024×1024.
  /// PNG остаётся со сжатием без потерь; level влияет лишь на размер и время.
  static Uint8List cropAndEncodeForStorage({
    required Uint8List sourceBytes,
    required Rect normalizedCrop,
  }) {
    final decoded = decode(sourceBytes);
    if (decoded == null) {
      throw const FormatException('Файл не является изображением.');
    }
    final cropSize = (normalizedCrop.width * decoded.width)
        .round()
        .clamp(
          1,
          decoded.width < decoded.height ? decoded.width : decoded.height,
        )
        .toInt();
    final maxLeft = decoded.width - cropSize;
    final maxTop = decoded.height - cropSize;
    final left = (normalizedCrop.left * decoded.width)
        .round()
        .clamp(0, maxLeft)
        .toInt();
    final top = (normalizedCrop.top * decoded.height)
        .round()
        .clamp(0, maxTop)
        .toInt();
    var cropped = image.copyCrop(
      decoded,
      x: left,
      y: top,
      width: cropSize,
      height: cropSize,
    );
    if (cropped.width > maxStoredSide || cropped.height > maxStoredSide) {
      cropped = image.copyResize(
        cropped,
        width: maxStoredSide,
        height: maxStoredSide,
        interpolation: image.Interpolation.cubic,
        linearBlend: true,
      );
    }
    return Uint8List.fromList(image.encodePng(cropped, level: 9));
  }
}
