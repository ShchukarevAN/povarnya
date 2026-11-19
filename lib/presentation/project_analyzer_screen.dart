import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../app_theme.dart';
import '../domain/catalog.dart';
import '../domain/recipe_node.dart';

class SourceFunction {
  const SourceFunction({
    required this.file,
    required this.name,
    required this.startLine,
    required this.endLine,
    required this.source,
    required this.variables,
  });

  final String file;
  final String name;
  final int startLine;
  final int endLine;
  final String source;
  final List<SourceVariable> variables;
  int get lines => endLine - startLine + 1;
}

class SourceVariable {
  const SourceVariable({
    required this.name,
    required this.type,
    required this.line,
  });
  final String name;
  final String type;
  final int line;
}

class ModuleStatistic {
  const ModuleStatistic({
    required this.id,
    required this.occurrences,
    required this.estimatedBytes,
    required this.type,
  });

  final String id;
  final int occurrences;
  final int estimatedBytes;
  final String type;
}

class RecipeStructure {
  const RecipeStructure({
    required this.id,
    required this.title,
    required this.rootNodes,
  });

  final String id;
  final String title;
  final List<RecipeStructureNode> rootNodes;
}

class RecipeStructureNode {
  RecipeStructureNode({
    required this.id,
    required this.parentId,
    required this.cardId,
    required this.sortOrder,
    required this.value,
    required this.text,
  });

  final String id;
  final String? parentId;
  final String cardId;
  final int sortOrder;
  final int? value;
  final String? text;
  final children = <RecipeStructureNode>[];
}

class ProjectAudit {
  const ProjectAudit({
    required this.title,
    required this.passed,
    required this.details,
  });

  final String title;
  final bool passed;
  final String details;
}

class ProjectSnapshot {
  const ProjectSnapshot({
    required this.functions,
    required this.modules,
    required this.recipes,
    required this.databaseBytes,
    required this.audits,
  });

  final List<SourceFunction> functions;
  final List<ModuleStatistic> modules;
  final List<RecipeStructure> recipes;
  final int databaseBytes;
  final List<ProjectAudit> audits;
}

class ProjectAnalyzerService {
  const ProjectAnalyzerService(this.root);
  final String root;

  Future<ProjectSnapshot> scanProject() async {
    final functions = await _scanFunctions();
    final database = await _scanDatabase();
    final audits = await _scanAudits();
    return ProjectSnapshot(
      functions: functions,
      modules: database.$1,
      recipes: database.$2,
      databaseBytes: database.$3,
      audits: audits,
    );
  }

  Future<List<ProjectAudit>> _scanAudits() async => [
    _auditRecipeIngredients(),
    await _auditFastingReset(),
    await _auditSearchCalculation(),
    await _auditModuleFiltering(),
    await _auditApplicationVersion(),
    await _auditCatalogWithoutStartupMigrations(),
    await _auditAnalyzerScope(),
    await _auditProfilerIsolation(),
    await _auditSingleRecipeRenderer(),
    await _auditRecipeNodePersistence(),
    await _auditExternalFlutterSdk(),
    await _auditSplashAnimationIsolation(),
  ];

  ProjectAudit _auditRecipeIngredients() {
    final mismatches = <String>[];
    for (final recipe in catalogRecipes) {
      final fromTree = <String>{};

      void visit(RecipeNode node) {
        if (node.card.kind == CardKind.ingredient) {
          fromTree.add(node.card.nominative);
        }
        for (final child in node.children) {
          visit(child);
        }
      }

      for (final step in recipe.buildSteps()) {
        visit(step);
      }
      if (fromTree.length != recipe.ingredients.length ||
          !fromTree.containsAll(recipe.ingredients)) {
        mismatches.add(recipe.id);
      }
    }
    return ProjectAudit(
      title: 'Единый состав рецептов',
      passed: mismatches.isEmpty,
      details: mismatches.isEmpty
          ? 'Все ${catalogRecipes.length} рецептов получают состав из модульного дерева без расхождений.'
          : 'Состав расходится с деревом: ${mismatches.join(', ')}',
    );
  }

  Future<ProjectAudit> _auditFastingReset() async {
    final source = await File('$root/lib/data/recipe_database.dart')
        .readAsString();
    final body = _block(source, 'Future<void> resetLocalData()');
    final passed = body?.contains('_recipeFasting.clear()') ?? false;
    return ProjectAudit(
      title: 'Полный сброс кэша рецептов',
      passed: passed,
      details: passed
          ? 'resetLocalData очищает кэш постности вместе с остальными данными.'
          : 'В resetLocalData отсутствует _recipeFasting.clear().',
    );
  }

