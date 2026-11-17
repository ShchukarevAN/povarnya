import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_info.dart';
import '../app_theme.dart';
import '../data/app_settings.dart';
import '../data/recipe_database.dart';
import '../domain/catalog.dart';
import '../domain/catalog_search.dart';
import '../domain/recipe_node.dart';
import 'recipe_screen.dart' show moduleIcon;

List<CatalogRecipe> sortRecipesAlphabetically(Iterable<CatalogRecipe> recipes) {
  return searchAndSortByLabel(
    recipes,
    query: '',
    labelOf: (recipe) => recipe.title,
  );
}

/// Координаты видимых частей карточки результата перед её раскрытием.
///
/// Они передаются корневому экрану только на время анимации: сам рецепт не
/// зависит от геометрии списка поиска.
class RecipeSearchEntryGeometry {
  const RecipeSearchEntryGeometry({
    required this.card,
    required this.title,
    required this.ingredients,
    required this.ingredientRects,
  });

  final Rect card;
  final Rect title;
  final Rect ingredients;
  final Map<String, Rect> ingredientRects;
}

/// Единая анимация для панели фильтров и её ручки. Во время drag-перетаскивания
/// длительность равна нулю, чтобы положение совпадало с указателем.
Widget filterPanelSlide({
  required bool isDragging,
  required double right,
  required double width,
  required Widget child,
}) => AnimatedPositioned(
  duration: isDragging ? Duration.zero : const Duration(milliseconds: 260),
  curve: Curves.easeOutCubic,
  top: 0,
  bottom: 0,
  right: right,
  width: width,
  child: child,
);

class RecipeSearchScreen extends StatefulWidget {
  const RecipeSearchScreen({
    super.key,
    required this.onCreateRecipe,
    required this.onOpenRecipe,
    this.onOpenRecipeWithTransition,
    required this.onToggleTheme,
    required this.themeLabel,
  });

  final VoidCallback onCreateRecipe;
  final ValueChanged<CatalogRecipe> onOpenRecipe;
  final void Function(CatalogRecipe, RecipeSearchEntryGeometry)?
  onOpenRecipeWithTransition;
  final VoidCallback onToggleTheme;
  final String themeLabel;

  @override
  State<RecipeSearchScreen> createState() => _RecipeSearchScreenState();
}

class _RecipeSearchScreenState extends State<RecipeSearchScreen> {
  static final _ingredientCardsByName = <String, CardDefinition>{
    for (final card in CatalogCards.all)
      if (card.kind == CardKind.ingredient) card.nominative: card,
  };
  static final _ingredientCards = _ingredientCardsByName.values.toList()
    ..sort((left, right) => left.nominative.compareTo(right.nominative));

  final Set<String> _selectedIngredients = {};
  final Set<String> _excludedIngredients = {};
  String _titleQuery = '';
  String _filterQuery = '';
  late bool _compactFilterIngredients;
  double _filterReveal = 0;
  bool _isFilterDragging = false;
  bool _isEdgeFilterDragging = false;
  double _filterDragStartReveal = 0;
  late bool _randomOrder;
  List<String> _randomRecipeIds = const [];
  Set<String> _favoriteRecipeIds = const {};
  Map<String, RecipeCategory> _recipeCategories = const {};
  Map<String, RecipeFasting> _recipeFasting = const {};
  Map<String, String> _recipeTitles = const {};
  RecipeFasting? _fastingFilter;
  final Set<RecipeCategory> _expandedCategories = {};

  @override
  void initState() {
    super.initState();
    _randomOrder = AppSettings().randomRecipeOrder;
    _compactFilterIngredients = AppSettings().compactFilterIngredients;
    if (_randomOrder) _createRandomRecipeOrder();
    _loadFavoriteRecipes();
    _loadRecipeCategories();
    _loadRecipeFasting();
    _loadRecipeTitles();
  }

  Future<void> _loadRecipeTitles() async {
    final titles = await RecipeDatabase().loadRecipeTitles();
    if (mounted) setState(() => _recipeTitles = titles);
  }

  String _titleOf(CatalogRecipe recipe) =>
      _recipeTitles[recipe.id]?.trim().isNotEmpty == true
      ? _recipeTitles[recipe.id]!.trim()
      : recipe.title;

  Future<void> _loadRecipeCategories() async {
    final categories = await RecipeDatabase().loadRecipeCategories();
    if (mounted) setState(() => _recipeCategories = categories);
  }

