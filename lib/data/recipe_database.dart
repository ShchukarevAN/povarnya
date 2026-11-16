import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../domain/catalog.dart';
import '../domain/recipe_node.dart';
import 'data_directory.dart';

import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Локальное хранилище. Медиа лежат рядом с БД, SQLite содержит лишь метаданные.
class RecipeDatabase {
  factory RecipeDatabase() => _instance;
  RecipeDatabase._();

  static final RecipeDatabase _instance = RecipeDatabase._();
  static const _favoriteRecipeFlag = 1;
  Database? _database;
  final Map<String, String> _recipeNotes = {};
  final Map<String, int> _recipeServings = {};
  final Map<String, int> _recipeMultipliers = {};
  final Map<String, RecipeCategory> _recipeCategories = {};
  final Map<String, RecipeFasting> _recipeFasting = {};
  final Map<String, bool> _recipeFavorites = {};
  final Map<String, String?> _recipePhotoPaths = {};
  final Map<String, Uint8List?> _recipePhotoBytes = {};
  final Map<String, List<RecipeNode>> _recipeSteps = {};
  Future<Database> open() async {
    if (_database != null) return _database!;
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final dataDirectory = await povarnyaDataDirectory();
    await dataDirectory.create(recursive: true);
    _database = await databaseFactory.openDatabase(
      path.join(dataDirectory.path, 'recipes.db'),
      options: OpenDatabaseOptions(version: 1, onCreate: _createSchema),
    );
    await _ensureSchemaCompatibility(_database!);
    final rows = await _database!.rawQuery(
      'SELECT COUNT(*) AS count FROM document_root',
    );
    final count = rows.first['count'] as int? ?? 0;
    if (count == 0) {
      await _seedCatalog(_database!);
      await _writeCatalogRevision(_database!);
    } else if (await _needsCatalogRefresh(_database!)) {
      await _addMissingCatalogEntries(_database!);
      await _writeCatalogRevision(_database!);
    }
    return _database!;
  }

  Future<void> _createSchema(Database database, int version) async {
    await database.execute(
      "CREATE TABLE card (id TEXT PRIMARY KEY, kind INTEGER NOT NULL, nominative TEXT NOT NULL, forms_json TEXT NOT NULL DEFAULT '{}')",
    );
    await database.execute(
      "CREATE TABLE document_root (id TEXT PRIMARY KEY, title TEXT NOT NULL, document_kind INTEGER NOT NULL, note TEXT NOT NULL DEFAULT '', is_customized INTEGER NOT NULL DEFAULT 0, servings INTEGER NOT NULL DEFAULT 2 CHECK(servings BETWEEN 0 AND 255), recipe_multiplier INTEGER NOT NULL DEFAULT 2 CHECK(recipe_multiplier BETWEEN 0 AND 255), category TEXT NOT NULL DEFAULT 'other', fasting TEXT NOT NULL DEFAULT 'non-lean', flags INTEGER NOT NULL DEFAULT 0, open_count INTEGER NOT NULL DEFAULT 0, change_count INTEGER NOT NULL DEFAULT 0, last_open_day INTEGER NOT NULL DEFAULT 0, last_change_day INTEGER NOT NULL DEFAULT 0)",
    );
    await database.execute(
      "CREATE TABLE node (id TEXT PRIMARY KEY, root_id TEXT NOT NULL REFERENCES document_root(id) ON DELETE CASCADE, parent_id TEXT REFERENCES node(id) ON DELETE CASCADE, card_id TEXT NOT NULL REFERENCES card(id), sort_order INTEGER NOT NULL, grammar_case INTEGER NOT NULL DEFAULT 0, join_text TEXT NOT NULL DEFAULT ' ', value INTEGER, upper_value INTEGER, numeric_unit INTEGER, text_value TEXT CHECK(length(text_value) <= 255))",
    );
    await database.execute(
      'CREATE INDEX node_by_parent ON node(parent_id, sort_order)',
    );
    await database.execute(
      'CREATE TABLE visual_asset (visual_key TEXT PRIMARY KEY, relative_path TEXT NOT NULL, media_type TEXT NOT NULL, width INTEGER, height INTEGER, checksum TEXT)',
    );
    await database.execute(
      'CREATE TABLE recipe_photo (recipe_id TEXT PRIMARY KEY REFERENCES document_root(id) ON DELETE CASCADE, file_name TEXT NOT NULL, image_bytes BLOB, updated_at INTEGER NOT NULL)',
    );
    await database.execute(
      'CREATE TABLE app_metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
    );
  }