  Future<ProjectAudit> _auditSearchCalculation() async {
    final source = await File(
      '$root/lib/presentation/recipe_search_screen.dart',
    ).readAsString();
    final state = _block(source, 'class _RecipeSearchScreenState');
    final build = state == null
        ? null
        : _block(state, 'Widget build(BuildContext context)');
    final categories = state == null
        ? null
        : _block(state, 'List<Widget> _categorySections');
    final resultReads = build == null
        ? 0
        : RegExp(r'\b_results\b').allMatches(build).length;
    final passed =
        resultReads == 1 && !(categories?.contains('_results') ?? true);
    return ProjectAudit(
      title: 'Однократный расчёт поиска',
      passed: passed,
      details: passed
          ? 'Результаты вычисляются один раз за build и передаются в группировку категорий.'
          : 'Ожидалось одно чтение _results в build и ни одного внутри _categorySections; найдено $resultReads.',
    );
  }

  Future<ProjectAudit> _auditModuleFiltering() async {
    final source = await File('$root/lib/presentation/recipe_screen.dart')
        .readAsString();
    final state = _block(source, 'class _CardLibraryState');
    final matching = state == null
        ? null
        : _block(state, 'List<CardDefinition> _matching');
    final catalogScans = state == null
        ? 0
        : RegExp(r'\bCatalogCards\.all\b').allMatches(state).length;
    final passed =
        state != null &&
        state.contains('static final _cardsByKind') &&
        catalogScans == 1 &&
        !(matching?.contains('searchAndSortByLabel') ?? true);
    return ProjectAudit(
      title: 'Кэшированная фильтрация модулей',
      passed: passed,
      details: passed
          ? 'Каталог группируется и сортируется один раз; ввод выполняет только линейную фильтрацию.'
          : 'Библиотека модулей снова сканирует или сортирует CatalogCards.all во время build.',
    );
  }

  Future<ProjectAudit> _auditApplicationVersion() async {
    final lib = Directory('$root/lib');
    final declarations = <String>[];
    var hasAlias = false;
    await for (final item in lib.list(recursive: true)) {
      if (item is! File || !item.path.endsWith('.dart')) continue;
      final source = await item.readAsString();
      if (RegExp(
        r'\b(?:final(?:\s+Future<String>)?|const|String)\s+appVersionLabel\b',
      ).hasMatch(source)) {
        hasAlias = true;
      }
      for (final _ in RegExp(
        r'\b(?:final(?:\s+Future<String>)?|const|String)\s+appVersion\b',
      ).allMatches(source)) {
        declarations.add(item.path.substring(root.length + 1));
      }
    }
    final versionSource = File('$root/lib/app_version.dart');
    final versionText = await versionSource.exists()
        ? await versionSource.readAsString()
        : '';
    final readme = File('$root/README.md');
    final readmeText = await readme.exists() ? await readme.readAsString() : '';
    final passed =
        declarations.length == 1 &&
        declarations.single == 'lib/app_version.dart' &&
        versionText.contains('PackageInfo.fromPlatform()') &&
        !hasAlias &&
        !readmeText.contains('Текущая версия:');
    return ProjectAudit(
      title: 'Единый источник версии приложения',
      passed: passed,
      details: passed
          ? 'Версия читается из сборочных метаданных одной переменной appVersion; алиасов и копии в README нет.'
          : 'Найдены лишние объявления версии, appVersionLabel или вручную записанная текущая версия.',
    );
  }

  Future<ProjectAudit> _auditCatalogWithoutStartupMigrations() async {
    final databaseSource = await File('$root/lib/data/recipe_database.dart')
        .readAsString();
    const obsoleteMigrations = [
      '_normalizeMulticookerSteps',
      '_setExistingEggCategories',
      '_completeRequiredCookingTimes',
    ];
    final presentMigrations = obsoleteMigrations
        .where(databaseSource.contains)
        .toList();
    final missingEggCategories = <String>[];
    final legacyMulticookerSteps = <String>[];
    final times = <String, (int, int?)>{};

    bool containsCard(RecipeNode node, String cardId) {
      if (node.card.id == cardId) return true;
      return node.children.any((child) => containsCard(child, cardId));
    }

    void visit(RecipeNode node) {
      if (node.card.id == 'ingredient.eggs' &&
          (node.text == null || node.text!.trim().isEmpty)) {
        missingEggCategories.add(node.id);
      }
      if (node.card.id == 'action.select' &&
          containsCard(node, 'utensil.multicooker-program')) {
        legacyMulticookerSteps.add(node.id);
      }
      final time = node.children
          .where((child) => child.card.id == 'quantity.time')
          .firstOrNull;
      if (time?.value != null) times[node.id] = (time!.value!, time.upperValue);
      for (final child in node.children) {
        visit(child);
      }
    }

    for (final recipe in catalogRecipes) {
      for (final step in recipe.buildSteps()) {
        visit(step);
      }
    }
    const requiredTimes = <String, (int, int?)>{
      'cocoa-4': (1, null),
      'squash-caviar-3': (5, null),
      'squash-caviar-4': (5, null),
      'squash-caviar-5': (5, null),
      'soviet-goulash-2': (3, null),
      'soviet-goulash-4': (2, null),
      'soviet-goulash-8': (5, 7),
      'soviet-goulash-10': (5, null),
      'soviet-goulash-14': (5, null),
    };
    final incorrectTimes = requiredTimes.entries
        .where((entry) => times[entry.key] != entry.value)
        .map((entry) => entry.key)
        .toList();
    final passed =
        presentMigrations.isEmpty &&
        missingEggCategories.isEmpty &&
        legacyMulticookerSteps.isEmpty &&
        incorrectTimes.isEmpty;
    final problems = <String>[
      if (presentMigrations.isNotEmpty)
        'остались миграции: ${presentMigrations.join(', ')}',
      if (missingEggCategories.isNotEmpty)
        'яйца без категории: ${missingEggCategories.join(', ')}',
      if (legacyMulticookerSteps.isNotEmpty)
        'старые шаги мультиварки: ${legacyMulticookerSteps.join(', ')}',
      if (incorrectTimes.isNotEmpty)
        'нет исходных интервалов: ${incorrectTimes.join(', ')}',
    ];
    return ProjectAudit(
      title: 'Самодостаточный каталог без стартовых миграций',
      passed: passed,
      details: passed
          ? 'Категории яиц, интервалы времени и актуальные шаги мультиварки заданы в исходном каталоге; миграций при запуске нет.'
          : problems.join('; '),
    );
  }