  Future<void> _loadRecipeFasting() async {
    final values = await RecipeDatabase().loadRecipeFastingCategories();
    if (mounted) setState(() => _recipeFasting = values);
  }

  Future<void> _loadFavoriteRecipes() async {
    final ids = await RecipeDatabase().favoriteRecipeIds();
    if (mounted) setState(() => _favoriteRecipeIds = ids);
  }

  Future<void> _setRecipeFavorite(CatalogRecipe recipe, bool favorite) async {
    final previous = _favoriteRecipeIds;
    setState(() {
      _favoriteRecipeIds = {..._favoriteRecipeIds};
      if (favorite) {
        _favoriteRecipeIds.add(recipe.id);
      } else {
        _favoriteRecipeIds.remove(recipe.id);
      }
    });
    try {
      await RecipeDatabase().setRecipeFavorite(recipe.id, favorite);
    } catch (_) {
      if (mounted) setState(() => _favoriteRecipeIds = previous);
    }
  }

  List<CatalogRecipe> get _results {
    final results = catalogRecipes.where((recipe) {
      final ingredientsMatch =
          recipe.ingredients.containsAll(_selectedIngredients) &&
          recipe.ingredients.intersection(_excludedIngredients).isEmpty;
      return ingredientsMatch &&
          (_fastingFilter == null || _fastingOf(recipe) == _fastingFilter);
    });
    final sortedResults = searchAndSortByLabel(
      results,
      query: _titleQuery,
      labelOf: _titleOf,
    );
    if (!_randomOrder) return sortedResults;
    final positions = {
      for (var index = 0; index < _randomRecipeIds.length; index++)
        _randomRecipeIds[index]: index,
    };
    return sortedResults.toList()..sort(
      (left, right) => (positions[left.id] ?? 1 << 30).compareTo(
        positions[right.id] ?? 1 << 30,
      ),
    );
  }

  RecipeCategory _categoryOf(CatalogRecipe recipe) =>
      _recipeCategories[recipe.id] ?? recipe.category;

  RecipeFasting _fastingOf(CatalogRecipe recipe) =>
      _recipeFasting[recipe.id] ?? recipe.fasting;

  bool get _hasSearchConditions =>
      _titleQuery.trim().isNotEmpty ||
      _selectedIngredients.isNotEmpty ||
      _excludedIngredients.isNotEmpty ||
      _fastingFilter != null;

  void _toggleResultOrder() {
    setState(() {
      _randomOrder = !_randomOrder;
      if (_randomOrder) _createRandomRecipeOrder();
    });
    AppSettings().randomRecipeOrder = _randomOrder;
    AppSettings().save();
  }

  void _createRandomRecipeOrder() {
    _randomRecipeIds = catalogRecipes.map((recipe) => recipe.id).toList()
      ..shuffle(math.Random.secure());
  }

  void _toggleFilters() => setState(() {
    _filterReveal = _filterReveal >= .5 ? 0 : 1;
  });

  void _toggleCompactFilterIngredients() {
    setState(() => _compactFilterIngredients = !_compactFilterIngredients);
    AppSettings().compactFilterIngredients = _compactFilterIngredients;
    AppSettings().save();
  }

  void _dragFilters(double horizontalDelta, double panelWidth) => setState(() {
    _isFilterDragging = true;
    // Тяга влево раскрывает правую панель, тяга вправо прячет её.
    _filterReveal = (_filterReveal - horizontalDelta / panelWidth)
        .clamp(0.0, 1.0)
        .toDouble();
  });

  void _startFilterDrag() => _filterDragStartReveal = _filterReveal;

  void _finishFilterDrag() => setState(() {
    _isFilterDragging = false;
    final wasOpened = _filterDragStartReveal >= .99;
    final closeDistance = _filterDragStartReveal - _filterReveal;
    // Закрытие начинается заметно раньше: достаточно убрать открытую панель
    // на четверть ширины. Открытие из скрытого состояния оставляет порог 33%.
    final shouldClose = wasOpened ? closeDistance >= .25 : _filterReveal < .33;
    _filterReveal = shouldClose ? 0 : 1;
  });

  void _startEdgeFilterDrag(
    DragStartDetails details,
    double screenWidth,
    double panelWidth,
  ) {
    // В портретной раскладке жесты работают с обеих кромок: справа — открыть
    // скрытые фильтры, слева у открытой панели — закрыть их.
    final x = details.localPosition.dx;
    final atRightScreenEdge = _filterReveal == 0 && x >= screenWidth - 36;
    final panelLeft = screenWidth - panelWidth;
    final atOpenPanelLeftEdge =
        _filterReveal >= .99 && x >= panelLeft - 8 && x <= panelLeft + 36;
    if (!atRightScreenEdge && !atOpenPanelLeftEdge) return;
    _isEdgeFilterDragging = true;
    _startFilterDrag();
  }

