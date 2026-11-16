import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// Returns the persistent directory shared by the database and settings.
///
/// Desktop launch scripts can keep the data inside the project by setting
/// [POVARNYA_DATA_DIR]. Mobile platforms instead use the application's
/// private support directory, because their current directory is not writable.
Future<Directory> povarnyaDataDirectory() async {
  final configuredPath = Platform.environment['POVARNYA_DATA_DIR'];
  if (configuredPath != null && configuredPath.isNotEmpty) {
    return Directory(configuredPath);
  }
  if (Platform.isAndroid || Platform.isIOS) {
    return getApplicationSupportDirectory();
  }
  return Directory(path.join(Directory.current.path, 'database'));
}

/// Постоянный закрытый каталог фотографий рецептов.
///
/// Он находится рядом с базой приложения, поэтому переживает обычное обновление
/// APK и не засоряет пользовательскую галерею. Старые мобильные версии хранили
/// фотографии в системном кэше; при первом обращении переносим их отсюда.
Future<Directory> povarnyaRecipePhotoDirectory() async {
  final data = await povarnyaDataDirectory();
  final directory = Directory(path.join(data.path, 'recipe_photos'));
  if (Platform.isAndroid || Platform.isIOS) {
    final cache = await getApplicationCacheDirectory();
    final legacyDirectory = Directory(path.join(cache.path, 'recipe_photos'));
    await _migrateLegacyRecipePhotos(legacyDirectory, directory);
  }
  return directory;
}

/// Удаляет и новое постоянное хранилище, и оставшийся кэш старых версий.
Future<void> deletePovarnyaRecipePhotoFiles() async {
  final data = await povarnyaDataDirectory();
  final directory = Directory(path.join(data.path, 'recipe_photos'));
  if (await directory.exists()) await directory.delete(recursive: true);

  if (Platform.isAndroid || Platform.isIOS) {
    final cache = await getApplicationCacheDirectory();
    final legacyDirectory = Directory(path.join(cache.path, 'recipe_photos'));
    if (await legacyDirectory.exists()) {
      await legacyDirectory.delete(recursive: true);
    }
  }
}

Future<void> _migrateLegacyRecipePhotos(
  Directory legacyDirectory,
  Directory persistentDirectory,
) async {
  if (!await legacyDirectory.exists()) return;

  await persistentDirectory.create(recursive: true);
  await for (final entity in legacyDirectory.list(followLinks: false)) {
    if (entity is! File) continue;
    final target = File(
      path.join(persistentDirectory.path, path.basename(entity.path)),
    );
    if (!await target.exists()) await entity.copy(target.path);
  }

  // Старую копию удаляем только после успешного переноса всех файлов.
  await legacyDirectory.delete(recursive: true);
}