  Future<ProjectAudit> _auditAnalyzerScope() async {
    final options = await File('$root/analysis_options.yaml').readAsString();
    const requiredExclusions = ['.dart_tool/**', 'Инструментарий/**'];
    final missing = requiredExclusions
        .where((path) => !options.contains('- $path'))
        .toList();
    return ProjectAudit(
      title: 'Границы статического анализа',
      passed: missing.isEmpty,
      details: missing.isEmpty
          ? 'Кэши, проектный инструментарий и сторонний код исключены из анализа проекта.'
          : 'Не исключены служебные каталоги: ${missing.join(', ')}',
    );
  }

  Future<ProjectAudit> _auditProfilerIsolation() async {
    final writer = await File('$root/lib/performance_trace.dart')
        .readAsString();
    final analyzer = await File(
      '$root/lib/presentation/project_analyzer_screen.dart',
    ).readAsString();
    final recordFrames = _block(writer, 'void _recordFrames');
    final runtime = _block(
      analyzer,
      'class _Runtime'
      'TabState',
    );
    final readTrace = runtime == null
        ? null
        : _block(runtime, 'Future<void> _readFrameTrace()');
    final batchedWrites =
        writer.contains('Timer.periodic(') &&
        writer.contains('_pendingFrames') &&
        writer.contains('void _flushPendingFrames()') &&
        !(recordFrames?.contains('writeAsString') ?? true);
    final incrementalReads =
        analyzer.contains('_traceReadOffset') &&
        (readTrace?.contains('openRead(_traceReadOffset') ?? false) &&
        !(readTrace?.contains('readAsLines') ?? true);
    final passed = batchedWrites && incrementalReads;
    return ProjectAudit(
      title: 'Профилировщик не искажает измерения',
      passed: passed,
      details: passed
          ? 'Кадры накапливаются в памяти и записываются пакетами; анализатор читает только новые байты трассы.'
          : 'Трассировка снова выполняет файловую запись на каждый кадр или перечитывает файл целиком.',
    );
  }

  Future<ProjectAudit> _auditSingleRecipeRenderer() async {
    final source = await File('$root/lib/domain/recipe_renderer.dart')
        .readAsString();
    final stringRenderers = RegExp(r'\bString\s+render\s*\(')
        .allMatches(source)
        .length;
    final partRenderers = RegExp(r'\bList<RecipeRenderPart>\s+renderParts\s*\(')
        .allMatches(source)
        .length;
    final passed = stringRenderers == 0 && partRenderers == 1;
    return ProjectAudit(
      title: 'Единый сборщик предложения рецепта',
      passed: passed,
      details: passed
          ? 'Предложение собирает только renderParts; параллельной строковой реализации render нет.'
          : 'Ожидался один renderParts и отсутствие отдельного String render; найдено: $partRenderers и $stringRenderers.',
    );
  }

  Future<ProjectAudit> _auditRecipeNodePersistence() async {
    final source = await File('$root/lib/data/recipe_database.dart')
        .readAsString();
    final nodeInserts = RegExp(r"batch\.insert\('node'")
        .allMatches(source)
        .length;
    final serializerReferences = RegExp(r'\b_addNodeTree\s*\(')
        .allMatches(source)
        .length;
    final passed = nodeInserts == 1 && serializerReferences == 5;
    return ProjectAudit(
      title: 'Единая сериализация дерева RecipeNode',
      passed: passed,
      details: passed
          ? 'Сохранение, первичное заполнение, обновление и добавление рецептов используют один _addNodeTree.'
          : 'Ожидалась одна реализация INSERT node и четыре её вызова; найдено: $nodeInserts и ${serializerReferences - 1}.',
    );
  }