  /// Дополняет единственную пользовательскую БД новыми колонками на месте.
  /// При первом запуске множитель копирует уже выбранное число порций, включая
  /// компактное представление 256 как нуля в однобайтном поле.
  Future<void> _ensureSchemaCompatibility(Database database) async {
    await database.execute(
      'CREATE TABLE IF NOT EXISTS app_metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
    );
    await database.execute(
      'CREATE TABLE IF NOT EXISTS recipe_photo (recipe_id TEXT PRIMARY KEY REFERENCES document_root(id) ON DELETE CASCADE, file_name TEXT NOT NULL, image_bytes BLOB, updated_at INTEGER NOT NULL)',
    );
    final photoColumns = await database.rawQuery(
      'PRAGMA table_info(recipe_photo)',
    );
    if (!photoColumns.any((column) => column['name'] == 'image_bytes')) {
      await database.execute(
        'ALTER TABLE recipe_photo ADD COLUMN image_bytes BLOB',
      );
    }
    final columns = await database.rawQuery('PRAGMA table_info(document_root)');
    final hasMultiplier = columns.any(
      (column) => column['name'] == 'recipe_multiplier',
    );
    if (!hasMultiplier) {
      await database.execute(
        'ALTER TABLE document_root ADD COLUMN recipe_multiplier INTEGER NOT NULL DEFAULT 2 CHECK(recipe_multiplier BETWEEN 0 AND 255)',
      );
      await database.execute(
        'UPDATE document_root SET recipe_multiplier = servings',
      );
    }
    final existingColumnNames = columns
        .map((column) => column['name'] as String)
        .toSet();
    if (!existingColumnNames.contains('category')) {
      await database.execute(
        "ALTER TABLE document_root ADD COLUMN category TEXT NOT NULL DEFAULT 'other'",
      );
      final batch = database.batch();
      for (final recipe in catalogRecipes) {
        batch.update(
          'document_root',
          {'category': recipe.category.storageKey},
          where: 'id = ?',
          whereArgs: [recipe.id],
        );
      }
      await batch.commit(noResult: true);
    }
    if (!existingColumnNames.contains('fasting')) {
      await database.execute(
        "ALTER TABLE document_root ADD COLUMN fasting TEXT NOT NULL DEFAULT 'non-lean'",
      );
      final batch = database.batch();
      for (final recipe in catalogRecipes) {
        batch.update(
          'document_root',
          {'fasting': recipe.fasting.storageKey},
          where: 'id = ?',
          whereArgs: [recipe.id],
        );
      }
      await batch.commit(noResult: true);
    }
    const metricColumns = <String, String>{
      // Битовые метки рецепта. Младший бит — «любимый»; остальные пока
      // свободны, поэтому новые переключатели не потребуют новых колонок.
      'flags': 'INTEGER NOT NULL DEFAULT 0',
      'open_count': 'INTEGER NOT NULL DEFAULT 0',
      'change_count': 'INTEGER NOT NULL DEFAULT 0',
      'last_open_day': 'INTEGER NOT NULL DEFAULT 0',
      'last_change_day': 'INTEGER NOT NULL DEFAULT 0',
    };
    for (final metric in metricColumns.entries) {
      if (existingColumnNames.contains(metric.key)) continue;
      await database.execute(
        'ALTER TABLE document_root ADD COLUMN ${metric.key} ${metric.value}',
      );
    }
  }

  Future<bool> _needsCatalogRefresh(Database database) async {
    final rows = await database.query(
      'app_metadata',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: ['catalog_revision'],
      limit: 1,
    );
    return rows.isEmpty || rows.first['value'] != catalogRevision;
  }

  Future<void> _writeCatalogRevision(Database database) => database.insert(
    'app_metadata',
    {'key': 'catalog_revision', 'value': catalogRevision},
    conflictAlgorithm: ConflictAlgorithm.replace,
  );

  int _todayKey([DateTime? now]) {
    final value = now ?? DateTime.now();
    return value.year * 10000 + value.month * 100 + value.day;
  }

