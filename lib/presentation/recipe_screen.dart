import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderBox;
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image/image.dart' as image;

import '../app_theme.dart';
import '../app_info.dart';
import '../data/app_settings.dart';
import '../data/recipe_database.dart';
import '../data/recipe_photo_storage.dart';
import '../domain/catalog.dart';
import '../domain/catalog_search.dart';
import '../domain/nutrition.dart';
import '../domain/recipe_node.dart';
import '../domain/recipe_renderer.dart';

class _NodeDrag {
  const _NodeDrag(this.node, this.source);
  final RecipeNode node;
  final List<RecipeNode> source;
}

/// Идентификаторы тепловых операций, отображаемых в разделе «Готовка».
const cookingActionCardIds = {
  'action.bake',
  'action.boil',
  'action.fry',
  'action.heat',
  'action.preheat',
  'action.saute',
  'action.stew',
};

/// Подготовительные операции над ингредиентами, вынесенные из общих действий.
const preparationActionCardIds = {
  'action.cut',
  'action.grate',
  'action.rinse',
  'action.clean',
  'action.cool',
  'action.beat',
  'action.shred',
  'action.blend',
  'action.mash',
  'action.drain',
  'action.soak',
  'action.thaw',
  'action.freeze',
  'action.sift',
  'action.dry-off',
  'action.dry',
  'action.whisk',
  'action.strain',
};

/// Операции сборки и оформления блюда, вынесенные из общих действий.
const assemblyActionCardIds = {
  'action.transfer',
  'action.plate',
  'action.close',
  'action.grease',
  'action.form',
  'action.fill',
  'action.roll-out',
  'action.coat',
  'action.pinch',
  'action.wrap',
};

// Размеры песочницы намеренно общие для сетки пиктограмм и самих карточек.
// Иначе расчёт позиций расходится с реальной шириной виджета при раскрытии.
const _sandboxIconSize = 18.0;
const _sandboxCompactGap = 2.0;
const _sandboxCompactHorizontalPadding = 6.0;
const _sandboxRegularHorizontalPadding = 10.0;
const _sandboxCompactLabelGap = 4.0;
const _sandboxRegularLabelGap = 6.0;

double _sandboxExpandedWidth(
  String cardId,
  double compactWidth,
  Map<String, TextPainter> labelWidths,
  bool compactVertical,
) =>
    compactWidth +
    (compactVertical ? _sandboxCompactLabelGap : _sandboxRegularLabelGap) +
    labelWidths[cardId]!.width;

/// Цвета модулей происходят из активной цветовой схемы, а не из фиксированных
/// светлых оттенков. Поэтому различимы и на светлом фоне, и в тёмной/OLED теме.
Color moduleColor(BuildContext context, CardKind kind) {
  return _moduleColor(Theme.of(context).colorScheme, kind);
}

Color _moduleColor(ColorScheme scheme, CardKind kind) {
  final accent = switch (kind) {
    CardKind.action => scheme.primary,
    CardKind.ingredient => scheme.secondary,
    CardKind.quantity => scheme.tertiary,
    CardKind.utensil || CardKind.text => scheme.outline,
  };
  // Карточки — главный носитель категории модуля. Слабая тонировка делала
  // три акцентные роли почти неразличимыми, особенно на светлых поверхностях.
  final opacity = scheme.brightness == Brightness.dark ? .44 : .28;
  return Color.alphaBlend(accent.withValues(alpha: opacity), scheme.surface);
}

/// Пиктограммы действий намеренно различны: в карточках и в визуализации
/// рецепта операция должна считываться без чтения подписи.
IconData actionIcon(String id) => switch (id) {
  'action.prepare' => Icons.power_settings_new,
  'action.cut' => Icons.content_cut,
  'action.grate' => Icons.grid_on,
  'action.mix' => Icons.blender,
  'action.add' => Icons.add_circle_outline,
  'action.boil' => Icons.soup_kitchen,
  'action.heat' => Icons.local_fire_department_outlined,
  'action.cool' => Icons.ac_unit_outlined,
  'action.freeze' => Icons.ac_unit,
  'action.dry-off' => Icons.water_damage_outlined,
  'action.dry' => Icons.wb_sunny_outlined,
  'action.rinse' => Icons.water_drop_outlined,
  'action.clean' => Icons.cleaning_services_outlined,
  'action.transfer' => Icons.swap_horiz,
  'action.pour' => Icons.format_color_fill,
  'action.stir' => Icons.rotate_right,
  'action.close' => Icons.lock_outline,
  'action.select' => Icons.tune,
  'action.leave' => Icons.timer_outlined,
  'action.open' => Icons.lock_open_outlined,
  'action.fry' => Icons.outdoor_grill,
  'action.saute' => Icons.restaurant_menu,
  'action.turn-off' => Icons.power_settings_new,
  'action.grease' => Icons.brush_outlined,
  'action.beat' => Icons.handyman_outlined,
  'action.dip' => Icons.opacity,
  'action.shred' => Icons.drag_handle,
  'action.blend' => Icons.blur_on_outlined,
  'action.stew' => Icons.soup_kitchen,
  'action.knead' => Icons.back_hand_outlined,
  'action.form' => Icons.category_outlined,
  'action.preheat' => Icons.fireplace_outlined,
  'action.bake' => Icons.bakery_dining,
  'action.drain' => Icons.vertical_align_bottom,
  'action.fill' => Icons.inventory_2_outlined,
  'action.mash' => Icons.compress_outlined,
  'action.strain' => Icons.filter_alt_outlined,
  'action.roll-out' => Icons.view_stream_outlined,
  'action.coat' => Icons.grain_outlined,
  'action.pinch' => Icons.pan_tool_outlined,
  'action.wrap' => Icons.wrap_text_outlined,
  'action.continue' => Icons.more_time_outlined,
  _ => Icons.restaurant_menu,
};

const _iconifyAssets = <String, String>{
  'action.stew': 'assets/icons/material-symbols-cooking.svg',
  'action.bake': 'assets/icons/material-symbols-oven.svg',
  'action.heat': 'assets/icons/material-symbols-microwave.svg',
  'ingredient.apples': 'assets/icons/material-symbols-nutrition.svg',
  'ingredient.plums': 'assets/icons/material-symbols-nutrition.svg',
  'ingredient.tomato-paste': 'assets/icons/material-symbols-nutrition.svg',
  'ingredient.eggs': 'assets/icons/material-symbols-egg.svg',
  'ingredient.egg-yolk': 'assets/icons/material-symbols-egg.svg',
  'ingredient.egg-white': 'assets/icons/material-symbols-egg.svg',
  'ingredient.chicken-fillet': 'assets/icons/at-icons-meat.svg',
  'ingredient.pork': 'assets/icons/at-icons-meat.svg',
  'ingredient.carrot': 'assets/icons/boxicons-carrot.svg',
  'ingredient.potato': 'assets/icons/iconoven-potato-sharp.svg',
  'ingredient.cheese': 'assets/icons/bx-cheese.svg',
  'ingredient.bay-leaf': 'assets/icons/coolicons-leaf.svg',
  'ingredient.parsley': 'assets/icons/coolicons-leaf.svg',
};

/// Прогревает разбор векторных пиктограмм, используемых шагами и модулями.
/// На слабом устройстве это устраняет разовую паузу при первом входе в рецепт.
Future<void> preloadRecipeInterfaceAssets(BuildContext context) => Future.wait(
  _iconifyAssets.values.toSet().map(
    (asset) => SvgAssetLoader(asset).loadBytes(context),
  ),
);

Widget moduleIcon(
  BuildContext context,
  CardDefinition card, {
  double? size,
  Color? color,
}) {
  final asset = _iconifyAssets[card.id];
  if (asset != null) {
    final foreground =
        color ??
        IconTheme.of(context).color ??
        Theme.of(context).colorScheme.onSurface;
    return SvgPicture.asset(
      asset,
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(foreground, BlendMode.srcIn),
    );
  }
  return Icon(cardIcon(card), size: size, color: color);
}

IconData cardIcon(CardDefinition card) {
  if (card.kind == CardKind.action) return actionIcon(card.id);
  return switch (card.id) {
    'ingredient.pork' ||
    'ingredient.beef' ||
    'ingredient.chicken-fillet' ||
    'ingredient.minced-meat' => Icons.set_meal,
    'ingredient.pike' ||
    'ingredient.perch' ||
    'ingredient.herring' ||
    'ingredient.cod' ||
    'ingredient.pollock' ||
    'ingredient.salmon' ||
    'ingredient.pink-salmon' ||
    'ingredient.trout' => Icons.set_meal,
    'ingredient.potato' => Icons.circle,
    'ingredient.radishes' => Icons.circle,
    'ingredient.carrot' => Icons.straighten,
    'ingredient.onion' => Icons.trip_origin,
    'ingredient.garlic' => Icons.bubble_chart_outlined,
    'ingredient.apples' => Icons.apple,
    'ingredient.plums' => Icons.album,
    'ingredient.eggs' ||
    'ingredient.egg-yolk' ||
    'ingredient.egg-white' => Icons.egg_alt_outlined,
    'ingredient.milk' ||
    'ingredient.kefir' ||
    'ingredient.sour-cream' ||
    'ingredient.cream' => Icons.local_drink_outlined,
    'ingredient.flour' ||
    'ingredient.baking-powder' ||
    'ingredient.batter' => Icons.bakery_dining_outlined,
    'ingredient.buckwheat' || 'ingredient.pearl-barley' => Icons.grain,
    'ingredient.noodles' || 'ingredient.pasta' => Icons.ramen_dining,
    'ingredient.water' ||
    'ingredient.cucumber-brine' ||
    'ingredient.kvass' => Icons.water_drop_outlined,
    'ingredient.vegetable-oil' || 'ingredient.butter' => Icons.opacity,
    'ingredient.pickled-cucumbers' => Icons.eco,
    'ingredient.zucchini' => Icons.spa,
    'ingredient.tomato-paste' => Icons.ramen_dining,
    'ingredient.corn-starch' => Icons.scatter_plot_outlined,
    'ingredient.sweet-paprika' => Icons.local_fire_department,
    'ingredient.cheese' => Icons.change_history,
    'ingredient.cottage-cheese' => Icons.blur_circular,
    'ingredient.bay-leaf' => Icons.park_outlined,
    'ingredient.yeast' => Icons.bubble_chart_outlined,
    'ingredient.bread' => Icons.bakery_dining,
    'ingredient.salt' ||
    'ingredient.sugar' ||
    'ingredient.black-pepper' => Icons.grain_outlined,
    'ingredient.cabbage' => Icons.filter_vintage,
    'ingredient.sauerkraut' => Icons.kebab_dining_outlined,
    'ingredient.cucumber' => Icons.eco_outlined,
    'ingredient.gelatin' => Icons.layers_outlined,
    'ingredient.mayonnaise' => Icons.soup_kitchen_outlined,
    'ingredient.raspberries' ||
    'ingredient.strawberries' => Icons.local_florist,
    'ingredient.ham' => Icons.set_meal,
    'ingredient.chanterelles' ||
    'ingredient.porcini' ||
    'ingredient.honey-mushrooms' => Icons.forest_outlined,
    'ingredient.olives' => Icons.circle,
    'ingredient.beans' => Icons.grain,
    'ingredient.condensed-milk' => Icons.local_drink_outlined,
    'ingredient.canned' => Icons.inventory_2_outlined,
    'ingredient.lard' => Icons.set_meal,
    'ingredient.raisins' || 'ingredient.walnuts' => Icons.park_outlined,
    'ingredient.sorrel' => Icons.grass,
    'ingredient.dill' ||
    'ingredient.parsley' ||
    'ingredient.green-onion' => Icons.grass,
    'ingredient.bones' => Icons.set_meal,
    'quantity.mass' => Icons.scale_outlined,
    'quantity.volume' => Icons.water_drop_outlined,
    'quantity.time' => Icons.schedule,
    'quantity.temperature' => Icons.device_thermostat,
    'quantity.count' => Icons.format_list_numbered,
    'quantity.fat-content' => Icons.percent,
    'characteristic.shape' => Icons.category_outlined,
    'utensil.whisk' => Icons.spa_outlined,
    'utensil.colander' => Icons.filter_alt_outlined,
    'utensil.meat-grinder' => Icons.settings,
    'utensil.sieve' => Icons.filter_list,
    'utensil.rolling-pin' => Icons.horizontal_rule,
    'utensil.grater' => Icons.grid_4x4,
    'utensil.oven' => Icons.microwave_outlined,
    'utensil.pot' => Icons.soup_kitchen_outlined,
    'utensil.lid' => Icons.circle_outlined,
    'utensil.baking-sheet' => Icons.rectangle_outlined,
    'utensil.frying-pan' => Icons.panorama_horizontal_outlined,
    'utensil.plate' => Icons.dinner_dining_outlined,
    'text.free' => Icons.short_text,
    _ => switch (card.kind) {
      CardKind.ingredient => Icons.restaurant,
      CardKind.utensil => Icons.kitchen_outlined,
      _ => Icons.circle_outlined,
    },
  };
}

bool _hasAllowedChildKind(RecipeNode parent, CardDefinition child) {
  if (parent.card.id == 'action.continue') {
    return child.kind == CardKind.action;
  }
  if (parent.card.id == 'action.wrap') {
    return child.kind == CardKind.ingredient || child.kind == CardKind.text;
  }
  if (parent.card.id == 'utensil.moulinex-ce5a0ff2') {
    return child.id == 'utensil.multicooker-program';
  }
  if (parent.card.id == 'ingredient.canned' &&
      child.kind == CardKind.ingredient) {
    return child.kind == CardKind.ingredient && child.id != parent.card.id;
  }
  return parent.card.kind == CardKind.action
      ? child.kind == CardKind.ingredient ||
            child.kind == CardKind.utensil ||
            child.kind == CardKind.text ||
            child.id == 'quantity.time' ||
            child.id == 'quantity.temperature'
      : parent.card.kind == CardKind.ingredient
      ? ((child.id == 'quantity.mass' || child.id == 'quantity.volume') &&
                _allowsQuantity(parent.card, child)) ||
            child.id == 'quantity.count' ||
            child.id == 'quantity.fat-content' ||
            child.id == 'characteristic.shape' ||
            (child.id == 'quantity.spoon' &&
                _canUseSpoonWithIngredient(parent.card)) ||
            child.kind == CardKind.text
      : false;
}

/// Набор единиц определяется продуктом: сливочное масло взвешивают, а не
/// измеряют объёмом. Остальные ингредиенты сохраняют обычный выбор массы
/// либо объёма.
bool _allowsQuantity(CardDefinition ingredient, CardDefinition quantity) {
  if (ingredient.id == 'ingredient.butter') {
    return quantity.id == 'quantity.mass';
  }
  return quantity.id == 'quantity.mass' || quantity.id == 'quantity.volume';
}

/// Единое правило для новой карточки и уже вставленного модуля. При переносе
/// [movingNode] предварительно исключается из целевого списка: одинаковые
/// условия работают для всех зон вставки и не зависят от позиции в строке.
bool canAddChild(
  RecipeNode parent,
  CardDefinition child, {
  RecipeNode? movingNode,
}) {
  final existing = parent.children
      .where((item) => !identical(item, movingNode))
      .toList(growable: false);
  if (parent.card.id == 'action.continue') {
    return child.kind == CardKind.action && existing.isEmpty;
  }
  if (parent.card.id == 'action.wrap') {
    return (child.kind == CardKind.ingredient || child.kind == CardKind.text) &&
        existing.length < 2;
  }
  if (parent.card.id == 'ingredient.canned' &&
      child.kind == CardKind.ingredient) {
    return child.id != parent.card.id &&
        !existing.any((item) => item.card.kind == CardKind.ingredient);
  }
  // У ингредиента может быть только одно количество: либо масса, либо объём.
  if ((child.id == 'quantity.mass' ||
          child.id == 'quantity.volume' ||
          child.id == 'quantity.count' ||
          child.id == 'quantity.spoon') &&
      existing.any(
        (item) =>
            item.card.id == 'quantity.mass' ||
            item.card.id == 'quantity.volume' ||
            item.card.id == 'quantity.count' ||
            item.card.id == 'quantity.spoon',
      ))
    return false;
  if (child.id == 'quantity.fat-content' &&
      existing.any((item) => item.card.id == 'quantity.fat-content')) {
    return false;
  }
  if (child.id == 'quantity.time' &&
      existing.any((item) => item.card.id == 'quantity.time'))
    return false;
  if (child.id == 'quantity.temperature' &&
      existing.any((item) => item.card.id == 'quantity.temperature'))
    return false;
  return _hasAllowedChildKind(parent, child) &&
      !existing.any((item) => item.card.id == child.id);
}