  Future<ProjectAudit> _auditExternalFlutterSdk() async {
    const sdkPath = '/home/smirnovom/Среды разработки/flutter';
    final environmentFile = File('$root/Инструментарий/среда_разработки.sh');
    final environmentSource = await environmentFile.exists()
        ? await environmentFile.readAsString()
        : '';
    final legacySdk = Directory('$root/Инструментарий/flutter');
    final externalSdk = Directory(sdkPath);
    final passed =
        !await legacySdk.exists() &&
        await externalSdk.exists() &&
        environmentSource.contains(sdkPath) &&
        environmentSource.contains('POVARNYA_FLUTTER_ROOT');
    return ProjectAudit(
      title: 'Flutter SDK отделён от проекта',
      passed: passed,
      details: passed
          ? 'SDK находится в «Среды разработки», а единая конфигурация допускает переопределение пути.'
          : 'Flutter SDK отсутствует по внешнему пути, остался внутри проекта или не задан в общей конфигурации.',
    );
  }

  Future<ProjectAudit> _auditSplashAnimationIsolation() async {
    final pubspec = await File('$root/pubspec.yaml').readAsString();
    final loadingWidget = await File('$root/lib/startup_loading_video.dart')
        .readAsString();
    final localPackage = Directory('$root/third_party/media_kit_video');
    final mediaKitDependency = RegExp(
      r'^\s{2}media_kit(?:_video|_libs_video)?:',
      multiLine: true,
    ).hasMatch(pubspec);
    final animation = File('$root/assets/animations/Загрузочный экран.webp');
    final passed =
        !mediaKitDependency &&
        !await localPackage.exists() &&
        await animation.exists() &&
        loadingWidget.contains('Image.asset(') &&
        !loadingWidget.contains('VideoController');
    return ProjectAudit(
      title: 'Заставка без нативного видеоплагина',
      passed: passed,
      details: passed
          ? 'Анимация рисуется Flutter из WebP; media_kit и локальный форк не используются.'
          : 'Обнаружен media_kit, локальный форк, отсутствует WebP или заставка снова зависит от видеоплагина.',
    );
  }

  String? _block(String source, String marker) {
    final markerIndex = source.indexOf(marker);
    if (markerIndex < 0) return null;
    final start = source.indexOf('{', markerIndex);
    if (start < 0) return null;
    var depth = 0;
    for (var index = start; index < source.length; index++) {
      if (source[index] == '{') depth++;
      if (source[index] == '}') depth--;
      if (depth == 0) return source.substring(markerIndex, index + 1);
    }
    return null;
  }

  Future<List<SourceFunction>> _scanFunctions() async {
    final lib = Directory('$root/lib');
    final files = <File>[];
    await for (final item in lib.list(recursive: true)) {
      if (item is File && item.path.endsWith('.dart')) files.add(item);
    }
    final result = <SourceFunction>[];
    final signature = RegExp(
      r'^\s*(?:[A-Za-z_<>?, ]+\s+)?([A-Za-z_]\w*)\s*\([^;]*\)\s*(?:async\s*)?(\{|=>)',
    );
    for (final file in files) {
      final lines = await file.readAsLines();
      for (var index = 0; index < lines.length; index++) {
        final match = signature.firstMatch(lines[index]);
        if (match == null) continue;
        if (match.group(2) == '=>') {
          result.add(
            SourceFunction(
              file: file.path.substring(root.length + 1),
              name: match.group(1)!,
              startLine: index + 1,
              endLine: index + 1,
              source: lines[index],
              variables: _extractVariableDeclarations(lines[index], index + 1),
            ),
          );
          continue;
        }
        var depth = 0;
        var end = index;
        for (; end < lines.length; end++) {
          depth += '{'.allMatches(lines[end]).length;
          depth -= '}'.allMatches(lines[end]).length;
          if (depth == 0) break;
        }
        if (end >= lines.length) continue;
        result.add(
          SourceFunction(
            file: file.path.substring(root.length + 1),
            name: match.group(1)!,
            startLine: index + 1,
            endLine: end + 1,
            source: lines.sublist(index, end + 1).join('\n'),
            variables: _extractVariableDeclarations(
              lines.sublist(index, end + 1).join('\n'),
              index + 1,
            ),
          ),
        );
        index = end;
      }
    }
    result.sort((a, b) => b.lines.compareTo(a.lines));
    return result;
  }

  List<SourceVariable> _extractVariableDeclarations(
    String source,
    int firstLine,
  ) {
    final declaration = RegExp(
      r'\b(final|var|const|int|double|bool|String|Widget|Color|List<[^>]+>|Map<[^>]+>)\s+(\w+)',
    );
    final seen = <String>{};
    return declaration
        .allMatches(source)
        .where((match) => seen.add(match.group(2)!))
        .map(
          (match) => SourceVariable(
            name: match.group(2)!,
            type: match.group(1)!,
            line:
                firstLine +
                '\n'.allMatches(source.substring(0, match.start)).length,
          ),
        )
        .toList();
  }