  /// Учитывает не более одного открытия одного рецепта за календарный день.
  /// Запись выполняется при входе в рецепт, а не при его закрытии.
  Future<void> recordRecipeOpened(String recipeId) async {
    final database = await open();
    final day = _todayKey();
    await database.rawUpdate(
      '''UPDATE document_root
         SET open_count = open_count + CASE WHEN last_open_day = ? THEN 0 ELSE 1 END,
             last_open_day = ?
         WHERE id = ?''',
      [day, day, recipeId],
    );
  }

  /// Идентификаторы десяти рецептов с наибольшим числом дней открытия.
  /// При равенстве приоритет получает чаще изменяемый рецепт, затем название.
  Future<List<String>> mostOpenedRecipeIds({int limit = 10}) async {
    final database = await open();
    final rows = await database.query(
      'document_root',
      columns: ['id'],
      orderBy: 'open_count DESC, change_count DESC, title COLLATE NOCASE ASC',
      limit: limit,
    );
    return rows.map((row) => row['id'] as String).toList();
  }

  /// Личная заметка не входит в состав модульного рецепта и сохраняется
  /// отдельно: обновления встроенного каталога её не перезаписывают.
  Future<String> loadRecipeNote(String recipeId) async {
    final cached = _recipeNotes[recipeId];
    if (cached != null) return cached;
    final database = await open();
    final rows = await database.query(
      'document_root',
      columns: ['note'],
      where: 'id = ?',
      whereArgs: [recipeId],
      limit: 1,
    );
    final note = rows.isEmpty ? '' : (rows.first['note'] as String? ?? '');
    _recipeNotes[recipeId] = note;
    return note;
  }

  Future<void> saveRecipeNote(String recipeId, String note) async {
    final database = await open();
    await database.update(
      'document_root',
      {'note': note},
      where: 'id = ?',
      whereArgs: [recipeId],
    );
    _recipeNotes[recipeId] = note;
  }

  Future<int> loadRecipeServings(String recipeId) async {
    final cached = _recipeServings[recipeId];
    if (cached != null) return cached;
    final database = await open();
    final rows = await database.query(
      'document_root',
      columns: ['servings'],
      where: 'id = ?',
      whereArgs: [recipeId],
      limit: 1,
    );
    final stored = rows.isEmpty ? 2 : rows.first['servings'] as int? ?? 2;
    final servings = stored == 0 ? 256 : stored;
    _recipeServings[recipeId] = servings;
    return servings;
  }

  Future<int> loadRecipeMultiplier(String recipeId) async {
    final cached = _recipeMultipliers[recipeId];
    if (cached != null) return cached;
    final database = await open();
    final rows = await database.query(
      'document_root',
      columns: ['recipe_multiplier'],
      where: 'id = ?',
      whereArgs: [recipeId],
      limit: 1,
    );
    final stored = rows.isEmpty
        ? 2
        : rows.first['recipe_multiplier'] as int? ?? 2;
    final multiplier = stored == 0 ? 256 : stored;
    _recipeMultipliers[recipeId] = multiplier;
    return multiplier;
  }

  /// Категория блюда. Словарь хранится строковым ключом, поэтому порядок enum
  /// можно менять без миграции пользовательской базы.
  Future<RecipeCategory> loadRecipeCategory(String recipeId) async {
    final cached = _recipeCategories[recipeId];
    if (cached != null) return cached;
    final database = await open();
    final rows = await database.query(
      'document_root',
      columns: ['category'],
      where: 'id = ?',
      whereArgs: [recipeId],
      limit: 1,
    );
    final category = RecipeCategory.fromStorage(
      rows.isEmpty ? null : rows.first['category'] as String?,
    );
    _recipeCategories[recipeId] = category;
    return category;
  }

  Future<Map<String, RecipeCategory>> loadRecipeCategories() async {
    final database = await open();
    final rows = await database.query(
      'document_root',
      columns: ['id', 'category'],
    );
    final categories = <String, RecipeCategory>{
      for (final row in rows)
        row['id'] as String: RecipeCategory.fromStorage(
          row['category'] as String?,
        ),
    };
    _recipeCategories.addAll(categories);
    return categories;
  }

