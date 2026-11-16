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

/// Каталог фотографий рецептов. На ПК снимки лежат рядом с базой и входят в
/// локальный набор данных проекта; на телефоне они являются воспроизводимым
/// кешем приложения и не засоряют пользовательскую галерею.
Future<Directory> povarnyaRecipePhotoDirectory() async {
  if (Platform.isAndroid || Platform.isIOS) {
    final cache = await getApplicationCacheDirectory();
    return Directory(path.join(cache.path, 'recipe_photos'));
  }
  final data = await povarnyaDataDirectory();
  return Directory(path.join(data.path, 'recipe_photos'));
}