  Future<(List<ModuleStatistic>, List<RecipeStructure>, int)>
  _scanDatabase() async {
    final file = File('$root/database/recipes.db');
    if (!await file.exists())
      return (<ModuleStatistic>[], <RecipeStructure>[], 0);
    sqfliteFfiInit();
    final factory = databaseFactoryFfi;
    final database = await factory.openDatabase(
      file.path,
      options: OpenDatabaseOptions(readOnly: true),
    );
    try {
      final size = await database.rawQuery('PRAGMA page_count');
      final pageSize = await database.rawQuery('PRAGMA page_size');
      final databaseBytes =
          (size.first.values.first as int) *
          (pageSize.first.values.first as int);
      final moduleRows = await database.rawQuery(
        'SELECT node.card_id, card.kind, COUNT(*) AS occurrences, '
        'SUM(LENGTH(node.id) + LENGTH(node.root_id) + LENGTH(node.card_id) + '
        "COALESCE(LENGTH(node.parent_id), 0) + COALESCE(LENGTH(node.join_text), 0) + COALESCE(LENGTH(node.text_value), 0) + 24) AS estimated_bytes "
        'FROM node JOIN card ON card.id = node.card_id GROUP BY node.card_id, card.kind ORDER BY occurrences DESC, node.card_id',
      );
      final modules = moduleRows
          .map(
            (row) => ModuleStatistic(
              id: row['card_id'] as String,
              occurrences: row['occurrences'] as int,
              estimatedBytes: row['estimated_bytes'] as int? ?? 0,
              type: _cardType(row['kind'] as int),
            ),
          )
          .toList();
      final roots = await database.query(
        'document_root',
        columns: ['id', 'title'],
        orderBy: 'title COLLATE NOCASE',
      );
      final recipes = <RecipeStructure>[];
      for (final rootRow in roots) {
        final id = rootRow['id'] as String;
        final rows = await database.query(
          'node',
          where: 'root_id = ?',
          whereArgs: [id],
          orderBy: 'sort_order',
        );
        final byId = <String, RecipeStructureNode>{};
        for (final row in rows) {
          final node = RecipeStructureNode(
            id: row['id'] as String,
            parentId: row['parent_id'] as String?,
            cardId: row['card_id'] as String,
            sortOrder: row['sort_order'] as int,
            value: row['value'] as int?,
            text: row['text_value'] as String?,
          );
          byId[node.id] = node;
        }
        final top = <RecipeStructureNode>[];
        for (final node in byId.values) {
          if (node.parentId == null) {
            top.add(node);
          } else {
            byId[node.parentId]?.children.add(node);
          }
        }
        recipes.add(
          RecipeStructure(
            id: id,
            title: rootRow['title'] as String,
            rootNodes: top,
          ),
        );
      }
      return (modules, recipes, databaseBytes);
    } finally {
      await database.close();
    }
  }

  String _cardType(int kind) => switch (kind) {
    0 => 'Действие',
    1 => 'Ингредиент',
    2 => 'Количество',
    3 => 'Утварь',
    4 => 'Текст',
    _ => 'Неизвестно',
  };
}

class ProjectAnalyzerScreen extends StatefulWidget {
  const ProjectAnalyzerScreen({super.key});

  @override
  State<ProjectAnalyzerScreen> createState() => _ProjectAnalyzerScreenState();
}

class _ProjectAnalyzerScreenState extends State<ProjectAnalyzerScreen> {
  late final String _projectRoot;
  late Future<ProjectSnapshot> _snapshot;

  @override
  void initState() {
    super.initState();
    _projectRoot =
        Platform.environment['POVARNYA_PROJECT_ROOT'] ?? Directory.current.path;
    _snapshot = ProjectAnalyzerService(_projectRoot).scanProject();
  }

  void _refresh() => setState(
    () => _snapshot = ProjectAnalyzerService(_projectRoot).scanProject(),
  );

  @override
  Widget build(BuildContext context) => SelectionArea(
    child: DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Анализатор проекта «Поварня»'),
          actions: [
            IconButton(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
              tooltip: 'Обновить',
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Код'),
              Tab(text: 'Проверки'),
              Tab(text: 'База данных'),
              Tab(text: 'Производительность'),
            ],
          ),
        ),
        body: FutureBuilder<ProjectSnapshot>(
          future: _snapshot,
          builder: (context, snapshot) {
            if (snapshot.hasError)
              return Center(child: Text('Ошибка анализа: ${snapshot.error}'));
            if (!snapshot.hasData)
              return const Center(child: CircularProgressIndicator());
            final data = snapshot.data!;
            return TabBarView(
              children: [
                _CodeTab(functions: data.functions),
                _AuditTab(audits: data.audits),
                _DatabaseTab(snapshot: data),
                _RuntimeTab(root: _projectRoot),
              ],
            );
          },
        ),
      ),
    ),
  );
}

class _AuditTab extends StatelessWidget {
  const _AuditTab({required this.audits});
  final List<ProjectAudit> audits;

  @override
  Widget build(BuildContext context) {
    final passed = audits.where((audit) => audit.passed).length;
    final colors = Theme.of(context).colorScheme;
    final semantic = semanticColors(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Пройдено $passed из ${audits.length} целевых проверок',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        for (final audit in audits)
          Card(
            child: ListTile(
              leading: Icon(
                audit.passed ? Icons.check_circle : Icons.error,
                color: audit.passed ? semantic.success : colors.error,
              ),
              title: Text(audit.title),
              subtitle: Text(audit.details),
            ),
          ),
      ],
    );
  }
}

