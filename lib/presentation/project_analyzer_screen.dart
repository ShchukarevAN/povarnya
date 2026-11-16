import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../app_theme.dart';

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

class ProjectSnapshot {
  const ProjectSnapshot({
    required this.functions,
    required this.modules,
    required this.recipes,
    required this.databaseBytes,
  });

  final List<SourceFunction> functions;
  final List<ModuleStatistic> modules;
  final List<RecipeStructure> recipes;
  final int databaseBytes;
}

class ProjectAnalyzerService {
  const ProjectAnalyzerService(this.root);
  final String root;

  Future<ProjectSnapshot> scanProject() async {
    final functions = await _scanFunctions();
    final database = await _scanDatabase();
    return ProjectSnapshot(
      functions: functions,
      modules: database.$1,
      recipes: database.$2,
      databaseBytes: database.$3,
    );
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
      length: 3,
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
  int _readTraceLines = 0;

  String get _program =>
      '${widget.root}/build/linux/x64/release/bundle/povarnya';
  String get _trace => '${widget.root}/database/analyzer_frame_trace.jsonl';

  Future<void> _start() async {
    if (_process != null) return;
    final executable = File(_program);
    if (!await executable.exists()) return;
    await File(_trace).writeAsString('');
    _frames.clear();
    _readTraceLines = 0;
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
    final lines = await trace.readAsLines();
    if (lines.length <= _readTraceLines) return;
    for (final line in lines.skip(_readTraceLines)) {
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
    _readTraceLines = lines.length;
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