  void _updateEdgeFilterDrag(DragUpdateDetails details, double panelWidth) {
    if (_isEdgeFilterDragging) _dragFilters(details.delta.dx, panelWidth);
  }

  void _finishEdgeFilterDrag() {
    if (!_isEdgeFilterDragging) return;
    _isEdgeFilterDragging = false;
    _finishFilterDrag();
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
        actions: [
          IconButton(
            onPressed: widget.onToggleTheme,
            icon: const Icon(Icons.brightness_6),
            tooltip: 'Тема: ${widget.themeLabel}. Сменить тему',
          ),
          Builder(
            builder: (buttonContext) => IconButton(
              onPressed: () => showSettingsPopover(buttonContext),
              icon: const Icon(Icons.settings_outlined),
              tooltip: 'Настройки',
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: widget.onCreateRecipe,
        icon: const Icon(Icons.add),
        label: const Text('Создать рецепт'),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final panelWidth = constraints.maxWidth.clamp(0.0, 360.0).toDouble();
          final isOpen = _filterReveal >= .5;
          // В портретной/узкой раскладке важнее показать больше результатов и
          // фильтров, чем сохранять настольные вертикальные интервалы.
          final compactVertical = constraints.maxWidth < 1000;
          return GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragStart: compactVertical
                ? (details) => _startEdgeFilterDrag(
                    details,
                    constraints.maxWidth,
                    panelWidth,
                  )
                : null,
            onHorizontalDragUpdate: compactVertical
                ? (details) => _updateEdgeFilterDrag(details, panelWidth)
                : null,
            onHorizontalDragEnd: compactVertical
                ? (_) => _finishEdgeFilterDrag()
                : null,
            onHorizontalDragCancel: compactVertical
                ? _finishEdgeFilterDrag
                : null,
            child: Stack(
              children: [
                ListView(
                  padding: EdgeInsets.all(compactVertical ? 8 : 24),
                  children: [
                    Text(
                      'Поиск лакомств',
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    SizedBox(height: compactVertical ? 8 : 24),
                    TextField(
                      onChanged: (value) => setState(() => _titleQuery = value),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Theme.of(context)
                            .colorScheme
                            .primaryContainer,
                        prefixIcon: Icon(
                          Icons.search,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        labelText: 'Название лакомства',
                        labelStyle: TextStyle(
                          color: Theme.of(context)
                              .colorScheme
                              .onPrimaryContainer,
                        ),
                        suffixIcon: IconButton(
                          key: const ValueKey('recipe-order-toggle'),
                          constraints: Theme.of(context)
                              .inputDecorationTheme
                              .suffixIconConstraints,
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                          tooltip: _randomOrder
                              ? 'Случайный порядок: включён'
                              : 'Алфавитный порядок: включён',
                          onPressed: _toggleResultOrder,
                          icon: _randomOrder
                              ? Icon(
                                  Icons.shuffle,
                                  color: Theme.of(context).colorScheme.primary,
                                )
                              : Text(
                                  'А→Я',
                                  style: Theme.of(context).textTheme.labelLarge
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                        ),
                      ),
                    ),
                    SizedBox(height: compactVertical ? 5 : 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (final fasting in RecipeFasting.values)
                          FilterChip(
                            avatar: Icon(
                              fasting == RecipeFasting.lean
                                  ? Icons.eco_outlined
                                  : Icons.restaurant_outlined,
                              size: 18,
                            ),
                            label: Text(fasting.title),
                            selected: _fastingFilter == fasting,
                            onSelected: (selected) => setState(() {
                              _fastingFilter = selected ? fasting : null;
                            }),
                          ),
                      ],
                    ),
                    SizedBox(height: compactVertical ? 8 : 28),
                    if (_hasSearchConditions) ...[
                      _ResultCount(count: results.length),
                      SizedBox(height: compactVertical ? 4 : 12),
                      ..._recipeCards(results, compactVertical),
                    ] else ...[
                      ..._categorySections(compactVertical, results),
                    ],
                    if (_hasSearchConditions && results.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Center(
                          child: Text(
                            'Рецепты по этому сочетанию не найдены.',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.outline,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                filterPanelSlide(
                  isDragging: _isFilterDragging,
                  right: -panelWidth * (1 - _filterReveal),
                  width: panelWidth,
                  child: Material(
                    elevation: 12,
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                    child: _filterPanel(compactVertical: compactVertical),
                  ),
                ),
                filterPanelSlide(
                  isDragging: _isFilterDragging,
                  right: panelWidth * _filterReveal,
                  width: 48,
                  // Ручка не должна растягиваться на ширину самой панели.
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _toggleFilters,
                        onHorizontalDragStart: (_) => _startFilterDrag(),
                        onHorizontalDragUpdate: (details) =>
                            _dragFilters(details.delta.dx, panelWidth),
                        onHorizontalDragEnd: (_) => _finishFilterDrag(),
                        onHorizontalDragCancel: _finishFilterDrag,
                        child: Tooltip(
                          message: isOpen
                              ? 'Скрыть фильтры'
                              : 'Открыть фильтры',
                          child: Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: SizedBox(
                              width: 48,
                              height: 48,
                              child: Center(
                                child: Icon(
                                  isOpen
                                      ? Icons.chevron_right
                                      : Icons.chevron_left,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _filterPanel({required bool compactVertical}) => SafeArea(
    child: ListView(
      padding: EdgeInsets.all(compactVertical ? 5 : 16),
      children: [
        Text(
          'Фильтры',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(height: compactVertical ? 4 : 16),
        TextField(
          onChanged: (value) => setState(() => _filterQuery = value),
          decoration: InputDecoration(
            isDense: true,
            prefixIcon: const Icon(Icons.search),
            labelText: 'Найти ингредиент',
            suffixIcon: IconButton(
              constraints: Theme.of(context)
                  .inputDecorationTheme
                  .suffixIconConstraints,
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              tooltip: _compactFilterIngredients
                  ? 'Показывать названия ингредиентов'
                  : 'Показывать пиктограммы ингредиентов',
              onPressed: _toggleCompactFilterIngredients,
              icon: Icon(
                _compactFilterIngredients
                    ? Icons.view_stream_outlined
                    : Icons.grid_view_outlined,
              ),
            ),
          ),
        ),
        SizedBox(height: compactVertical ? 4 : 16),
        ..._ingredientGroups().entries.expand(
          (entry) => [
            _IngredientFilterGroup(
              title: entry.key,
              compactVertical: compactVertical,
              children: entry.value.map(_ingredientChip).toList(),
            ),
            SizedBox(height: compactVertical ? 3 : 14),
          ],
        ),
      ],
    ),
  );

  Widget _ingredientChip(String ingredient) {
    final included = _selectedIngredients.contains(ingredient);
    final excluded = _excludedIngredients.contains(ingredient);
    final colors = Theme.of(context).colorScheme;
    final card = _ingredientCardsByName[ingredient]!;
    final chip = _HatchedIngredientFilter(
      // Штриховка описывает следующий щелчок: нейтральный фильтр будет
      // включён, включённый — исключён, исключённый — снят.
      hoverColor: !included && !excluded
          ? colors.primary
          : included
          ? colors.error
          : colors.outline,
      child: InputChip(
        label: _compactFilterIngredients
            ? SizedBox(width: 20, height: 20, child: moduleIcon(context, card))
            : Text(ingredient),
        avatar: included
            ? const Icon(Icons.check, size: 18)
            : excluded
            ? const Icon(Icons.remove, size: 18)
            : null,
        selected: included,
        color: WidgetStateProperty.resolveWith((_) {
          if (excluded) return colors.errorContainer;
          if (included) return colors.primaryContainer;
          return colors.surfaceContainerLow;
        }),
        side: BorderSide(
          color: excluded
              ? colors.error
              : included
              ? colors.primary
              : colors.outlineVariant,
        ),
        labelStyle: TextStyle(
          color: excluded
              ? colors.onErrorContainer
              : included
              ? colors.onPrimaryContainer
              : colors.onSurface,
        ),
        onPressed: () => setState(() {
          if (!included && !excluded) {
            _selectedIngredients.add(ingredient);
          } else if (included) {
            _selectedIngredients.remove(ingredient);
            _excludedIngredients.add(ingredient);
          } else {
            _excludedIngredients.remove(ingredient);
          }
        }),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: const VisualDensity(horizontal: -2, vertical: -3),
      ),
    );
    // В обычном режиме название уже видно на самой карточке. Подсказка нужна
    // только компактному пиктографическому виду и сообщает исключительно имя
    // ингредиента, а не следующее действие при нажатии.
    return _compactFilterIngredients
        ? Tooltip(message: ingredient, child: chip)
        : chip;
  }

  List<Widget> _recipeCards(
    Iterable<CatalogRecipe> recipes,
    bool compactVertical,
  ) => [
    for (final recipe in recipes)
      _RecipeResultCard(
        recipe: recipe,
        title: _titleOf(recipe),
        category: _categoryOf(recipe),
        compactVertical: compactVertical,
        isFavorite: _favoriteRecipeIds.contains(recipe.id),
        onFavoriteChanged: (favorite) => _setRecipeFavorite(recipe, favorite),
        onTap: (geometry) {
          final transition = widget.onOpenRecipeWithTransition;
          if (transition != null && geometry != null) {
            transition(recipe, geometry);
          } else {
            widget.onOpenRecipe(recipe);
          }
        },
      ),
  ];

  List<Widget> _categorySections(
    bool compactVertical,
    List<CatalogRecipe> results,
  ) {
    final recipesByCategory = <RecipeCategory, List<CatalogRecipe>>{
      for (final category in RecipeCategory.values) category: [],
    };
    for (final recipe in results) {
      recipesByCategory[_categoryOf(recipe)]!.add(recipe);
    }
    final sections = <Widget>[];
    for (final category in RecipeCategory.values) {
      final recipes = recipesByCategory[category]!;
      if (recipes.isEmpty) continue;
      final expanded = _expandedCategories.contains(category);
      final colors = Theme.of(context).colorScheme;
      final accent = _recipeCategoryAccent(context, category);
      sections.add(
        Card(
          color: Color.alphaBlend(
            accent.withValues(
              alpha: colors.brightness == Brightness.dark ? .20 : .09,
            ),
            colors.surfaceContainerLow,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: accent.withValues(alpha: .42)),
          ),
          child: ListTile(
            leading: Icon(_categoryIcon(category), color: accent),
            title: Text(category.title),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${recipes.length}'),
                Icon(expanded ? Icons.expand_less : Icons.expand_more),
              ],
            ),
            onTap: () => setState(() {
              if (expanded) {
                _expandedCategories.remove(category);
              } else {
                _expandedCategories.add(category);
              }
            }),
          ),
        ),
      );
      if (expanded) sections.addAll(_recipeCards(recipes, compactVertical));
    }
    return sections;
  }

  IconData _categoryIcon(RecipeCategory category) => switch (category) {
    RecipeCategory.soup => Icons.soup_kitchen_outlined,
    RecipeCategory.porridge => Icons.rice_bowl_outlined,
    RecipeCategory.sideDish => Icons.restaurant_outlined,
    RecipeCategory.main => Icons.dinner_dining_outlined,
    RecipeCategory.salad => Icons.eco_outlined,
    RecipeCategory.pastry => Icons.bakery_dining_outlined,
    RecipeCategory.dessert => Icons.icecream_outlined,
    RecipeCategory.drink => Icons.local_drink_outlined,
    RecipeCategory.preserve => Icons.inventory_2_outlined,
    RecipeCategory.snack => Icons.tapas_outlined,
    RecipeCategory.other => Icons.category_outlined,
  };

  Map<String, List<String>> _ingredientGroups() {
    final groupOrder = IngredientGroup.values
        .map((group) => group.title)
        .toList();
    final groups = <String, List<String>>{
      for (final name in groupOrder) name: [],
    };
    // Карточки уже сгруппированы и отсортированы один раз; при вводе остаётся
    // только линейная проверка подстроки без повторных поисков по каталогу.
    final normalizedQuery = _filterQuery.trim().toLowerCase();
    for (final card in _ingredientCards) {
      if (normalizedQuery.isNotEmpty &&
          !card.nominative.toLowerCase().contains(normalizedQuery)) {
        continue;
      }
      groups[CatalogCards.ingredientGroup(card).title]!.add(card.nominative);
    }
    return Map.fromEntries(
      groupOrder
          .where((name) => groups[name]!.isNotEmpty)
          .map((name) => MapEntry(name, groups[name]!)),
    );
  }
}

/// Лёгкая диагональная сетка появляется только под курсором. Её цвет
/// сообщает состояние, в которое приведёт следующее нажатие.
class _HatchedIngredientFilter extends StatefulWidget {
  const _HatchedIngredientFilter({
    required this.child,
    required this.hoverColor,
  });
  final Widget child;
  final Color hoverColor;

  @override
  State<_HatchedIngredientFilter> createState() =>
      _HatchedIngredientFilterState();
}

class _HatchedIngredientFilterState extends State<_HatchedIngredientFilter> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    onEnter: (_) => setState(() => _hovering = true),
    onExit: (_) => setState(() => _hovering = false),
    child: Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: _hovering ? 1 : 0,
              duration: const Duration(milliseconds: 130),
              curve: Curves.easeOutCubic,
              child: CustomPaint(
                foregroundPainter: _IngredientFilterHatchPainter(
                  widget.hoverColor,
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _IngredientFilterHatchPainter extends CustomPainter {
  const _IngredientFilterHatchPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.height / 2),
    );
    final paint = Paint()
      ..color = color.withValues(alpha: .14)
      ..strokeWidth = 1;
    canvas
      ..save()
      ..clipRRect(bounds);
    for (var start = -size.height; start < size.width; start += 7) {
      canvas.drawLine(
        Offset(start, size.height),
        Offset(start + size.height, 0),
        paint,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_IngredientFilterHatchPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Выделяет число совпадений вторичным акцентом, не смешивая его с поиском.
class _ResultCount extends StatelessWidget {
  const _ResultCount({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Chip(
        avatar: Icon(
          Icons.menu_book_outlined,
          color: colors.onSecondaryContainer,
        ),
        backgroundColor: colors.secondaryContainer,
        side: BorderSide(color: colors.secondary),
        label: Text(
          'Найдено: $count',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: colors.onSecondaryContainer,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// Карточка рецепта отделяет название, состав и переход разными акцентами.
class _RecipeResultCard extends StatefulWidget {
  const _RecipeResultCard({
    required this.recipe,
    required this.title,
    required this.category,
    required this.compactVertical,
    required this.onTap,
    required this.isFavorite,
    required this.onFavoriteChanged,
  });
  final CatalogRecipe recipe;
  final String title;
  final RecipeCategory category;
  final bool compactVertical;
  final ValueChanged<RecipeSearchEntryGeometry?> onTap;
  final bool isFavorite;
  final ValueChanged<bool> onFavoriteChanged;

  @override
  State<_RecipeResultCard> createState() => _RecipeResultCardState();
}

class _RecipeResultCardState extends State<_RecipeResultCard>
    with SingleTickerProviderStateMixin {
  static const _favoriteDragThreshold = 18.0;
  static const _favoriteDragVisualRange = 72.0;
  static const _favoriteHoldDelay = Duration(seconds: 1);
  bool _showFavoriteChoices = false;
  bool _favoritePointerIsDown = false;
  double _favoriteDragDistance = 0;
  Timer? _favoriteHoldTimer;
  final GlobalKey _favoriteIconKey = GlobalKey();
  OverlayEntry? _favoriteChoicesOverlay;
  late final AnimationController _favoriteChoicesController =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 360),
        reverseDuration: const Duration(milliseconds: 200),
      )..addStatusListener((status) {
        if (status == AnimationStatus.dismissed &&
            _showFavoriteChoices &&
            mounted) {
          _removeFavoriteChoicesOverlay();
          setState(() => _showFavoriteChoices = false);
        }
      });

  @override
  void dispose() {
    _favoriteHoldTimer?.cancel();
    _removeFavoriteChoicesOverlay();
    _favoriteChoicesController.dispose();
    super.dispose();
  }

  Rect? _rectFor(GlobalKey key) {
    final renderObject = key.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return null;
    return renderObject.localToGlobal(Offset.zero) & renderObject.size;
  }

  void _open(
    GlobalKey cardKey,
    GlobalKey titleKey,
    GlobalKey ingredientsKey,
    Map<String, GlobalKey> ingredientKeys,
  ) {
    final card = _rectFor(cardKey);
    final title = _rectFor(titleKey);
    final ingredients = _rectFor(ingredientsKey);
    if (card == null || title == null || ingredients == null) {
      widget.onTap(null);
      return;
    }
    widget.onTap(
      RecipeSearchEntryGeometry(
        card: card,
        title: title,
        ingredients: ingredients,
        ingredientRects: {
          for (final entry in ingredientKeys.entries)
            if (_rectFor(entry.value) case final rect?) entry.key: rect,
        },
      ),
    );
  }

  void _startFavoriteHold() {
    _favoriteHoldTimer?.cancel();
    _favoritePointerIsDown = true;
    _favoriteDragDistance = 0;
    _favoriteHoldTimer = Timer(_favoriteHoldDelay, () {
      if (mounted && _favoritePointerIsDown) {
        setState(() => _showFavoriteChoices = true);
        _showFavoriteChoicesOverlay();
        _favoriteChoicesController.forward(from: 0);
      }
    });
  }

  void _updateFavoriteDrag(DragUpdateDetails details) {
    if (!_showFavoriteChoices) return;
    _favoriteDragDistance += details.primaryDelta ?? 0;
    // Сердца рисуются в Overlay, поэтому просим его перестроиться напрямую,
    // не затрагивая весь список рецептов на каждом пикселе drag-жеста.
    _favoriteChoicesOverlay?.markNeedsBuild();
  }

  double _favoriteEmphasis({required bool upper}) {
    if (_favoriteDragDistance == 0) return 0;
    final intensity = (_favoriteDragDistance.abs() / _favoriteDragVisualRange)
        .clamp(0.0, 1.0);
    final selectedIsUpper = _favoriteDragDistance < 0;
    return ((upper == selectedIsUpper ? 1.0 : -1.0) * intensity).toDouble();
  }

  void _finishFavoriteDrag() {
    _favoriteHoldTimer?.cancel();
    _favoritePointerIsDown = false;
    if (!_showFavoriteChoices) return;
    final favorite = _favoriteDragDistance <= -_favoriteDragThreshold
        ? true
        : _favoriteDragDistance >= _favoriteDragThreshold
        ? false
        : null;
    _favoriteChoicesController.reverse();
    if (favorite != null) widget.onFavoriteChanged(favorite);
  }

  void _cancelFavoriteHold() {
    _favoriteHoldTimer?.cancel();
    _favoritePointerIsDown = false;
    if (_showFavoriteChoices) {
      _favoriteChoicesController.reverse();
    }
  }

  void _showFavoriteChoicesOverlay() {
    _removeFavoriteChoicesOverlay();
    final targetBox = _favoriteIconKey.currentContext?.findRenderObject();
    final overlay = Overlay.of(context, rootOverlay: true);
    final overlayBox = overlay.context.findRenderObject();
    if (targetBox is! RenderBox || overlayBox is! RenderBox) return;
    final position = targetBox.localToGlobal(Offset.zero, ancestor: overlayBox);
    _favoriteChoicesOverlay = OverlayEntry(
      builder: (context) => Positioned(
        left: position.dx,
        top: position.dy,
        width: targetBox.size.width,
        height: targetBox.size.height,
        child: IgnorePointer(
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              _FavoriteChoice(
                progress: _favoriteChoicesController,
                destination: const Offset(0, -36),
                icon: Icons.favorite,
                color: Theme.of(context).colorScheme.error,
                emphasis: _favoriteEmphasis(upper: true),
              ),
              _FavoriteChoice(
                progress: _favoriteChoicesController,
                destination: const Offset(0, 36),
                icon: Icons.heart_broken,
                color: Theme.of(context).colorScheme.error,
                emphasis: _favoriteEmphasis(upper: false),
              ),
            ],
          ),
        ),
      ),
    );
    overlay.insert(_favoriteChoicesOverlay!);
  }

  void _removeFavoriteChoicesOverlay() {
    _favoriteChoicesOverlay?.remove();
    _favoriteChoicesOverlay = null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final categoryAccent = _recipeCategoryAccent(context, widget.category);
    final cardColor = Color.alphaBlend(
      categoryAccent.withValues(
        alpha: colors.brightness == Brightness.dark ? .22 : .10,
      ),
      colors.surfaceContainerLow,
    );
    final cardKey = GlobalKey();
    final titleKey = GlobalKey();
    final ingredientsKey = GlobalKey();
    final ingredients = widget.recipe.ingredientsByAmount;
    final ingredientKeys = {
      for (final ingredient in ingredients) ingredient: GlobalKey(),
    };
    return Card(
      key: cardKey,
      color: cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: categoryAccent.withValues(alpha: .42)),
      ),
      clipBehavior: Clip.none,
      child: ListTile(
        dense: widget.compactVertical,
        visualDensity: widget.compactVertical
            ? const VisualDensity(vertical: -2)
            : VisualDensity.standard,
        onTap: () => _open(cardKey, titleKey, ingredientsKey, ingredientKeys),
        leading: SizedBox(
          key: _favoriteIconKey,
          width: 48,
          height: 48,
          child: Listener(
            behavior: HitTestBehavior.opaque,
            // Listener отслеживает время удержания независимо от того,
            // победил ли вертикальный drag распознаватель жестов.
            onPointerDown: (_) => _startFavoriteHold(),
            onPointerUp: (_) => _finishFavoriteDrag(),
            onPointerCancel: (_) => _cancelFavoriteHold(),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              // Непустой обработчик забирает обычный tap у ListTile: иконка
              // никогда не открывает рецепт.
              onTap: () {},
              onVerticalDragUpdate: _updateFavoriteDrag,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  CircleAvatar(
                    backgroundColor: widget.isFavorite
                        ? colors.errorContainer
                        : colors.secondaryContainer,
                    foregroundColor: widget.isFavorite
                        ? colors.onErrorContainer
                        : colors.onSecondaryContainer,
                    child: const Icon(Icons.restaurant_menu),
                  ),
                ],
              ),
            ),
          ),
        ),
        title: Text(
          key: titleKey,
          widget.title,
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(color: colors.onSurface, fontWeight: FontWeight.w600),
        ),
        subtitle: Wrap(
          key: ingredientsKey,
          spacing: 0,
          runSpacing: 0,
          children: [
            for (var index = 0; index < ingredients.length; index++) ...[
              if (index > 0)
                Text(
                  ', ',
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: colors.onSurfaceVariant),
                ),
              Text(
                ingredients[index],
                key: ingredientKeys[ingredients[index]],
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: colors.onSurfaceVariant),
              ),
            ],
          ],
        ),
        trailing: Icon(Icons.chevron_right, color: colors.primary),
      ),
    );
  }
}

/// Категория различается мягким оттенком карточки, не создавая новых
/// произвольных цветов: используются только роли текущей палитры темы.
Color _recipeCategoryAccent(BuildContext context, RecipeCategory category) {
  final colors = Theme.of(context).colorScheme;
  final semantic = semanticColors(context);
  return switch (category) {
    RecipeCategory.soup => colors.secondary,
    RecipeCategory.porridge => colors.tertiary,
    RecipeCategory.sideDish => semantic.warning,
    RecipeCategory.main => colors.primary,
    RecipeCategory.salad => semantic.success,
    RecipeCategory.pastry => colors.tertiary,
    RecipeCategory.dessert => semantic.error,
    RecipeCategory.drink => colors.primary,
    RecipeCategory.preserve => semantic.warning,
    RecipeCategory.snack => colors.secondary,
    RecipeCategory.other => colors.outline,
  };
}

class _FavoriteChoice extends StatelessWidget {
  const _FavoriteChoice({
    required this.progress,
    required this.destination,
    required this.icon,
    required this.color,
    required this.emphasis,
  });

  final Animation<double> progress;
  final Offset destination;
  final IconData icon;
  final Color color;

  /// -1 — уменьшить/приглушить, +1 — увеличить/насытить на 10 %.
  final double emphasis;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: AnimatedBuilder(
      animation: progress,
      builder: (context, child) {
        final value = Curves.easeOutCubic.transform(progress.value);
        final saturation =
            (HSLColor.fromColor(color).saturation * (1 + .1 * emphasis)).clamp(
              0.0,
              1.0,
            );
        final animatedColor = HSLColor.fromColor(color)
            .withSaturation(saturation)
            .toColor();
        return Opacity(
          opacity: (value * (1 + .1 * emphasis)).clamp(0.0, 1.0),
          child: Transform.translate(
            // Обе иконки стартуют в центре значка рецепта и расходятся к
            // границе его круга: верхняя — сразу над ним, нижняя — под ним.
            offset: destination * value,
            child: Transform.scale(
              scale: (.2 + .8 * value) * (1 + .1 * emphasis),
              child: Icon(icon, color: animatedColor, size: 24),
            ),
          ),
        );
      },
    ),
  );
}

/// Отделяет группы фильтров тонированной подложкой от общей панели.
class _IngredientFilterGroup extends StatelessWidget {
  const _IngredientFilterGroup({
    required this.title,
    required this.children,
    required this.compactVertical,
  });
  final String title;
  final List<Widget> children;
  final bool compactVertical;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compactVertical ? 3 : 10),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall
                ?.copyWith(color: colors.tertiary, fontWeight: FontWeight.w700),
          ),
          SizedBox(height: compactVertical ? 2 : 8),
          Wrap(
            spacing: compactVertical ? 3 : 8,
            runSpacing: compactVertical ? 3 : 8,
            children: children,
          ),
        ],
      ),
    );
  }
}