enum _SortField { name, size, occurrences }

class _CodeTab extends StatefulWidget {
  const _CodeTab({required this.functions});
  final List<SourceFunction> functions;

  @override
  State<_CodeTab> createState() => _CodeTabState();
}

class _CodeTabState extends State<_CodeTab> {
  _SortField _field = _SortField.size;
  bool _ascending = false;

  void _sortBy(_SortField field) => setState(() {
    _ascending = field == _field ? !_ascending : field == _SortField.name;
    _field = field;
  });

  @override
  Widget build(BuildContext context) {
    final functions = [...widget.functions]
      ..sort((left, right) {
        final comparison = _field == _SortField.name
            ? left.name.compareTo(right.name)
            : left.lines.compareTo(right.lines);
        return _ascending ? comparison : -comparison;
      });
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Функции: ${functions.length}. Нажмите строку, чтобы открыть исходный код.',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            TextButton.icon(
              onPressed: () => _sortBy(_SortField.name),
              icon: Icon(
                _field == _SortField.name
                    ? (_ascending ? Icons.arrow_upward : Icons.arrow_downward)
                    : Icons.sort_by_alpha,
              ),
              label: const Text('Название'),
            ),
            TextButton.icon(
              onPressed: () => _sortBy(_SortField.size),
              icon: Icon(
                _field == _SortField.size
                    ? (_ascending ? Icons.arrow_upward : Icons.arrow_downward)
                    : Icons.format_list_numbered,
              ),
              label: const Text('Строки'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (final function in functions)
          Card(
            child: ListTile(
              title: Text(function.name),
              subtitle: Text(
                '${function.file}:${function.startLine}–${function.endLine}',
              ),
              trailing: Text('${function.lines} строк'),
              onTap: () => showDialog<void>(
                context: context,
                builder: (_) => _FunctionDialog(function: function),
              ),
            ),
          ),
      ],
    );
  }
}

class _FunctionDialog extends StatefulWidget {
  const _FunctionDialog({required this.function});
  final SourceFunction function;
  @override
  State<_FunctionDialog> createState() => _FunctionDialogState();
}