bool _canUseSpoonWithIngredient(CardDefinition ingredient) {
  // Все приправы получают ложку: размер и доля выбираются уже в самом
  // едином модуле «Ложка». Аналогично ложка остаётся доступной жидкостям и
  // молочным продуктам, где такая мера также естественна.
  const allowedGroups = {IngredientGroup.liquids, IngredientGroup.dairy};
  // Некоторые продукты могут состоять сразу в двух каталоговых подгруппах:
  // например, чеснок — овощ и приправа. `ingredientGroup` возвращает лишь
  // первую из них, поэтому для специй проверяем полное исходное множество.
  return allowedGroups.contains(CatalogCards.ingredientGroup(ingredient)) ||
      (CatalogCards.ingredientGroupIds[IngredientGroup.spices] ?? const {})
          .contains(ingredient.id) ||
      _spoonMeasuredIngredientIds.contains(ingredient.id);
}

/// Ингредиенты общей группы, которые в бытовых рецептах регулярно задают
/// ложками. Они не становятся «специями» в каталоге и фильтрах, но получают
/// тот же количественный подмодуль.
const _spoonMeasuredIngredientIds = {'ingredient.baking-powder'};

bool canAddStep(CardDefinition card) =>
    card.kind == CardKind.action ||
    card.id == CatalogCards.freeText.id ||
    card.id == CatalogCards.recipeDish.id;

GrammarCase grammarCaseFor(RecipeNode parent, CardDefinition child) =>
    grammarCaseForChild(parent, RecipeNode(id: 'preview', card: child));

/// В редакторе запятая или «и» — самостоятельный элемент между карточками,
/// а не часть текста следующего ингредиента. Так структура модуля остаётся
/// чистой, а пунктуация совпадает с режимом просмотра.
bool _showsIngredientEnumeration(RecipeNode parent, RecipeNode child) {
  if (parent.card.id == 'action.wrap' ||
      child.card.kind != CardKind.ingredient ||
      joinTextForChild(parent, child) != null) {
    return false;
  }
  final ingredients = parent.children
      .where((item) => item.card.kind == CardKind.ingredient)
      .toList();
  return ingredients.length > 1 && ingredients.indexOf(child) > 0;
}

class RecipeScreen extends StatefulWidget {
  const RecipeScreen({
    super.key,
    required this.onClose,
    required this.onToggleTheme,
    this.onRecipeSaved,
    this.onOpenSimilarRecipe,
    this.initialEditing = true,
    this.initialRecipe,
    this.themeLabel = 'Светлая',
    this.hideEntranceTitle = false,
    this.entranceTitleAnchor,
    this.entranceIngredientAnchors,
    this.onEntranceReady,
    this.revealRecipePhoto = true,
  });
  final VoidCallback onClose;
  final VoidCallback onToggleTheme;
  final VoidCallback? onRecipeSaved;
  final ValueChanged<CatalogRecipe>? onOpenSimilarRecipe;
  final bool initialEditing;
  final CatalogRecipe? initialRecipe;
  final String themeLabel;

  /// Во время раскрытия карточки поиска место заголовка остаётся неизменным,
  /// но текст показывает переходный слой из главного экрана.
  final bool hideEntranceTitle;
  final GlobalKey? entranceTitleAnchor;
  final Map<String, GlobalKey>? entranceIngredientAnchors;
  final VoidCallback? onEntranceReady;

  /// Крышка фотографии открывается лишь после завершения внешнего перехода
  /// из карточки поиска в экран рецепта.
  final bool revealRecipePhoto;
  @override
  State<RecipeScreen> createState() => _RecipeScreenState();
}