  /// Постность блюда хранится отдельно от его основного раздела.
  Future<RecipeFasting> loadRecipeFasting(String recipeId) async {
    final cached = _recipeFasting[recipeId];
    if (cached != null) return cached;
    final database = await open();
    final rows = await database.query(
      'document_root',
      columns: ['fasting'],
      where: 'id = ?',
      whereArgs: [recipeId],
      limit: 1,
    );
    final fasting = RecipeFasting.fromStorage(
      rows.isEmpty ? null : rows.first['fasting'] as String?,
    );
    _recipeFasting[recipeId] = fasting;
    return fasting;
  }

  Future<Map<String, RecipeFasting>> loadRecipeFastingCategories() async {
    final database = await open();
    final rows = await database.query(
      'document_root',
      columns: ['id', 'fasting'],
    );
    final values = <String, RecipeFasting>{
      for (final row in rows)
        row['id'] as String: RecipeFasting.fromStorage(
          row['fasting'] as String?,
        ),
    };
    _recipeFasting.addAll(values);
    return values;
  }

  /// Возвращает локальную метку «любимый рецепт».
  Future<bool> loadRecipeFavorite(String recipeId) async {
    final cached = _recipeFavorites[recipeId];
    if (cached != null) return cached;
    final database = await open();
    final rows = await database.query(
      'document_root',
      columns: ['flags'],
      where: 'id = ?',
      whereArgs: [recipeId],
      limit: 1,
    );
    final flags = rows.isEmpty ? 0 : rows.first['flags'] as int? ?? 0;
    final favorite = (flags & _favoriteRecipeFlag) != 0;
    _recipeFavorites[recipeId] = favorite;
    return favorite;
  }

  /// Устанавливает локальную метку «любимый рецепт».
  Future<void> setRecipeFavorite(String recipeId, bool favorite) async {
    final database = await open();
    await database.rawUpdate(
      '''UPDATE document_root
         SET flags = CASE WHEN ? = 1 THEN flags | ? ELSE flags & ~? END
         WHERE id = ?''',
      [favorite ? 1 : 0, _favoriteRecipeFlag, _favoriteRecipeFlag, recipeId],
    );
    _recipeFavorites[recipeId] = favorite;
  }

  /// Идентификаторы рецептов с установленным младшим битом «любимый».
  Future<Set<String>> favoriteRecipeIds() async {
    final database = await open();
    final rows = await database.query(
      'document_root',
      columns: ['id'],
      where: 'flags & ? != 0',
      whereArgs: [_favoriteRecipeFlag],
    );
    return rows.map((row) => row['id'] as String).toSet();
  }

  /// Путь не загружает байты изображения: декодирование остаётся ленивым и
  /// начинается только когда карточка фотографии действительно видна.
  Future<String?> loadRecipePhotoPath(String recipeId) async {
    if (!Platform.isAndroid && !Platform.isIOS) return null;
    if (_recipePhotoPaths.containsKey(recipeId)) {
      return _recipePhotoPaths[recipeId];
    }
    final database = await open();
    final rows = await database.query(
      'recipe_photo',
      columns: ['file_name'],
      where: 'recipe_id = ?',
      whereArgs: [recipeId],
      limit: 1,
    );
    if (rows.isEmpty) return _recipePhotoPaths[recipeId] = null;
    final directory = await povarnyaRecipePhotoDirectory();
    final photoPath = path.join(
      directory.path,
      rows.first['file_name'] as String,
    );
    return _recipePhotoPaths[recipeId] = await File(photoPath).exists()
        ? photoPath
        : null;
  }