class _FunctionDialogState extends State<_FunctionDialog> {
  bool _byType = false;
  @override
  Widget build(BuildContext context) {
    final variables = [...widget.function.variables]
      ..sort(
        (a, b) => _byType ? a.type.compareTo(b.type) : a.name.compareTo(b.name),
      );
    return SelectionArea(
      child: AlertDialog(
        title: Text('${widget.function.name} — ${widget.function.lines} строк'),
        content: SizedBox(
          width: 1050,
          height: 620,
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: SingleChildScrollView(
                  child: _HighlightedCode(
                    source: widget.function.source,
                    variables: widget.function.variables,
                  ),
                ),
              ),
              const VerticalDivider(),
              SizedBox(
                width: 260,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('Переменные'),
                        IconButton(
                          onPressed: () => setState(() => _byType = !_byType),
                          icon: Icon(
                            _byType ? Icons.sort_by_alpha : Icons.category,
                          ),
                          tooltip: _byType
                              ? 'Сортировать по названию'
                              : 'Сортировать по типу',
                        ),
                      ],
                    ),
                    Expanded(
                      child: ListView(
                        children: [
                          for (final variable in variables)
                            ListTile(
                              dense: true,
                              title: Text(variable.name),
                              subtitle: Text(
                                '${variable.type} · строка ${variable.line}',
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HighlightedCode extends StatelessWidget {
  const _HighlightedCode({required this.source, required this.variables});
  final String source;
  final List<SourceVariable> variables;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final semantic = semanticColors(context);
    final lookup = {for (final value in variables) value.name: value};
    final token = RegExp(
      r'''(//[^\n]*|"[^"]*"|'[^']*'|\b(?:class|return|final|var|const|if|else|for|while|async|await|void|int|double|bool|String)\b|\b\w+\b)''',
    );
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final match in token.allMatches(source)) {
      if (match.start > cursor)
        spans.add(TextSpan(text: source.substring(cursor, match.start)));
      final text = match.group(0)!;
      final variable = lookup[text];
      final color = text.startsWith('//')
          ? semantic.success
          : (text.startsWith('\"') || text.startsWith("'"))
          ? semantic.warning
          : RegExp(
              r'^(class|return|final|var|const|if|else|for|while|async|await|void|int|double|bool|String)$',
            ).hasMatch(text)
          ? colors.tertiary
          : colors.primary;
      spans.add(
        variable == null
            ? TextSpan(
                text: text,
                style: TextStyle(color: color),
              )
            : WidgetSpan(
                child: Tooltip(
                  message:
                      'Тип: ${variable.type}\nВпервые задана: строка ${variable.line}',
                  child: Text(
                    text,
                    style: TextStyle(
                      color: colors.secondary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
      );
      cursor = match.end;
    }
    if (cursor < source.length)
      spans.add(TextSpan(text: source.substring(cursor)));
    return SelectableText.rich(
      TextSpan(
        style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
        children: spans,
      ),
    );
  }
}

class _DatabaseTab extends StatefulWidget {
  const _DatabaseTab({required this.snapshot});
  final ProjectSnapshot snapshot;

  @override
  State<_DatabaseTab> createState() => _DatabaseTabState();
}

class _DatabaseTabState extends State<_DatabaseTab> {
  _SortField _field = _SortField.size;
  bool _ascending = false;

  void _sortBy(_SortField field) => setState(() {
    _ascending = field == _field ? !_ascending : field == _SortField.name;
    _field = field;
  });

  String _bytes(int value) =>
      value < 1024 ? '$value Б' : '${(value / 1024).toStringAsFixed(1)} КиБ';

  @override
  Widget build(BuildContext context) {
    final modules = [...widget.snapshot.modules]
      ..sort((left, right) {
        final comparison = _field == _SortField.name
            ? left.id.compareTo(right.id)
            : _field == _SortField.occurrences
            ? left.occurrences.compareTo(right.occurrences)
            : left.estimatedBytes.compareTo(right.estimatedBytes);
        return _ascending ? comparison : -comparison;
      });
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'SQLite: ${_bytes(widget.snapshot.databaseBytes)} · рецептов: ${widget.snapshot.recipes.length}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Text(
                'Модули',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            TextButton.icon(
              onPressed: () => _sortBy(_SortField.name),
              icon: Icon(
                _field == _SortField.name
                    ? (_ascending ? Icons.arrow_upward : Icons.arrow_downward)
                    : Icons.sort_by_alpha,
              ),
              label: const Text('Название'),
            ),
            TextButton.icon(
              onPressed: () => _sortBy(_SortField.size),
              icon: Icon(
                _field == _SortField.size
                    ? (_ascending ? Icons.arrow_upward : Icons.arrow_downward)
                    : Icons.storage,
              ),
              label: const Text('Объём'),
            ),
            TextButton.icon(
              onPressed: () => _sortBy(_SortField.occurrences),
              icon: Icon(
                _field == _SortField.occurrences
                    ? (_ascending ? Icons.arrow_upward : Icons.arrow_downward)
                    : Icons.repeat,
              ),
              label: const Text('Включения'),
            ),
          ],
        ),
        for (final module in modules)
          ListTile(
            title: Text(module.id),
            subtitle: Text('Тип: ${module.type}'),
            trailing: Text(
              '${module.occurrences} включений · ${_bytes(module.estimatedBytes)} данных',
            ),
          ),
        const Divider(height: 32),
        Text('Рецепты', style: Theme.of(context).textTheme.titleLarge),
        for (final recipe in widget.snapshot.recipes)
          Card(
            child: ListTile(
              title: Text(recipe.title),
              subtitle: Text(recipe.id),
              onTap: () => showDialog<void>(
                context: context,
                builder: (_) => SelectionArea(
                  child: AlertDialog(
                    title: Text(recipe.title),
                    content: SizedBox(
                      width: 700,
                      child: SingleChildScrollView(
                        child: _RecipeTree(nodes: recipe.rootNodes),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _RecipeTree extends StatelessWidget {
  const _RecipeTree({required this.nodes, this.depth = 0});
  final List<RecipeStructureNode> nodes;
  final int depth;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final node in nodes) ...[
        Padding(
          padding: EdgeInsets.only(left: depth * 20.0, top: 3),
          child: Text(
            '${node.cardId}${node.value == null ? '' : ': ${node.value}'}${node.text == null || node.text!.isEmpty ? '' : ' — ${node.text}'}',
          ),
        ),
        if (node.children.isNotEmpty)
          _RecipeTree(nodes: node.children, depth: depth + 1),
      ],
    ],
  );
}

class _RuntimeTab extends StatefulWidget {
  const _RuntimeTab({required this.root});
  final String root;

  @override
  State<_RuntimeTab> createState() => _RuntimeTabState();
}

class _RuntimeTabState extends State<_RuntimeTab> {
  Process? _process;
  Timer? _timer;
  int _memoryBytes = 0;
  int _cpuTicks = 0;
  final _frames = <_FrameSample>[];
  int _traceReadOffset = 0;
  String _traceRemainder = '';

  String get _program =>
      '${widget.root}/build/linux/x64/release/bundle/povarnya';
  String get _trace => '${widget.root}/database/analyzer_frame_trace.jsonl';

  Future<void> _start() async {
    if (_process != null) return;
    final executable = File(_program);
    if (!await executable.exists()) return;
    await File(_trace).writeAsString('');
    _frames.clear();
    _traceReadOffset = 0;
    _traceRemainder = '';
    final process = await Process.start(
      executable.path,
      [],
      environment: {
        ...Platform.environment,
        'POVARNYA_DATA_DIR': '${widget.root}/database',
        'POVARNYA_PERF_TRACE_PATH': _trace,
      },
    );
    process.exitCode.whenComplete(() {
      if (mounted) setState(() => _stop());
    });
    setState(() => _process = process);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _sample());
    await _sample();
  }

  Future<void> _sample() async {
    final process = _process;
    if (process == null) return;
    final stat = File('/proc/${process.pid}/stat');
    final status = File('/proc/${process.pid}/status');
    if (!await stat.exists() || !await status.exists()) {
      _stop();
      return;
    }
    final values = (await stat.readAsString()).split(' ');
    final rss = RegExp(r'VmRSS:\s+(\d+) kB')
        .firstMatch(await status.readAsString());
    if (!mounted) return;
    setState(() {
      _cpuTicks = int.parse(values[13]) + int.parse(values[14]);
      _memoryBytes = (int.tryParse(rss?.group(1) ?? '') ?? 0) * 1024;
    });
    await _readFrameTrace();
  }

  Future<void> _readFrameTrace() async {
    final trace = File(_trace);
    if (!await trace.exists()) return;
    final length = await trace.length();
    if (length < _traceReadOffset) {
      _traceReadOffset = 0;
      _traceRemainder = '';
    }
    if (length == _traceReadOffset) return;
    final addition = await trace
        .openRead(_traceReadOffset, length)
        .transform(utf8.decoder)
        .join();
    _traceReadOffset = length;
    final content = '$_traceRemainder$addition';
    final lines = content.split('\n');
    _traceRemainder = content.endsWith('\n') ? '' : lines.removeLast();
    if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
    for (final line in lines) {
      try {
        final values = jsonDecode(line) as Map<String, dynamic>;
        _frames.add(
          _FrameSample(
            timestamp: values['timestamp'] as int,
            buildMs: (values['buildUs'] as int) / 1000,
            rasterMs: (values['rasterUs'] as int) / 1000,
          ),
        );
      } on FormatException {
        // Последняя строка может читаться одновременно с записью кадра.
      }
    }
    if (_frames.length > 90) _frames.removeRange(0, _frames.length - 90);
    if (mounted) setState(() {});
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    _process?.kill();
    _process = null;
    _memoryBytes = 0;
    _cpuTicks = 0;
    _frames.clear();
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Наблюдение за готовой программой',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        const Text(
          'Запускает release-бинарник отдельным процессом. График получает реальные длительности действий Flutter: построение интерфейса и растеризацию каждого кадра.',
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _process == null ? _start : _stop,
          icon: Icon(_process == null ? Icons.play_arrow : Icons.stop),
          label: Text(
            _process == null
                ? 'Запустить программу для наблюдения'
                : 'Остановить программу',
          ),
        ),
        const SizedBox(height: 24),
        Text(
          _process == null
              ? 'Программа не запущена.'
              : 'PID: ${_process!.pid}\nПамять: ${(_memoryBytes / 1024 / 1024).toStringAsFixed(1)} МиБ\nНакопленное CPU-время: $_cpuTicks тиков',
        ),
        const SizedBox(height: 24),
        Text(
          'Время действий кадра',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        SizedBox(height: 220, child: _FrameChart(frames: List.of(_frames))),
        const Text(
          'Бирюзовый — построение интерфейса; оранжевый — растеризация. Показаны последние 90 кадров, шкала — миллисекунды.',
        ),
      ],
    ),
  );
}

class _FrameSample {
  const _FrameSample({
    required this.timestamp,
    required this.buildMs,
    required this.rasterMs,
  });
  final int timestamp;
  final double buildMs;
  final double rasterMs;
}

class _FrameChart extends StatelessWidget {
  const _FrameChart({required this.frames});
  final List<_FrameSample> frames;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _FrameChartPainter(frames, Theme.of(context).colorScheme),
    child: Center(
      child: frames.isEmpty
          ? const Text('После запуска программы здесь появятся кадры.')
          : null,
    ),
  );
}

class _FrameChartPainter extends CustomPainter {
  _FrameChartPainter(this.frames, this.colors);
  final List<_FrameSample> frames;
  final ColorScheme colors;

  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()..color = colors.surfaceContainerHighest;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(12)),
      background,
    );
    if (frames.isEmpty) return;
    final maximum = frames
        .map((frame) => frame.buildMs + frame.rasterMs)
        .reduce((a, b) => a > b ? a : b)
        .clamp(16, 100)
        .toDouble();
    final width = size.width / (frames.length - 1).clamp(1, 90);
    final build = Paint()
      ..color = colors.primary
      ..strokeWidth = 2;
    final raster = Paint()
      ..color = colors.error
      ..strokeWidth = 2;
    for (var index = 1; index < frames.length; index++) {
      final before = frames[index - 1];
      final current = frames[index];
      double y(double value) =>
          size.height - 12 - value / maximum * (size.height - 24);
      canvas.drawLine(
        Offset((index - 1) * width, y(before.buildMs)),
        Offset(index * width, y(current.buildMs)),
        build,
      );
      canvas.drawLine(
        Offset((index - 1) * width, y(before.buildMs + before.rasterMs)),
        Offset(index * width, y(current.buildMs + current.rasterMs)),
        raster,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _FrameChartPainter oldDelegate) => true;
}