class _RecipeScreenState extends State<RecipeScreen>
    with SingleTickerProviderStateMixin {
  final RecipeRenderer _renderer = const RecipeRenderer();
  // При входе в полноэкранный режим раскладка может смениться с Column на Row.
  // GlobalKey сохраняет центральный холст и активное поле ввода при переносе.
  final _recipeCanvasKey = GlobalKey<_RecipeCanvasState>();

  /// При входном переходе нельзя сначала показать каталожную версию, а потом
  /// подменить её локально сохранённой: у шагов в эти два кадра различаются
  /// координаты. Пока БД загружается, оставляем холст пустым; затем дерево
  /// появляется сразу в окончательном виде, по которому измеряются якоря.
  late final List<RecipeNode> _steps = widget.onEntranceReady == null
      ? (widget.initialRecipe?.buildSteps() ?? [])
      : [];
  late final List<RecipeNode> _catalogSteps =
      widget.initialRecipe?.buildSteps() ?? [];
  late final TextEditingController _noteController;
  late final TextEditingController _titleController;
  late final TextEditingController _servingsController;
  late final TextEditingController _recipeMultiplierController;
  late final FocusNode _servingsFocusNode;
  late final List<CatalogRecipe> _similarRecipes = widget.initialRecipe == null
      ? const []
      : similarRecipesFor(widget.initialRecipe!, catalogRecipes);
  int _servings = 2;
  int _recipeMultiplier = 2;
  late RecipeCategory _category =
      widget.initialRecipe?.category ?? RecipeCategory.other;
  late RecipeFasting _fasting =
      widget.initialRecipe?.fasting ?? RecipeFasting.nonLean;
  late bool _editing = widget.initialEditing;
  late final AnimationController _modeTransition = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 390),
  )..addStatusListener(_completeModeTransitionIfNeeded);
  late final AnimationController _backSwipeController =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 230),
      )..addStatusListener((status) {
        if (status == AnimationStatus.completed && _closingFromBackSwipe) {
          unawaited(_completeBackSwipeClose());
        }
      });
  late bool _modeTransitionFromEditing = _editing;
  bool _isModeDragging = false;
  bool _modeDragDirectionAccepted = false;
  bool _revertModeAfterDrag = false;
  bool _closingFromEscape = false;
  bool _backSwipeActive = false;
  bool _closingFromBackSwipe = false;
  bool _showVisuals = true;
  bool _showGrammar = false;
  bool _isRecipeModuleDragging = false;
  bool _revealPhotoAfterModeTransition = true;
  late bool _compactSandboxModules;
  late double _rightPanelFraction;
  late double _bottomPanelFraction;
  bool? _wasVerticalWorkspace;
  String? _savedContentFingerprint;
  String? _recipePhotoPath;
  Uint8List? _recipePhotoBytes;
  bool _savingRecipePhoto = false;
  late String _title = widget.initialRecipe?.title ?? 'Новый рецепт';

  @override
  void initState() {
    super.initState();
    // Focus-обработчики не всегда получают Escape в Linux: его может удержать
    // нативное поле ввода или иной потомок. Глобальный обработчик вызывается
    // до маршрутизации по Focus-дереву и потому работает из любого места
    // экрана рецепта.
    HardwareKeyboard.instance.addHandler(_handleKeyboardEvent);
    final initialServings = widget.initialRecipe?.servings ?? 2;
    _servings = initialServings;
    _recipeMultiplier = initialServings;
    _noteController = TextEditingController();
    _titleController = TextEditingController(text: _title);
    _servingsController = TextEditingController(text: '$initialServings');
    _recipeMultiplierController = TextEditingController(
      text: '$initialServings',
    );
    _servingsFocusNode = FocusNode()
      ..addListener(() {
        if (!_servingsFocusNode.hasFocus) _restoreServingsIfInvalid();
      });
    _rightPanelFraction = AppSettings().rightPanelFraction;
    _bottomPanelFraction = AppSettings().bottomPanelFraction;
    _compactSandboxModules = AppSettings().compactSandboxModules;
    _loadSavedRecipe();
  }

  Future<void> _loadSavedRecipe() async {
    final recipeId = widget.initialRecipe?.id;
    if (recipeId == null) return;
    final database = RecipeDatabase();
    final values = await Future.wait<dynamic>([
      database.recordRecipeOpened(recipeId),
      database.loadRecipeTitle(recipeId),
      database.loadRecipeNote(recipeId),
      database.loadRecipeSteps(recipeId),
      database.loadRecipeServings(recipeId),
      database.loadRecipeMultiplier(recipeId),
      database.loadRecipeCategory(recipeId),
      database.loadRecipeFasting(recipeId),
      database.loadRecipePhotoPath(recipeId),
      database.loadRecipePhotoBytes(recipeId),
    ]);
    if (!mounted) return;
    final savedSteps = values[3] as List<RecipeNode>;
    setState(() {
      _title = (values[1] as String).trim().isEmpty
          ? _title
          : values[1] as String;
      _titleController.text = _title;
      _noteController.text = values[2] as String;
      _servings = values[4] as int;
      _servingsController.text = '$_servings';
      _recipeMultiplier = values[5] as int;
      _recipeMultiplierController.text = '$_recipeMultiplier';
      _category = values[6] as RecipeCategory;
      _fasting = values[7] as RecipeFasting;
      _recipePhotoPath = values[8] as String?;
      _recipePhotoBytes = values[9] as Uint8List?;
      _steps
        ..clear()
        ..addAll(savedSteps.isNotEmpty ? savedSteps : _catalogSteps);
      _updateRecipeDishLabels();
      _savedContentFingerprint = _contentFingerprint();
    });
    // Внешний переход измеряет слова ингредиентов. Сообщаем ему о готовности
    // только после того, как виджеты уже получили размеры из сохранённого
    // дерева, а не из временной версии каталога.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onEntranceReady?.call();
    });
  }

  /// Сохраняет только отличающееся от загруженного состояние.
  /// Возвращает null, если запись не удалась; иначе сообщает, была ли запись.
  Future<bool?> _saveChangesIfNeeded() async {
    final recipeId = widget.initialRecipe?.id;
    if (recipeId == null || _savedContentFingerprint == null) return false;
    if (_title.trim().isEmpty) {
      _title = widget.initialRecipe?.title ?? 'Новый рецепт';
      _titleController.text = _title;
      _updateRecipeDishLabels();
    }
    if (_contentFingerprint() == _savedContentFingerprint) return false;
    try {
      await RecipeDatabase().saveRecipeContent(
        recipeId: recipeId,
        title: _title.trim(),
        steps: _steps,
        note: _noteController.text,
        servings: _servings,
        recipeMultiplier: _recipeMultiplier,
        category: _category,
        fasting: _fasting,
      );
      _savedContentFingerprint = _contentFingerprint();
      return true;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось сохранить рецепт.')),
        );
      }
      return null;
    }
  }

  Future<void> _saveAndClose() async {
    final saved = await _saveChangesIfNeeded();
    if (saved == null) return;
    if (mounted) {
      widget.onClose();
      if (saved) widget.onRecipeSaved?.call();
    }
  }

  Future<void> _openSimilarRecipe(CatalogRecipe recipe) async {
    final saved = await _saveChangesIfNeeded();
    if (saved == null || !mounted) return;
    if (saved) widget.onRecipeSaved?.call();
    widget.onOpenSimilarRecipe?.call(recipe);
  }

  Future<void> _selectRecipePhoto() async {
    final recipeId = widget.initialRecipe?.id;
    if (recipeId == null || _savingRecipePhoto) return;
    try {
      final sourceBytes = await RecipePhotoStorage.selectImageBytes();
      if (sourceBytes == null || !mounted) return;
      final crop = await showDialog<Rect>(
        context: context,
        builder: (_) => _SquarePhotoCropDialog(sourceBytes: sourceBytes),
      );
      if (crop == null || !mounted) return;
      setState(() => _savingRecipePhoto = true);
      final storedPhoto = await RecipePhotoStorage.cropAndStore(
        recipeId: recipeId,
        sourceBytes: sourceBytes,
        normalizedCrop: crop,
      );
      if (!mounted) return;
      setState(() {
        _recipePhotoPath = storedPhoto.path;
        _recipePhotoBytes = storedPhoto.bytes;
        _savingRecipePhoto = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _savingRecipePhoto = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось обработать изображение.')),
      );
    }
  }

  String _contentFingerprint() => jsonEncode({
    'title': _title,
    'note': _noteController.text,
    'servings': _servings,
    'recipeMultiplier': _recipeMultiplier,
    'category': _category.storageKey,
    'fasting': _fasting.storageKey,
    'steps': _steps.map(_snapshotNode).toList(),
  });

  void _updateRecipeDishLabels() {
    void visit(RecipeNode node) {
      if (node.card.id == 'text.recipe-dish') node.text = _title;
      for (final child in node.children) visit(child);
    }

    for (final step in _steps) visit(step);
  }

  Map<String, Object?> _snapshotNode(RecipeNode node) => {
    'id': node.id,
    'card': node.card.id,
    'grammarCase': node.caseFromParent.index,
    'join': node.joinWithPrevious,
    'value': node.value,
    'upperValue': node.upperValue,
    'unit': node.unit?.index,
    'text': node.text,
    'children': node.children.map(_snapshotNode).toList(),
  };

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyboardEvent);
    _modeTransition.dispose();
    _backSwipeController.dispose();
    _noteController.dispose();
    _titleController.dispose();
    _servingsController.dispose();
    _recipeMultiplierController.dispose();
    _servingsFocusNode.dispose();
    super.dispose();
  }

  bool _handleKeyboardEvent(KeyEvent event) {
    final isEscape =
        event.logicalKey == LogicalKeyboardKey.escape ||
        event.physicalKey == PhysicalKeyboardKey.escape;
    if (event is! KeyDownEvent || !isEscape) return false;
    // Автоповтор клавиши не должен запускать параллельные сохранения.
    if (!_closingFromEscape) {
      _closingFromEscape = true;
      unawaited(_closeFromEscape());
    }
    return true;
  }

  Future<void> _closeFromEscape() async {
    await _saveAndClose();
    // При успешном закрытии экран будет размонтирован. Если сохранение не
    // удалось, разрешаем пользователю повторить попытку.
    if (mounted) _closingFromEscape = false;
  }

  void _startWorkspaceDrag() => _startModeDrag();

  void _dragWorkspace(double horizontalDelta, double width) {
    // Пока жест был начат в редакторе, [_editing] уже мог переключиться в
    // false, хотя палец всё ещё завершает переход «редактор → просмотр».
    // В этом случае вправо продолжает означать просмотр, а не выход к поиску.
    final startedFromViewer = !_modeTransitionFromEditing;
    if (!_editing &&
        startedFromViewer &&
        (_backSwipeActive || horizontalDelta > 0)) {
      if (!_backSwipeActive) {
        setState(() {
          _backSwipeActive = true;
          _isModeDragging = false;
          _modeTransition.stop();
        });
      }
      _backSwipeController.value =
          (_backSwipeController.value + horizontalDelta / width).clamp(
            0.0,
            1.0,
          );
      return;
    }
    _dragMode(horizontalDelta, width);
  }

  void _finishWorkspaceDrag() {
    if (!_backSwipeActive) {
      _finishModeDrag();
      return;
    }
    setState(() => _backSwipeActive = false);
    // Возврат подтверждается только после прохождения половины экрана.
    if (_backSwipeController.value >= .5) {
      _closingFromBackSwipe = true;
      _backSwipeController.forward();
    } else {
      _backSwipeController.reverse();
    }
  }

  Future<void> _completeBackSwipeClose() async {
    final saved = await _saveChangesIfNeeded();
    if (saved == null) {
      if (mounted) {
        _closingFromBackSwipe = false;
        _backSwipeController.reverse();
      }
      return;
    }
    if (!mounted) return;
    widget.onClose();
    if (saved) widget.onRecipeSaved?.call();
  }

  void _completeModeTransitionIfNeeded(AnimationStatus status) {
    if (status == AnimationStatus.dismissed &&
        _revertModeAfterDrag &&
        _editing != _modeTransitionFromEditing) {
      setState(() {
        _editing = _modeTransitionFromEditing;
        _revertModeAfterDrag = false;
      });
    } else if (status == AnimationStatus.completed) {
      _revertModeAfterDrag = false;
      if (_modeTransitionFromEditing && !_editing) {
        // Центральная колонка заканчивает трансформацию за 390 мс, а правая
        // панель — за 420 мс. Небольшой запас не позволяет крышке начать
        // подъём поверх ещё движущейся песочницы.
        Future<void>.delayed(const Duration(milliseconds: 80), () {
          if (mounted && !_editing && _modeTransitionFromEditing) {
            setState(() => _revealPhotoAfterModeTransition = true);
          }
        });
      }
    }
  }

  void _restoreServingsIfInvalid() {
    final enteredValue = int.tryParse(_servingsController.text);
    if (enteredValue == null || enteredValue < 1 || enteredValue > 256) {
      _servingsController.text = '$_servings';
    }
  }

  RecipeNode _newNode(CardDefinition card, {RecipeNode? parent}) => RecipeNode(
    id: 'node.${DateTime.now().microsecondsSinceEpoch}',
    card: card,
    caseFromParent: parent == null
        ? GrammarCase.unspecified
        : grammarCaseFor(parent, card),
    value:
        card.id == 'quantity.mass' ||
            card.id == 'quantity.volume' ||
            card.id == 'quantity.time' ||
            card.id == 'quantity.temperature' ||
            card.id == 'quantity.count' ||
            card.id == 'quantity.fat-content'
        ? 1
        : null,
    text: card.id == 'text.recipe-dish'
        ? _title
        : card.id == 'ingredient.eggs'
        ? 'С1'
        : card.id == 'characteristic.shape'
        ? 'кубиками'
        : null,
    unit: card.id == 'quantity.mass'
        ? NumericUnit.grams
        : card.id == 'quantity.volume'
        ? NumericUnit.milliliters
        : card.id == 'quantity.time'
        ? NumericUnit.minutes
        : card.id == 'quantity.temperature'
        ? NumericUnit.celsius
        : card.id == 'quantity.count'
        ? NumericUnit.pieces
        : card.id == 'quantity.fat-content'
        ? NumericUnit.percent
        : null,
  );

  bool _canDrop(Object data, RecipeNode? parent) {
    final card = data is CardDefinition ? data : (data as _NodeDrag).node.card;
    if (parent == null) return canAddStep(card);
    return canAddChild(
      parent,
      card,
      movingNode: data is _NodeDrag ? data.node : null,
    );
  }

  void _drop(
    Object data,
    List<RecipeNode> target,
    int index, {
    RecipeNode? parent,
  }) => setState(() {
    if (data is CardDefinition) {
      target.insert(index, _newNode(data, parent: parent));
      return;
    }
    final drag = data as _NodeDrag;
    final oldIndex = drag.source.indexOf(drag.node);
    drag.source.removeAt(oldIndex);
    if (identical(target, drag.source) && oldIndex < index) index--;
    target.insert(index.clamp(0, target.length), drag.node);
  });

  void _discard(_NodeDrag drag) =>
      setState(() => drag.source.remove(drag.node));

  void _setRecipeModuleDragging(bool value) {
    if (!mounted || _isRecipeModuleDragging == value) return;
    setState(() => _isRecipeModuleDragging = value);
  }

  void _resizeRightPanel(double delta, BoxConstraints constraints) {
    final availableWidth = constraints.maxWidth;
    if (availableWidth <= 0) return;
    final minimumFraction = 280 / availableWidth;
    final maximumFraction = (availableWidth - 360) / availableWidth;
    setState(() {
      _rightPanelFraction = (_rightPanelFraction - delta / availableWidth)
          .clamp(minimumFraction, maximumFraction)
          .toDouble();
    });
  }

  void _saveRightPanelFraction() {
    AppSettings().rightPanelFraction = _rightPanelFraction;
    AppSettings().save();
  }

  void _resizeBottomPanel(double delta, BoxConstraints constraints) {
    final availableHeight = constraints.maxHeight;
    if (availableHeight <= 0) return;
    final minimumFraction = 180 / availableHeight;
    final maximumFraction = 1 - 200 / availableHeight;
    if (minimumFraction > maximumFraction) return;
    setState(() {
      // Верхняя граница нижней панели движется противоположно её высоте:
      // перетаскивание вниз уменьшает панель, вверх — увеличивает.
      _bottomPanelFraction = (_bottomPanelFraction - delta / availableHeight)
          .clamp(minimumFraction, maximumFraction)
          .toDouble();
    });
  }

  void _saveBottomPanelFraction() {
    AppSettings().bottomPanelFraction = _bottomPanelFraction;
    AppSettings().save();
  }

  void _toggleCompactSandboxModules() {
    setState(() => _compactSandboxModules = !_compactSandboxModules);
    AppSettings().compactSandboxModules = _compactSandboxModules;
    AppSettings().save();
  }

  /// Один контроллер принадлежит всему рецепту, а не каждой строке. Поэтому
  /// шаг, который ListView создаст позже, попадает в ту же фазу перехода, что
  /// уже видимые шаги, и экран не разделяется на старую и новую половины.
  void _toggleEditingWithTransition() {
    setState(() {
      _modeTransitionFromEditing = _editing;
      if (_editing) _revealPhotoAfterModeTransition = false;
      _editing = !_editing;
      _modeTransition.forward(from: 0);
    });
  }

  void _startModeDrag() {
    if (_isModeDragging) return;
    setState(() {
      _isModeDragging = true;
      _modeDragDirectionAccepted = false;
      _revertModeAfterDrag = false;
      _modeTransition.stop();
      _modeTransitionFromEditing = _editing;
      _modeTransition.value = 0;
    });
  }

  void _dragMode(double horizontalDelta, double width) {
    if (!_isModeDragging || width <= 0) return;
    // Из просмотра редактор открывается влево; из редактора просмотр
    // возвращается вправо. Движение в неверную сторону не запускает переход.
    final directedDelta = _modeTransitionFromEditing
        ? horizontalDelta
        : -horizontalDelta;
    if (!_modeDragDirectionAccepted) {
      if (directedDelta <= 0) return;
      setState(() {
        _modeDragDirectionAccepted = true;
        if (_modeTransitionFromEditing) {
          _revealPhotoAfterModeTransition = false;
        }
        _editing = !_modeTransitionFromEditing;
      });
    }
    _modeTransition.value = (_modeTransition.value + directedDelta / width)
        .clamp(0.0, 1.0);
  }

  void _finishModeDrag() {
    if (!_isModeDragging) return;
    if (!_modeDragDirectionAccepted) {
      setState(() => _isModeDragging = false);
      return;
    }
    final threshold = _modeTransitionFromEditing ? .25 : .33;
    final shouldComplete = _modeTransition.value >= threshold;
    setState(() {
      _isModeDragging = false;
      _modeDragDirectionAccepted = false;
    });
    if (shouldComplete) {
      _modeTransition.forward();
    } else {
      _revertModeAfterDrag = true;
      _modeTransition.reverse();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        tooltip: 'К поиску',
        onPressed: _saveAndClose,
      ),
      actions: [
        IconButton(
          tooltip: _editing ? 'Просмотр рецепта' : 'Редактировать рецепт',
          onPressed: _toggleEditingWithTransition,
          icon: Icon(_editing ? Icons.visibility : Icons.edit),
        ),
        IconButton(
          tooltip: 'Кухонная справка',
          onPressed: () => showRecipeReferenceDialog(context),
          icon: const Icon(Icons.help_outline),
        ),
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
    drawer: Drawer(
      child: SafeArea(
        child: ListView(
          children: [
            const ListTile(title: Text('Настройки просмотра')),
            SwitchListTile(
              value: _showVisuals,
              onChanged: (value) => setState(() => _showVisuals = value),
              title: const Text('Показывать иллюстрации шагов'),
            ),
            SwitchListTile(
              value: _showGrammar,
              onChanged: (value) => setState(() => _showGrammar = value),
              title: const Text('Показывать грамматику'),
            ),
          ],
        ),
      ),
    ),
    body: AnimatedBuilder(
      animation: _backSwipeController,
      child: _workspace(),
      builder: (context, child) => Transform.translate(
        offset: Offset(
          MediaQuery.sizeOf(context).width * _backSwipeController.value,
          0,
        ),
        child: child,
      ),
    ),
  );

  Widget _workspace() => LayoutBuilder(
    builder: (context, constraints) {
      final isVertical = constraints.maxWidth < 1000;
      final sandbox = _CardLibrary(
        showGrammar: _showGrammar,
        onDiscard: _discard,
        showDiscardOverlay: _isRecipeModuleDragging,
        compactModules: _compactSandboxModules,
        compactVertical: isVertical,
        onToggleCompactModules: _toggleCompactSandboxModules,
      );
      final canvas = _RecipeCanvas(
        key: _recipeCanvasKey,
        title: _title,
        titleController: _titleController,
        onTitleChanged: (value) => setState(() {
          _title = value;
          _updateRecipeDishLabels();
        }),
        steps: _steps,
        editing: _editing,
        modeTransition: _modeTransition,
        modeTransitionFromEditing: _modeTransitionFromEditing,
        modeDragging: _isModeDragging,
        moduleDragging: _isRecipeModuleDragging,
        renderer: _renderer,
        showVisuals: _showVisuals,
        servings: _servings,
        recipeMultiplier: _recipeMultiplier,
        recipeMultiplierController: _recipeMultiplierController,
        onRecipeMultiplierChanged: (value) => setState(() {
          _recipeMultiplier = value;
        }),
        category: _category,
        onCategoryChanged: (value) => setState(() => _category = value),
        fasting: _fasting,
        onFastingChanged: (value) => setState(() => _fasting = value),
        canDrop: _canDrop,
        onDrop: _drop,
        onModuleDragChanged: _setRecipeModuleDragging,
        hideTitle: widget.hideEntranceTitle,
        entranceTitleAnchor: widget.entranceTitleAnchor,
        entranceIngredientAnchors: widget.entranceIngredientAnchors,
        compactVertical: isVertical,
      );
      final center = canvas;
      final notePanel = _RecipeNotes(
        controller: _noteController,
        servingsController: _servingsController,
        servingsFocusNode: _servingsFocusNode,
        onServingsEditingComplete: _restoreServingsIfInvalid,
        servings: _servings,
        similarRecipes: _similarRecipes,
        onOpenSimilarRecipe: _openSimilarRecipe,
        nutrition: NutritionCatalog.perServing(
          _steps,
          recipeMultiplier: _recipeMultiplier,
        ),
        onServingsChanged: (value) => setState(() {
          _servings = value;
        }),
        recipePhotoPath: _recipePhotoPath,
        recipePhotoBytes: _recipePhotoBytes,
        savingRecipePhoto: _savingRecipePhoto,
        onPickRecipePhoto: _selectRecipePhoto,
        revealRecipePhoto:
            widget.revealRecipePhoto && _revealPhotoAfterModeTransition,
      );
      final sidePanel = AnimatedSwitcher(
        // Песочница и примечания меняются синхронно с центральным шагом.
        duration: const Duration(milliseconds: 420),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) => ClipRect(
          child: SlideTransition(
            position: Tween<Offset>(
              // В вертикальной раскладке нижняя панель приходит сверху вниз;
              // справа налево остаётся только для боковой колонки на широком
              // экране.
              begin: constraints.maxWidth < 1000
                  ? const Offset(0, -1)
                  : const Offset(1, 0),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        ),
        child: _editing
            ? KeyedSubtree(key: const ValueKey('sandbox'), child: sandbox)
            : KeyedSubtree(key: const ValueKey('notes'), child: notePanel),
      );
      const handleSize = 9.0;
      const layoutDuration = Duration(milliseconds: 320);
      // Обычное изменение размера окна не должно задерживать перерасчёт
      // содержимого. Анимация нужна именно при переходе правой колонки вниз
      // и обратно.
      final changesWorkspaceDirection =
          _wasVerticalWorkspace != null && _wasVerticalWorkspace != isVertical;
      _wasVerticalWorkspace = isVertical;
      final transitionDuration = changesWorkspaceDirection
          ? layoutDuration
          : Duration.zero;
      final width = constraints.maxWidth;
      final height = constraints.maxHeight;

      late final Rect canvasRect;
      late final Rect panelRect;
      late final Rect handleRect;
      if (isVertical) {
        final minimumFraction = 180 / height;
        final maximumFraction = 1 - 200 / height;
        final visibleFraction = minimumFraction <= maximumFraction
            ? _bottomPanelFraction
                  .clamp(minimumFraction, maximumFraction)
                  .toDouble()
            : .5;
        final panelHeight = height * visibleFraction;
        final canvasHeight = (height - panelHeight - handleSize).clamp(
          0.0,
          height,
        );
        canvasRect = Rect.fromLTWH(0, 0, width, canvasHeight);
        handleRect = Rect.fromLTWH(0, canvasHeight, width, handleSize);
        panelRect = Rect.fromLTWH(
          0,
          canvasHeight + handleSize,
          width,
          panelHeight,
        );
      } else {
        final minimumFraction = 280 / width;
        final maximumFraction = (width - 360) / width;
        final visibleFraction = _rightPanelFraction
            .clamp(minimumFraction, maximumFraction)
            .toDouble();
        final panelWidth = width * visibleFraction;
        final canvasWidth = (width - panelWidth - handleSize).clamp(0.0, width);
        canvasRect = Rect.fromLTWH(0, 0, canvasWidth, height);
        handleRect = Rect.fromLTWH(canvasWidth, 0, handleSize, height);
        panelRect = Rect.fromLTWH(
          canvasWidth + handleSize,
          0,
          panelWidth,
          height,
        );
      }

      // Один Stack сохраняет сами виджеты между сменой раскладки. Поэтому
      // правая колонка не пересоздаётся снизу, а переезжает в эту позицию.
      return Stack(
        children: [
          AnimatedPositioned.fromRect(
            duration: transitionDuration,
            curve: Curves.easeInOutCubic,
            rect: canvasRect,
            child: GestureDetector(
              key: const ValueKey('recipe-mode-swipe-surface'),
              behavior: HitTestBehavior.translucent,
              onHorizontalDragStart: (_) => _startWorkspaceDrag(),
              onHorizontalDragUpdate: (details) =>
                  _dragWorkspace(details.delta.dx, canvasRect.width),
              onHorizontalDragEnd: (_) => _finishWorkspaceDrag(),
              onHorizontalDragCancel: _finishWorkspaceDrag,
              child: center,
            ),
          ),
          AnimatedPositioned.fromRect(
            duration: transitionDuration,
            curve: Curves.easeInOutCubic,
            rect: panelRect,
            child: sidePanel,
          ),
          AnimatedPositioned.fromRect(
            duration: transitionDuration,
            curve: Curves.easeInOutCubic,
            rect: handleRect,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 160),
              child: isVertical
                  ? _RowResizeHandle(
                      key: const ValueKey('row-resize-handle'),
                      onDragUpdate: (delta) =>
                          _resizeBottomPanel(delta, constraints),
                      onDragEnd: _saveBottomPanelFraction,
                    )
                  : _ColumnResizeHandle(
                      key: const ValueKey('column-resize-handle'),
                      onDragUpdate: (delta) =>
                          _resizeRightPanel(delta, constraints),
                      onDragEnd: _saveRightPanelFraction,
                    ),
            ),
          ),
        ],
      );
    },
  );
}