  Future<void> saveRecipePhotoFileName(String recipeId, String fileName) async {
    final database = await open();
    await database.insert('recipe_photo', {
      'recipe_id': recipeId,
      'file_name': fileName,
      'image_bytes': null,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    final directory = await povarnyaRecipePhotoDirectory();
    _recipePhotoPaths[recipeId] = path.join(directory.path, fileName);
  }

  /// На ПК данные изображения находятся в SQLite, а на телефоне — в закрытом
  /// постоянном каталоге приложения. Этот метод не вызывается для обычного
  /// списка рецептов, поэтому BLOB декодируется только при фактическом открытии
  /// нужного блюда.
  Future<Uint8List?> loadRecipePhotoBytes(String recipeId) async {
    if (Platform.isAndroid || Platform.isIOS) return null;
    if (_recipePhotoBytes.containsKey(recipeId)) {
      return _recipePhotoBytes[recipeId];
    }
    final database = await open();
    final rows = await database.query(
      'recipe_photo',
      columns: ['image_bytes'],
      where: 'recipe_id = ?',
      whereArgs: [recipeId],
      limit: 1,
    );
    final bytes = rows.isEmpty ? null : rows.first['image_bytes'] as Uint8List?;
    _recipePhotoBytes[recipeId] = bytes;
    return bytes;
  }

  Future<void> saveRecipePhotoBytes(String recipeId, Uint8List bytes) async {
    final database = await open();
    await database.insert('recipe_photo', {
      'recipe_id': recipeId,
      'file_name': '',
      'image_bytes': bytes,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    _recipePhotoBytes[recipeId] = bytes;
    _recipePhotoPaths.remove(recipeId);
  }

  /// Удаляет только пользовательские фотографии, не затрагивая рецепты,
  /// заметки, избранное и остальные данные каталога.
  Future<void> deleteAllRecipePhotos() async {
    final database = await open();
    await database.delete('recipe_photo');
    _recipePhotoPaths.clear();
    _recipePhotoBytes.clear();
    await deletePovarnyaRecipePhotoFiles();
  }

  /// Сбрасывает единственное локальное хранилище приложения. После удаления
  /// база сразу создаётся заново с встроенным каталогом, но без заметок,
  /// пользовательских правок, избранного, статистики и фотографий.
  Future<void> resetLocalData() async {
    final openDatabase = _database;
    _database = null;
    if (openDatabase != null) await openDatabase.close();
    _recipeNotes.clear();
    _recipeServings.clear();
    _recipeMultipliers.clear();
    _recipeCategories.clear();
    _recipeFasting.clear();
    _recipeFavorites.clear();
    _recipePhotoPaths.clear();
    _recipePhotoBytes.clear();
    _recipeSteps.clear();
    final dataDirectory = await povarnyaDataDirectory();
    if (await dataDirectory.exists()) {
      await dataDirectory.delete(recursive: true);
    }
    await deletePovarnyaRecipePhotoFiles();
    await open();
  }

  /// Восстанавливает модульное дерево из локальной БД, сохраняя порядок и
  /// вложенность. Если рецепта ещё нет в БД, возвращает пустой список.
  Future<List<RecipeNode>> loadRecipeSteps(String recipeId) async {
    final cached = _recipeSteps[recipeId];
    if (cached != null) return _cloneNodes(cached);
    final database = await open();
    final rows = await database.query(
      'node',
      where: 'root_id = ?',
      whereArgs: [recipeId],
      orderBy: 'parent_id IS NOT NULL, parent_id, sort_order',
    );
    final nodesByStoredId = <String, RecipeNode>{};
    final validRows = <Map<String, Object?>>[];
    const prefixSeparator = '.';
    final prefix = '$recipeId$prefixSeparator';

    for (final row in rows) {
      final card = CatalogCards.byId[row['card_id'] as String?];
      if (card == null) continue;
      final storedId = row['id'] as String;
      final unitIndex = row['numeric_unit'] as int?;
      nodesByStoredId[storedId] = RecipeNode(
        id: storedId.startsWith(prefix)
            ? storedId.substring(prefix.length)
            : storedId,
        card: card,
        caseFromParent: GrammarCase.values[row['grammar_case'] as int? ?? 0],
        joinWithPrevious: row['join_text'] as String? ?? ' ',
        value: row['value'] as int?,
        upperValue: row['upper_value'] as int?,
        unit: unitIndex == null ? null : NumericUnit.values[unitIndex],
        text: row['text_value'] as String?,
      );
      validRows.add(row);
    }

    final roots = <RecipeNode>[];
    for (final row in validRows) {
      final node = nodesByStoredId[row['id'] as String]!;
      final parentId = row['parent_id'] as String?;
      if (parentId == null) {
        roots.add(node);
      } else {
        nodesByStoredId[parentId]?.children.add(node);
      }
    }
    _recipeSteps[recipeId] = roots;
    return _cloneNodes(roots);
  }

  /// Подготавливает данные встроенных рецептов до открытия первого экрана.
  /// Редактор получает независимые копии узлов, поэтому его изменения не
  /// могут испортить этот кэш до явного сохранения.
  Future<void> preloadRecipeContent(Iterable<String> recipeIds) async {
    await Future.wait([
      for (final recipeId in recipeIds)
        Future.wait([
          loadRecipeNote(recipeId),
          loadRecipeServings(recipeId),
          loadRecipeMultiplier(recipeId),
          loadRecipeCategory(recipeId),
          loadRecipeFasting(recipeId),
          loadRecipeSteps(recipeId),
        ]),
    ]);
  }

  List<RecipeNode> _cloneNodes(Iterable<RecipeNode> nodes) => [
    for (final node in nodes)
      RecipeNode(
        id: node.id,
        card: node.card,
        caseFromParent: node.caseFromParent,
        joinWithPrevious: node.joinWithPrevious,
        value: node.value,
        upperValue: node.upperValue,
        unit: node.unit,
        text: node.text,
        children: _cloneNodes(node.children),
      ),
  ];

  /// Атомарно записывает всё дерево и заметку при выходе из рецепта.
  Future<void> saveRecipeContent({
    required String recipeId,
    required List<RecipeNode> steps,
    required String note,
    required int servings,
    required int recipeMultiplier,
    required RecipeCategory category,
    required RecipeFasting fasting,
  }) async {
    final database = await open();
    final batch = database.batch();
    batch.delete('node', where: 'root_id = ?', whereArgs: [recipeId]);
    batch.update(
      'document_root',
      {
        'note': note,
        'servings': _encodeOneByte(servings),
        'recipe_multiplier': _encodeOneByte(recipeMultiplier),
        'category': category.storageKey,
        'fasting': fasting.storageKey,
        'is_customized': 1,
      },
      where: 'id = ?',
      whereArgs: [recipeId],
    );

    _addNodeTree(batch, recipeId, steps);
    await batch.commit(noResult: true);
    await _recordRecipeChanged(recipeId, database);
    _recipeNotes[recipeId] = note;
    _recipeServings[recipeId] = servings;
    _recipeMultipliers[recipeId] = recipeMultiplier;
    _recipeCategories[recipeId] = category;
    _recipeFasting[recipeId] = fasting;
    _recipeSteps[recipeId] = _cloneNodes(steps);
  }

  /// Учитывает не более одного сохранённого изменения за календарный день.
  Future<void> _recordRecipeChanged(String recipeId, Database database) async {
    final day = _todayKey();
    await database.rawUpdate(
      '''UPDATE document_root
         SET change_count = change_count + CASE WHEN last_change_day = ? THEN 0 ELSE 1 END,
             last_change_day = ?
         WHERE id = ?''',
      [day, day, recipeId],
    );
  }

  int _encodeOneByte(int value) =>
      value == 256 ? 0 : value.clamp(1, 255).toInt();

  String? _storedText(String? value) {
    if (value == null) return null;
    return value.length <= freeTextMaxLength
        ? value
        : value.substring(0, freeTextMaxLength);
  }

  /// Сериализует дерево модулей одинаково для пользовательского сохранения,
  /// первого заполнения БД и обновления встроенного каталога.
  void _addNodeTree(Batch batch, String recipeId, Iterable<RecipeNode> roots) {
    void addNode(RecipeNode node, String? parentId, int order) {
      batch.insert('node', {
        'id': '$recipeId.${node.id}',
        'root_id': recipeId,
        'parent_id': parentId == null ? null : '$recipeId.$parentId',
        'card_id': node.card.id,
        'sort_order': order,
        'grammar_case': node.caseFromParent.index,
        'join_text': node.joinWithPrevious,
        'value': node.value,
        'upper_value': node.upperValue,
        'numeric_unit': node.unit?.index,
        'text_value': _storedText(node.text),
      });
      for (final child in node.children.indexed) {
        addNode(child.$2, node.id, child.$1);
      }
    }

    for (final root in roots.indexed) {
      addNode(root.$2, null, root.$1);
    }
  }

  Future<void> _seedCatalog(Database database) async {
    final batch = database.batch();
    for (final card in CatalogCards.all) {
      batch.insert('card', {
        'id': card.id,
        'kind': card.kind.index,
        'nominative': card.nominative,
        'forms_json': jsonEncode(
          card.forms.map((key, value) => MapEntry(key.index.toString(), value)),
        ),
      });
    }
    for (final recipe in catalogRecipes) {
      batch.insert('document_root', {
        'id': recipe.id,
        'title': recipe.title,
        'document_kind': 0,
        'servings': _encodeOneByte(recipe.servings),
        'recipe_multiplier': _encodeOneByte(recipe.servings),
        'category': recipe.category.storageKey,
        'fasting': recipe.fasting.storageKey,
      });
      _addNodeTree(batch, recipe.id, recipe.buildSteps());
    }
    await batch.commit(noResult: true);
  }

  /// Добавляет новые предустановленные карточки и рецепты в уже существующую
  /// базу, не изменяя рецепты, которые пользователь мог отредактировать.
  Future<void> _addMissingCatalogEntries(Database database) async {
    final rootRows = await database.query(
      'document_root',
      columns: [
        'id',
        'note',
        'is_customized',
        'flags',
        'open_count',
        'change_count',
        'last_open_day',
        'last_change_day',
        'category',
        'fasting',
      ],
    );
    final existingRootIds = rootRows.map((row) => row['id'] as String).toSet();
    final existingNotes = {
      for (final row in rootRows)
        row['id'] as String: row['note'] as String? ?? '',
    };
    final customizedRecipeIds = rootRows
        .where((row) => (row['is_customized'] as int? ?? 0) != 0)
        .map((row) => row['id'] as String)
        .toSet();
    final existingUsage = {
      for (final row in rootRows)
        row['id'] as String: <String, int>{
          'open_count': row['open_count'] as int? ?? 0,
          'flags': row['flags'] as int? ?? 0,
          'change_count': row['change_count'] as int? ?? 0,
          'last_open_day': row['last_open_day'] as int? ?? 0,
          'last_change_day': row['last_change_day'] as int? ?? 0,
        },
    };
    final batch = database.batch();
    // Эти встроенные записи обновляются вместе с каталогом. Пользовательские
    // рецепты имеют другие идентификаторы и не затрагиваются.
    // Встроенный каталог — часть программы, поэтому неотредактированные
    // записи синхронизируются с его актуальной модульной структурой.
    final catalogRecipesToRefresh = catalogRecipes
        .map((recipe) => recipe.id)
        .toSet();
    // Ранний черновой вариант драников был заменён рецептом из капусты и
    // картошки, поэтому не должен оставаться в локальном каталоге.
    if (existingRootIds.contains('potato-pancakes')) {
      batch.delete(
        'document_root',
        where: 'id = ?',
        whereArgs: ['potato-pancakes'],
      );
    }
    for (final card in CatalogCards.all) {
      final values = {
        'id': card.id,
        'kind': card.kind.index,
        'nominative': card.nominative,
        'forms_json': jsonEncode(
          card.forms.map((key, value) => MapEntry(key.index.toString(), value)),
        ),
      };
      batch.insert('card', values, conflictAlgorithm: ConflictAlgorithm.ignore);
      batch.update(
        'card',
        values..remove('id'),
        where: 'id = ?',
        whereArgs: [card.id],
      );
    }
    for (final recipe in catalogRecipes) {
      if (existingRootIds.contains(recipe.id)) {
        if (!catalogRecipesToRefresh.contains(recipe.id) ||
            customizedRecipeIds.contains(recipe.id)) {
          continue;
        }
        // SQLite foreign_keys выключен по умолчанию в sqflite_ffi, поэтому
        // дочерние узлы удаляем явно до удаления корня.
        batch.delete('node', where: 'root_id = ?', whereArgs: [recipe.id]);
        batch.delete('document_root', where: 'id = ?', whereArgs: [recipe.id]);
      }
      final usage = existingUsage[recipe.id];
      batch.insert('document_root', {
        'id': recipe.id,
        'title': recipe.title,
        'document_kind': 0,
        'note': existingNotes[recipe.id] ?? '',
        'servings': _encodeOneByte(recipe.servings),
        'recipe_multiplier': _encodeOneByte(recipe.servings),
        'category': recipe.category.storageKey,
        'fasting': recipe.fasting.storageKey,
        'flags': usage?['flags'] ?? 0,
        'open_count': usage?['open_count'] ?? 0,
        'change_count': usage?['change_count'] ?? 0,
        'last_open_day': usage?['last_open_day'] ?? 0,
        'last_change_day': usage?['last_change_day'] ?? 0,
      });
      _addNodeTree(batch, recipe.id, recipe.buildSteps());
    }
    await batch.commit(noResult: true);
  }
}