/// Вертикальная граница между рецептом и правой панелью. Она намеренно шире
/// одной линии, чтобы её было удобно захватывать мышью.
class _ColumnResizeHandle extends StatelessWidget {
  const _ColumnResizeHandle({
    super.key,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  final ValueChanged<double> onDragUpdate;
  final VoidCallback onDragEnd;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.resizeColumn,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: (details) => onDragUpdate(details.delta.dx),
      onHorizontalDragEnd: (_) => onDragEnd(),
      child: SizedBox(
        width: 9,
        child: Center(
          child: VerticalDivider(
            width: 1,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
    ),
  );
}

/// Горизонтальная граница для вертикальной раскладки: меняет высоту нижней
/// панели и остаётся удобной для захвата пальцем или мышью.
class _RowResizeHandle extends StatelessWidget {
  const _RowResizeHandle({
    super.key,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  final ValueChanged<double> onDragUpdate;
  final VoidCallback onDragEnd;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.resizeRow,
    child: GestureDetector(
      key: const ValueKey('bottom-panel-resize-handle'),
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: (details) => onDragUpdate(details.delta.dy),
      onVerticalDragEnd: (_) => onDragEnd(),
      child: SizedBox(
        height: 9,
        child: Center(
          child: Divider(
            height: 1,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
    ),
  );
}

class _RecipeNotes extends StatelessWidget {
  const _RecipeNotes({
    required this.controller,
    required this.servingsController,
    required this.servingsFocusNode,
    required this.onServingsEditingComplete,
    required this.servings,
    required this.similarRecipes,
    required this.onOpenSimilarRecipe,
    required this.nutrition,
    required this.onServingsChanged,
    required this.recipePhotoPath,
    required this.recipePhotoBytes,
    required this.savingRecipePhoto,
    required this.onPickRecipePhoto,
    required this.revealRecipePhoto,
  });
  final TextEditingController controller;
  final TextEditingController servingsController;
  final FocusNode servingsFocusNode;
  final VoidCallback onServingsEditingComplete;
  final int servings;
  final List<CatalogRecipe> similarRecipes;
  final ValueChanged<CatalogRecipe> onOpenSimilarRecipe;
  final NutritionTotals nutrition;
  final ValueChanged<int> onServingsChanged;
  final String? recipePhotoPath;
  final Uint8List? recipePhotoBytes;
  final bool savingRecipePhoto;
  final VoidCallback onPickRecipePhoto;
  final bool revealRecipePhoto;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final portrait =
          MediaQuery.sizeOf(context).height > MediaQuery.sizeOf(context).width;
      // В портретном режиме фото не должно вытеснять всю правую/нижнюю
      // панель. При достаточной ширине показатели занимают остаток той же
      // строки; при увеличении масштаба строка естественно вернётся в столбец.
      final useHeaderRow = portrait && constraints.maxWidth >= 460;
      final photo = _RecipePhotoPanel(
        path: recipePhotoPath,
        bytes: recipePhotoBytes,
        saving: savingRecipePhoto,
        onPick: onPickRecipePhoto,
        reveal: revealRecipePhoto,
      );
      final header = useHeaderRow
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: (constraints.maxWidth * .36).clamp(132.0, 210.0),
                  child: photo,
                ),
                const SizedBox(width: 16),
                Expanded(child: _servingsAndNutrition(context)),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                photo,
                const SizedBox(height: 12),
                _servingsAndNutrition(context),
              ],
            );
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            header,
            const SizedBox(height: 8),
            Text('Примечания', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: TextField(
                key: const ValueKey('recipe-notes-field'),
                controller: controller,
                minLines: 2,
                maxLines: 12,
                textAlignVertical: TextAlignVertical.top,
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'Ваши впечатления или замечания по рецепту',
                  alignLabelWithHint: true,
                ),
              ),
            ),
            if (similarRecipes.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'Похожие рецепты',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              for (final recipe in similarRecipes)
                Card(
                  margin: const EdgeInsets.only(bottom: 6),
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    onTap: () => onOpenSimilarRecipe(recipe),
                    dense: true,
                    leading: const Icon(Icons.restaurant_menu),
                    title: Text(recipe.title),
                    subtitle: Text(
                      similarRecipeIngredientPreview(recipe),
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
            ],
          ],
        ),
      );
    },
  );

  Widget _servingsAndNutrition(BuildContext context) => SizedBox(
    width: double.infinity,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final field = _servingsField();
        final nutritionSummary = _nutritionSummary(context);
        // Поле порций вместе с краткой КБЖУ уверенно помещается примерно от
        // 320 px; более ранний перенос создавал лишнее движение на телефонах.
        final narrow = constraints.maxWidth < 320;
        final layout = narrow
            ? Column(
                key: const ValueKey('servings-nutrition-narrow'),
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [field, const SizedBox(height: 10), nutritionSummary],
              )
            : Row(
                key: const ValueKey('servings-nutrition-wide'),
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [field, const SizedBox(width: 16), nutritionSummary],
              );
        return Align(
          alignment: Alignment.center,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SizeTransition(
                sizeFactor: animation,
                axisAlignment: -1,
                child: child,
              ),
            ),
            child: layout,
          ),
        );
      },
    ),
  );

  Widget _servingsField() => SizedBox(
    width: 118,
    height: 42,
    child: TextField(
      key: const ValueKey('recipe-servings-field'),
      controller: servingsController,
      focusNode: servingsFocusNode,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        isDense: true,
        suffixText: servingsWord(servings),
      ),
      onChanged: (text) {
        final value = int.tryParse(text);
        if (value != null && value >= 1 && value <= 256) {
          onServingsChanged(value);
        }
      },
      onTapOutside: (_) => onServingsEditingComplete(),
    ),
  );

  Widget _nutritionSummary(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('На порцию:', style: Theme.of(context).textTheme.titleSmall),
      _NutritionSummary(nutrition: nutrition),
    ],
  );
}

/// Квадратная область фотографии с ленивой декодировкой файла. Крышка сначала
/// закрывает снимок, затем поднимается вверх, открывая его снизу.
class _RecipePhotoPanel extends StatefulWidget {
  const _RecipePhotoPanel({
    required this.path,
    required this.bytes,
    required this.saving,
    required this.onPick,
    required this.reveal,
  });

  final String? path;
  final Uint8List? bytes;
  final bool saving;
  final VoidCallback onPick;
  final bool reveal;

  @override
  State<_RecipePhotoPanel> createState() => _RecipePhotoPanelState();
}

class _RecipePhotoPanelState extends State<_RecipePhotoPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _revealController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1050),
  );
  ImageStream? _imageStream;
  ImageStreamListener? _imageListener;
  bool _imageReady = false;
  bool _revealStarted = false;

  @override
  void initState() {
    super.initState();
    // Первый кадр всегда рисуется только с крышкой. Декодирование запускается
    // после него в фоне, а подъём разрешается лишь по ImageStreamListener.
    if (widget.path != null || widget.bytes != null) _queueImageLoad();
  }

  @override
  void didUpdateWidget(covariant _RecipePhotoPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final photoChanged =
        widget.path != oldWidget.path || widget.bytes != oldWidget.bytes;
    if (photoChanged) _queueImageLoad();
    if (widget.reveal && !oldWidget.reveal) _queueRevealIfReady();
  }

  ImageProvider<Object>? _photoProvider() {
    final bytes = widget.bytes;
    if (bytes != null) return MemoryImage(bytes);
    final path = widget.path;
    return path == null ? null : FileImage(File(path));
  }

  void _queueImageLoad() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) _loadImageInBackground();
  });

  void _loadImageInBackground() {
    final previousStream = _imageStream;
    final previousListener = _imageListener;
    if (previousStream != null && previousListener != null) {
      previousStream.removeListener(previousListener);
    }
    _imageListener = null;
    _imageStream = null;
    _revealController.reset();
    _revealStarted = false;
    _imageReady = false;
    final provider = _photoProvider();
    if (provider == null) return;
    final stream = provider.resolve(createLocalImageConfiguration(context));
    final listener = ImageStreamListener(
      (_, _) {
        if (!mounted || !identical(stream, _imageStream)) return;
        setState(() => _imageReady = true);
        _queueRevealIfReady();
      },
      onError: (_, __) {
        // Нераскодированное изображение не имитируем анимацией: крышка
        // остаётся закрытой, а пользователь может выбрать другой файл.
      },
    );
    _imageStream = stream;
    _imageListener = listener;
    stream.addListener(listener);
  }

  void _queueRevealIfReady() =>
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.reveal && _imageReady && !_revealStarted) {
          _startReveal();
        }
      });

  void _startReveal() {
    if (_revealStarted || !_imageReady || !widget.reveal) return;
    _revealStarted = true;
    _revealController
      ..reset()
      ..forward();
  }

  @override
  void dispose() {
    final stream = _imageStream;
    final listener = _imageListener;
    if (stream != null && listener != null) stream.removeListener(listener);
    _revealController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final photoPath = widget.path;
    final photoBytes = widget.bytes;
    final hasPhoto = photoPath != null || photoBytes != null;
    final colors = Theme.of(context).colorScheme;
    return AspectRatio(
      aspectRatio: 1,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceContainerHighest,
            border: Border.all(color: colors.outlineVariant),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (hasPhoto && _imageReady)
                AnimatedBuilder(
                  animation: _revealController,
                  builder: (context, _) {
                    final value = Curves.easeOutCubic.transform(
                      _revealController.value,
                    );
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        ClipRect(
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            heightFactor: value,
                            child: photoBytes != null
                                ? Image.memory(
                                    photoBytes,
                                    fit: BoxFit.cover,
                                    width: double.infinity,
                                    height: double.infinity,
                                    errorBuilder: (_, _, _) => const SizedBox(),
                                  )
                                : Image.file(
                                    File(photoPath!),
                                    fit: BoxFit.cover,
                                    width: double.infinity,
                                    height: double.infinity,
                                    errorBuilder: (_, _, _) => const SizedBox(),
                                  ),
                          ),
                        ),
                        if (value < 0.999)
                          FractionalTranslation(
                            translation: Offset(0, -value),
                            child: const _RecipePhotoLid(),
                          ),
                      ],
                    );
                  },
                )
              else
                const _RecipePhotoLid(),
              if (widget.saving)
                const Center(child: CircularProgressIndicator())
              else
                Align(
                  alignment: Alignment.topLeft,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Material(
                      color: colors.surface.withValues(alpha: 0.88),
                      borderRadius: BorderRadius.circular(10),
                      child: IconButton(
                        tooltip: hasPhoto
                            ? 'Заменить фотографию'
                            : 'Добавить фотографию',
                        onPressed: widget.onPick,
                        icon: const Icon(Icons.add_photo_alternate_outlined),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecipePhotoLid extends StatelessWidget {
  const _RecipePhotoLid();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ColoredBox(
      // Неподвижная часть — ровно фон правой панели, а не полупрозрачный
      // квадрат поверх снимка. Изображение становится видно только там,
      // откуда крышка уже поднялась.
      color: colors.surface,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final diameter = constraints.maxWidth;
          return Align(
            alignment: Alignment.bottomCenter,
            child: CustomPaint(
              size: Size(diameter, diameter / 2),
              painter: _PanLidPainter(
                light: colors.surfaceContainerHighest,
                middle: colors.outlineVariant,
                dark: colors.outline,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Крышка — не отдельная квадратная картинка: это полукруг, чей диаметр
/// совпадает с шириной фотографии, а прямая кромка всегда касается её низа.
class _PanLidPainter extends CustomPainter {
  const _PanLidPainter({
    required this.light,
    required this.middle,
    required this.dark,
  });

  final Color light;
  final Color middle;
  final Color dark;

  @override
  void paint(Canvas canvas, Size size) {
    final diameter = size.width;
    final lidPath = Path()
      ..moveTo(0, size.height)
      ..arcTo(Rect.fromLTWH(0, 0, diameter, diameter), math.pi, math.pi, false)
      ..close();
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [light, middle, light],
        stops: const [0, .58, 1],
      ).createShader(Offset.zero & size);
    canvas.drawPath(lidPath, paint);
    canvas.drawPath(
      lidPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = dark,
    );
    final handleWidth = diameter * .28;
    final handleHeight = size.height * .14;
    final handle = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(diameter / 2, size.height * .64),
        width: handleWidth,
        height: handleHeight,
      ),
      Radius.circular(handleHeight),
    );
    canvas.drawRRect(handle, Paint()..color = dark);
  }

  @override
  bool shouldRepaint(covariant _PanLidPainter oldDelegate) =>
      light != oldDelegate.light ||
      middle != oldDelegate.middle ||
      dark != oldDelegate.dark;
}

/// Диалог без сторонних UI-пакетов: полупрозрачная квадратная рамка тянется
/// пальцем или мышью, а ползунок меняет её сторону.
class _SquarePhotoCropDialog extends StatefulWidget {
  const _SquarePhotoCropDialog({required this.sourceBytes});
  final Uint8List sourceBytes;

  @override
  State<_SquarePhotoCropDialog> createState() => _SquarePhotoCropDialogState();
}

class _SquarePhotoCropDialogState extends State<_SquarePhotoCropDialog> {
  late final image.Image? _source = RecipePhotoStorage.decode(
    widget.sourceBytes,
  );
  late final double _minimumSide = (_source == null
      ? 1
      : (_source!.width < _source!.height ? _source!.width : _source!.height) *
            0.2);
  late double _side = _source == null
      ? 1
      : (_source!.width < _source!.height ? _source!.width : _source!.height)
            .toDouble();
  double _left = 0;
  double _top = 0;

  void _keepCropInsideSource() {
    if (_source == null) return;
    _left = _left.clamp(0, _source!.width - _side).toDouble();
    _top = _top.clamp(0, _source!.height - _side).toDouble();
  }

  Rect _normalizedCrop() => Rect.fromLTRB(
    _left / _source!.width,
    _top / _source!.height,
    (_left + _side) / _source!.width,
    (_top + _side) / _source!.height,
  );

  @override
  Widget build(BuildContext context) {
    if (_source == null) {
      return AlertDialog(
        title: const Text('Не удалось открыть изображение'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Закрыть'),
          ),
        ],
      );
    }
    final source = _source!;
    final maxSide =
        (source.width < source.height ? source.width : source.height)
            .toDouble();
    return AlertDialog(
      title: const Text('Обрезать фотографию'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.48,
              child: Center(
                child: AspectRatio(
                  aspectRatio: source.width / source.height,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final scale = constraints.maxWidth / source.width;
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.memory(widget.sourceBytes, fit: BoxFit.fill),
                          Positioned(
                            left: _left * scale,
                            top: _top * scale,
                            width: _side * scale,
                            height: _side * scale,
                            child: GestureDetector(
                              onPanUpdate: (details) => setState(() {
                                _left += details.delta.dx / scale;
                                _top += details.delta.dy / scale;
                                _keepCropInsideSource();
                              }),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 3,
                                  ),
                                  color: Colors.black.withValues(alpha: 0.12),
                                ),
                                child: const Center(
                                  child: Icon(
                                    Icons.open_with,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
            Slider(
              value: _side,
              min: _minimumSide,
              max: maxSide,
              label: '${_side.round()} px',
              onChanged: (value) => setState(() {
                _side = value;
                _keepCropInsideSource();
              }),
            ),
            const Text('Перетащите квадрат и выберите его размер.'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _normalizedCrop()),
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}

/// Три ведущих ингредиента и подсказка, что список продолжается.
/// При уменьшении колонки стандартное многоточие Flutter заменяет конец
/// строки, не позволяя подписи выйти за границы карточки.
String similarRecipeIngredientPreview(CatalogRecipe recipe) {
  final ingredients = recipe.ingredientsByAmount;
  final preview = ingredients.take(3).join(', ');
  return ingredients.length > 3 ? '$preview, …' : preview;
}

/// Подбирает русскую форму слова «порция» для целого количества.
String servingsWord(int value) {
  final lastTwoDigits = value % 100;
  if (lastTwoDigits >= 11 && lastTwoDigits <= 14) return 'порций';
  return switch (value % 10) {
    1 => 'порция',
    2 || 3 || 4 => 'порции',
    _ => 'порций',
  };
}

class _NutritionSummary extends StatelessWidget {
  const _NutritionSummary({required this.nutrition});
  final NutritionTotals nutrition;

  String _number(double value) => value.toStringAsFixed(1).replaceAll('.0', '');

  @override
  Widget build(BuildContext context) => SelectableText(
    'Калории: ${_number(nutrition.kilocalories)} ккал\n'
    'Белки: ${_number(nutrition.protein)} г\n'
    'Жиры: ${_number(nutrition.fat)} г\n'
    'Углеводы: ${_number(nutrition.carbohydrates)} г',
    style: Theme.of(context).textTheme.bodyLarge,
  );
}

class _CardLibrary extends StatefulWidget {
  const _CardLibrary({
    required this.showGrammar,
    required this.onDiscard,
    required this.showDiscardOverlay,
    required this.compactModules,
    required this.compactVertical,
    required this.onToggleCompactModules,
  });
  final bool showGrammar;
  final ValueChanged<_NodeDrag> onDiscard;
  final bool showDiscardOverlay;
  final bool compactModules;
  final bool compactVertical;
  final VoidCallback onToggleCompactModules;

  @override
  State<_CardLibrary> createState() => _CardLibraryState();
}

class _CardLibraryState extends State<_CardLibrary> {
  String _query = '';

  static const _characteristicIds = {'characteristic.shape'};

  static const _applianceIds = {
    'utensil.grater',
    'utensil.sieve',
    'utensil.colander',
    'utensil.meat-grinder',
    'utensil.whisk',
    'utensil.rolling-pin',
  };

  static final _cardsByKind = <CardKind, List<CardDefinition>>{
    for (final kind in CardKind.values)
      kind: searchAndSortByLabel(
        CatalogCards.all.where((card) => card.kind == kind),
        query: '',
        labelOf: (card) => card.nominative,
      ),
  };

  /// Песочница использует ту же единственную классификацию, что и фильтры
  /// поиска. Новая группа или карточка не требуют второго списка идентификаторов.
  static final _ingredientsByGroup = <IngredientGroup, List<CardDefinition>>{
    for (final group in IngredientGroup.values)
      group: _cardsByKind[CardKind.ingredient]!
          .where((card) => CatalogCards.ingredientGroup(card) == group)
          .toList(),
  };

  static final _actions = _cardsByKind[CardKind.action]!
      .where(
        (card) =>
            !cookingActionCardIds.contains(card.id) &&
            !preparationActionCardIds.contains(card.id) &&
            !assemblyActionCardIds.contains(card.id),
      )
      .toList();

  static final _cookingActions = _cardsByKind[CardKind.action]!
      .where((card) => cookingActionCardIds.contains(card.id))
      .toList();

  static final _preparationActions = _cardsByKind[CardKind.action]!
      .where((card) => preparationActionCardIds.contains(card.id))
      .toList();

  static final _assemblyActions = _cardsByKind[CardKind.action]!
      .where((card) => assemblyActionCardIds.contains(card.id))
      .toList();

  static final _quantities = _cardsByKind[CardKind.quantity]!
      .where((card) => !_characteristicIds.contains(card.id))
      .toList();

  static final _characteristics = _cardsByKind[CardKind.quantity]!
      .where((card) => _characteristicIds.contains(card.id))
      .toList();

  static final _appliances = _cardsByKind[CardKind.utensil]!
      .where((card) => _applianceIds.contains(card.id))
      .toList();

  static final _utensils = _cardsByKind[CardKind.utensil]!
      .where((card) => !_applianceIds.contains(card.id))
      .toList();

  List<CardDefinition> _matching(List<CardDefinition> cards) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return cards;
    return cards
        .where((card) => card.nominative.toLowerCase().contains(query))
        .toList();
  }

  Widget _section(String title, List<CardDefinition> cards) {
    final matchingCards = _matching(cards);
    if (matchingCards.isEmpty) return const SizedBox.shrink();
    return _Section(
      title,
      matchingCards,
      compact: widget.compactModules,
      compactVertical: widget.compactVertical,
    );
  }

  @override
  Widget build(BuildContext context) => DragTarget<Object>(
    onWillAcceptWithDetails: (details) => details.data is _NodeDrag,
    onAcceptWithDetails: (details) =>
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => widget.onDiscard(details.data as _NodeDrag),
        ),
    builder: (context, candidates, rejected) => Stack(
      fit: StackFit.expand,
      children: [
        ListView(
          padding: EdgeInsets.all(widget.compactVertical ? 5 : 16),
          children: [
            const Text(
              'Модули',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: widget.compactVertical ? 4 : 12),
            SearchBar(
              key: const ValueKey('sandbox-module-search'),
              onChanged: (query) => setState(() => _query = query),
              hintText: 'Поиск карточек',
              trailing: [
                IconButton(
                  key: const ValueKey('sandbox-display-mode'),
                  onPressed: widget.onToggleCompactModules,
                  icon: Icon(
                    widget.compactModules
                        ? Icons.view_agenda_outlined
                        : Icons.grid_view_rounded,
                  ),
                  tooltip: widget.compactModules
                      ? 'Показывать названия модулей'
                      : 'Показывать только пиктограммы',
                ),
              ],
            ),
            SizedBox(height: widget.compactVertical ? 4 : 16),
            _section('Подготовка', _preparationActions),
            _section('Сборка', _assemblyActions),
            _section('Готовка', _cookingActions),
            _section('Действия', _actions),
            ...IngredientGroup.values.map(
              (group) => _section(group.title, _ingredientsByGroup[group]!),
            ),
            _section('Количество', _quantities),
            _section('Характеристики', _characteristics),
            _section('Приборы', _appliances),
            _section('Утварь', _utensils),
            _section('Иное', _cardsByKind[CardKind.text]!),
          ],
        ),
        if (widget.showDiscardOverlay)
          const IgnorePointer(child: _DiscardOverlay()),
      ],
    ),
  );
}

class _Section extends StatelessWidget {
  const _Section(
    this.title,
    this.cards, {
    this.compact = false,
    this.compactVertical = false,
  });
  final String title;
  final List<CardDefinition> cards;
  final bool compact;
  final bool compactVertical;
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: compactVertical ? 7 : 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        SizedBox(height: compactVertical ? 3 : 6),
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(compactVertical ? 4 : 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: compact
              ? _CompactModuleGrid(
                  cards: cards,
                  compactVertical: compactVertical,
                )
              : Wrap(
                  // Полное и пиктографическое представления используют одну
                  // плотность строк. В карточках нет внешнего Card-margin,
                  // поэтому названия не раздвигают сетку в портрете.
                  spacing: compactVertical ? 2 : 6,
                  runSpacing: compactVertical ? 2 : 6,
                  children: [
                    for (final card in cards)
                      _SandboxModuleDraggable(card: card),
                  ],
                ),
        ),
      ],
    ),
  );
}

class _SandboxModuleDraggable extends StatelessWidget {
  const _SandboxModuleDraggable({
    required this.card,
    this.compact = false,
    this.forceShowLabel = false,
    this.expandLeft = false,
    this.onHoverChanged,
    this.moduleKey,
  });

  final CardDefinition card;
  final bool compact;
  final bool forceShowLabel;
  final bool expandLeft;
  final void Function(bool active, Offset position)? onHoverChanged;
  final GlobalKey? moduleKey;

  @override
  Widget build(BuildContext context) => Draggable<Object>(
    data: card,
    feedback: Material(
      color: Colors.transparent,
      child: _ModuleCard(card: card),
    ),
    childWhenDragging: Opacity(
      opacity: .3,
      child: _ModuleCard(card: card, compact: compact),
    ),
    child: _ModuleCard(
      key: moduleKey,
      card: card,
      compact: compact,
      forceShowLabel: forceShowLabel,
      expandLeft: expandLeft,
      onHoverChanged: onHoverChanged,
    ),
  );
}

/// Управляемая раскладка пиктограмм песочницы.
///
/// Обычный Wrap при раскрытии подписи переносит именно наведённую карточку;
/// указатель оказывается за её границей, и она тут же схлопывается. Здесь
/// подпись сначала расходится вправо в свободное место строки. Только её
/// недостающая часть растёт влево, а пересекающиеся элементы плавно уходят
/// на следующую строку.
class _CompactModuleGrid extends StatefulWidget {
  const _CompactModuleGrid({
    required this.cards,
    required this.compactVertical,
  });
  final List<CardDefinition> cards;
  final bool compactVertical;

  @override
  State<_CompactModuleGrid> createState() => _CompactModuleGridState();
}

class _CompactModuleGridState extends State<_CompactModuleGrid> {
  String? _activeCardId;
  Timer? _hoverLockTimer;
  bool _hoverChangesLocked = false;
  Offset? _lastPointerPosition;
  final Map<String, GlobalKey> _moduleKeys = {};

  GlobalKey _moduleKey(String cardId) =>
      _moduleKeys.putIfAbsent(cardId, GlobalKey.new);

  @override
  void dispose() {
    _hoverLockTimer?.cancel();
    super.dispose();
  }

  void _lockHoverChanges() {
    _hoverLockTimer?.cancel();
    _hoverChangesLocked = true;
    // AnimatedPositioned и раскрытие подписи длятся 160 мс. Небольшой запас
    // не даёт карточкам, пролетающим под неподвижным курсором, перехватить
    // фокус на последнем кадре анимации.
    _hoverLockTimer = Timer(const Duration(milliseconds: 190), () {
      if (!mounted) return;
      setState(() {
        _hoverChangesLocked = false;
        // MouseRegion может прислать onExit во время блокировки, когда
        // карточка исчезла из-под курсора из-за drag-and-drop. После паузы
        // проверяем реальные границы, а не ждём ещё одного события мыши.
        if (!_pointerIsOverActiveCard()) _activeCardId = null;
      });
    });
  }

  bool _pointerIsOverActiveCard() {
    final activeCardId = _activeCardId;
    final pointer = _lastPointerPosition;
    final context = activeCardId == null
        ? null
        : _moduleKeys[activeCardId]?.currentContext;
    if (pointer == null || context == null) return false;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return false;
    return box.size.contains(box.globalToLocal(pointer));
  }

  void _setActive(String cardId, bool active, Offset position) {
    _lastPointerPosition = position;
    if (active) {
      if (_hoverChangesLocked && _activeCardId != cardId) return;
      if (_activeCardId != cardId) setState(() => _activeCardId = cardId);
      _lockHoverChanges();
    } else if (_activeCardId == cardId && !_hoverChangesLocked) {
      setState(() => _activeCardId = null);
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final gap = widget.compactVertical ? _sandboxCompactGap : 6.0;
      final horizontalPadding = widget.compactVertical
          ? _sandboxCompactHorizontalPadding
          : _sandboxRegularHorizontalPadding;
      final verticalPadding = widget.compactVertical ? 2.0 : 8.0;
      final compactWidth = _sandboxIconSize + horizontalPadding * 2;
      final lineHeight = _sandboxIconSize + verticalPadding * 2;
      final textStyle = Theme.of(context).textTheme.bodyMedium;
      final labelWidths = {
        for (final card in widget.cards)
          card.id: TextPainter(
            text: TextSpan(text: card.nominative, style: textStyle),
            textDirection: Directionality.of(context),
            maxLines: 1,
          )..layout(),
      };
      double expandedWidth(String cardId) => _sandboxExpandedWidth(
        cardId,
        compactWidth,
        labelWidths,
        widget.compactVertical,
      ).clamp(compactWidth, constraints.maxWidth).toDouble();
      final compactPositions = <int, Offset>{};
      final compactRows = <int, int>{};
      var x = 0.0;
      var row = 0;
      for (final entry in widget.cards.indexed) {
        if (x > 0 && x + compactWidth > constraints.maxWidth) {
          x = 0;
          row++;
        }
        compactPositions[entry.$1] = Offset(x, row * (lineHeight + gap));
        compactRows[entry.$1] = row;
        x += compactWidth + gap;
      }

      final activeIndex = widget.cards.indexWhere(
        (card) => card.id == _activeCardId,
      );
      final positions = Map<int, Offset>.from(compactPositions);
      var maximumRow = row;
      if (activeIndex >= 0) {
        final activePosition = compactPositions[activeIndex]!;
        final activeRow = compactRows[activeIndex]!;
        // Между пиктограммой и подписью используется отдельный фиксированный
        // интервал, а не межкарточный [gap]. Раньше эти величины путались,
        // из-за чего раскрытая карточка оказывалась шире рассчитанной ячейки.
        final fullWidth = expandedWidth(_activeCardId!);
        final activeRight = activePosition.dx + compactWidth;
        final extraWidth = fullWidth - compactWidth;
        // Сначала используем свободное место справа. Если его недостаточно,
        // ровно остаток раскрываем влево: для 200 px при 100 px справа это
        // будет 100 px вправо и 100 px влево.
        final expandRight = extraWidth.clamp(
          0.0,
          (constraints.maxWidth - activeRight).clamp(0.0, double.infinity),
        );
        final activeLeft = (activePosition.dx - (extraWidth - expandRight))
            .clamp(0.0, double.infinity);
        positions[activeIndex] = Offset(activeLeft, activePosition.dy);

        // Пиктограммы слева, которые пересекает левая часть раскрытия,
        // уходят вниз. Пиктограммы справа сначала сдвигаются вправо на
        // величину раскрытия; вниз переходит только та, которой после этого
        // действительно перестало хватать строки.
        final displaced = <int>[
          for (var index = 0; index < activeIndex; index++)
            if (compactRows[index] == activeRow &&
                compactPositions[index]!.dx + compactWidth + gap > activeLeft)
              index,
        ];
        for (
          var index = activeIndex + 1;
          index < widget.cards.length && compactRows[index] == activeRow;
          index++
        ) {
          final shiftedX = compactPositions[index]!.dx + expandRight;
          if (shiftedX + compactWidth <= constraints.maxWidth) {
            positions[index] = Offset(shiftedX, activePosition.dy);
          } else {
            displaced.add(index);
          }
        }
        final following = <int>[
          ...displaced,
          for (var index = 0; index < widget.cards.length; index++)
            if (compactRows[index]! > activeRow) index,
        ];
        var carriedX = 0.0;
        var carriedRow = activeRow + 1;
        for (final index in following) {
          if (carriedX > 0 && carriedX + compactWidth > constraints.maxWidth) {
            carriedX = 0;
            carriedRow++;
          }
          positions[index] = Offset(carriedX, carriedRow * (lineHeight + gap));
          carriedX += compactWidth + gap;
          maximumRow = maximumRow < carriedRow ? carriedRow : maximumRow;
        }
      }

      return SizedBox(
        height: (maximumRow + 1) * lineHeight + maximumRow * gap,
        child: Stack(
          // Любая промежуточная геометрия AnimatedPositioned остаётся внутри
          // секции; пиктограммы не могут «выехать» за её края.
          clipBehavior: Clip.hardEdge,
          children: [
            for (final entry in widget.cards.indexed)
              AnimatedPositioned(
                key: ValueKey('compact-module-position-${entry.$2.id}'),
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOutCubic,
                left: positions[entry.$1]!.dx,
                top: positions[entry.$1]!.dy,
                child: SizedBox(
                  // Фиксируем реальную ширину закрытой ячейки. При раскрытии
                  // размер становится ровно вычисленным [fullWidth], поэтому
                  // крайние пиктограммы не выходят за контейнер.
                  width: entry.$2.id == _activeCardId
                      ? expandedWidth(entry.$2.id)
                      : compactWidth,
                  child: _SandboxModuleDraggable(
                    card: entry.$2,
                    compact: true,
                    forceShowLabel: entry.$2.id == _activeCardId,
                    onHoverChanged: (active, position) =>
                        _setActive(entry.$2.id, active, position),
                    moduleKey: _moduleKey(entry.$2.id),
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}

class _ModuleCard extends StatefulWidget {
  const _ModuleCard({
    super.key,
    required this.card,
    this.dragHandle = true,
    this.compact = false,
    this.forceShowLabel = false,
    this.expandLeft = false,
    this.onHoverChanged,
  });
  final CardDefinition card;
  final bool dragHandle;
  final bool compact;
  final bool forceShowLabel;
  final bool expandLeft;
  final void Function(bool active, Offset position)? onHoverChanged;

  @override
  State<_ModuleCard> createState() => _ModuleCardState();
}

class _ModuleCardState extends State<_ModuleCard> {
  bool _hovering = false;

  bool get _showLabel => !widget.compact || widget.forceShowLabel || _hovering;

  @override
  Widget build(BuildContext context) {
    final background = moduleColor(context, widget.card.kind);
    final foreground = contrastColorFor(background);
    // На портретном экране карточки в песочнице и в дереве не должны
    // тратить высоту на настольный вертикальный воздух.
    final compactVertical = MediaQuery.sizeOf(context).width < 1000;
    final verticalPadding = compactVertical ? 2.0 : 8.0;
    final horizontalPadding = compactVertical
        ? _sandboxCompactHorizontalPadding
        : _sandboxRegularHorizontalPadding;
    return MouseRegion(
      onEnter: widget.compact
          ? (event) {
              setState(() => _hovering = true);
              widget.onHoverChanged?.call(true, event.position);
            }
          : null,
      onExit: widget.compact
          ? (event) {
              setState(() => _hovering = false);
              widget.onHoverChanged?.call(false, event.position);
            }
          : null,
      child: Semantics(
        label: widget.card.nominative,
        child: AnimatedSize(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          child: Card(
            // Внешний стандартный отступ Card добавлял невидимые 4 px с
            // каждой стороны только в полном режиме. Оставляем его нулевым
            // для обоих представлений — расстояние задаёт контейнер секции.
            margin: EdgeInsets.zero,
            color: background,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: horizontalPadding,
                vertical: verticalPadding,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_showLabel && widget.expandLeft)
                    _ModuleCardLabel(
                      show: _showLabel,
                      dragHandle: widget.dragHandle,
                      label: widget.card.nominative,
                      foreground: foreground,
                    ),
                  if (widget.dragHandle)
                    moduleIcon(
                      context,
                      widget.card,
                      size: 18,
                      color: foreground,
                    ),
                  if (!widget.expandLeft || !_showLabel)
                    _ModuleCardLabel(
                      show: _showLabel,
                      dragHandle: widget.dragHandle,
                      label: widget.card.nominative,
                      foreground: foreground,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ModuleCardLabel extends StatelessWidget {
  const _ModuleCardLabel({
    required this.show,
    required this.dragHandle,
    required this.label,
    required this.foreground,
  });

  final bool show;
  final bool dragHandle;
  final String label;
  final Color foreground;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: const Duration(milliseconds: 160),
    switchInCurve: Curves.easeOutCubic,
    switchOutCurve: Curves.easeInCubic,
    transitionBuilder: (child, animation) => FadeTransition(
      opacity: animation,
      child: SizeTransition(
        axis: Axis.horizontal,
        sizeFactor: animation,
        child: child,
      ),
    ),
    child: show
        ? Row(
            key: const ValueKey('label'),
            mainAxisSize: MainAxisSize.min,
            children: [
              if (dragHandle)
                SizedBox(
                  width: MediaQuery.sizeOf(context).width < 1000
                      ? _sandboxCompactLabelGap
                      : _sandboxRegularLabelGap,
                ),
              Text(label, style: TextStyle(color: foreground)),
            ],
          )
        : const SizedBox(key: ValueKey('icon-only')),
  );
}

class _RecipeCanvas extends StatefulWidget {
  const _RecipeCanvas({
    super.key,
    required this.title,
    required this.titleController,
    required this.onTitleChanged,
    required this.steps,
    required this.editing,
    required this.modeTransition,
    required this.modeTransitionFromEditing,
    required this.modeDragging,
    required this.moduleDragging,
    required this.renderer,
    required this.showVisuals,
    required this.servings,
    required this.recipeMultiplier,
    required this.recipeMultiplierController,
    required this.onRecipeMultiplierChanged,
    required this.category,
    required this.onCategoryChanged,
    required this.fasting,
    required this.onFastingChanged,
    required this.canDrop,
    required this.onDrop,
    this.compact = false,
    required this.compactVertical,
    required this.onModuleDragChanged,
    required this.hideTitle,
    this.entranceTitleAnchor,
    this.entranceIngredientAnchors,
  });
  final String title;
  final TextEditingController titleController;
  final ValueChanged<String> onTitleChanged;
  final List<RecipeNode> steps;
  final bool editing;
  final Animation<double> modeTransition;
  final bool modeTransitionFromEditing;
  final bool modeDragging;

  /// Пока модуль находится в руках, зоны вставки расширяют только область
  /// попадания. Это даёт допуск ±50 px, не раздвигая обычное дерево.
  final bool moduleDragging;
  final RecipeRenderer renderer;
  final bool showVisuals;
  final int servings;
  final int recipeMultiplier;
  final TextEditingController recipeMultiplierController;
  final ValueChanged<int> onRecipeMultiplierChanged;
  final RecipeCategory category;
  final ValueChanged<RecipeCategory> onCategoryChanged;
  final RecipeFasting fasting;
  final ValueChanged<RecipeFasting> onFastingChanged;
  final bool Function(Object, RecipeNode?) canDrop;
  final void Function(Object, List<RecipeNode>, int, {RecipeNode? parent})
  onDrop;
  final bool compact;
  final bool compactVertical;
  final ValueChanged<bool> onModuleDragChanged;
  final bool hideTitle;
  final GlobalKey? entranceTitleAnchor;
  final Map<String, GlobalKey>? entranceIngredientAnchors;

  @override
  State<_RecipeCanvas> createState() => _RecipeCanvasState();
}

class _RecipeCanvasState extends State<_RecipeCanvas> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _editorColumnKey = GlobalKey();
  Timer? _outlineHideTimer;
  bool _showMobileOutline = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_showOutlineWhileScrolling);
  }

  void _showOutlineWhileScrolling() {
    _outlineHideTimer?.cancel();
    if (!_showMobileOutline && mounted) {
      setState(() => _showMobileOutline = true);
    }
    _outlineHideTimer = Timer(const Duration(seconds: 1), () {
      if (mounted) setState(() => _showMobileOutline = false);
    });
  }

  @override
  void dispose() {
    _outlineHideTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  /// Каждая входная подпись получает якорь на конкретном первом узле
  /// ингредиента, а не на совпадении его русского написания в строке.
  /// Идентификатор узла устойчив к падежу, повторению слова и свободному
  /// тексту внутри другого модуля.
  Map<String, GlobalKey> _entranceNodeAnchors() {
    final anchors = widget.entranceIngredientAnchors;
    if (anchors == null || anchors.isEmpty) return const {};
    final firstNodeIds = firstIngredientNodeIds(widget.steps, anchors.keys);
    return {
      for (final entry in firstNodeIds.entries)
        entry.value: anchors[entry.key]!,
    };
  }

  Widget _stepEntry(int index, RecipeNode node) => AnimatedSize(
    duration: const Duration(milliseconds: 390),
    curve: Curves.easeInOutQuart,
    alignment: Alignment.topLeft,
    child: _SequentialStepModeSwitch(
      editing: widget.editing,
      animation: widget.modeTransition,
      fromEditing: widget.modeTransitionFromEditing,
      dragging: widget.modeDragging,
      editor: Row(
        // Номер — самостоятельный элемент слева от корневой карточки
        // в обоих представлениях рецепта. Он не входит в текст шага.
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _StepNumber(number: index + 1, kind: node.card.kind),
          const SizedBox(width: 8),
          Flexible(
            child: _TreeEditor(
              node: node,
              source: widget.steps,
              canDrop: widget.canDrop,
              onDrop: widget.onDrop,
              onModuleDragChanged: widget.onModuleDragChanged,
              moduleDragging: widget.moduleDragging,
              compactLayout: widget.compactVertical,
            ),
          ),
        ],
      ),
      viewer: _RenderedStep(
        number: index + 1,
        kind: node.card.kind,
        parts: widget.renderer.renderParts(
          node,
          servings: widget.servings,
          recipeMultiplier: widget.recipeMultiplier,
        ),
        visualKey: widget.renderer.visualKey(node),
        showVisual: widget.showVisuals,
        compactVertical: widget.compactVertical,
        entranceNodeAnchors: _entranceNodeAnchors(),
        hideEntranceIngredients: widget.hideTitle,
      ),
    ),
  );

  Widget _recipeList(BuildContext context) => ScrollConfiguration(
    behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
    child: ListView(
      controller: _scrollController,
      padding: EdgeInsets.all(widget.compactVertical ? 8 : 28),
      children: [
        Opacity(
          opacity: widget.hideTitle ? 0 : 1,
          child: widget.editing
              ? TextField(
                  controller: widget.titleController,
                  maxLength: 120,
                  style: Theme.of(context).textTheme.headlineMedium,
                  decoration: const InputDecoration(
                    labelText: 'Название рецепта',
                    counterText: '',
                    isDense: true,
                  ),
                  onChanged: widget.onTitleChanged,
                )
              : Text(
                  key: widget.entranceTitleAnchor,
                  widget.title,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
        ),
        SizedBox(height: widget.compactVertical ? 5 : 18),
        AnimatedSize(
          duration: const Duration(milliseconds: 390),
          curve: Curves.easeInOutQuart,
          alignment: Alignment.topLeft,
          child: widget.editing
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _RecipeMultiplierEditor(
                      controller: widget.recipeMultiplierController,
                      value: widget.recipeMultiplier,
                      onChanged: widget.onRecipeMultiplierChanged,
                    ),
                    SizedBox(height: widget.compactVertical ? 5 : 18),
                  ],
                )
              : const SizedBox.shrink(),
        ),
        if (!widget.editing) ...[
          Row(
            children: [
              Expanded(
                child: _RecipeCategoryPicker(
                  value: widget.category,
                  onChanged: widget.onCategoryChanged,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _RecipeFastingPicker(
                  value: widget.fasting,
                  onChanged: widget.onFastingChanged,
                ),
              ),
            ],
          ),
          SizedBox(height: widget.compactVertical ? 5 : 18),
        ],
        ...widget.steps.indexed.expand(
          (entry) => [
            if (widget.editing)
              _InsertZone(
                parent: null,
                target: widget.steps,
                index: entry.$1,
                canDrop: widget.canDrop,
                onDrop: widget.onDrop,
                compact: widget.compactVertical,
                tolerant: widget.moduleDragging,
              ),
            _stepEntry(entry.$1, entry.$2),
          ],
        ),
        if (widget.editing)
          _InsertZone(
            parent: null,
            target: widget.steps,
            index: widget.steps.length,
            canDrop: widget.canDrop,
            onDrop: widget.onDrop,
            compact: widget.compactVertical,
            tolerant: widget.moduleDragging,
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final outline = _RecipeOutline(
        controller: _scrollController,
        steps: widget.steps,
      );
      final list = _recipeList(context);
      final isNarrow = constraints.maxWidth < 1000;
      return _EditorColumnBounds(
        boundaryKey: _editorColumnKey,
        child: SizedBox.expand(
          key: _editorColumnKey,
          child: Stack(
            children: [
              Positioned.fill(
                child: AnimatedPadding(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeInOutCubic,
                  padding: EdgeInsets.only(left: isNarrow ? 0 : 55),
                  child: list,
                ),
              ),
              AnimatedPositioned(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeInOutCubic,
                left: isNarrow ? 4 : 0,
                top: isNarrow ? 8 : 0,
                bottom: isNarrow ? 8 : 0,
                width: 54,
                child: IgnorePointer(
                  ignoring: isNarrow && !_showMobileOutline,
                  child: AnimatedOpacity(
                    key: const ValueKey('mobile-recipe-outline'),
                    opacity: isNarrow ? (_showMobileOutline ? 1 : 0) : 1,
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeInOutCubic,
                    child: outline,
                  ),
                ),
              ),
              AnimatedPositioned(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeInOutCubic,
                left: 54,
                top: 0,
                bottom: 0,
                width: 1,
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: isNarrow ? 0 : 1,
                    duration: const Duration(milliseconds: 180),
                    child: VerticalDivider(
                      width: 1,
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                ),
              ),
              if (isNarrow && widget.editing)
                Positioned(
                  top: 0,
                  right: 0,
                  bottom: 0,
                  width: constraints.maxWidth * .15,
                  child: GestureDetector(
                    // Полоса предназначена для большого пальца: она
                    // прокручивает редактор, но не отдаёт жест вложенным
                    // Draggable и DropTarget.
                    behavior: HitTestBehavior.opaque,
                    onVerticalDragUpdate: (details) {
                      if (!_scrollController.hasClients) return;
                      final position = _scrollController.position;
                      _scrollController.jumpTo(
                        (position.pixels - details.delta.dy).clamp(
                          0.0,
                          position.maxScrollExtent,
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

/// Граница центрального холста рецепта. Вложенные модули используют именно
/// её, а не ширину своего непосредственного родителя: при добавлении нового
/// потомка могут расшириться все родительские карточки вплоть до этой границы.
class _EditorColumnBounds extends InheritedWidget {
  const _EditorColumnBounds({required this.boundaryKey, required super.child});

  final GlobalKey boundaryKey;

  @override
  bool updateShouldNotify(_EditorColumnBounds oldWidget) =>
      boundaryKey != oldWidget.boundaryKey;
}

class _RecipeMultiplierEditor extends StatelessWidget {
  const _RecipeMultiplierEditor({
    required this.controller,
    required this.value,
    required this.onChanged,
  });

  final TextEditingController controller;
  final int value;
  final ValueChanged<int> onChanged;

  void restoreIfInvalid() {
    final enteredValue = int.tryParse(controller.text);
    if (enteredValue == null || enteredValue < 1 || enteredValue > 256) {
      controller.text = '$value';
    }
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 220,
    child: TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: const InputDecoration(labelText: 'Множитель рецепта'),
      onChanged: (text) {
        final value = int.tryParse(text);
        if (value != null && value >= 1 && value <= 256) onChanged(value);
      },
      onSubmitted: (_) => restoreIfInvalid(),
      onTapOutside: (_) => restoreIfInvalid(),
    ),
  );
}

/// Выбор раздела блюда доступен в режиме чтения непосредственно перед
/// пошаговым описанием. Новое значение попадает в общую транзакцию при выходе
/// из рецепта, как заметка и дерево модулей.
class _RecipeCategoryPicker extends StatelessWidget {
  const _RecipeCategoryPicker({required this.value, required this.onChanged});

  final RecipeCategory value;
  final ValueChanged<RecipeCategory> onChanged;

  @override
  Widget build(BuildContext context) {
    final foreground = contrastColorFor(Theme.of(context).colorScheme.surface);
    final style = TextStyle(fontSize: 17, color: foreground);
    return DropdownButtonFormField<RecipeCategory>(
      key: ValueKey('recipe-category-picker-${value.storageKey}'),
      initialValue: value,
      isExpanded: true,
      style: style,
      iconEnabledColor: foreground,
      decoration: InputDecoration(
        labelText: 'Категория блюда',
        labelStyle: TextStyle(color: foreground),
        isDense: true,
      ),
      items: [
        for (final category in RecipeCategory.values)
          DropdownMenuItem(
            value: category,
            child: Text(category.title, style: style),
          ),
      ],
      onChanged: (category) {
        if (category != null) onChanged(category);
      },
    );
  }
}

/// Выбор постности не заменяет основную категорию: он лишь добавляет второй
/// путь группировки и поиска рецепта.
class _RecipeFastingPicker extends StatelessWidget {
  const _RecipeFastingPicker({required this.value, required this.onChanged});

  final RecipeFasting value;
  final ValueChanged<RecipeFasting> onChanged;

  @override
  Widget build(BuildContext context) {
    final foreground = contrastColorFor(Theme.of(context).colorScheme.surface);
    final style = TextStyle(fontSize: 17, color: foreground);
    return DropdownButtonFormField<RecipeFasting>(
      key: ValueKey('recipe-fasting-picker-${value.storageKey}'),
      initialValue: value,
      isExpanded: true,
      style: style,
      iconEnabledColor: foreground,
      decoration: InputDecoration(
        labelText: 'Питание',
        labelStyle: TextStyle(color: foreground),
        isDense: true,
      ),
      items: [
        for (final fasting in RecipeFasting.values)
          DropdownMenuItem(
            value: fasting,
            child: Text(fasting.title, style: style),
          ),
      ],
      onChanged: (fasting) {
        if (fasting != null) onChanged(fasting);
      },
    );
  }
}

/// Короткая кулинарная памятка намеренно хранится в интерфейсе: это не
/// рецептурные данные и не требует отдельного модуля или записи в БД.
Future<void> showRecipeReferenceDialog(BuildContext context) =>
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Кухонная справка'),
        content: const SingleChildScrollView(
          child: SelectableText(
            'Яйца\n'
            '1 яйцо С1 примерно равно 1¼ яйца С2. В рецепте удобно считать: '
            '4 яйца С2 ≈ 3 яйца С1.\n\n'
            'Ложки без горки\n'
            'Чайная — 5 мл, десертная — 10 мл, столовая — 15 мл.\n\n'
            'Ориентировочные массы\n'
            'Мука: без горки 3 / 6 / 9 г; с горкой 5 / 10 / 15 г.\n'
            'Сахар: без горки 4 / 8 / 12 г; с горкой 6 / 12 / 18 г.\n'
            'Вода и другие жидкости измеряются объёмом; «горка» к ним не применяется.\n\n'
            'Порядок значений в строках: чайная / десертная / столовая ложка.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: Navigator.of(context).pop,
            child: const Text('Понятно'),
          ),
        ],
      ),
    );

class _OutlineNode {
  const _OutlineNode(this.kind, this.depth, this.parentIndex);
  final CardKind kind;
  final int depth;
  final int? parentIndex;
}

class _RecipeOutline extends StatelessWidget {
  const _RecipeOutline({required this.controller, required this.steps});
  final ScrollController controller;
  final List<RecipeNode> steps;

  List<_OutlineNode> get _nodes {
    final nodes = <_OutlineNode>[];
    void addNode(RecipeNode node, int depth, int? parentIndex) {
      final index = nodes.length;
      nodes.add(_OutlineNode(node.card.kind, depth, parentIndex));
      for (final child in node.children) {
        addNode(child, depth + 1, index);
      }
    }

    for (final step in steps) {
      addNode(step, 0, null);
    }
    return nodes;
  }

  void _jumpTo(Offset localPosition, double height) {
    if (!controller.hasClients ||
        !controller.position.hasContentDimensions ||
        height <= 0) {
      return;
    }
    final fraction = (localPosition.dy / height).clamp(0.0, 1.0);
    controller.animateTo(
      controller.position.maxScrollExtent * fraction,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (details) =>
          _jumpTo(details.localPosition, constraints.maxHeight),
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final position =
              controller.hasClients && controller.position.hasContentDimensions
              ? controller.position
              : null;
          return CustomPaint(
            painter: _RecipeOutlinePainter(
              colorScheme: Theme.of(context).colorScheme,
              nodes: _nodes,
              offset: position?.pixels ?? 0,
              viewport: position?.viewportDimension ?? 0,
              contentExtent: position == null
                  ? 0
                  : position.maxScrollExtent + position.viewportDimension,
            ),
            child: const SizedBox.expand(),
          );
        },
      ),
    ),
  );
}

class _RecipeOutlinePainter extends CustomPainter {
  const _RecipeOutlinePainter({
    required this.colorScheme,
    required this.nodes,
    required this.offset,
    required this.viewport,
    required this.contentExtent,
  });
  final ColorScheme colorScheme;
  final List<_OutlineNode> nodes;
  final double offset;
  final double viewport;
  final double contentExtent;

  @override
  void paint(Canvas canvas, Size size) {
    final track = RRect.fromRectAndRadius(
      Rect.fromLTWH(18, 18, 18, size.height - 36),
      const Radius.circular(9),
    );
    canvas.drawRRect(track, Paint()..color = colorScheme.surfaceContainerHigh);
    if (nodes.isNotEmpty) {
      final gap = 2.0;
      final height =
          ((size.height - 44 - gap * (nodes.length - 1)) / nodes.length).clamp(
            2.0,
            18.0,
          );
      for (var index = 0; index < nodes.length; index++) {
        final node = nodes[index];
        final top = 22 + index * (height + gap);
        final left = 21.0 + (node.depth * 5.0).clamp(0.0, 15.0);
        final centerY = top + height / 2;
        if (node.parentIndex case final parentIndex?) {
          final parent = nodes[parentIndex];
          final parentTop = 22 + parentIndex * (height + gap);
          final parentX = 21.0 + (parent.depth * 5.0).clamp(0.0, 15.0) + 5;
          final parentY = parentTop + height / 2;
          final connector = Paint()
            ..color = colorScheme.outlineVariant
            ..strokeWidth = 1;
          canvas.drawLine(
            Offset(parentX, parentY),
            Offset(parentX, centerY),
            connector,
          );
          canvas.drawLine(
            Offset(parentX, centerY),
            Offset(left, centerY),
            connector,
          );
        }
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(left, top, 12 - node.depth.clamp(0, 4) * 1.5, height),
            const Radius.circular(3),
          ),
          Paint()
            ..color = _moduleColor(
              colorScheme,
              node.kind,
            ).withValues(alpha: .9),
        );
      }
    }
    if (contentExtent > 0 && viewport > 0) {
      final trackHeight = size.height - 36;
      final top = 18 + (offset / contentExtent) * trackHeight;
      final height = ((viewport / contentExtent) * trackHeight).clamp(
        18.0,
        trackHeight,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(18, top, 18, height),
          const Radius.circular(9),
        ),
        Paint()..color = colorScheme.primary.withValues(alpha: .32),
      );
    }
  }

  @override
  bool shouldRepaint(_RecipeOutlinePainter old) =>
      old.nodes != nodes ||
      old.offset != offset ||
      old.viewport != viewport ||
      old.contentExtent != contentExtent ||
      old.colorScheme != colorScheme;
}

class _TreeEditor extends StatelessWidget {
  const _TreeEditor({
    required this.node,
    required this.source,
    required this.canDrop,
    required this.onDrop,
    required this.onModuleDragChanged,
    required this.moduleDragging,
    this.parent,
    this.siblingIndex = 0,
    this.depth = 0,
    this.compactLayout = false,
  });
  final RecipeNode node;
  final List<RecipeNode> source;
  final bool Function(Object, RecipeNode?) canDrop;
  final void Function(Object, List<RecipeNode>, int, {RecipeNode? parent})
  onDrop;
  final ValueChanged<bool> onModuleDragChanged;
  final bool moduleDragging;
  final RecipeNode? parent;
  final int siblingIndex;
  final int depth;
  final bool compactLayout;
  @override
  Widget build(BuildContext context) => Padding(
    // Отступ отделяет только соседние корневые шаги. Для вложения он создаёт
    // лишнюю нижнюю полосу вокруг дочерней карточки и визуально раздувает
    // родительский модуль после сброса.
    padding: EdgeInsets.only(bottom: depth == 0 ? (compactLayout ? 1 : 5) : 0),
    child: Draggable<Object>(
      data: _NodeDrag(node, source),
      onDragStarted: () => onModuleDragChanged(true),
      onDragEnd: (_) => onModuleDragChanged(false),
      feedback: Material(
        color: Colors.transparent,
        child: _ModuleCard(card: node.card),
      ),
      child: _NodeBody(
        node: node,
        parent: parent,
        siblingIndex: siblingIndex,
        highlighted: false,
        showDropCavity: false,
        compactLayout: compactLayout,
        depth: depth,
        children: [
          for (final entry in node.children.indexed) ...[
            _InsertZone(
              parent: node,
              target: node.children,
              index: entry.$1,
              canDrop: canDrop,
              onDrop: onDrop,
              compact: compactLayout,
              tolerant: moduleDragging,
            ),
            if (_showsIngredientEnumeration(node, entry.$2))
              _EditorEnumerationSeparator(
                text: separatorForChild(node, entry.$2).trim(),
                color: contrastColorFor(moduleColor(context, node.card.kind)),
              ),
            _TreeEditor(
              node: entry.$2,
              source: node.children,
              canDrop: canDrop,
              onDrop: onDrop,
              onModuleDragChanged: onModuleDragChanged,
              moduleDragging: moduleDragging,
              parent: node,
              siblingIndex: entry.$1,
              depth: depth + 1,
              compactLayout: compactLayout,
            ),
          ],
          _InsertZone(
            parent: node,
            target: node.children,
            index: node.children.length,
            canDrop: canDrop,
            onDrop: onDrop,
            compact: compactLayout,
            tolerant: moduleDragging,
          ),
        ],
      ),
    ),
  );
}

class _NodeBody extends StatelessWidget {
  const _NodeBody({
    required this.node,
    required this.highlighted,
    required this.showDropCavity,
    this.parent,
    required this.siblingIndex,
    this.children = const [],
    required this.compactLayout,
    required this.depth,
  });
  final RecipeNode node;
  final bool highlighted;
  final bool showDropCavity;
  final RecipeNode? parent;
  final int siblingIndex;
  final List<Widget> children;
  final bool compactLayout;
  final int depth;
  String get _label {
    if (node.card.id != 'quantity.mass' &&
        node.card.id != 'quantity.volume' &&
        node.card.id != 'quantity.time' &&
        node.card.id != 'quantity.temperature' &&
        node.card.id != 'quantity.count' &&
        node.card.id != 'quantity.fat-content') {
      final grammarCase = parent == null
          ? node.caseFromParent
          : grammarCaseForChild(parent!, node);
      final prefix = parent == null ? null : joinTextForChild(parent!, node);
      final label = node.card.formFor(grammarCase);
      if (prefix == null || prefix.trim().isEmpty) return label;
      return '${prefix.trim()} $label';
    }
    final unit = node.unit == NumericUnit.grams
        ? 'г'
        : node.unit == NumericUnit.milliliters
        ? 'мл'
        : node.unit == NumericUnit.minutes
        ? 'мин'
        : node.unit == NumericUnit.pieces
        ? 'шт.'
        : node.unit == NumericUnit.percent
        ? '%'
        : '°C';
    final number = node.upperValue == null
        ? '${node.value ?? 0}'
        : '${node.value ?? 0}–${node.upperValue}';
    return '$number $unit';
  }

  @override
  Widget build(BuildContext context) {
    // Редактор — это другое представление тех же шагов. Поэтому текст
    // карточки берёт ровно тот же стиль, что и строка рецепта в _RenderedStep:
    // без искусственного полужирного начертания и увеличения кегля.
    final background = highlighted
        ? Theme.of(context).colorScheme.secondaryContainer
        : moduleColor(context, node.card.kind);
    final foreground = contrastColorFor(background);
    final labelStyle = Theme.of(context).textTheme.titleLarge
        ?.copyWith(color: foreground);
    // Вложенный модуль не должен получать вторую «рамку» из стандартного
    // отступа Card. Его внутренний воздух меньше, поэтому окончательно
    // вставленный потомок занимает почти тот же объём, что и ямка при
    // перетаскивании.
    final nested = depth > 0;
    final padding = compactLayout
        ? (nested ? 2.0 : 7.0)
        : (nested ? 3.0 : 10.0);
    final gap = compactLayout ? 3.0 : (nested ? 4.0 : 6.0);
    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      child: Container(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: EdgeInsets.all(padding),
          child: Wrap(
            spacing: gap,
            runSpacing: gap,
            // На широком экране центрирование делает дерево спокойнее. В узком
            // режиме высокий потомок не должен оставлять пустое место под
            // родительской подписью.
            crossAxisAlignment: compactLayout
                ? WrapCrossAlignment.start
                : WrapCrossAlignment.center,
            runAlignment: WrapAlignment.start,
            children: [
              Wrap(
                spacing: gap,
                crossAxisAlignment: compactLayout
                    ? WrapCrossAlignment.start
                    : WrapCrossAlignment.center,
                children: [
                  moduleIcon(context, node.card, color: foreground),
                  node.card.id == 'quantity.mass' ||
                          node.card.id == 'quantity.volume' ||
                          node.card.id == 'quantity.time' ||
                          node.card.id == 'quantity.temperature' ||
                          node.card.id == 'quantity.count' ||
                          node.card.id == 'quantity.fat-content'
                      ? _ParameterLabel(node: node, style: labelStyle)
                      : node.card.id == 'text.free'
                      ? _FreeTextLabel(node: node, style: labelStyle)
                      : node.card.id == 'text.recipe-dish'
                      ? Text(
                          node.text?.trim().isNotEmpty == true
                              ? node.text!.trim()
                              : 'блюдо',
                          style: labelStyle,
                        )
                      : node.card.id == 'utensil.multicooker-program'
                      ? _MulticookerProgramLabel(
                          node: node,
                          label: _label,
                          style: labelStyle,
                        )
                      : node.card.id == 'ingredient.minced-meat'
                      ? _MincedMeatLabel(
                          node: node,
                          label: _label,
                          style: labelStyle,
                        )
                      : node.card.id == 'ingredient.eggs'
                      ? _EggCategoryLabel(
                          node: node,
                          label: _label,
                          style: labelStyle,
                        )
                      : node.card.id == 'characteristic.shape'
                      ? _ShapeLabel(
                          node: node,
                          label: _label,
                          style: labelStyle,
                        )
                      : node.card.id == 'quantity.spoon'
                      ? _SpoonLabel(node: node, style: labelStyle)
                      : Text(_label, style: labelStyle),
                ],
              ),
              ...children,
              _ModuleDropCavity(visible: showDropCavity),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditorEnumerationSeparator extends StatelessWidget {
  const _EditorEnumerationSeparator({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 1),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleLarge?.copyWith(color: color),
    ),
  );
}

/// Показывает точку, в которой отпущенный модуль станет последним вложением.
/// Нулевая высота в обычном состоянии не отнимает место у дерева рецепта.
class _ModuleDropCavity extends StatefulWidget {
  const _ModuleDropCavity({required this.visible});
  final bool visible;

  @override
  State<_ModuleDropCavity> createState() => _ModuleDropCavityState();
}

class _ModuleDropCavityState extends State<_ModuleDropCavity> {
  static const _preferredWidth = 132.0;
  double _availableWidth = 0;

  @override
  void initState() {
    super.initState();
    _scheduleMeasurement();
  }

  @override
  void didUpdateWidget(covariant _ModuleDropCavity oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.visible) {
      _availableWidth = 0;
      return;
    }
    _scheduleMeasurement();
  }

  void _scheduleMeasurement() {
    if (!widget.visible) return;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _measureFreeLineSpace(),
    );
  }

  void _measureFreeLineSpace() {
    if (!mounted || !widget.visible) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    // Для вложенного ингредиента расширяется вся цепочка родительских
    // карточек. Поэтому остаток нужен до разделителя центрального столбца,
    // а не до правой границы ближайшего действия или внутреннего Wrap.
    final columnBounds = context
        .dependOnInheritedWidgetOfExactType<_EditorColumnBounds>();
    final boundaryBox = columnBounds?.boundaryKey.currentContext
        ?.findRenderObject();
    if (boundaryBox is! RenderBox || !boundaryBox.hasSize) return;
    final left = box.localToGlobal(Offset.zero, ancestor: boundaryBox).dx;
    final width = _preferredWidth.clamp(0.0, boundaryBox.size.width - left);
    if ((width - _availableWidth).abs() > .5) {
      setState(() => _availableWidth = width);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      width: widget.visible ? _availableWidth : 0,
      height: widget.visible ? 34 : 0,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: widget.visible ? colors.secondaryContainer : Colors.transparent,
        border: Border.all(
          color: widget.visible ? colors.secondary : Colors.transparent,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      // Узкий остаток строки всё равно показывает саму ямку, но иконка не
      // должна вылезать за неё и создавать новое переполнение.
      clipBehavior: Clip.hardEdge,
      child: widget.visible && _availableWidth >= 28
          ? Icon(
              Icons.subdirectory_arrow_right,
              size: 18,
              color: colors.secondary,
            )
          : null,
    );
  }
}

class _ParameterLabel extends StatefulWidget {
  const _ParameterLabel({required this.node, required this.style});
  final RecipeNode node;
  final TextStyle? style;
  @override
  State<_ParameterLabel> createState() => _ParameterLabelState();
}

class _ParameterLabelState extends State<_ParameterLabel> {
  bool editing = false;
  late final TextEditingController controller = TextEditingController();
  late final FocusNode focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _restoreText();
    focusNode.addListener(() {
      if (mounted && editing && !focusNode.hasFocus) save();
    });
  }

  void _restoreText() {
    controller.text = widget.node.upperValue == null
        ? '${widget.node.value ?? 0}'
        : '${widget.node.value ?? 0}-${widget.node.upperValue}';
  }

  String get _currentLabel {
    final unit = widget.node.unit == NumericUnit.grams
        ? 'г'
        : widget.node.unit == NumericUnit.milliliters
        ? 'мл'
        : widget.node.unit == NumericUnit.minutes
        ? 'мин'
        : widget.node.unit == NumericUnit.pieces
        ? 'шт.'
        : widget.node.unit == NumericUnit.percent
        ? '%'
        : '°C';
    final number = widget.node.upperValue == null
        ? '${widget.node.value ?? 0}'
        : '${widget.node.value ?? 0}–${widget.node.upperValue}';
    return '$number $unit';
  }

  bool _applyValue(String source) {
    final parts = source.trim().split(RegExp(r'[-–]'));
    final lower = int.tryParse(parts.first.trim());
    final upper = parts.length == 2 ? int.tryParse(parts.last.trim()) : null;
    final isTime = widget.node.card.id == 'quantity.time';
    final isFatContent = widget.node.card.id == 'quantity.fat-content';
    if (lower != null &&
        lower > 0 &&
        (!isFatContent || lower <= 100) &&
        parts.length <= 2 &&
        (parts.length == 1 || (isTime && upper != null && upper >= lower))) {
      widget.node.value = lower;
      widget.node.upperValue = upper;
      return true;
    } else {
      return false;
    }
  }

  void save() {
    if (!editing) return;
    if (!_applyValue(controller.text)) {
      _restoreText();
    }
    setState(() => editing = false);
  }

  @override
  void dispose() {
    controller.dispose();
    focusNode.dispose();
    super.dispose();
  }

  void startEditing() {
    setState(() {
      _restoreText();
      editing = true;
    });
    // Поле создаётся только после setState. Запрашиваем фокус на следующем
    // кадре, иначе Draggable может оставить фокус на карточке, а не в поле.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && editing) {
        focusNode.requestFocus();
        controller.selection = TextSelection(
          baseOffset: 0,
          extentOffset: controller.text.length,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) => editing
      ? SizedBox(
          width: 100,
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            style: widget.style,
            keyboardType: TextInputType.number,
            inputFormatters: [
              widget.node.card.id == 'quantity.time'
                  ? _timeRangeInputFormatter
                  : FilteringTextInputFormatter.digitsOnly,
            ],
            onChanged: (value) {
              // Обновляем карточку и её вложенное дерево на каждой корректной
              // цифре, а не ждём Enter или потери фокуса.
              if (_applyValue(value)) setState(() {});
            },
            onSubmitted: (_) => save(),
            onTapOutside: (_) => save(),
            decoration: const InputDecoration(isDense: true, hintText: '10–15'),
          ),
        )
      : InkWell(
          onTap: startEditing,
          child: Text(_currentLabel, style: widget.style),
        );
}

/// Время допускает единственный разделитель диапазона («10-15» или «10–15»).
/// Остальные числовые модули получают только целые цифры.
final _timeRangeInputFormatter = TextInputFormatter.withFunction(
  (oldValue, newValue) => RegExp(r'^\d*(?:[-–]\d*)?$').hasMatch(newValue.text)
      ? newValue
      : oldValue,
);

/// Нажатие на карточку единой программы открывает список режимов CE5A0FF2.
/// Режим остаётся значением узла, поэтому словарь не разрастается карточками.
class _MulticookerProgramLabel extends StatefulWidget {
  const _MulticookerProgramLabel({
    required this.node,
    required this.label,
    required this.style,
  });

  final RecipeNode node;
  final String label;
  final TextStyle? style;

  @override
  State<_MulticookerProgramLabel> createState() =>
      _MulticookerProgramLabelState();
}

class _MulticookerProgramLabelState extends State<_MulticookerProgramLabel> {
  String get _text {
    final program = widget.node.text?.trim() ?? '';
    return program.isEmpty ? widget.label : '${widget.label} «$program»';
  }

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: 'Выбрать режим мультиварки',
    padding: EdgeInsets.zero,
    onSelected: (value) =>
        setState(() => widget.node.text = value.isEmpty ? null : value),
    itemBuilder: (context) => [
      const PopupMenuItem(value: '', child: Text('Без выбранного режима')),
      const PopupMenuDivider(),
      for (final mode in CatalogCards.multicookerProgramOptions)
        PopupMenuItem(value: mode, child: Text('«$mode»')),
    ],
    child: Text(_text, style: widget.style),
  );
}

/// Категория яйца — параметр конкретного ингредиента, а не новая карточка.
/// Это сохраняет общий модуль «Яйца» и позволяет выбирать С2, С1, С0 или СВ.
class _EggCategoryLabel extends StatefulWidget {
  const _EggCategoryLabel({
    required this.node,
    required this.label,
    required this.style,
  });

  final RecipeNode node;
  final String label;
  final TextStyle? style;

  @override
  State<_EggCategoryLabel> createState() => _EggCategoryLabelState();
}

class _EggCategoryLabelState extends State<_EggCategoryLabel> {
  String get _category => widget.node.text?.trim().isNotEmpty == true
      ? widget.node.text!.trim()
      : 'С1';

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: 'Выбрать категорию яиц',
    padding: EdgeInsets.zero,
    onSelected: (value) => setState(() => widget.node.text = value),
    itemBuilder: (context) => [
      for (final category in CatalogCards.eggCategoryOptions)
        PopupMenuItem(value: category, child: Text(category)),
    ],
    child: Text('${widget.label} $_category', style: widget.style),
  );
}

/// Форма нарезки выбирается как значение одной карточки, чтобы не создавать
/// отдельные словарные карточки «Кубики», «Соломка» и т. п.
class _ShapeLabel extends StatefulWidget {
  const _ShapeLabel({
    required this.node,
    required this.label,
    required this.style,
  });

  final RecipeNode node;
  final String label;
  final TextStyle? style;

  @override
  State<_ShapeLabel> createState() => _ShapeLabelState();
}

class _ShapeLabelState extends State<_ShapeLabel> {
  String get _value => widget.node.text?.trim().isNotEmpty == true
      ? widget.node.text!.trim()
      : 'кубиками';

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: 'Выбрать форму',
    padding: EdgeInsets.zero,
    onSelected: (value) => setState(() => widget.node.text = value),
    itemBuilder: (context) => [
      for (final option in CatalogCards.shapeOptions.entries)
        PopupMenuItem(value: option.value, child: Text(option.key)),
    ],
    child: Text('${widget.label}: $_value', style: widget.style),
  );
}

/// Размер и доля ложки — свойства одного количественного модуля. Это
/// позволяет применять его ко всем уместным специям, не создавая карточки
/// «чайная ложка», «десертная ложка» и т. п.
class _SpoonLabel extends StatefulWidget {
  const _SpoonLabel({required this.node, required this.style});

  final RecipeNode node;
  final TextStyle? style;

  @override
  State<_SpoonLabel> createState() => _SpoonLabelState();
}

class _SpoonLabelState extends State<_SpoonLabel> {
  String get _value => widget.node.text?.trim().isNotEmpty == true
      ? widget.node.text!.trim()
      : '1 ч. л.';

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: 'Выбрать размер ложки',
    padding: EdgeInsets.zero,
    onSelected: (value) => setState(() => widget.node.text = value),
    itemBuilder: (context) => [
      for (final option in CatalogCards.spoonOptions)
        PopupMenuItem(value: option, child: Text(option)),
    ],
    child: Text(_value, style: widget.style),
  );
}

/// Нажатие на «Фарш» позволяет уточнить его вид, не создавая отдельную
/// карточку для говяжьего, куриного и остальных вариантов.
class _MincedMeatLabel extends StatefulWidget {
  const _MincedMeatLabel({
    required this.node,
    required this.label,
    required this.style,
  });

  final RecipeNode node;
  final String label;
  final TextStyle? style;

  @override
  State<_MincedMeatLabel> createState() => _MincedMeatLabelState();
}

class _MincedMeatLabelState extends State<_MincedMeatLabel> {
  String get _text {
    final specification = widget.node.text?.trim() ?? '';
    return specification.isEmpty
        ? widget.label
        : '${widget.label} $specification';
  }

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: 'Выбрать вид фарша',
    padding: EdgeInsets.zero,
    onSelected: (value) =>
        setState(() => widget.node.text = value.isEmpty ? null : value),
    itemBuilder: (context) => [
      const PopupMenuItem(value: '', child: Text('Без уточнения')),
      const PopupMenuDivider(),
      for (final type in CatalogCards.mincedMeatOptions)
        PopupMenuItem(value: type, child: Text(type)),
    ],
    child: Text(_text, style: widget.style),
  );
}

/// Редактируемый короткий текст для исключений, которые не требуют новой
/// словарной карточки. Ширина поля повторяет текущую длину текста.
class _FreeTextLabel extends StatefulWidget {
  const _FreeTextLabel({required this.node, required this.style});
  final RecipeNode node;
  final TextStyle? style;

  @override
  State<_FreeTextLabel> createState() => _FreeTextLabelState();
}

class _FreeTextLabelState extends State<_FreeTextLabel> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.node.text ?? '',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: _widthForCurrentText(context),
    child: TextField(
      controller: _controller,
      style: widget.style,
      maxLength: freeTextMaxLength,
      onChanged: (value) => setState(() => widget.node.text = value),
      decoration: const InputDecoration(
        isDense: true,
        hintText: 'Введите текст',
        counterText: '',
      ),
    ),
  );

  double _widthForCurrentText(BuildContext context) {
    final style = widget.style ?? DefaultTextStyle.of(context).style;
    final text = _controller.text.isEmpty ? 'Текст' : _controller.text;
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      maxLines: 1,
    )..layout();
    return (painter.width + 38).clamp(88, 520).toDouble();
  }
}

class _InsertZone extends StatelessWidget {
  const _InsertZone({
    required this.parent,
    required this.target,
    required this.index,
    required this.canDrop,
    required this.onDrop,
    this.compact = false,
    this.tolerant = false,
  });
  final RecipeNode? parent;
  final List<RecipeNode> target;
  final int index;
  final bool Function(Object, RecipeNode?) canDrop;
  final void Function(Object, List<RecipeNode>, int, {RecipeNode? parent})
  onDrop;
  final bool compact;

  /// Во время перетаскивания зона захвата шире самой ямки на 50 px с каждой
  /// стороны. В покое она не занимает лишнее место в строке.
  final bool tolerant;
  @override
  Widget build(BuildContext context) => DragTarget<Object>(
    onWillAcceptWithDetails: (details) => canDrop(details.data, parent),
    onAcceptWithDetails: (details) =>
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => onDrop(details.data, target, index, parent: parent),
        ),
    builder: (context, candidates, rejected) {
      final hasCandidate = candidates.isNotEmpty;
      final visualWidth = parent == null
          ? double.infinity
          : hasCandidate
          ? 80.0
          : 18.0;
      // SizedBox задаёт именно область попадания DragTarget. Визуальная ямка
      // остаётся прежней ширины и центрируется внутри неё: курсор можно
      // провести на 50 px левее или правее, не получая пустот в обычном
      // состоянии редактора.
      final hitWidth = parent == null
          ? double.infinity
          : tolerant
          ? 118.0
          : visualWidth;
      final height = hasCandidate ? 34.0 : (compact ? 8.0 : 28.0);
      return SizedBox(
        width: hitWidth,
        height: height,
        child: Align(
          alignment: Alignment.center,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: visualWidth,
            height: height,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: hasCandidate
                  ? Theme.of(context).colorScheme.secondaryContainer
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: hasCandidate
                ? Icon(
                    Icons.subdirectory_arrow_right,
                    size: 18,
                    color: Theme.of(context).colorScheme.secondary,
                  )
                : null,
          ),
        ),
      );
    },
  );
}

/// Полупрозрачная цель удаления. Не принимает события сама: DropTarget
/// песочницы под ней получает сброшенный существующий модуль.
class _DiscardOverlay extends StatelessWidget {
  const _DiscardOverlay();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.error.withValues(alpha: .34),
        border: Border.all(color: colors.error, width: 2),
      ),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: colors.errorContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            'Перетащите сюда модуль для удаления',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: colors.onErrorContainer,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

/// Переход между строкой рецепта и деревом модулей.
///
/// [AnimatedSwitcher] по умолчанию рисует уходящий и входящий дочерние
/// виджеты одновременно. Для шагов это недопустимо: одинаковые слова и
/// карточки оказываются друг поверх друга. Здесь фазы строго разделены:
/// сначала растворяется только старое представление, затем появляется только
/// новое. Размер окружающего [AnimatedSize] меняется плавно, но текста-дубля
/// на экране никогда нет.
class _SequentialStepModeSwitch extends StatelessWidget {
  const _SequentialStepModeSwitch({
    required this.editing,
    required this.animation,
    required this.fromEditing,
    required this.dragging,
    required this.editor,
    required this.viewer,
  });

  final bool editing;
  final Animation<double> animation;
  final bool fromEditing;
  final bool dragging;
  final Widget editor;
  final Widget viewer;

  Widget _child(bool isEditing) => KeyedSubtree(
    key: ValueKey('step-mode.$isEditing'),
    child: isEditing ? editor : viewer,
  );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: animation,
    builder: (context, _) {
      final progress = animation.value;
      final transitioning =
          dragging ||
          animation.status == AnimationStatus.forward ||
          animation.status == AnimationStatus.reverse;
      final showingOutgoing = transitioning && progress < .45;
      final showingIncoming = transitioning && !showingOutgoing;
      final isEditing = showingOutgoing ? fromEditing : editing;
      final opacity = showingOutgoing
          ? 1 - Curves.easeInCubic.transform(progress / .45)
          : showingIncoming
          ? Curves.easeOutCubic.transform((progress - .45) / .55)
          : 1.0;
      final scale = showingOutgoing
          ? 1 - .015 * (progress / .45)
          : showingIncoming
          ? .985 + .015 * ((progress - .45) / .55)
          : 1.0;
      return Opacity(
        opacity: opacity,
        child: Transform.scale(
          alignment: Alignment.centerLeft,
          scale: scale,
          child: _child(isEditing),
        ),
      );
    },
  );
}

class _RenderedStep extends StatelessWidget {
  const _RenderedStep({
    required this.number,
    required this.kind,
    required this.parts,
    required this.visualKey,
    required this.showVisual,
    required this.compactVertical,
    required this.entranceNodeAnchors,
    required this.hideEntranceIngredients,
  });
  final int number;
  final CardKind kind;
  final List<RecipeRenderPart> parts;
  final String visualKey;
  final bool showVisual;
  final bool compactVertical;
  final Map<String, GlobalKey> entranceNodeAnchors;
  final bool hideEntranceIngredients;

  IconData get _icon {
    final primaryCardId = visualKey.split(':').first;
    if (primaryCardId.startsWith('action.')) return actionIcon(primaryCardId);
    return switch (visualKey) {
      final key
          when key.contains('ingredient.pork') ||
              key.contains('ingredient.chicken-fillet') =>
        Icons.set_meal,
      final key
          when key.contains('ingredient.apple') ||
              key.contains('ingredient.plums') =>
        Icons.apple,
      _ => Icons.restaurant,
    };
  }

  /// Разбивает строку на обычные виджеты текста. Якорь нужен только первому
  /// упоминанию ингредиента при входной анимации из поиска.
  Widget _stepText(BuildContext context) {
    final style = Theme.of(context).textTheme.titleLarge;
    final fragments = <Widget>[];
    for (final part in parts) {
      if (part.nodeId == null) {
        fragments.add(Text(part.text, style: style));
        continue;
      }
      final ingredientAnchor = entranceNodeAnchors[part.nodeId];
      fragments.add(
        Opacity(
          opacity: ingredientAnchor != null && hideEntranceIngredients ? 0 : 1,
          child: Text(
            part.text,
            key: ingredientAnchor,
            style: style,
            overflow: TextOverflow.visible,
          ),
        ),
      );
    }
    if (!parts.map((part) => part.text).join().trimRight().endsWith('.')) {
      fragments.add(Text('.', style: style));
    }
    return Wrap(
      spacing: 0,
      runSpacing: 0,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: fragments,
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      // На телефоне и в узкой центральной колонке приоритет у текста шага.
      // Порог оставляет место номеру, отступам и читаемой строке рецепта.
      final displayVisual = showVisual && constraints.maxWidth >= 430;
      return Card(
        margin: EdgeInsets.only(bottom: compactVertical ? 3 : 12),
        child: Padding(
          padding: EdgeInsets.all(compactVertical ? 6 : 20),
          child: Row(
            // Иллюстрация, номер и текст составляют один шаг: текст должен
            // располагаться в центре всей высоты карточки, а не у её верхнего
            // края. В узком режиме иллюстрация не строится совсем.
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _StepNumber(number: number, kind: kind),
              const SizedBox(width: 12),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SizeTransition(
                    axis: Axis.horizontal,
                    axisAlignment: -1,
                    sizeFactor: animation,
                    child: child,
                  ),
                ),
                child: displayVisual
                    ? Padding(
                        key: ValueKey('step-visual-$number'),
                        padding: const EdgeInsets.only(right: 16),
                        child: CircleAvatar(
                          radius: 28,
                          child: Icon(_icon, size: 30),
                        ),
                      )
                    : const SizedBox(key: ValueKey('step-visual-hidden')),
              ),
              Expanded(child: _stepText(context)),
            ],
          ),
        ),
      );
    },
  );
}

/// Цвет берётся из той же палитры, что и карточка корневого модуля шага.
/// Поэтому он меняется при замене типа модуля и остаётся согласованным с
/// конструктором в режиме просмотра.
class _StepNumber extends StatelessWidget {
  const _StepNumber({super.key, required this.number, required this.kind});
  final int number;
  final CardKind kind;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 34),
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: moduleColor(context, kind),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      '$number.',
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w800,
        color: contrastColorFor(moduleColor(context, kind)),
      ),
    ),
  );
}
