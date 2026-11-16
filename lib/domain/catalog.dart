import 'recipe_node.dart';

/// Версия встроенной библиотеки карточек и рецептов.
///
/// Изменяется только при изменении данных каталога. По ней локальная БД
/// понимает, что нужно один раз синхронизировать встроенные записи, вместо
/// полного удаления и создания каталога при каждом запуске приложения.
const catalogRevision = 'catalog-v9';

/// Раздел блюда в каталоге. Значение [storageKey] хранится в локальной БД,
/// а [title] показывается в поиске и выборе на экране рецепта.
enum RecipeCategory {
  soup('soup', 'Похлёбки'),
  porridge('porridge', 'Каши'),
  sideDish('side-dish', 'Гарниры'),
  main('main', 'Вторые блюда'),
  salad('salad', 'Салаты'),
  pastry('pastry', 'Выпечка'),
  dessert('dessert', 'Десерты'),
  drink('drink', 'Напитки'),
  preserve('preserve', 'Заготовки'),
  snack('snack', 'Закуски'),
  other('other', 'Другое');

  const RecipeCategory(this.storageKey, this.title);
  final String storageKey;
  final String title;

  static RecipeCategory fromStorage(String? value) {
    for (final category in RecipeCategory.values) {
      if (category.storageKey == value) return category;
    }
    return RecipeCategory.other;
  }
}

/// Постность — независимая от вида блюда характеристика. Например, щи могут
/// одновременно быть «Похлёбкой» и «Постными».
enum RecipeFasting {
  lean('lean', 'Постные'),
  nonLean('non-lean', 'Непостные');

  const RecipeFasting(this.storageKey, this.title);
  final String storageKey;
  final String title;

  static RecipeFasting fromStorage(String? value) {
    for (final fasting in RecipeFasting.values) {
      if (fasting.storageKey == value) return fasting;
    }
    return RecipeFasting.nonLean;
  }
}

/// Исходное распределение всех встроенных рецептов по разделам.
/// Пользовательский выбор сохраняется отдельно в БД и имеет приоритет.
const _catalogRecipeCategories = <String, RecipeCategory>{
  'traditional-mushroom-soup': RecipeCategory.soup,
  'traditional-milk-noodle-soup': RecipeCategory.soup,
  'fresh-cabbage-soup': RecipeCategory.soup,
  'rassolnik-chicken-fillet': RecipeCategory.soup,
  'pike-ukha': RecipeCategory.soup,
  'beetroot-soup': RecipeCategory.soup,
  'classic-borscht': RecipeCategory.soup,
  'okroshka-ham': RecipeCategory.soup,
  'traditional-buckwheat-mushrooms': RecipeCategory.porridge,
  'traditional-oatmeal': RecipeCategory.porridge,
  'traditional-millet-porridge': RecipeCategory.porridge,
  'traditional-pea-porridge': RecipeCategory.porridge,
  'traditional-semolina-porridge': RecipeCategory.porridge,
  'traditional-pearl-barley': RecipeCategory.porridge,
  'milk-buckwheat': RecipeCategory.porridge,
  'merchant-buckwheat-chicken': RecipeCategory.main,
  'potato-puree': RecipeCategory.sideDish,
  'traditional-squash-caviar': RecipeCategory.snack,
  'traditional-baked-beet': RecipeCategory.sideDish,
  'cabbage-potato-pancakes': RecipeCategory.main,
  'zucchini-sour-cream': RecipeCategory.sideDish,
  'traditional-syrniki': RecipeCategory.dessert,
  'traditional-yeast-pancakes': RecipeCategory.pastry,
  'milk-pancakes': RecipeCategory.pastry,
  'mannik-kefir': RecipeCategory.pastry,
  'honey-kovrizhka': RecipeCategory.pastry,
  'milk-bread-oven': RecipeCategory.pastry,
  'traditional-cottage-cheese-casserole': RecipeCategory.dessert,
  'curd-casserole-apples': RecipeCategory.dessert,
  'buckwheat-pudding-apples': RecipeCategory.dessert,
  'baked-apples-honey': RecipeCategory.dessert,
  'gogol-mogol': RecipeCategory.dessert,
  'homemade-cream-ice-cream': RecipeCategory.dessert,
  'homemade-chocolate-ice-cream': RecipeCategory.dessert,
  'homemade-banana-ice-cream': RecipeCategory.dessert,
  'homemade-creme-brulee-ice-cream': RecipeCategory.dessert,
  'traditional-raspberry-jam': RecipeCategory.preserve,
  'apple-plum-jam': RecipeCategory.preserve,
  'apple-plum-compote': RecipeCategory.drink,
  'bread-kvass': RecipeCategory.drink,
  'traditional-cocoa-milk': RecipeCategory.drink,
  'olivier-ham': RecipeCategory.salad,
  'traditional-capital-salad': RecipeCategory.salad,
  'herring-under-fur-coat': RecipeCategory.salad,
  'vinaigrette': RecipeCategory.salad,
  'beef-stroganoff': RecipeCategory.main,
  'traditional-soviet-goulash': RecipeCategory.main,
  'lazy-cabbage-rolls-multicooker': RecipeCategory.main,
  'classic-roast': RecipeCategory.main,
  'potato-baba-meat': RecipeCategory.main,
  'meat-egg-casserole': RecipeCategory.main,
  'pork-escalope-cream': RecipeCategory.main,
  'buckwheat-cabbage-rolls': RecipeCategory.main,
  'mimosa-pink-salmon': RecipeCategory.salad,
  'cranberry-kissel': RecipeCategory.drink,
  'apple-pastila': RecipeCategory.dessert,
  'lean-pea-kissel': RecipeCategory.snack,
  'lean-shchi-grains-mushrooms': RecipeCategory.soup,
  'lean-stuffed-turnip': RecipeCategory.main,
  'lean-kundyubki': RecipeCategory.main,
  'lean-kulebyaka-cabbage-mushrooms': RecipeCategory.pastry,
  'lean-levashniki-apple': RecipeCategory.pastry,
  'fried-mushrooms-sour-cream': RecipeCategory.sideDish,
};

enum IngredientGroup {
  vegetables('Овощи'),
  grains('Снедь'),
  dairy('Молочное'),
  animals('Живность'),
  fruits('Фрукты'),
  liquids('Жидкости'),
  other('Ингредиенты'),
  spices('Специи');

  const IngredientGroup(this.title);
  final String title;
}

/// Предустановленный локальный каталог, составленный из обсуждённых рецептов.
class CatalogRecipe {
  CatalogRecipe({
    required this.id,
    required this.title,
    required this.buildSteps,
    this.servings = 2,
    this.detailedSteps = const [],
  });
  final String id;
  final String title;
  final List<RecipeNode> Function() buildSteps;

  /// Исходное число порций и начальное значение множителя рецепта.
  final int servings;
  final List<String> detailedSteps;

  /// Состав всегда выводится из модульного дерева. Благодаря единому источнику
  /// названия в поиске не могут разойтись с карточками самого рецепта.
  late final Set<String> ingredients = _collectIngredients();

  Set<String> _collectIngredients() {
    final result = <String>{};

    void visit(RecipeNode node) {
      if (node.card.kind == CardKind.ingredient) {
        result.add(node.card.nominative);
      }
      for (final child in node.children) {
        visit(child);
      }
    }

    for (final step in buildSteps()) {
      visit(step);
    }
    return Set.unmodifiable(result);
  }

  RecipeCategory get category =>
      _catalogRecipeCategories[id] ?? RecipeCategory.other;

  /// Признак рассчитывается по составу встроенного рецепта. Это даёт
  /// однозначное начальное значение без дублирования ещё одного большого
  /// списка идентификаторов. Пользовательский выбор хранится в БД отдельно.
  RecipeFasting get fasting =>
      _nonLeanIngredientLabels.any(ingredients.contains)
      ? RecipeFasting.nonLean
      : RecipeFasting.lean;

  /// Ингредиенты для карточки результата: сначала самые объёмные по рецепту.
  ///
  /// Складываются все явно заданные массы и объёмы одного продукта. Вода нужна
  /// для процесса приготовления, но не показывается в кратком составе под
  /// названием блюда. При равных количествах сохраняется порядок первого
  /// использования в шагах; не встретившиеся в дереве названия идут в конце по
  /// алфавиту.
  late final List<String> ingredientsByAmount = _ingredientsByAmount();

  List<String> _ingredientsByAmount() {
    final amounts = <String, int>{};
    final firstAppearance = <String, int>{};
    var appearanceIndex = 0;

    void visit(RecipeNode node) {
      final label = node.card.nominative;
      if (node.card.kind == CardKind.ingredient &&
          node.card.id != CatalogCards.water.id &&
          ingredients.contains(label)) {
        firstAppearance.putIfAbsent(label, () => appearanceIndex++);
        amounts.update(
          label,
          (amount) => amount + _ingredientAmount(node),
          ifAbsent: () => _ingredientAmount(node),
        );
      }
      for (final child in node.children) {
        visit(child);
      }
    }

    for (final step in buildSteps()) {
      visit(step);
    }

    final labels = ingredients
        .where((label) => label != CatalogCards.water.nominative)
        .toList();
    labels.sort((left, right) {
      final amountComparison = (amounts[right] ?? 0).compareTo(
        amounts[left] ?? 0,
      );
      if (amountComparison != 0) return amountComparison;

      final appearanceComparison = (firstAppearance[left] ?? 1 << 30).compareTo(
        firstAppearance[right] ?? 1 << 30,
      );
      if (appearanceComparison != 0) return appearanceComparison;
      return left.compareTo(right);
    });
    return List.unmodifiable(labels);
  }

  int _ingredientAmount(RecipeNode ingredient) {
    var total = 0;

    void collect(RecipeNode node) {
      for (final child in node.children) {
        if (child.card.id == CatalogCards.mass.id ||
            child.card.id == CatalogCards.volume.id) {
          total += child.value ?? 0;
        } else if (child.card.kind != CardKind.ingredient) {
          collect(child);
        }
      }
    }

    collect(ingredient);
    return total;
  }
}

/// Продукты животного происхождения, по которым встроенный рецепт считается
/// непостным. Масло растительное намеренно не входит в список: это обычный
/// постный вариант, хотя в строгие дни его могут исключать отдельно.
const _nonLeanIngredientLabels = <String>{
  'Куриное филе',
  'Свинина',
  'Говядина',
  'Ветчина',
  'Сало',
  'Фарш',
  'Яйца',
  'Желток',
  'Белок',
  'Молоко',
  'Кефир',
  'Сметана',
  'Сливки',
  'Сливочное масло',
  'Творог',
  'Сыр твёрдый',
  'Сыр плавленый',
  'Щука',
  'Окунь',
  'Сельдь',
  'Треска',
  'Минтай',
  'Лосось',
  'Горбуша',
  'Форель',
};

/// Возвращает не больше [limit] рецептов с наиболее похожим составом.
///
/// Все ингредиенты уже отсортированы по количеству. Общий непрерывный префикс
/// имеет наибольший вес, затем учитывается общая последовательность продуктов
/// и только потом их общее число. Поэтому «1, 2, 5» ближе к «1, 2, 3», чем
/// «2, 1, 3», хотя во втором случае общих продуктов больше.
List<CatalogRecipe> similarRecipesFor(
  CatalogRecipe recipe,
  Iterable<CatalogRecipe> candidates, {
  int limit = 3,
}) {
  final ingredients = recipe.ingredientsByAmount;
  if (ingredients.isEmpty || limit <= 0) return const [];

  final scored =
      <({CatalogRecipe recipe, int prefix, int sequence, int shared})>[];
  for (final candidate in candidates) {
    if (candidate.id == recipe.id) continue;
    final candidateIngredients = candidate.ingredientsByAmount;
    final candidateIngredientSet = candidateIngredients.toSet();
    final shared = ingredients.where(candidateIngredientSet.contains).length;
    if (shared == 0) continue;
    scored.add((
      recipe: candidate,
      prefix: _sharedIngredientPrefixLength(ingredients, candidateIngredients),
      sequence: _ingredientSequenceLength(ingredients, candidateIngredients),
      shared: shared,
    ));
  }
  scored.sort((left, right) {
    final prefixComparison = right.prefix.compareTo(left.prefix);
    if (prefixComparison != 0) return prefixComparison;
    final sequenceComparison = right.sequence.compareTo(left.sequence);
    if (sequenceComparison != 0) return sequenceComparison;
    final sharedComparison = right.shared.compareTo(left.shared);
    if (sharedComparison != 0) return sharedComparison;
    return left.recipe.title.compareTo(right.recipe.title);
  });
  return scored.take(limit).map((item) => item.recipe).toList();
}

int _sharedIngredientPrefixLength(List<String> left, List<String> right) {
  var length = 0;
  while (length < left.length &&
      length < right.length &&
      left[length] == right[length]) {
    length++;
  }
  return length;
}

/// Длина наибольшей общей подпоследовательности: мера близости порядка
/// ингредиентов без требования, чтобы они стояли непосредственно рядом.
int _ingredientSequenceLength(List<String> left, List<String> right) {
  var previous = List<int>.filled(right.length + 1, 0);
  for (final leftIngredient in left) {
    final current = List<int>.filled(right.length + 1, 0);
    for (var index = 0; index < right.length; index++) {
      current[index + 1] = leftIngredient == right[index]
          ? previous[index] + 1
          : previous[index + 1] > current[index]
          ? previous[index + 1]
          : current[index];
    }
    previous = current;
  }
  return previous.last;
}

class CatalogCards {
  static const eggCategoryOptions = ['С2', 'С1', 'С0', 'СВ'];

  static const ingredientGroupIds = <IngredientGroup, Set<String>>{
    IngredientGroup.vegetables: {
      'ingredient.potato',
      'ingredient.cabbage',
      'ingredient.onion',
      'ingredient.garlic',
      'ingredient.carrot',
      'ingredient.zucchini',
      'ingredient.beet',
      'ingredient.turnip',
      'ingredient.radish',
      'ingredient.bell-pepper',
      'ingredient.eggplant',
      'ingredient.green-peas',
      'ingredient.celery',
      'ingredient.horseradish',
      'ingredient.sauerkraut',
      'ingredient.cucumber',
      'ingredient.sorrel',
      'ingredient.radishes',
    },
    IngredientGroup.grains: {
      'ingredient.buckwheat',
      'ingredient.pearl-barley',
      'ingredient.rice',
      'ingredient.millet',
      'ingredient.oats',
      'ingredient.semolina',
      'ingredient.peas',
      'ingredient.flour',
      'ingredient.noodles',
      'ingredient.pasta',
      'ingredient.beans',
    },
    IngredientGroup.dairy: {
      'ingredient.milk',
      'ingredient.cottage-cheese',
      'ingredient.cream',
      'ingredient.sour-cream',
      'ingredient.butter',
      'ingredient.kefir',
      'ingredient.cheese',
      'ingredient.processed-cheese',
      'ingredient.condensed-milk',
      'ingredient.boiled-condensed-milk',
    },
    IngredientGroup.animals: {
      // Мясо, рыба, яйца и фарш — единая продуктовая подгруппа.
      'ingredient.chicken-fillet',
      'ingredient.pork',
      'ingredient.beef',
      'ingredient.ham',
      'ingredient.lard',
      'ingredient.bones',
      'ingredient.eggs',
      'ingredient.egg-yolk',
      'ingredient.egg-white',
      'ingredient.minced-meat',
      'ingredient.pike',
      'ingredient.perch',
      'ingredient.herring',
      'ingredient.cod',
      'ingredient.pollock',
      'ingredient.salmon',
      'ingredient.pink-salmon',
      'ingredient.trout',
    },
    IngredientGroup.spices: {
      'ingredient.salt',
      'ingredient.sugar',
      'ingredient.black-pepper',
      'ingredient.bay-leaf',
      'ingredient.dill',
      'ingredient.parsley',
      'ingredient.green-onion',
      'ingredient.garlic',
      'ingredient.sweet-paprika',
      'ingredient.mustard',
      'ingredient.coriander',
      'ingredient.cumin',
      'ingredient.cloves',
      'ingredient.cinnamon',
      'ingredient.vanilla',
    },
    IngredientGroup.fruits: {
      'ingredient.apples',
      'ingredient.plums',
      'ingredient.cranberries',
      'ingredient.lemon',
      'ingredient.prunes',
      'ingredient.raspberries',
      'ingredient.strawberries',
      'ingredient.raisins',
      'ingredient.walnuts',
      'ingredient.banana',
    },
    IngredientGroup.liquids: {
      'ingredient.water',
      'ingredient.vegetable-oil',
      'ingredient.cucumber-brine',
      'ingredient.vinegar',
      'ingredient.kvass',
    },
  };

  static IngredientGroup ingredientGroup(CardDefinition card) =>
      ingredientGroupIds.entries
          .where((entry) => entry.value.contains(card.id))
          .map((entry) => entry.key)
          .firstOrNull ??
      IngredientGroup.other;

  /// Режимы Moulinex CE5A0FF2. Название режима — значение экземпляра
  /// карточки, а не отдельная карточка в общем словаре.
  static const multicookerProgramOptions = [
    'Выпечка',
    'Джем/Десерт',
    'Жарка',
    'Йогурт',
    'Молочная каша',
    'Мультишеф',
    'Пароварка',
    'Плов',
    'Разогрев',
    'Рис/крупы',
    'Суп',
    'Тушение',
  ];

  /// Вид фарша хранится в экземпляре одной карточки. Пустое значение означает
  /// общий «Фарш», а не отдельный вид продукта.
  static const mincedMeatOptions = [
    'из говядины',
    'из свинины',
    'из курицы',
    'из индейки',
    'смешанный',
  ];

  /// Форма — параметр конкретного ингредиента после нарезки, а не отдельная
  /// словарная карточка на каждый вариант.
  static const shapeOptions = <String, String>{
    'Кубики': 'кубиками',
    'Соломка': 'соломкой',
    'Кольца': 'кольцами',
    'Полукольца': 'полукольцами',
    'Ломтики': 'ломтиками',
    'Дольки': 'дольками',
    'Брусочки': 'брусочками',
    'Кружки': 'кружками',
  };

  static const prepare = CardDefinition(
    id: 'action.prepare',
    kind: CardKind.action,
    nominative: 'Включить',
  );
  static const cut = CardDefinition(
    id: 'action.cut',
    kind: CardKind.action,
    nominative: 'Нарезать',
  );
  static const grate = CardDefinition(
    id: 'action.grate',
    kind: CardKind.action,
    nominative: 'Натереть',
  );
  static const mix = CardDefinition(
    id: 'action.mix',
    kind: CardKind.action,
    nominative: 'Смешать',
  );
  static const add = CardDefinition(
    id: 'action.add',
    kind: CardKind.action,
    nominative: 'Добавить',
  );
  static const boil = CardDefinition(
    id: 'action.boil',
    kind: CardKind.action,
    nominative: 'Варить',
  );
  static const heat = CardDefinition(
    id: 'action.heat',
    kind: CardKind.action,
    nominative: 'Подогреть',
  );
  static const cool = CardDefinition(
    id: 'action.cool',
    kind: CardKind.action,
    nominative: 'Остудить',
  );
  static const rinse = CardDefinition(
    id: 'action.rinse',
    kind: CardKind.action,
    nominative: 'Промыть',
  );
  static const clean = CardDefinition(
    id: 'action.clean',
    kind: CardKind.action,
    nominative: 'Очистить',
  );
  static const transfer = CardDefinition(
    id: 'action.transfer',
    kind: CardKind.action,
    nominative: 'Переложить',
  );
  static const plate = CardDefinition(
    id: 'action.plate',
    kind: CardKind.action,
    nominative: 'Выложить',
  );
  static const pour = CardDefinition(
    id: 'action.pour',
    kind: CardKind.action,
    nominative: 'Влить',
  );
  static const stir = CardDefinition(
    id: 'action.stir',
    kind: CardKind.action,
    nominative: 'Перемешать',
  );
  static const close = CardDefinition(
    id: 'action.close',
    kind: CardKind.action,
    nominative: 'Закрыть',
  );
  static const select = CardDefinition(
    id: 'action.select',
    kind: CardKind.action,
    nominative: 'Выбрать',
  );
  static const leave = CardDefinition(
    id: 'action.leave',
    kind: CardKind.action,
    nominative: 'Оставить',
  );
  static const open = CardDefinition(
    id: 'action.open',
    kind: CardKind.action,
    nominative: 'Открыть',
  );
  static const fry = CardDefinition(
    id: 'action.fry',
    kind: CardKind.action,
    nominative: 'Жарить',
  );
  static const saute = CardDefinition(
    id: 'action.saute',
    kind: CardKind.action,
    nominative: 'Обжарить',
  );
  static const turnOff = CardDefinition(
    id: 'action.turn-off',
    kind: CardKind.action,
    nominative: 'Отключить',
  );
  static const grease = CardDefinition(
    id: 'action.grease',
    kind: CardKind.action,
    nominative: 'Смазать',
  );
  static const beat = CardDefinition(
    id: 'action.beat',
    kind: CardKind.action,
    nominative: 'Отбить',
  );
  static const dip = CardDefinition(
    id: 'action.dip',
    kind: CardKind.action,
    nominative: 'Окунуть',
  );
  static const shred = CardDefinition(
    id: 'action.shred',
    kind: CardKind.action,
    nominative: 'Нашинковать',
  );
  static const blend = CardDefinition(
    id: 'action.blend',
    kind: CardKind.action,
    nominative: 'Измельчить',
  );
  static const stew = CardDefinition(
    id: 'action.stew',
    kind: CardKind.action,
    nominative: 'Тушить',
  );
  static const knead = CardDefinition(
    id: 'action.knead',
    kind: CardKind.action,
    nominative: 'Вымесить',
  );
  static const form = CardDefinition(
    id: 'action.form',
    kind: CardKind.action,
    nominative: 'Сформировать',
  );
  static const fill = CardDefinition(
    id: 'action.fill',
    kind: CardKind.action,
    nominative: 'Начинить',
  );
  static const mash = CardDefinition(
    id: 'action.mash',
    kind: CardKind.action,
    nominative: 'Размять',
  );
  static const preheat = CardDefinition(
    id: 'action.preheat',
    kind: CardKind.action,
    nominative: 'Разогреть',
  );
  static const bake = CardDefinition(
    id: 'action.bake',
    kind: CardKind.action,
    nominative: 'Выпекать',
  );
  static const drain = CardDefinition(
    id: 'action.drain',
    kind: CardKind.action,
    nominative: 'Слить',
  );
  static const coat = CardDefinition(
    id: 'action.coat',
    kind: CardKind.action,
    nominative: 'Обвалять',
  );
  static const pinch = CardDefinition(
    id: 'action.pinch',
    kind: CardKind.action,
    nominative: 'Защипнуть',
  );
  static const wrap = CardDefinition(
    id: 'action.wrap',
    kind: CardKind.action,
    nominative: 'Завернуть',
  );
  static const chickenFillet = CardDefinition(
    id: 'ingredient.chicken-fillet',
    kind: CardKind.ingredient,
    nominative: 'Куриное филе',
    forms: {GrammarCase.accusative: 'куриное филе'},
  );
  static const pearlBarley = CardDefinition(
    id: 'ingredient.pearl-barley',
    kind: CardKind.ingredient,
    nominative: 'Перловая крупа',
    forms: {GrammarCase.accusative: 'перловую крупу'},
  );
  static const pickledCucumbers = CardDefinition(
    id: 'ingredient.pickled-cucumbers',
    kind: CardKind.ingredient,
    nominative: 'Солёные огурцы',
    forms: {GrammarCase.accusative: 'солёные огурцы'},
  );
  static const tomatoPaste = CardDefinition(
    id: 'ingredient.tomato-paste',
    kind: CardKind.ingredient,
    nominative: 'Томатная паста',
    forms: {GrammarCase.accusative: 'томатную пасту'},
  );
  static const cucumberBrine = CardDefinition(
    id: 'ingredient.cucumber-brine',
    kind: CardKind.ingredient,
    nominative: 'Огуречный рассол',
    forms: {GrammarCase.accusative: 'огуречный рассол'},
  );
  static const parsley = CardDefinition(
    id: 'ingredient.parsley',
    kind: CardKind.ingredient,
    nominative: 'Петрушка',
    forms: {GrammarCase.accusative: 'петрушку'},
  );
  static const potato = CardDefinition(
    id: 'ingredient.potato',
    kind: CardKind.ingredient,
    nominative: 'Картошка',
    forms: {GrammarCase.accusative: 'картошку'},
  );
  static const apples = CardDefinition(
    id: 'ingredient.apples',
    kind: CardKind.ingredient,
    nominative: 'Яблоки',
    forms: {GrammarCase.accusative: 'яблоки'},
  );
  static const cottageCheese = CardDefinition(
    id: 'ingredient.cottage-cheese',
    kind: CardKind.ingredient,
    nominative: 'Творог',
    forms: {GrammarCase.accusative: 'творог'},
  );
  static const buckwheat = CardDefinition(
    id: 'ingredient.buckwheat',
    kind: CardKind.ingredient,
    nominative: 'Гречка',
    forms: {GrammarCase.accusative: 'гречку'},
  );
  static const pork = CardDefinition(
    id: 'ingredient.pork',
    kind: CardKind.ingredient,
    nominative: 'Свинина',
    forms: {GrammarCase.accusative: 'свинину'},
  );
  static const cabbage = CardDefinition(
    id: 'ingredient.cabbage',
    kind: CardKind.ingredient,
    nominative: 'Капуста',
    forms: {GrammarCase.accusative: 'капусту'},
  );
  static const eggs = CardDefinition(
    id: 'ingredient.eggs',
    kind: CardKind.ingredient,
    nominative: 'Яйца',
    forms: {GrammarCase.accusative: 'яйца'},
  );
  static const eggYolk = CardDefinition(
    id: 'ingredient.egg-yolk',
    kind: CardKind.ingredient,
    nominative: 'Желток',
    forms: {GrammarCase.accusative: 'желток'},
  );
  static const eggWhite = CardDefinition(
    id: 'ingredient.egg-white',
    kind: CardKind.ingredient,
    nominative: 'Белок',
    forms: {GrammarCase.accusative: 'белок'},
  );
  static const flour = CardDefinition(
    id: 'ingredient.flour',
    kind: CardKind.ingredient,
    nominative: 'Мука',
    forms: {GrammarCase.accusative: 'муку'},
  );
  static const milk = CardDefinition(
    id: 'ingredient.milk',
    kind: CardKind.ingredient,
    nominative: 'Молоко',
    forms: {GrammarCase.accusative: 'молоко'},
  );
  static const water = CardDefinition(
    id: 'ingredient.water',
    kind: CardKind.ingredient,
    nominative: 'Вода',
    forms: {GrammarCase.accusative: 'воду'},
  );
  static const salt = CardDefinition(
    id: 'ingredient.salt',
    kind: CardKind.ingredient,
    nominative: 'Соль',
    forms: {GrammarCase.accusative: 'соль'},
  );
  static const onion = CardDefinition(
    id: 'ingredient.onion',
    kind: CardKind.ingredient,
    nominative: 'Лук репчатый',
    forms: {GrammarCase.accusative: 'лук репчатый'},
  );
  static const garlic = CardDefinition(
    id: 'ingredient.garlic',
    kind: CardKind.ingredient,
    nominative: 'Чеснок',
    forms: {GrammarCase.accusative: 'чеснок'},
  );
  static const vegetableOil = CardDefinition(
    id: 'ingredient.vegetable-oil',
    kind: CardKind.ingredient,
    nominative: 'Растительное масло',
    forms: {GrammarCase.accusative: 'растительное масло'},
  );
  static const blackPepper = CardDefinition(
    id: 'ingredient.black-pepper',
    kind: CardKind.ingredient,
    nominative: 'Чёрный молотый перец',
    forms: {GrammarCase.accusative: 'чёрный молотый перец'},
  );
  static const dill = CardDefinition(
    id: 'ingredient.dill',
    kind: CardKind.ingredient,
    nominative: 'Укроп',
    forms: {GrammarCase.accusative: 'укроп'},
  );
  static const butter = CardDefinition(
    id: 'ingredient.butter',
    kind: CardKind.ingredient,
    nominative: 'Сливочное масло',
    forms: {GrammarCase.accusative: 'сливочное масло'},
  );
  static const bakingPowder = CardDefinition(
    id: 'ingredient.baking-powder',
    kind: CardKind.ingredient,
    nominative: 'Разрыхлитель',
    forms: {GrammarCase.accusative: 'разрыхлитель'},
  );
  static const cream = CardDefinition(
    id: 'ingredient.cream',
    kind: CardKind.ingredient,
    nominative: 'Сливки',
    forms: {GrammarCase.accusative: 'сливки'},
  );
  static const carrot = CardDefinition(
    id: 'ingredient.carrot',
    kind: CardKind.ingredient,
    nominative: 'Морковь',
    forms: {GrammarCase.accusative: 'морковь'},
  );
  static const bayLeaf = CardDefinition(
    id: 'ingredient.bay-leaf',
    kind: CardKind.ingredient,
    nominative: 'Лавровый лист',
    forms: {GrammarCase.accusative: 'лавровый лист'},
  );
  static const batter = CardDefinition(
    id: 'ingredient.batter',
    kind: CardKind.ingredient,
    nominative: 'Тесто',
    forms: {GrammarCase.accusative: 'тесто'},
  );
  static const yeast = CardDefinition(
    id: 'ingredient.yeast',
    kind: CardKind.ingredient,
    nominative: 'Дрожжи сухие',
    forms: {GrammarCase.accusative: 'дрожжи сухие'},
  );
  static const bread = CardDefinition(
    id: 'ingredient.bread',
    kind: CardKind.ingredient,
    nominative: 'Хлеб',
    forms: {GrammarCase.accusative: 'хлеб'},
  );
  static const cheese = CardDefinition(
    id: 'ingredient.cheese',
    kind: CardKind.ingredient,
    nominative: 'Сыр твёрдый',
    forms: {GrammarCase.accusative: 'сыр твёрдый'},
  );
  static const cornStarch = CardDefinition(
    id: 'ingredient.corn-starch',
    kind: CardKind.ingredient,
    nominative: 'Кукурузный крахмал',
    forms: {GrammarCase.accusative: 'кукурузный крахмал'},
  );
  static const potatoStarch = CardDefinition(
    id: 'ingredient.potato-starch',
    kind: CardKind.ingredient,
    nominative: 'Картофельный крахмал',
    forms: {GrammarCase.accusative: 'картофельный крахмал'},
  );
  static const sweetPaprika = CardDefinition(
    id: 'ingredient.sweet-paprika',
    kind: CardKind.ingredient,
    nominative: 'Паприка сладкая',
    forms: {GrammarCase.accusative: 'паприку сладкую'},
  );
  static const lid = CardDefinition(
    id: 'utensil.lid',
    kind: CardKind.utensil,
    nominative: 'Крышка',
    forms: {
      GrammarCase.accusative: 'крышку',
      GrammarCase.prepositional: 'крышке',
    },
  );
  static const multicooker = CardDefinition(
    id: 'utensil.moulinex-ce5a0ff2',
    kind: CardKind.utensil,
    nominative: 'Мультиварка Moulinex CE5A0FF2',
    forms: {
      GrammarCase.accusative: 'мультиварку Moulinex CE5A0FF2',
      GrammarCase.prepositional: 'мультиварке Moulinex CE5A0FF2',
    },
  );
  static const oven = CardDefinition(
    id: 'utensil.oven',
    kind: CardKind.utensil,
    nominative: 'Духовка',
    forms: {
      GrammarCase.accusative: 'духовку',
      GrammarCase.prepositional: 'духовке',
    },
  );
  static const ovenTopBottomHeat = CardDefinition(
    id: 'utensil.oven-top-bottom-heat',
    kind: CardKind.utensil,
    nominative: 'Верхний и нижний нагрев',
    forms: {GrammarCase.accusative: 'верхний и нижний нагрев'},
  );
  static const multicookerProgram = CardDefinition(
    id: 'utensil.multicooker-program',
    kind: CardKind.utensil,
    nominative: 'Программа мультиварки',
    forms: {GrammarCase.accusative: 'программу'},
  );
  static const zucchini = CardDefinition(
    id: 'ingredient.zucchini',
    kind: CardKind.ingredient,
    nominative: 'Кабачки',
    forms: {GrammarCase.accusative: 'кабачки'},
  );
  static const beet = CardDefinition(
    id: 'ingredient.beet',
    kind: CardKind.ingredient,
    nominative: 'Свёкла',
    forms: {GrammarCase.accusative: 'свёклу'},
  );
  static const turnip = CardDefinition(
    id: 'ingredient.turnip',
    kind: CardKind.ingredient,
    nominative: 'Репа',
    forms: {GrammarCase.accusative: 'репу'},
  );
  static const radish = CardDefinition(
    id: 'ingredient.radish',
    kind: CardKind.ingredient,
    nominative: 'Редька',
    forms: {GrammarCase.accusative: 'редьку'},
  );
  static const radishes = CardDefinition(
    id: 'ingredient.radishes',
    kind: CardKind.ingredient,
    nominative: 'Редис',
    forms: {GrammarCase.accusative: 'редис'},
  );
  static const bellPepper = CardDefinition(
    id: 'ingredient.bell-pepper',
    kind: CardKind.ingredient,
    nominative: 'Болгарский перец',
    forms: {GrammarCase.accusative: 'болгарский перец'},
  );
  static const eggplant = CardDefinition(
    id: 'ingredient.eggplant',
    kind: CardKind.ingredient,
    nominative: 'Баклажан',
    forms: {GrammarCase.accusative: 'баклажан'},
  );
  static const greenPeas = CardDefinition(
    id: 'ingredient.green-peas',
    kind: CardKind.ingredient,
    nominative: 'Зелёный горошек',
    forms: {GrammarCase.accusative: 'зелёный горошек'},
  );
  static const celery = CardDefinition(
    id: 'ingredient.celery',
    kind: CardKind.ingredient,
    nominative: 'Сельдерей',
    forms: {GrammarCase.accusative: 'сельдерей'},
  );
  static const horseradish = CardDefinition(
    id: 'ingredient.horseradish',
    kind: CardKind.ingredient,
    nominative: 'Хрен',
    forms: {GrammarCase.accusative: 'хрен'},
  );
  static const greenOnion = CardDefinition(
    id: 'ingredient.green-onion',
    kind: CardKind.ingredient,
    nominative: 'Зелёный лук',
    forms: {GrammarCase.accusative: 'зелёный лук'},
  );
  static const bones = CardDefinition(
    id: 'ingredient.bones',
    kind: CardKind.ingredient,
    nominative: 'Кости',
    forms: {GrammarCase.accusative: 'кости'},
  );
  static const mushrooms = CardDefinition(
    id: 'ingredient.mushrooms',
    kind: CardKind.ingredient,
    nominative: 'Грибы',
    forms: {GrammarCase.accusative: 'грибы'},
  );
  static const cranberries = CardDefinition(
    id: 'ingredient.cranberries',
    kind: CardKind.ingredient,
    nominative: 'Клюква',
    forms: {GrammarCase.accusative: 'клюкву'},
  );
  static const rice = CardDefinition(
    id: 'ingredient.rice',
    kind: CardKind.ingredient,
    nominative: 'Рис',
    forms: {GrammarCase.accusative: 'рис'},
  );
  static const millet = CardDefinition(
    id: 'ingredient.millet',
    kind: CardKind.ingredient,
    nominative: 'Пшено',
    forms: {GrammarCase.accusative: 'пшено'},
  );
  static const oats = CardDefinition(
    id: 'ingredient.oats',
    kind: CardKind.ingredient,
    nominative: 'Овсяные хлопья',
    forms: {GrammarCase.accusative: 'овсяные хлопья'},
  );
  static const semolina = CardDefinition(
    id: 'ingredient.semolina',
    kind: CardKind.ingredient,
    nominative: 'Манная крупа',
    forms: {GrammarCase.accusative: 'манную крупу'},
  );
  static const peas = CardDefinition(
    id: 'ingredient.peas',
    kind: CardKind.ingredient,
    nominative: 'Горох',
    forms: {GrammarCase.accusative: 'горох'},
  );
  static const beef = CardDefinition(
    id: 'ingredient.beef',
    kind: CardKind.ingredient,
    nominative: 'Говядина',
    forms: {GrammarCase.accusative: 'говядину'},
  );
  static const kefir = CardDefinition(
    id: 'ingredient.kefir',
    kind: CardKind.ingredient,
    nominative: 'Кефир',
    forms: {GrammarCase.accusative: 'кефир'},
  );
  static const processedCheese = CardDefinition(
    id: 'ingredient.processed-cheese',
    kind: CardKind.ingredient,
    nominative: 'Сыр плавленый',
    forms: {GrammarCase.accusative: 'плавленый сыр'},
  );
  static const breadcrumbs = CardDefinition(
    id: 'ingredient.breadcrumbs',
    kind: CardKind.ingredient,
    nominative: 'Панировочные сухари',
    forms: {GrammarCase.accusative: 'панировочные сухари'},
  );
  static const vinegar = CardDefinition(
    id: 'ingredient.vinegar',
    kind: CardKind.ingredient,
    nominative: 'Уксус',
    forms: {GrammarCase.accusative: 'уксус'},
  );
  static const mustard = CardDefinition(
    id: 'ingredient.mustard',
    kind: CardKind.ingredient,
    nominative: 'Горчица',
    forms: {GrammarCase.accusative: 'горчицу'},
  );
  static const coriander = CardDefinition(
    id: 'ingredient.coriander',
    kind: CardKind.ingredient,
    nominative: 'Кориандр',
    forms: {GrammarCase.accusative: 'кориандр'},
  );
  static const cumin = CardDefinition(
    id: 'ingredient.cumin',
    kind: CardKind.ingredient,
    nominative: 'Тмин',
    forms: {GrammarCase.accusative: 'тмин'},
  );
  static const cloves = CardDefinition(
    id: 'ingredient.cloves',
    kind: CardKind.ingredient,
    nominative: 'Гвоздика',
    forms: {GrammarCase.accusative: 'гвоздику'},
  );
  static const cinnamon = CardDefinition(
    id: 'ingredient.cinnamon',
    kind: CardKind.ingredient,
    nominative: 'Корица',
    forms: {GrammarCase.accusative: 'корицу'},
  );
  static const honey = CardDefinition(
    id: 'ingredient.honey',
    kind: CardKind.ingredient,
    nominative: 'Мёд',
    forms: {GrammarCase.accusative: 'мёд'},
  );
  static const vanilla = CardDefinition(
    id: 'ingredient.vanilla',
    kind: CardKind.ingredient,
    nominative: 'Ваниль',
    forms: {GrammarCase.accusative: 'ваниль'},
  );
  static const lemon = CardDefinition(
    id: 'ingredient.lemon',
    kind: CardKind.ingredient,
    nominative: 'Лимон',
    forms: {GrammarCase.accusative: 'лимон'},
  );
  static const prunes = CardDefinition(
    id: 'ingredient.prunes',
    kind: CardKind.ingredient,
    nominative: 'Чернослив',
    forms: {GrammarCase.accusative: 'чернослив'},
  );
  static const ryeFlour = CardDefinition(
    id: 'ingredient.rye-flour',
    kind: CardKind.ingredient,
    nominative: 'Ржаная мука',
    forms: {GrammarCase.accusative: 'ржаную муку'},
  );
  static const cocoa = CardDefinition(
    id: 'ingredient.cocoa',
    kind: CardKind.ingredient,
    nominative: 'Какао',
    forms: {GrammarCase.accusative: 'какао'},
  );
  static const chocolate = CardDefinition(
    id: 'ingredient.chocolate',
    kind: CardKind.ingredient,
    nominative: 'Шоколад',
    forms: {GrammarCase.accusative: 'шоколад'},
  );
  static const noodles = CardDefinition(
    id: 'ingredient.noodles',
    kind: CardKind.ingredient,
    nominative: 'Лапша',
    forms: {GrammarCase.accusative: 'лапшу'},
  );
  static const pasta = CardDefinition(
    id: 'ingredient.pasta',
    kind: CardKind.ingredient,
    nominative: 'Макароны',
    forms: {GrammarCase.accusative: 'макароны'},
  );
  static const mincedMeat = CardDefinition(
    id: 'ingredient.minced-meat',
    kind: CardKind.ingredient,
    nominative: 'Фарш',
    forms: {GrammarCase.accusative: 'фарш'},
  );
  static const kvass = CardDefinition(
    id: 'ingredient.kvass',
    kind: CardKind.ingredient,
    nominative: 'Квас',
    forms: {GrammarCase.accusative: 'квас'},
  );
  static const sauerkraut = CardDefinition(
    id: 'ingredient.sauerkraut',
    kind: CardKind.ingredient,
    nominative: 'Квашеная капуста',
    forms: {GrammarCase.accusative: 'квашеную капусту'},
  );
  static const gelatin = CardDefinition(
    id: 'ingredient.gelatin',
    kind: CardKind.ingredient,
    nominative: 'Желатин',
    forms: {GrammarCase.accusative: 'желатин'},
  );
  static const mayonnaise = CardDefinition(
    id: 'ingredient.mayonnaise',
    kind: CardKind.ingredient,
    nominative: 'Майонез',
    forms: {GrammarCase.accusative: 'майонез'},
  );
  static const cucumber = CardDefinition(
    id: 'ingredient.cucumber',
    kind: CardKind.ingredient,
    nominative: 'Огурец',
    forms: {GrammarCase.accusative: 'огурец'},
  );
  static const raspberries = CardDefinition(
    id: 'ingredient.raspberries',
    kind: CardKind.ingredient,
    nominative: 'Малина',
    forms: {GrammarCase.accusative: 'малину'},
  );
  static const strawberries = CardDefinition(
    id: 'ingredient.strawberries',
    kind: CardKind.ingredient,
    nominative: 'Клубника',
    forms: {GrammarCase.accusative: 'клубнику'},
  );
  static const ham = CardDefinition(
    id: 'ingredient.ham',
    kind: CardKind.ingredient,
    nominative: 'Ветчина',
    forms: {GrammarCase.accusative: 'ветчину'},
  );
  static const chanterelles = CardDefinition(
    id: 'ingredient.chanterelles',
    kind: CardKind.ingredient,
    nominative: 'Лисички',
    forms: {GrammarCase.accusative: 'лисички'},
  );
  static const porcini = CardDefinition(
    id: 'ingredient.porcini',
    kind: CardKind.ingredient,
    nominative: 'Белые грибы',
    forms: {GrammarCase.accusative: 'белые грибы'},
  );
  static const honeyMushrooms = CardDefinition(
    id: 'ingredient.honey-mushrooms',
    kind: CardKind.ingredient,
    nominative: 'Опята',
    forms: {GrammarCase.accusative: 'опята'},
  );
  static const olives = CardDefinition(
    id: 'ingredient.olives',
    kind: CardKind.ingredient,
    nominative: 'Оливки',
    forms: {GrammarCase.accusative: 'оливки'},
  );
  static const beans = CardDefinition(
    id: 'ingredient.beans',
    kind: CardKind.ingredient,
    nominative: 'Фасоль',
    forms: {GrammarCase.accusative: 'фасоль'},
  );
  static const condensedMilk = CardDefinition(
    id: 'ingredient.condensed-milk',
    kind: CardKind.ingredient,
    nominative: 'Сгущённое молоко',
    forms: {GrammarCase.accusative: 'сгущённое молоко'},
  );
  static const boiledCondensedMilk = CardDefinition(
    id: 'ingredient.boiled-condensed-milk',
    kind: CardKind.ingredient,
    nominative: 'Варёное сгущённое молоко',
    forms: {GrammarCase.accusative: 'варёное сгущённое молоко'},
  );
  static const banana = CardDefinition(
    id: 'ingredient.banana',
    kind: CardKind.ingredient,
    nominative: 'Банан',
    forms: {GrammarCase.accusative: 'банан'},
  );
  static const lard = CardDefinition(
    id: 'ingredient.lard',
    kind: CardKind.ingredient,
    nominative: 'Сало',
    forms: {GrammarCase.accusative: 'сало'},
  );
  static const raisins = CardDefinition(
    id: 'ingredient.raisins',
    kind: CardKind.ingredient,
    nominative: 'Изюм',
    forms: {GrammarCase.accusative: 'изюм'},
  );
  static const walnuts = CardDefinition(
    id: 'ingredient.walnuts',
    kind: CardKind.ingredient,
    nominative: 'Грецкие орехи',
    forms: {GrammarCase.accusative: 'грецкие орехи'},
  );
  static const sorrel = CardDefinition(
    id: 'ingredient.sorrel',
    kind: CardKind.ingredient,
    nominative: 'Щавель',
    forms: {GrammarCase.accusative: 'щавель'},
  );

  /// Контейнер для готового консервированного ингредиента. В него можно
  /// вложить рыбу, мясо, овощи или фрукт без создания отдельной карточки для
  /// каждой комбинации.
  static const canned = CardDefinition(
    id: 'ingredient.canned',
    kind: CardKind.ingredient,
    nominative: 'Консерва',
    forms: {GrammarCase.accusative: 'консерву'},
  );
  // Распространённые виды рыбы для русской и восточнославянской кухни.
  // Все они, как и мясо, яйца и фарш, находятся в группе «Живность».
  static const pike = CardDefinition(
    id: 'ingredient.pike',
    kind: CardKind.ingredient,
    nominative: 'Щука',
    forms: {GrammarCase.accusative: 'щуку'},
  );
  static const perch = CardDefinition(
    id: 'ingredient.perch',
    kind: CardKind.ingredient,
    nominative: 'Окунь',
    forms: {GrammarCase.accusative: 'окуня'},
  );
  static const herring = CardDefinition(
    id: 'ingredient.herring',
    kind: CardKind.ingredient,
    nominative: 'Сельдь',
    forms: {GrammarCase.accusative: 'сельдь'},
  );
  static const cod = CardDefinition(
    id: 'ingredient.cod',
    kind: CardKind.ingredient,
    nominative: 'Треска',
    forms: {GrammarCase.accusative: 'треску'},
  );
  static const pollock = CardDefinition(
    id: 'ingredient.pollock',
    kind: CardKind.ingredient,
    nominative: 'Минтай',
    forms: {GrammarCase.accusative: 'минтай'},
  );
  static const salmon = CardDefinition(
    id: 'ingredient.salmon',
    kind: CardKind.ingredient,
    nominative: 'Сёмга',
    forms: {GrammarCase.accusative: 'сёмгу'},
  );
  static const pinkSalmon = CardDefinition(
    id: 'ingredient.pink-salmon',
    kind: CardKind.ingredient,
    nominative: 'Горбуша',
    forms: {GrammarCase.accusative: 'горбушу'},
  );
  static const trout = CardDefinition(
    id: 'ingredient.trout',
    kind: CardKind.ingredient,
    nominative: 'Форель',
    forms: {GrammarCase.accusative: 'форель'},
  );
  static const soak = CardDefinition(
    id: 'action.soak',
    kind: CardKind.action,
    nominative: 'Замочить',
  );
  static const thaw = CardDefinition(
    id: 'action.thaw',
    kind: CardKind.action,
    nominative: 'Разморозить',
  );
  static const freeze = CardDefinition(
    id: 'action.freeze',
    kind: CardKind.action,
    nominative: 'Заморозить',
  );
  static const sift = CardDefinition(
    id: 'action.sift',
    kind: CardKind.action,
    nominative: 'Просеять',
  );
  static const dryOff = CardDefinition(
    id: 'action.dry-off',
    kind: CardKind.action,
    nominative: 'Обсушить',
  );
  static const dry = CardDefinition(
    id: 'action.dry',
    kind: CardKind.action,
    nominative: 'Высушить',
  );
  static const whisk = CardDefinition(
    id: 'action.whisk',
    kind: CardKind.action,
    nominative: 'Взбить',
  );
  static const strain = CardDefinition(
    id: 'action.strain',
    kind: CardKind.action,
    nominative: 'Процедить',
  );
  static const rollOut = CardDefinition(
    id: 'action.roll-out',
    kind: CardKind.action,
    nominative: 'Раскатать',
  );
  static const spoon = CardDefinition(
    id: 'quantity.spoon',
    kind: CardKind.quantity,
    nominative: 'Ложка',
  );

  /// Значение ложки хранится в самом узле рецепта, а не отдельной карточкой:
  /// это не раздувает библиотеку для каждой дроби и размера ложки.
  static const spoonOptions = <String>[
    '¼ ч. л.',
    '½ ч. л.',
    '¾ ч. л.',
    '1 ч. л.',
    '1½ ч. л.',
    '½ дес. л.',
    '1 дес. л.',
    '½ ст. л.',
    '1 ст. л.',
  ];
  static const fryingPan = CardDefinition(
    id: 'utensil.frying-pan',
    kind: CardKind.utensil,
    nominative: 'Сковорода',
    forms: {
      GrammarCase.accusative: 'сковороду',
      GrammarCase.prepositional: 'сковороде',
    },
  );
  static const pot = CardDefinition(
    id: 'utensil.pot',
    kind: CardKind.utensil,
    nominative: 'Кастрюля',
    forms: {
      GrammarCase.accusative: 'кастрюлю',
      GrammarCase.prepositional: 'кастрюле',
    },
  );
  static const bakingSheet = CardDefinition(
    id: 'utensil.baking-sheet',
    kind: CardKind.utensil,
    nominative: 'Противень',
    forms: {
      GrammarCase.accusative: 'противень',
      GrammarCase.prepositional: 'противне',
    },
  );
  static const grater = CardDefinition(
    id: 'utensil.grater',
    kind: CardKind.utensil,
    nominative: 'Тёрка',
    forms: {
      GrammarCase.accusative: 'тёрку',
      GrammarCase.prepositional: 'тёрке',
    },
  );
  static const sieve = CardDefinition(
    id: 'utensil.sieve',
    kind: CardKind.utensil,
    nominative: 'Сито',
    forms: {GrammarCase.accusative: 'сито', GrammarCase.prepositional: 'сите'},
  );
  static const colander = CardDefinition(
    id: 'utensil.colander',
    kind: CardKind.utensil,
    nominative: 'Дуршлаг',
    forms: {
      GrammarCase.accusative: 'дуршлаг',
      GrammarCase.prepositional: 'дуршлаге',
    },
  );
  static const meatGrinder = CardDefinition(
    id: 'utensil.meat-grinder',
    kind: CardKind.utensil,
    nominative: 'Мясорубка',
    forms: {
      GrammarCase.accusative: 'мясорубку',
      GrammarCase.prepositional: 'мясорубке',
    },
  );
  static const whiskTool = CardDefinition(
    id: 'utensil.whisk',
    kind: CardKind.utensil,
    nominative: 'Венчик',
    forms: {
      GrammarCase.accusative: 'венчик',
      GrammarCase.instrumental: 'венчиком',
      GrammarCase.prepositional: 'венчике',
    },
  );
  static const rollingPin = CardDefinition(
    id: 'utensil.rolling-pin',
    kind: CardKind.utensil,
    nominative: 'Скалка',
    forms: {
      GrammarCase.accusative: 'скалку',
      GrammarCase.instrumental: 'скалкой',
      GrammarCase.prepositional: 'скалке',
    },
  );
  static const servingPlate = CardDefinition(
    id: 'utensil.plate',
    kind: CardKind.utensil,
    nominative: 'Тарелка',
    forms: {
      GrammarCase.accusative: 'тарелку',
      GrammarCase.prepositional: 'тарелке',
    },
  );
  static const sourCream = CardDefinition(
    id: 'ingredient.sour-cream',
    kind: CardKind.ingredient,
    nominative: 'Сметана',
    forms: {GrammarCase.accusative: 'сметану'},
  );
  static const plums = CardDefinition(
    id: 'ingredient.plums',
    kind: CardKind.ingredient,
    nominative: 'Сливы',
    forms: {GrammarCase.accusative: 'сливы'},
  );
  static const sugar = CardDefinition(
    id: 'ingredient.sugar',
    kind: CardKind.ingredient,
    nominative: 'Сахар',
    forms: {GrammarCase.accusative: 'сахар'},
  );
  static const mass = CardDefinition(
    id: 'quantity.mass',
    kind: CardKind.quantity,
    nominative: 'Масса',
  );
  static const volume = CardDefinition(
    id: 'quantity.volume',
    kind: CardKind.quantity,
    nominative: 'Объём',
  );
  static const time = CardDefinition(
    id: 'quantity.time',
    kind: CardKind.quantity,
    nominative: 'Время',
  );
  static const temperature = CardDefinition(
    id: 'quantity.temperature',
    kind: CardKind.quantity,
    nominative: 'Температура',
  );
  static const count = CardDefinition(
    id: 'quantity.count',
    kind: CardKind.quantity,
    nominative: 'Количество',
  );
  static const fatContent = CardDefinition(
    id: 'quantity.fat-content',
    kind: CardKind.quantity,
    nominative: 'Жирность',
  );
  static const shape = CardDefinition(
    id: 'characteristic.shape',
    kind: CardKind.quantity,
    nominative: 'Форма',
  );
  static const freeText = CardDefinition(
    id: 'text.free',
    kind: CardKind.text,
    nominative: 'Текст',
  );
  static const all = [
    prepare,
    cut,
    grate,
    mix,
    add,
    boil,
    heat,
    cool,
    rinse,
    clean,
    transfer,
    plate,
    pour,
    stir,
    close,
    select,
    leave,
    open,
    fry,
    saute,
    stew,
    knead,
    form,
    fill,
    mash,
    preheat,
    bake,
    drain,
    coat,
    pinch,
    wrap,
    chickenFillet,
    pearlBarley,
    pickledCucumbers,
    tomatoPaste,
    cucumberBrine,
    parsley,
    turnOff,
    grease,
    beat,
    dip,
    shred,
    blend,
    potato,
    apples,
    cottageCheese,
    buckwheat,
    pork,
    cabbage,
    eggs,
    eggYolk,
    eggWhite,
    flour,
    milk,
    water,
    salt,
    onion,
    garlic,
    vegetableOil,
    blackPepper,
    dill,
    butter,
    bakingPowder,
    cream,
    carrot,
    bayLeaf,
    batter,
    yeast,
    bread,
    cheese,
    cornStarch,
    potatoStarch,
    sweetPaprika,
    lid,
    multicooker,
    oven,
    ovenTopBottomHeat,
    multicookerProgram,
    zucchini,
    sourCream,
    plums,
    sugar,
    mass,
    volume,
    time,
    temperature,
    count,
    fatContent,
    shape,
    beet,
    turnip,
    radish,
    radishes,
    bellPepper,
    eggplant,
    greenPeas,
    celery,
    horseradish,
    greenOnion,
    bones,
    mushrooms,
    cranberries,
    rice,
    millet,
    oats,
    semolina,
    peas,
    beef,
    kefir,
    processedCheese,
    breadcrumbs,
    vinegar,
    mustard,
    coriander,
    cumin,
    cloves,
    cinnamon,
    honey,
    vanilla,
    lemon,
    prunes,
    ryeFlour,
    cocoa,
    chocolate,
    noodles,
    pasta,
    mincedMeat,
    kvass,
    sauerkraut,
    gelatin,
    mayonnaise,
    cucumber,
    raspberries,
    strawberries,
    ham,
    chanterelles,
    porcini,
    honeyMushrooms,
    olives,
    beans,
    condensedMilk,
    boiledCondensedMilk,
    banana,
    lard,
    raisins,
    walnuts,
    sorrel,
    canned,
    pike,
    perch,
    herring,
    cod,
    pollock,
    salmon,
    pinkSalmon,
    trout,
    soak,
    thaw,
    freeze,
    sift,
    dryOff,
    dry,
    whisk,
    strain,
    rollOut,
    spoon,
    fryingPan,
    pot,
    bakingSheet,
    grater,
    sieve,
    colander,
    meatGrinder,
    whiskTool,
    rollingPin,
    servingPlate,
    freeText,
  ];

  /// Быстрый словарь для восстановления дерева рецепта из SQLite.
  static final Map<String, CardDefinition> byId = {
    for (final card in all) card.id: card,
  };
}

RecipeNode _node(
  String id,
  CardDefinition card, [
  List<RecipeNode> children = const [],
]) => RecipeNode(
  id: id,
  card: card,
  caseFromParent: GrammarCase.accusative,
  children: children,
);

/// Выбранный режим хранится в экземпляре единой карточки программы, а не в
/// отдельных словарных карточках «Жарка», «Суп» и т. п.
RecipeNode _multicookerProgram(String id, String mode) => RecipeNode(
  id: id,
  card: CatalogCards.multicookerProgram,
  caseFromParent: GrammarCase.accusative,
  text: mode,
);
RecipeNode _ingredient(
  String id,
  CardDefinition card, [
  List<RecipeNode> children = const [],
]) => RecipeNode(
  id: id,
  card: card,
  caseFromParent: GrammarCase.accusative,
  text: card.id == 'ingredient.eggs' ? 'С2' : null,
  children: children,
);

/// Готовый консервированный продукт: количество относится к вложенному
/// ингредиенту, поэтому КБЖУ и поиск используют фактический продукт, а не
/// абстрактную упаковку.
RecipeNode _cannedIngredient(String id, CardDefinition ingredient, int grams) =>
    RecipeNode(
      id: id,
      card: CatalogCards.canned,
      caseFromParent: GrammarCase.accusative,
      children: [
        _ingredient('$id-content', ingredient, [
          _mass('$id-content-mass', grams),
        ]),
      ],
    );

RecipeNode _text(String id, String text) =>
    RecipeNode(id: id, card: CatalogCards.freeText, text: text);

RecipeNode _mass(String id, int grams) => RecipeNode(
  id: id,
  card: CatalogCards.mass,
  value: grams,
  unit: NumericUnit.grams,
);

RecipeNode _volume(String id, int milliliters) => RecipeNode(
  id: id,
  card: CatalogCards.volume,
  value: milliliters,
  unit: NumericUnit.milliliters,
);

RecipeNode _time(String id, int minutes, [int? upperMinutes]) => RecipeNode(
  id: id,
  card: CatalogCards.time,
  value: minutes,
  upperValue: upperMinutes,
  unit: NumericUnit.minutes,
);

/// Единый структурный шаг включения CE5A0FF2. Режим остаётся параметром
/// модуля программы, а не отдельной карточкой; длительность — вложение шага.
RecipeNode _multicookerStep(
  String id,
  String mode, [
  int? minutes,
  int? upperMinutes,
]) => _node(id, CatalogCards.prepare, [
  RecipeNode(
    id: '$id-device',
    card: CatalogCards.multicooker,
    caseFromParent: GrammarCase.accusative,
    children: [_multicookerProgram('$id-program', mode)],
  ),
  if (minutes != null) _time('$id-time', minutes, upperMinutes),
]);

/// Одна из двух одинаковых партий яичной запеканки: объём чаши 5 л не
/// позволяет безопасно испечь всю смесь за один раз.
List<RecipeNode> _eggCasseroleBatch(String id) => [
  _node('$id-1', CatalogCards.mix, [
    _ingredient('$id-1-eggs', CatalogCards.eggs, [
      RecipeNode(
        id: '$id-1-eggs-count',
        card: CatalogCards.count,
        value: 12,
        unit: NumericUnit.pieces,
      ),
    ]),
    _ingredient('$id-1-sour-cream', CatalogCards.sourCream, [
      RecipeNode(
        id: '$id-1-sour-cream-mass',
        card: CatalogCards.mass,
        value: 150,
        unit: NumericUnit.grams,
      ),
    ]),
    _ingredient('$id-1-starch', CatalogCards.cornStarch, [
      RecipeNode(
        id: '$id-1-starch-mass',
        card: CatalogCards.mass,
        value: 15,
        unit: NumericUnit.grams,
      ),
    ]),
    _ingredient('$id-1-salt', CatalogCards.salt, [
      RecipeNode(
        id: '$id-1-salt-mass',
        card: CatalogCards.mass,
        value: 5,
        unit: NumericUnit.grams,
      ),
    ]),
  ]),
  _node('$id-2', CatalogCards.add, [
    _ingredient('$id-2-cheese', CatalogCards.cheese, [
      RecipeNode(
        id: '$id-2-cheese-mass',
        card: CatalogCards.mass,
        value: 75,
        unit: NumericUnit.grams,
      ),
    ]),
    _ingredient('$id-2-meat', CatalogCards.pork, [
      RecipeNode(
        id: '$id-2-meat-mass',
        card: CatalogCards.mass,
        value: 750,
        unit: NumericUnit.grams,
      ),
    ]),
    _ingredient('$id-2-onion', CatalogCards.onion, [
      RecipeNode(
        id: '$id-2-onion-mass',
        card: CatalogCards.mass,
        value: 100,
        unit: NumericUnit.grams,
      ),
    ]),
  ]),
  _node('$id-3', CatalogCards.grease, [
    _ingredient('$id-3-oil', CatalogCards.vegetableOil),
  ]),
  _multicookerStep('$id-4', 'Выпечка', 55),
  _node('$id-5', CatalogCards.leave, [
    _ingredient('$id-5-casserole', CatalogCards.eggs),
    RecipeNode(
      id: '$id-5-time',
      card: CatalogCards.time,
      value: 15,
      upperValue: 20,
      unit: NumericUnit.minutes,
    ),
  ]),
];

final _traditionalMushroomSoup = CatalogRecipe(
  id: 'traditional-mushroom-soup',
  title: 'Грибной суп',
  detailedSteps: [
    'Нарезать 100 г лука, 500 г грибов, 400 г картофеля и 100 г моркови.',
    'Обжарить лук на 70 мл растительного и 40 г сливочного масла до прозрачности.',
    'Добавить грибы, соль и чёрный перец; обжарить 10–15 минут.',
    'Влить 1 500 мл воды, добавить картофель и морковь; варить 5–7 минут.',
    'Добавить обжаренные грибы с луком и варить ещё 20 минут.',
  ],
  buildSteps: () => [
    _node('mushroom-soup-1', CatalogCards.cut, [
      _ingredient('mushroom-soup-1-onion', CatalogCards.onion, [
        _mass('mushroom-soup-1-onion-mass', 100),
      ]),
      _ingredient('mushroom-soup-1-mushrooms', CatalogCards.mushrooms, [
        _mass('mushroom-soup-1-mushrooms-mass', 500),
      ]),
    ]),
    _node('mushroom-soup-2', CatalogCards.cut, [
      _ingredient('mushroom-soup-2-potato', CatalogCards.potato, [
        _mass('mushroom-soup-2-potato-mass', 400),
      ]),
      _ingredient('mushroom-soup-2-carrot', CatalogCards.carrot, [
        _mass('mushroom-soup-2-carrot-mass', 100),
      ]),
    ]),
    _node('mushroom-soup-3', CatalogCards.add, [
      _ingredient('mushroom-soup-3-oil', CatalogCards.vegetableOil, [
        _volume('mushroom-soup-3-oil-volume', 75),
      ]),
      _ingredient('mushroom-soup-3-butter', CatalogCards.butter, [
        _mass('mushroom-soup-3-butter-mass', 40),
      ]),
    ]),
    _node('mushroom-soup-4', CatalogCards.saute, [
      _ingredient('mushroom-soup-4-onion', CatalogCards.onion),
      _time('mushroom-soup-4-time', 3, 5),
    ]),
    _node('mushroom-soup-5', CatalogCards.add, [
      _ingredient('mushroom-soup-5-mushrooms', CatalogCards.mushrooms),
      _ingredient('mushroom-soup-5-salt', CatalogCards.salt, [
        _mass('mushroom-soup-5-salt-mass', 3),
      ]),
      _ingredient('mushroom-soup-5-pepper', CatalogCards.blackPepper, [
        _mass('mushroom-soup-5-pepper-mass', 1),
      ]),
    ]),
    _node('mushroom-soup-6', CatalogCards.fry, [
      _ingredient('mushroom-soup-6-mushrooms', CatalogCards.mushrooms),
      _time('mushroom-soup-6-time', 10, 15),
    ]),
    _node('mushroom-soup-7', CatalogCards.pour, [
      _ingredient('mushroom-soup-7-water', CatalogCards.water, [
        _volume('mushroom-soup-7-water-volume', 1500),
      ]),
    ]),
    _node('mushroom-soup-8', CatalogCards.add, [
      _ingredient('mushroom-soup-8-potato', CatalogCards.potato),
      _ingredient('mushroom-soup-8-carrot', CatalogCards.carrot),
    ]),
    _node('mushroom-soup-9', CatalogCards.boil, [
      _ingredient('mushroom-soup-9-potato', CatalogCards.potato),
      _time('mushroom-soup-9-time', 5, 7),
    ]),
    _node('mushroom-soup-10', CatalogCards.add, [
      _ingredient('mushroom-soup-10-mushrooms', CatalogCards.mushrooms),
      _ingredient('mushroom-soup-10-onion', CatalogCards.onion),
    ]),
    _node('mushroom-soup-11', CatalogCards.boil, [
      _ingredient('mushroom-soup-11-mushrooms', CatalogCards.mushrooms),
      _time('mushroom-soup-11-time', 20),
    ]),
  ],
);

final _traditionalMilkNoodleSoup = CatalogRecipe(
  id: 'traditional-milk-noodle-soup',
  title: 'Молочный суп с лапшой',
  detailedSteps: [
    'Влить 500 мл воды и довести до кипения.',
    'Добавить 150 г лапши и варить 3–5 минут.',
    'Слить воду через дуршлаг, вернуть лапшу в чашу и влить 500 мл молока.',
    'Добавить соль и сахар, варить ещё 3–5 минут.',
    'Добавить сливочное масло перед подачей.',
  ],
  buildSteps: () => [
    _node('milk-noodle-1', CatalogCards.pour, [
      _ingredient('milk-noodle-1-water', CatalogCards.water, [
        _volume('milk-noodle-1-water-volume', 500),
      ]),
    ]),
    _node('milk-noodle-2', CatalogCards.boil, [
      _ingredient('milk-noodle-2-water', CatalogCards.water),
      _time('milk-noodle-2-time', 2, 3),
    ]),
    _node('milk-noodle-3', CatalogCards.add, [
      _ingredient('milk-noodle-3-noodles', CatalogCards.noodles, [
        _mass('milk-noodle-3-noodles-mass', 150),
      ]),
    ]),
    _node('milk-noodle-4', CatalogCards.boil, [
      _ingredient('milk-noodle-4-noodles', CatalogCards.noodles),
      _time('milk-noodle-4-time', 3, 5),
    ]),
    _node('milk-noodle-5', CatalogCards.drain, [
      _ingredient('milk-noodle-5-noodles', CatalogCards.noodles),
    ]),
    _node('milk-noodle-6', CatalogCards.pour, [
      _ingredient('milk-noodle-6-milk', CatalogCards.milk, [
        _volume('milk-noodle-6-milk-volume', 500),
      ]),
    ]),
    _node('milk-noodle-7', CatalogCards.add, [
      _ingredient('milk-noodle-7-salt', CatalogCards.salt, [
        _mass('milk-noodle-7-salt-mass', 1),
      ]),
      _ingredient('milk-noodle-7-sugar', CatalogCards.sugar, [
        _mass('milk-noodle-7-sugar-mass', 38),
      ]),
    ]),
    _node('milk-noodle-8', CatalogCards.boil, [
      _ingredient('milk-noodle-8-noodles', CatalogCards.noodles),
      _time('milk-noodle-8-time', 3, 5),
    ]),
    _node('milk-noodle-9', CatalogCards.add, [
      _ingredient('milk-noodle-9-butter', CatalogCards.butter, [
        _mass('milk-noodle-9-butter-mass', 20),
      ]),
    ]),
  ],
);

final _traditionalBuckwheatMushrooms = CatalogRecipe(
  id: 'traditional-buckwheat-mushrooms',
  title: 'Гречневая каша с грибами',
  detailedSteps: [
    'Нарезать 80 г лука и 500 г грибов, натереть 100 г моркови.',
    'Обжарить лук и морковь на 50 мл растительного масла.',
    'Добавить грибы, соль и обжарить.',
    'Промыть 300 г гречки, добавить к грибам и влить 550 мл воды.',
    'Варить под крышкой 20 минут и оставить на 10 минут.',
  ],
  buildSteps: () => [
    _node('buckwheat-mushrooms-1', CatalogCards.cut, [
      _ingredient('buckwheat-mushrooms-1-onion', CatalogCards.onion, [
        _mass('buckwheat-mushrooms-1-onion-mass', 80),
      ]),
      _ingredient('buckwheat-mushrooms-1-mushrooms', CatalogCards.mushrooms, [
        _mass('buckwheat-mushrooms-1-mushrooms-mass', 500),
      ]),
    ]),
    _node('buckwheat-mushrooms-2', CatalogCards.grate, [
      _ingredient('buckwheat-mushrooms-2-carrot', CatalogCards.carrot, [
        _mass('buckwheat-mushrooms-2-carrot-mass', 100),
      ]),
    ]),
    _node('buckwheat-mushrooms-3', CatalogCards.add, [
      _ingredient('buckwheat-mushrooms-3-oil', CatalogCards.vegetableOil, [
        _volume('buckwheat-mushrooms-3-oil-volume', 50),
      ]),
    ]),
    _node('buckwheat-mushrooms-4', CatalogCards.saute, [
      _ingredient('buckwheat-mushrooms-4-onion', CatalogCards.onion),
      _ingredient('buckwheat-mushrooms-4-carrot', CatalogCards.carrot),
      _time('buckwheat-mushrooms-4-time', 5),
    ]),
    _node('buckwheat-mushrooms-5', CatalogCards.add, [
      _ingredient('buckwheat-mushrooms-5-mushrooms', CatalogCards.mushrooms),
      _ingredient('buckwheat-mushrooms-5-salt', CatalogCards.salt, [
        _mass('buckwheat-mushrooms-5-salt-mass', 5),
      ]),
    ]),
    _node('buckwheat-mushrooms-6', CatalogCards.fry, [
      _ingredient('buckwheat-mushrooms-6-mushrooms', CatalogCards.mushrooms),
      _time('buckwheat-mushrooms-6-time', 7),
    ]),
    _node('buckwheat-mushrooms-7', CatalogCards.rinse, [
      _ingredient('buckwheat-mushrooms-7-buckwheat', CatalogCards.buckwheat, [
        _mass('buckwheat-mushrooms-7-buckwheat-mass', 300),
      ]),
    ]),
    _node('buckwheat-mushrooms-8', CatalogCards.add, [
      _ingredient('buckwheat-mushrooms-8-buckwheat', CatalogCards.buckwheat),
      _ingredient('buckwheat-mushrooms-8-water', CatalogCards.water, [
        _volume('buckwheat-mushrooms-8-water-volume', 550),
      ]),
    ]),
    _node('buckwheat-mushrooms-9', CatalogCards.boil, [
      _ingredient('buckwheat-mushrooms-9-buckwheat', CatalogCards.buckwheat),
      _time('buckwheat-mushrooms-9-time', 20),
    ]),
    _node('buckwheat-mushrooms-10', CatalogCards.leave, [
      _ingredient('buckwheat-mushrooms-10-buckwheat', CatalogCards.buckwheat),
      _time('buckwheat-mushrooms-10-time', 10),
    ]),
  ],
);

CatalogRecipe _porridgeRecipe({
  required String id,
  required String title,
  required CardDefinition grain,
  required int grainMass,
  required int waterVolume,
  required int boilMinutes,
  int? boilUpperMinutes,
  int? soakMinutes,
  int? soakUpperMinutes,
  int? milkVolume,
  int? milkBoilMinutes,
  int? butterMass,
  int sugarMass = 0,
  int saltMass = 1,
  bool seasonAfterFirstBoil = false,
  int finalBoilMinutes = 0,
  int restMinutes = 0,
}) {
  return CatalogRecipe(
    id: id,
    title: title,
    buildSteps: () => [
      if (soakMinutes != null)
        _node('$id-1', CatalogCards.soak, [
          _ingredient('$id-1-grain', grain, [
            _mass('$id-1-grain-mass', grainMass),
          ]),
          _ingredient('$id-1-water', CatalogCards.water, [
            _volume('$id-1-water-volume', waterVolume),
          ]),
          _time('$id-1-time', soakMinutes, soakUpperMinutes),
        ]),
      _node('$id-2', CatalogCards.rinse, [_ingredient('$id-2-grain', grain)]),
      _node('$id-3', CatalogCards.pour, [
        _ingredient('$id-3-water', CatalogCards.water, [
          _volume('$id-3-water-volume', waterVolume),
        ]),
      ]),
      _node('$id-4', CatalogCards.add, [
        _ingredient('$id-4-grain', grain, [
          _mass('$id-4-grain-mass', grainMass),
        ]),
        if (!seasonAfterFirstBoil)
          _ingredient('$id-4-salt', CatalogCards.salt, [
            _mass('$id-4-salt-mass', saltMass),
          ]),
        if (!seasonAfterFirstBoil && sugarMass > 0)
          _ingredient('$id-4-sugar', CatalogCards.sugar, [
            _mass('$id-4-sugar-mass', sugarMass),
          ]),
      ]),
      _node('$id-5', CatalogCards.boil, [
        _ingredient('$id-5-grain', grain),
        _time('$id-5-time', boilMinutes, boilUpperMinutes),
      ]),
      if (milkVolume != null)
        _node('$id-6', CatalogCards.pour, [
          _ingredient('$id-6-milk', CatalogCards.milk, [
            _volume('$id-6-milk-volume', milkVolume),
          ]),
        ]),
      if (milkVolume != null && seasonAfterFirstBoil)
        _node('$id-6-season', CatalogCards.add, [
          _ingredient('$id-6-salt', CatalogCards.salt, [
            _mass('$id-6-salt-mass', saltMass),
          ]),
          if (sugarMass > 0)
            _ingredient('$id-6-sugar', CatalogCards.sugar, [
              _mass('$id-6-sugar-mass', sugarMass),
            ]),
        ]),
      if (milkBoilMinutes != null)
        _node('$id-7', CatalogCards.boil, [
          _ingredient('$id-7-grain', grain),
          _time('$id-7-time', milkBoilMinutes),
        ]),
      if (milkVolume == null && seasonAfterFirstBoil)
        _node('$id-7-season', CatalogCards.add, [
          _ingredient('$id-7-salt', CatalogCards.salt, [
            _mass('$id-7-salt-mass', saltMass),
          ]),
          if (sugarMass > 0)
            _ingredient('$id-7-sugar', CatalogCards.sugar, [
              _mass('$id-7-sugar-mass', sugarMass),
            ]),
        ]),
      if (finalBoilMinutes > 0)
        _node('$id-7-final', CatalogCards.boil, [
          _ingredient('$id-7-grain', grain),
          _time('$id-7-final-time', finalBoilMinutes),
        ]),
      if (butterMass != null)
        _node('$id-8', CatalogCards.add, [
          _ingredient('$id-8-butter', CatalogCards.butter, [
            _mass('$id-8-butter-mass', butterMass),
          ]),
        ]),
      if (restMinutes > 0)
        _node('$id-9', CatalogCards.leave, [
          _ingredient('$id-9-grain', grain),
          _time('$id-9-time', restMinutes),
        ]),
    ],
  );
}

final _traditionalOatmeal = CatalogRecipe(
  id: 'traditional-oatmeal',
  title: 'Каша овсяная',
  buildSteps: () => [
    _node('oatmeal-1', CatalogCards.pour, [
      _ingredient('oatmeal-1-milk', CatalogCards.milk, [
        _volume('oatmeal-1-milk-volume', 475),
      ]),
      _ingredient('oatmeal-1-water', CatalogCards.water, [
        _volume('oatmeal-1-water-volume', 240),
      ]),
    ]),
    _node('oatmeal-2', CatalogCards.add, [
      _ingredient('oatmeal-2-sugar', CatalogCards.sugar, [
        _mass('oatmeal-2-sugar-mass', 13),
      ]),
      _ingredient('oatmeal-2-salt', CatalogCards.salt, [
        _mass('oatmeal-2-salt-mass', 1),
      ]),
    ]),
    _node('oatmeal-3', CatalogCards.heat, [
      _ingredient('oatmeal-3-milk', CatalogCards.milk),
      _time('oatmeal-3-time', 3),
    ]),
    _node('oatmeal-4', CatalogCards.add, [
      _ingredient('oatmeal-4-oats', CatalogCards.oats, [
        _mass('oatmeal-4-oats-mass', 90),
      ]),
    ]),
    _node('oatmeal-5', CatalogCards.boil, [
      _ingredient('oatmeal-5-oats', CatalogCards.oats),
      _time('oatmeal-5-time', 10, 12),
    ]),
    _node('oatmeal-6', CatalogCards.add, [
      _ingredient('oatmeal-6-butter', CatalogCards.butter, [
        _mass('oatmeal-6-butter-mass', 30),
      ]),
    ]),
    _node('oatmeal-7', CatalogCards.leave, [
      _ingredient('oatmeal-7-oats', CatalogCards.oats),
      _time('oatmeal-7-time', 3),
    ]),
  ],
);

final _traditionalPorridges = <CatalogRecipe>[
  _porridgeRecipe(
    id: 'traditional-millet-porridge',
    title: 'Каша пшённая',
    grain: CatalogCards.millet,
    grainMass: 100,
    waterVolume: 500,
    milkVolume: 500,
    sugarMass: 4,
    saltMass: 3,
    soakMinutes: 5,
    soakUpperMinutes: 10,
    boilMinutes: 8,
    boilUpperMinutes: 10,
    milkBoilMinutes: 5,
    butterMass: 30,
    seasonAfterFirstBoil: true,
    restMinutes: 5,
  ),
  _porridgeRecipe(
    id: 'traditional-pea-porridge',
    title: 'Каша гороховая',
    grain: CatalogCards.peas,
    grainMass: 180,
    waterVolume: 400,
    saltMass: 3,
    soakMinutes: 360,
    soakUpperMinutes: 480,
    boilMinutes: 45,
    boilUpperMinutes: 55,
    butterMass: 20,
    seasonAfterFirstBoil: true,
    finalBoilMinutes: 5,
  ),
];

final _traditionalSemolinaPorridge = CatalogRecipe(
  id: 'traditional-semolina-porridge',
  title: 'Манная каша',
  detailedSteps: [
    'Смешать 500 мл холодного молока и 45 г манной крупы венчиком.',
    'Нагревать смесь, постоянно перемешивая, до начала тихого кипения.',
    'Добавить сахар и соль, варить 3–5 минут.',
    'Добавить 15 г сливочного масла и оставить на 2 минуты.',
  ],
  buildSteps: () => [
    _node('semolina-1', CatalogCards.mix, [
      _ingredient('semolina-1-milk', CatalogCards.milk, [
        _volume('semolina-1-milk-volume', 500),
      ]),
      _ingredient('semolina-1-grain', CatalogCards.semolina, [
        _mass('semolina-1-grain-mass', 45),
      ]),
    ]),
    _node('semolina-2', CatalogCards.heat, [
      _ingredient('semolina-2-milk', CatalogCards.milk),
      _time('semolina-2-time', 5),
    ]),
    _node('semolina-3', CatalogCards.add, [
      _ingredient('semolina-3-sugar', CatalogCards.sugar, [
        _mass('semolina-3-sugar-mass', 8),
      ]),
      _ingredient('semolina-3-salt', CatalogCards.salt, [
        _mass('semolina-3-salt-mass', 1),
      ]),
    ]),
    _node('semolina-4', CatalogCards.boil, [
      _ingredient('semolina-4-grain', CatalogCards.semolina),
      _time('semolina-4-time', 3, 5),
    ]),
    _node('semolina-5', CatalogCards.add, [
      _ingredient('semolina-5-butter', CatalogCards.butter, [
        _mass('semolina-5-butter-mass', 15),
      ]),
    ]),
    _node('semolina-6', CatalogCards.leave, [
      _ingredient('semolina-6-grain', CatalogCards.semolina),
      _time('semolina-6-time', 2),
    ]),
  ],
);

final _traditionalSyrniki = CatalogRecipe(
  id: 'traditional-syrniki',
  title: 'Сырники',
  detailedSteps: [
    'Смешать 400 г творога, 1 яйцо, 40 г сахара, 35 г муки и соль.',
    'Сформировать сырники и обвалять их в оставшейся муке.',
    'Жарить на растительном масле по 2–3 минуты с каждой стороны.',
  ],
  buildSteps: () => [
    _node('syrniki-1', CatalogCards.mix, [
      _ingredient('syrniki-1-cottage-cheese', CatalogCards.cottageCheese, [
        _mass('syrniki-1-cottage-cheese-mass', 400),
      ]),
      _ingredient('syrniki-1-eggs', CatalogCards.eggs, [
        RecipeNode(
          id: 'syrniki-1-eggs-count',
          card: CatalogCards.count,
          value: 1,
          unit: NumericUnit.pieces,
        ),
      ]),
      _ingredient('syrniki-1-sugar', CatalogCards.sugar, [
        _mass('syrniki-1-sugar-mass', 40),
      ]),
      _ingredient('syrniki-1-flour', CatalogCards.flour, [
        _mass('syrniki-1-flour-mass', 35),
      ]),
      _ingredient('syrniki-1-salt', CatalogCards.salt, [
        _mass('syrniki-1-salt-mass', 1),
      ]),
    ]),
    _node('syrniki-2', CatalogCards.form, [
      _ingredient('syrniki-2-cottage-cheese', CatalogCards.cottageCheese),
      _ingredient('syrniki-2-flour', CatalogCards.flour, [
        _mass('syrniki-2-flour-mass', 25),
      ]),
    ]),
    _node('syrniki-3', CatalogCards.add, [
      _ingredient('syrniki-3-oil', CatalogCards.vegetableOil, [
        _volume('syrniki-3-oil-volume', 30),
      ]),
    ]),
    _node('syrniki-4', CatalogCards.fry, [
      _ingredient('syrniki-4-cottage-cheese', CatalogCards.cottageCheese),
      _time('syrniki-4-time', 2, 3),
    ]),
    _node('syrniki-5', CatalogCards.fry, [
      _ingredient('syrniki-5-cottage-cheese', CatalogCards.cottageCheese),
      _time('syrniki-5-time', 2, 3),
    ]),
  ],
);

final _traditionalYeastPancakes = CatalogRecipe(
  id: 'traditional-yeast-pancakes',
  title: 'Блины дрожжевые',
  detailedSteps: [
    'Подогреть 500 мл молока.',
    'Смешать 250 г муки, 10 г сухих дрожжей, сахар, соль и молоко.',
    'Оставить тесто на 60 минут.',
    'Добавить яйцо и 30 г сливочного масла.',
    'Жарить блины на смазанной чаше по 2 минуты с каждой стороны.',
  ],
  buildSteps: () => [
    _node('yeast-pancakes-1', CatalogCards.heat, [
      _ingredient('yeast-pancakes-1-milk', CatalogCards.milk, [
        _volume('yeast-pancakes-1-milk-volume', 500),
      ]),
      _time('yeast-pancakes-1-time', 3),
    ]),
    _node('yeast-pancakes-2', CatalogCards.mix, [
      _ingredient('yeast-pancakes-2-flour', CatalogCards.flour, [
        _mass('yeast-pancakes-2-flour-mass', 250),
      ]),
      _ingredient('yeast-pancakes-2-yeast', CatalogCards.yeast, [
        _mass('yeast-pancakes-2-yeast-mass', 10),
      ]),
      _ingredient('yeast-pancakes-2-sugar', CatalogCards.sugar, [
        _mass('yeast-pancakes-2-sugar-mass', 15),
      ]),
      _ingredient('yeast-pancakes-2-salt', CatalogCards.salt, [
        _mass('yeast-pancakes-2-salt-mass', 3),
      ]),
      _ingredient('yeast-pancakes-2-milk', CatalogCards.milk),
    ]),
    _node('yeast-pancakes-3', CatalogCards.leave, [
      _ingredient('yeast-pancakes-3-batter', CatalogCards.batter),
      _time('yeast-pancakes-3-time', 60),
    ]),
    _node('yeast-pancakes-4', CatalogCards.add, [
      _ingredient('yeast-pancakes-4-eggs', CatalogCards.eggs, [
        RecipeNode(
          id: 'yeast-pancakes-4-eggs-count',
          card: CatalogCards.count,
          value: 1,
          unit: NumericUnit.pieces,
        ),
      ]),
      _ingredient('yeast-pancakes-4-butter', CatalogCards.butter, [
        _mass('yeast-pancakes-4-butter-mass', 30),
      ]),
    ]),
    _node('yeast-pancakes-5', CatalogCards.grease, [
      _ingredient('yeast-pancakes-5-butter', CatalogCards.butter, [
        _mass('yeast-pancakes-5-butter-mass', 10),
      ]),
    ]),
    _node('yeast-pancakes-6', CatalogCards.fry, [
      _ingredient('yeast-pancakes-6-batter', CatalogCards.batter),
      _time('yeast-pancakes-6-time', 2),
    ]),
    _node('yeast-pancakes-7', CatalogCards.fry, [
      _ingredient('yeast-pancakes-7-batter', CatalogCards.batter),
      _time('yeast-pancakes-7-time', 2),
    ]),
  ],
);

/// Какао на молоке по рецепту «ГдеРецепт»: 500 мл молока, 25 г какао,
/// 30 г сахара и 40 мл воды. Порошок и сахар сначала разводятся водой,
/// после чего соединяются с горячим молоком.
final _traditionalCocoa = CatalogRecipe(
  id: 'traditional-cocoa-milk',
  title: 'Какао на молоке',
  detailedSteps: [
    'Смешать 25 г какао, 30 г сахара и 40 мл воды.',
    'Подогреть 500 мл молока.',
    'Добавить смесь какао в молоко и довести до кипения.',
  ],
  buildSteps: () => [
    _node('cocoa-1', CatalogCards.mix, [
      _ingredient('cocoa-1-cocoa', CatalogCards.cocoa, [
        _mass('cocoa-1-cocoa-mass', 25),
      ]),
      _ingredient('cocoa-1-sugar', CatalogCards.sugar, [
        _mass('cocoa-1-sugar-mass', 30),
      ]),
      _ingredient('cocoa-1-water', CatalogCards.water, [
        _volume('cocoa-1-water-volume', 40),
      ]),
    ]),
    _node('cocoa-2', CatalogCards.heat, [
      _ingredient('cocoa-2-milk', CatalogCards.milk, [
        _volume('cocoa-2-milk-volume', 500),
      ]),
    ]),
    _node('cocoa-3', CatalogCards.add, [
      _ingredient('cocoa-3-cocoa', CatalogCards.cocoa),
      _ingredient('cocoa-3-sugar', CatalogCards.sugar),
      _ingredient('cocoa-3-water', CatalogCards.water),
    ]),
    _node('cocoa-4', CatalogCards.boil, [
      _ingredient('cocoa-4-milk', CatalogCards.milk),
      _time('cocoa-4-time', 1),
    ]),
  ],
);

/// Классическая кабачковая икра по пошаговому рецепту IamCook. Количества
/// сохранены в карточках; ложки переведены в граммы и миллилитры: 15 мл
/// яблочного уксуса, 7 г соли и 8 г сахара.
final _traditionalSquashCaviar = CatalogRecipe(
  id: 'traditional-squash-caviar',
  title: 'Икра кабачковая',
  detailedSteps: [
    'Нарезать 1 кг кабачков, 230 г моркови и 200 г лука.',
    'Обжарить лук, морковь и кабачки по отдельности, используя до 100 мл масла.',
    'Соединить овощи и обжаривать 15–20 минут.',
    'Измельчить овощи блендером, кипятить 10 минут.',
    'Добавить 90 г томатной пасты, соль и сахар; прогреть 10 минут.',
    'Добавить чеснок и 15 мл уксуса, прогреть 3 минуты.',
  ],
  buildSteps: () => [
    _node('squash-caviar-1', CatalogCards.cut, [
      _ingredient('squash-caviar-1-zucchini', CatalogCards.zucchini, [
        _mass('squash-caviar-1-zucchini-mass', 1000),
      ]),
      _ingredient('squash-caviar-1-carrot', CatalogCards.carrot, [
        _mass('squash-caviar-1-carrot-mass', 230),
      ]),
      _ingredient('squash-caviar-1-onion', CatalogCards.onion, [
        _mass('squash-caviar-1-onion-mass', 200),
      ]),
    ]),
    _node('squash-caviar-2', CatalogCards.add, [
      _ingredient('squash-caviar-2-oil', CatalogCards.vegetableOil, [
        _volume('squash-caviar-2-oil-volume', 100),
      ]),
    ]),
    _node('squash-caviar-3', CatalogCards.fry, [
      _ingredient('squash-caviar-3-onion', CatalogCards.onion),
      _time('squash-caviar-3-time', 5),
    ]),
    _node('squash-caviar-4', CatalogCards.fry, [
      _ingredient('squash-caviar-4-carrot', CatalogCards.carrot),
      _time('squash-caviar-4-time', 5),
    ]),
    _node('squash-caviar-5', CatalogCards.fry, [
      _ingredient('squash-caviar-5-zucchini', CatalogCards.zucchini),
      _time('squash-caviar-5-time', 5),
    ]),
    _node('squash-caviar-6', CatalogCards.fry, [
      _ingredient('squash-caviar-6-zucchini', CatalogCards.zucchini),
      _ingredient('squash-caviar-6-carrot', CatalogCards.carrot),
      _ingredient('squash-caviar-6-onion', CatalogCards.onion),
      _time('squash-caviar-6-time', 15, 20),
    ]),
    _node('squash-caviar-7', CatalogCards.blend, [
      _ingredient('squash-caviar-7-zucchini', CatalogCards.zucchini),
      _ingredient('squash-caviar-7-carrot', CatalogCards.carrot),
      _ingredient('squash-caviar-7-onion', CatalogCards.onion),
    ]),
    _node('squash-caviar-8', CatalogCards.boil, [
      _ingredient('squash-caviar-8-zucchini', CatalogCards.zucchini),
      _time('squash-caviar-8-time', 10),
    ]),
    _node('squash-caviar-9', CatalogCards.add, [
      _ingredient('squash-caviar-9-tomato-paste', CatalogCards.tomatoPaste, [
        _mass('squash-caviar-9-tomato-paste-mass', 90),
      ]),
      _ingredient('squash-caviar-9-salt', CatalogCards.salt, [
        _mass('squash-caviar-9-salt-mass', 7),
      ]),
      _ingredient('squash-caviar-9-sugar', CatalogCards.sugar, [
        _mass('squash-caviar-9-sugar-mass', 8),
      ]),
    ]),
    _node('squash-caviar-10', CatalogCards.heat, [
      _ingredient('squash-caviar-10-zucchini', CatalogCards.zucchini),
      _time('squash-caviar-10-time', 10),
    ]),
    _node('squash-caviar-11', CatalogCards.add, [
      _ingredient('squash-caviar-11-garlic', CatalogCards.garlic, [
        RecipeNode(
          id: 'squash-caviar-11-garlic-count',
          card: CatalogCards.count,
          value: 2,
          unit: NumericUnit.pieces,
        ),
      ]),
      _ingredient('squash-caviar-11-vinegar', CatalogCards.vinegar, [
        _volume('squash-caviar-11-vinegar-volume', 15),
      ]),
    ]),
    _node('squash-caviar-12', CatalogCards.heat, [
      _ingredient('squash-caviar-12-zucchini', CatalogCards.zucchini),
      _time('squash-caviar-12-time', 3),
    ]),
  ],
);

/// Малиновое варенье по рецепту «Фото-рецепты»: 1 кг малины и 700 г сахара,
/// выдержка сутки и кипячение 10 минут.
final _traditionalRaspberryJam = CatalogRecipe(
  id: 'traditional-raspberry-jam',
  title: 'Варенье малиновое',
  detailedSteps: [
    'Смешать 1 кг малины и 700 г сахара.',
    'Оставить на 24 часа.',
    'Довести до кипения и кипятить 10 минут.',
  ],
  buildSteps: () => [
    _node('raspberry-jam-1', CatalogCards.mix, [
      _ingredient('raspberry-jam-1-raspberries', CatalogCards.raspberries, [
        _mass('raspberry-jam-1-raspberries-mass', 1000),
      ]),
      _ingredient('raspberry-jam-1-sugar', CatalogCards.sugar, [
        _mass('raspberry-jam-1-sugar-mass', 700),
      ]),
    ]),
    _node('raspberry-jam-2', CatalogCards.leave, [
      _ingredient('raspberry-jam-2-raspberries', CatalogCards.raspberries),
      _time('raspberry-jam-2-time', 1440),
    ]),
    _node('raspberry-jam-3', CatalogCards.boil, [
      _ingredient('raspberry-jam-3-raspberries', CatalogCards.raspberries),
      _time('raspberry-jam-3-time', 10),
    ]),
  ],
);

/// Перловая каша на воде со сливочным маслом по рецепту GARLYN. В отличие от
/// общего шаблона каш отдельно хранит десятиминутное замачивание и программу
/// мультиварки, указанные в источнике.
final _traditionalPearlBarley = CatalogRecipe(
  id: 'traditional-pearl-barley',
  title: 'Каша перловая',
  detailedSteps: [
    'Замочить 230 г перловой крупы на 10 минут, затем промыть.',
    'Добавить 500 мл воды и соль.',
    'Выбрать программу «Молочная каша» на 40 минут.',
    'Оставить кашу под крышкой на 10–15 минут.',
    'Добавить 50 г сливочного масла и перемешать.',
  ],
  buildSteps: () => [
    _node('pearl-barley-1', CatalogCards.soak, [
      _ingredient('pearl-barley-1-grain', CatalogCards.pearlBarley, [
        _mass('pearl-barley-1-grain-mass', 230),
      ]),
      _time('pearl-barley-1-time', 10),
    ]),
    _node('pearl-barley-2', CatalogCards.rinse, [
      _ingredient('pearl-barley-2-grain', CatalogCards.pearlBarley),
    ]),
    _node('pearl-barley-3', CatalogCards.pour, [
      _ingredient('pearl-barley-3-water', CatalogCards.water, [
        _volume('pearl-barley-3-water-volume', 500),
      ]),
    ]),
    _node('pearl-barley-4', CatalogCards.add, [
      _ingredient('pearl-barley-4-grain', CatalogCards.pearlBarley, [
        _mass('pearl-barley-4-grain-mass', 230),
      ]),
      _ingredient('pearl-barley-4-salt', CatalogCards.salt),
    ]),
    _multicookerStep('pearl-barley-5', 'Молочная каша', 40),
    _node('pearl-barley-6', CatalogCards.leave, [
      _ingredient('pearl-barley-6-grain', CatalogCards.pearlBarley),
      _time('pearl-barley-6-time', 10, 15),
    ]),
    _node('pearl-barley-7', CatalogCards.add, [
      _ingredient('pearl-barley-7-butter', CatalogCards.butter, [
        _mass('pearl-barley-7-butter-mass', 50),
      ]),
    ]),
    _node('pearl-barley-8', CatalogCards.stir, [
      _ingredient('pearl-barley-8-grain', CatalogCards.pearlBarley),
    ]),
  ],
);

/// Классическая творожная запеканка по московской рецептуре: все массы,
/// температура и время выпекания перенесены в параметры карточек.
final _traditionalCottageCheeseCasserole = CatalogRecipe(
  id: 'traditional-cottage-cheese-casserole',
  title: 'Творожная запеканка классическая',
  detailedSteps: [
    'Смешать 500 г творога, 3 яйца, 45 г манной крупы, 100 г сахара, 50 г масла, 1 г ванили, 50 г изюма и 3 г соли.',
    'Смазать форму маслом и выложить массу.',
    'Запекать при 180 °C 35 минут.',
  ],
  buildSteps: () => [
    _node('cottage-casserole-1', CatalogCards.mix, [
      _ingredient(
        'cottage-casserole-1-cottage-cheese',
        CatalogCards.cottageCheese,
        [_mass('cottage-casserole-1-cottage-cheese-mass', 500)],
      ),
      _ingredient('cottage-casserole-1-eggs', CatalogCards.eggs, [
        RecipeNode(
          id: 'cottage-casserole-1-eggs-count',
          card: CatalogCards.count,
          value: 3,
          unit: NumericUnit.pieces,
        ),
      ]),
      _ingredient('cottage-casserole-1-semolina', CatalogCards.semolina, [
        _mass('cottage-casserole-1-semolina-mass', 45),
      ]),
      _ingredient('cottage-casserole-1-sugar', CatalogCards.sugar, [
        _mass('cottage-casserole-1-sugar-mass', 100),
      ]),
      _ingredient('cottage-casserole-1-butter', CatalogCards.butter, [
        _mass('cottage-casserole-1-butter-mass', 50),
      ]),
      _ingredient('cottage-casserole-1-vanilla', CatalogCards.vanilla, [
        _mass('cottage-casserole-1-vanilla-mass', 1),
      ]),
      _ingredient('cottage-casserole-1-raisins', CatalogCards.raisins, [
        _mass('cottage-casserole-1-raisins-mass', 50),
      ]),
      _ingredient('cottage-casserole-1-salt', CatalogCards.salt, [
        _mass('cottage-casserole-1-salt-mass', 3),
      ]),
    ]),
    _node('cottage-casserole-2', CatalogCards.grease, [
      _ingredient('cottage-casserole-2-baking-sheet', CatalogCards.bakingSheet),
      _ingredient('cottage-casserole-2-butter', CatalogCards.butter),
    ]),
    _node('cottage-casserole-3', CatalogCards.transfer, [
      _ingredient(
        'cottage-casserole-3-cottage-cheese',
        CatalogCards.cottageCheese,
      ),
      _ingredient('cottage-casserole-3-baking-sheet', CatalogCards.bakingSheet),
    ]),
    _node('cottage-casserole-4', CatalogCards.preheat, [
      _ingredient('cottage-casserole-4-oven', CatalogCards.oven),
    ]),
    _node('cottage-casserole-5', CatalogCards.select, [
      _ingredient('cottage-casserole-5-heat', CatalogCards.ovenTopBottomHeat),
      RecipeNode(
        id: 'cottage-casserole-5-temperature',
        card: CatalogCards.temperature,
        value: 180,
        unit: NumericUnit.celsius,
      ),
    ]),
    _node('cottage-casserole-6', CatalogCards.bake, [
      _ingredient(
        'cottage-casserole-6-cottage-cheese',
        CatalogCards.cottageCheese,
      ),
      _time('cottage-casserole-6-time', 35),
    ]),
  ],
);

/// Минимальная печёная свёкла: противень, 180 °C и один час — параметры
/// опубликованного рецепта без необязательных добавок.
final _traditionalBakedBeet = CatalogRecipe(
  id: 'traditional-baked-beet',
  title: 'Печёная свёкла',
  detailedSteps: [
    'Разогреть духовку до 180 °C.',
    'Выложить свёклу на противень.',
    'Запекать 60 минут.',
  ],
  buildSteps: () => [
    _node('baked-beet-1', CatalogCards.preheat, [
      _ingredient('baked-beet-1-oven', CatalogCards.oven),
    ]),
    _node('baked-beet-2', CatalogCards.select, [
      _ingredient('baked-beet-2-heat', CatalogCards.ovenTopBottomHeat),
      RecipeNode(
        id: 'baked-beet-2-temperature',
        card: CatalogCards.temperature,
        value: 180,
        unit: NumericUnit.celsius,
      ),
    ]),
    _node('baked-beet-3', CatalogCards.transfer, [
      _ingredient('baked-beet-3-beet', CatalogCards.beet),
      _ingredient('baked-beet-3-baking-sheet', CatalogCards.bakingSheet),
    ]),
    _node('baked-beet-4', CatalogCards.bake, [
      _ingredient('baked-beet-4-beet', CatalogCards.beet),
      _time('baked-beet-4-time', 60),
    ]),
  ],
);

/// Классический салат «Столичный» с курицей. Состав, массы и времена варки
/// перенесены без замены продуктов из опубликованной рецептуры.
final _traditionalCapitalSalad = CatalogRecipe(
  id: 'traditional-capital-salad',
  title: 'Салат «Столичный» с курицей',
  detailedSteps: [
    'Отварить 350 г куриного филе 20 минут до готовности.',
    'Отварить 400 г картофеля и 150 г моркови 25 минут до мягкости.',
    'Сварить 4 яйца вкрутую 10 минут.',
    'Нарезать небольшими кубиками куриное филе, картофель, морковь, яйца и 200 г солёных огурцов.',
    'Соединить подготовленные продукты со 180 г зелёного горошка.',
    'Добавить 140 г майонеза, 5 г соли и 2 г чёрного перца, перемешать.',
    'Добавить 20 г укропа.',
  ],
  buildSteps: () => [
    _node('capital-salad-1', CatalogCards.boil, [
      _ingredient('capital-salad-1-chicken', CatalogCards.chickenFillet, [
        _mass('capital-salad-1-chicken-mass', 350),
      ]),
      _time('capital-salad-1-time', 20),
    ]),
    _node('capital-salad-2', CatalogCards.boil, [
      _ingredient('capital-salad-2-potato', CatalogCards.potato, [
        _mass('capital-salad-2-potato-mass', 400),
      ]),
      _ingredient('capital-salad-2-carrot', CatalogCards.carrot, [
        _mass('capital-salad-2-carrot-mass', 150),
      ]),
      _time('capital-salad-2-time', 25),
    ]),
    _node('capital-salad-3', CatalogCards.boil, [
      _ingredient('capital-salad-3-eggs', CatalogCards.eggs, [
        RecipeNode(
          id: 'capital-salad-3-eggs-count',
          card: CatalogCards.count,
          value: 4,
          unit: NumericUnit.pieces,
        ),
      ]),
      _time('capital-salad-3-time', 10),
    ]),
    _node('capital-salad-4', CatalogCards.cut, [
      _ingredient('capital-salad-4-chicken', CatalogCards.chickenFillet),
      _ingredient('capital-salad-4-potato', CatalogCards.potato),
      _ingredient('capital-salad-4-carrot', CatalogCards.carrot),
      _ingredient('capital-salad-4-eggs', CatalogCards.eggs),
      _ingredient('capital-salad-4-cucumbers', CatalogCards.pickledCucumbers, [
        _mass('capital-salad-4-cucumbers-mass', 200),
      ]),
    ]),
    _node('capital-salad-5', CatalogCards.mix, [
      _ingredient('capital-salad-5-chicken', CatalogCards.chickenFillet),
      _ingredient('capital-salad-5-potato', CatalogCards.potato),
      _ingredient('capital-salad-5-carrot', CatalogCards.carrot),
      _ingredient('capital-salad-5-eggs', CatalogCards.eggs),
      _ingredient('capital-salad-5-cucumbers', CatalogCards.pickledCucumbers),
      _ingredient('capital-salad-5-peas', CatalogCards.greenPeas, [
        _mass('capital-salad-5-peas-mass', 180),
      ]),
    ]),
    _node('capital-salad-6', CatalogCards.add, [
      _ingredient('capital-salad-6-mayonnaise', CatalogCards.mayonnaise, [
        _mass('capital-salad-6-mayonnaise-mass', 140),
      ]),
      _ingredient('capital-salad-6-salt', CatalogCards.salt, [
        _mass('capital-salad-6-salt-mass', 5),
      ]),
      _ingredient('capital-salad-6-pepper', CatalogCards.blackPepper, [
        _mass('capital-salad-6-pepper-mass', 2),
      ]),
    ]),
    _node('capital-salad-7', CatalogCards.mix, [
      _ingredient('capital-salad-7-mayonnaise', CatalogCards.mayonnaise),
    ]),
    _node('capital-salad-8', CatalogCards.add, [
      _ingredient('capital-salad-8-dill', CatalogCards.dill, [
        _mass('capital-salad-8-dill-mass', 20),
      ]),
    ]),
  ],
);

/// Гуляш по опубликованной советской рецептуре: все величины остаются в
/// исходных единицах, включая объём растительного масла и воды.
final _traditionalSovietGoulash = CatalogRecipe(
  id: 'traditional-soviet-goulash',
  title: 'Гуляш из говядины по-советски',
  detailedSteps: [
    'Нарезать 800 г говядины и 2 луковицы.',
    'Обжарить 60 г муки на сухой поверхности до кремового цвета.',
    'Обжарить 80 г томатной пасты на 30 мл растительного масла, добавить муку и 200 мл воды, перемешать.',
    'Обжарить говядину на оставшихся 50 мл растительного масла до корочки.',
    'Добавить лук и обжарить до золотистого цвета.',
    'Влить 800 мл воды и варить 90–120 минут под приоткрытой крышкой.',
    'Добавить 15 г сахара, соль, чёрный перец, 2 лавровых листа и томатную заправку; перемешать и прогреть до нужной густоты.',
  ],
  buildSteps: () => [
    _node('soviet-goulash-1', CatalogCards.cut, [
      _ingredient('soviet-goulash-1-beef', CatalogCards.beef, [
        _mass('soviet-goulash-1-beef-mass', 800),
      ]),
      _ingredient('soviet-goulash-1-onion', CatalogCards.onion, [
        RecipeNode(
          id: 'soviet-goulash-1-onion-count',
          card: CatalogCards.count,
          value: 2,
          unit: NumericUnit.pieces,
        ),
      ]),
    ]),
    _node('soviet-goulash-2', CatalogCards.fry, [
      _ingredient('soviet-goulash-2-flour', CatalogCards.flour, [
        _mass('soviet-goulash-2-flour-mass', 60),
      ]),
      _time('soviet-goulash-2-time', 3),
    ]),
    _node('soviet-goulash-3', CatalogCards.add, [
      _ingredient('soviet-goulash-3-oil', CatalogCards.vegetableOil, [
        _volume('soviet-goulash-3-oil-volume', 30),
      ]),
    ]),
    _node('soviet-goulash-4', CatalogCards.fry, [
      _ingredient('soviet-goulash-4-paste', CatalogCards.tomatoPaste, [
        _mass('soviet-goulash-4-paste-mass', 80),
      ]),
      _time('soviet-goulash-4-time', 2),
    ]),
    _node('soviet-goulash-5', CatalogCards.add, [
      _ingredient('soviet-goulash-5-flour', CatalogCards.flour),
      _ingredient('soviet-goulash-5-water', CatalogCards.water, [
        _volume('soviet-goulash-5-water-volume', 200),
      ]),
    ]),
    _node('soviet-goulash-6', CatalogCards.mix, [
      _ingredient('soviet-goulash-6-paste', CatalogCards.tomatoPaste),
      _ingredient('soviet-goulash-6-flour', CatalogCards.flour),
      _ingredient('soviet-goulash-6-water', CatalogCards.water),
    ]),
    _node('soviet-goulash-7', CatalogCards.add, [
      _ingredient('soviet-goulash-7-oil', CatalogCards.vegetableOil, [
        _volume('soviet-goulash-7-oil-volume', 50),
      ]),
    ]),
    _node('soviet-goulash-8', CatalogCards.fry, [
      _ingredient('soviet-goulash-8-beef', CatalogCards.beef),
      _time('soviet-goulash-8-time', 5, 7),
    ]),
    _node('soviet-goulash-9', CatalogCards.add, [
      _ingredient('soviet-goulash-9-onion', CatalogCards.onion),
    ]),
    _node('soviet-goulash-10', CatalogCards.fry, [
      _ingredient('soviet-goulash-10-onion', CatalogCards.onion),
      _time('soviet-goulash-10-time', 5),
    ]),
    _node('soviet-goulash-11', CatalogCards.add, [
      _ingredient('soviet-goulash-11-water', CatalogCards.water, [
        _volume('soviet-goulash-11-water-volume', 800),
      ]),
    ]),
    _node('soviet-goulash-12', CatalogCards.boil, [
      _ingredient('soviet-goulash-12-beef', CatalogCards.beef),
      _time('soviet-goulash-12-time', 90, 120),
    ]),
    _node('soviet-goulash-13', CatalogCards.add, [
      _ingredient('soviet-goulash-13-sugar', CatalogCards.sugar, [
        _mass('soviet-goulash-13-sugar-mass', 15),
      ]),
      _ingredient('soviet-goulash-13-salt', CatalogCards.salt),
      _ingredient('soviet-goulash-13-pepper', CatalogCards.blackPepper),
      _ingredient('soviet-goulash-13-bay-leaf', CatalogCards.bayLeaf, [
        RecipeNode(
          id: 'soviet-goulash-13-bay-leaf-count',
          card: CatalogCards.count,
          value: 2,
          unit: NumericUnit.pieces,
        ),
      ]),
      _ingredient('soviet-goulash-13-paste', CatalogCards.tomatoPaste),
    ]),
    _node('soviet-goulash-14', CatalogCards.stew, [
      _ingredient('soviet-goulash-14-beef', CatalogCards.beef),
      _time('soviet-goulash-14-time', 5),
    ]),
  ],
);

/// Ленивые голубцы из согласованной рецептуры для CE5A0FF2. В ней нет
/// свободных деталей: продукты, действия, режимы и интервалы представлены
/// существующими модульными карточками.
final _lazyCabbageRolls = CatalogRecipe(
  id: 'lazy-cabbage-rolls-multicooker',
  title: 'Ленивые голубцы в томатно-сметанном соусе',
  servings: 8,
  detailedSteps: [
    'Нашинковать 750 г капусты, ошпарить и откинуть на дуршлаг.',
    'Промыть 120 г риса, отварить 8–10 минут до полуготовности и слить воду.',
    'На программе «Жарка» обжарить 150 г лука и 120 г моркови на 20 мл масла.',
    'Смешать фарш, капусту, рис, зажарку, яйца С2, чеснок, соль, перец и паприку; оставить на 10 минут.',
    'Сформировать 14–16 голубцов и обжарить партиями по 3–4 минуты.',
    'Смешать томатную пасту, воду, сахар и соль; добавить лавровый лист.',
    'На программе «Тушение» готовить 12–15 минут, затем дать давлению снизиться 10 минут.',
    'Добавить 150 г сметаны, прогреть на «Жарке» 2–3 минуты и оставить под крышкой на 10 минут.',
  ],
  buildSteps: () => [
    _node('lazy-rolls-1', CatalogCards.shred, [
      _ingredient('lazy-rolls-1-cabbage', CatalogCards.cabbage, [
        _mass('lazy-rolls-1-cabbage-mass', 750),
      ]),
    ]),
    _node('lazy-rolls-2', CatalogCards.boil, [
      _ingredient('lazy-rolls-2-cabbage', CatalogCards.cabbage),
      _time('lazy-rolls-2-time', 5, 7),
    ]),
    _node('lazy-rolls-3', CatalogCards.drain, [
      _ingredient('lazy-rolls-3-cabbage', CatalogCards.cabbage),
    ]),
    _node('lazy-rolls-4', CatalogCards.rinse, [
      _ingredient('lazy-rolls-4-rice', CatalogCards.rice, [
        _mass('lazy-rolls-4-rice-mass', 120),
      ]),
    ]),
    _node('lazy-rolls-5', CatalogCards.boil, [
      _ingredient('lazy-rolls-5-rice', CatalogCards.rice),
      _time('lazy-rolls-5-time', 8, 10),
    ]),
    _node('lazy-rolls-6', CatalogCards.drain, [
      _ingredient('lazy-rolls-6-rice', CatalogCards.rice),
    ]),
    _multicookerStep('lazy-rolls-7', 'Жарка', 7, 8),
    _node('lazy-rolls-8', CatalogCards.add, [
      _ingredient('lazy-rolls-8-oil', CatalogCards.vegetableOil, [
        _volume('lazy-rolls-8-oil-volume', 20),
      ]),
    ]),
    _node('lazy-rolls-9', CatalogCards.fry, [
      _ingredient('lazy-rolls-9-onion', CatalogCards.onion, [
        _mass('lazy-rolls-9-onion-mass', 150),
      ]),
      _time('lazy-rolls-9-time', 3, 4),
    ]),
    _node('lazy-rolls-10', CatalogCards.fry, [
      _ingredient('lazy-rolls-10-carrot', CatalogCards.carrot, [
        _mass('lazy-rolls-10-carrot-mass', 120),
      ]),
      _time('lazy-rolls-10-time', 3, 4),
    ]),
    _node('lazy-rolls-11', CatalogCards.mix, [
      _ingredient('lazy-rolls-11-minced-meat', CatalogCards.mincedMeat, [
        _mass('lazy-rolls-11-minced-meat-mass', 750),
      ]),
      _ingredient('lazy-rolls-11-cabbage', CatalogCards.cabbage),
      _ingredient('lazy-rolls-11-rice', CatalogCards.rice),
      _ingredient('lazy-rolls-11-onion', CatalogCards.onion),
      _ingredient('lazy-rolls-11-carrot', CatalogCards.carrot),
      _ingredient('lazy-rolls-11-eggs', CatalogCards.eggs, [
        RecipeNode(
          id: 'lazy-rolls-11-eggs-count',
          card: CatalogCards.count,
          value: 2,
          unit: NumericUnit.pieces,
        ),
      ])..text = 'С2',
      _ingredient('lazy-rolls-11-garlic', CatalogCards.garlic, [
        _mass('lazy-rolls-11-garlic-mass', 9),
      ]),
      _ingredient('lazy-rolls-11-salt', CatalogCards.salt, [
        _mass('lazy-rolls-11-salt-mass', 13),
      ]),
      _ingredient('lazy-rolls-11-pepper', CatalogCards.blackPepper, [
        _mass('lazy-rolls-11-pepper-mass', 1),
      ]),
      _ingredient('lazy-rolls-11-paprika', CatalogCards.sweetPaprika, [
        _mass('lazy-rolls-11-paprika-mass', 2),
      ]),
    ]),
    _node('lazy-rolls-12', CatalogCards.leave, [
      _ingredient('lazy-rolls-12-minced-meat', CatalogCards.mincedMeat),
      _time('lazy-rolls-12-time', 10),
    ]),
    _node('lazy-rolls-13', CatalogCards.form, [
      _ingredient('lazy-rolls-13-minced-meat', CatalogCards.mincedMeat),
    ]),
    _node('lazy-rolls-14', CatalogCards.fry, [
      _ingredient('lazy-rolls-14-minced-meat', CatalogCards.mincedMeat),
      _time('lazy-rolls-14-time', 3, 4),
    ]),
    _node('lazy-rolls-15', CatalogCards.mix, [
      _ingredient('lazy-rolls-15-tomato-paste', CatalogCards.tomatoPaste, [
        _mass('lazy-rolls-15-tomato-paste-mass', 50),
      ]),
      _ingredient('lazy-rolls-15-water', CatalogCards.water, [
        _volume('lazy-rolls-15-water-volume', 450),
      ]),
      _ingredient('lazy-rolls-15-sugar', CatalogCards.sugar, [
        _mass('lazy-rolls-15-sugar-mass', 5),
      ]),
      _ingredient('lazy-rolls-15-salt', CatalogCards.salt, [
        _mass('lazy-rolls-15-salt-mass', 4),
      ]),
    ]),
    _node('lazy-rolls-16', CatalogCards.add, [
      _ingredient('lazy-rolls-16-tomato-paste', CatalogCards.tomatoPaste),
      _ingredient('lazy-rolls-16-water', CatalogCards.water),
      _ingredient('lazy-rolls-16-bay-leaf', CatalogCards.bayLeaf, [
        RecipeNode(
          id: 'lazy-rolls-16-bay-leaf-count',
          card: CatalogCards.count,
          value: 2,
          unit: NumericUnit.pieces,
        ),
      ]),
    ]),
    _multicookerStep('lazy-rolls-17', 'Тушение', 12, 15),
    _node('lazy-rolls-18', CatalogCards.stew, [
      _ingredient('lazy-rolls-18-minced-meat', CatalogCards.mincedMeat),
      _time('lazy-rolls-18-time', 12, 15),
    ]),
    _node('lazy-rolls-19', CatalogCards.leave, [
      _ingredient('lazy-rolls-19-minced-meat', CatalogCards.mincedMeat),
      _time('lazy-rolls-19-time', 10),
    ]),
    _node('lazy-rolls-20', CatalogCards.add, [
      _ingredient('lazy-rolls-20-sour-cream', CatalogCards.sourCream, [
        _mass('lazy-rolls-20-sour-cream-mass', 150),
      ]),
    ]),
    _multicookerStep('lazy-rolls-21', 'Жарка', 2, 3),
    _node('lazy-rolls-22', CatalogCards.heat, [
      _ingredient('lazy-rolls-22-sour-cream', CatalogCards.sourCream),
      _time('lazy-rolls-22-time', 2, 3),
    ]),
    _node('lazy-rolls-23', CatalogCards.turnOff),
    _node('lazy-rolls-24', CatalogCards.leave, [
      _ingredient('lazy-rolls-24-minced-meat', CatalogCards.mincedMeat),
      _time('lazy-rolls-24-time', 10),
    ]),
  ],
);

/// Простой базовый пломбир без сырых яиц и без мороженицы. Сливки взбиваются
/// до мягких пиков, поэтому домашняя морозилка даёт кремовую текстуру даже
/// без перемешивания во время заморозки.
final _homemadeCreamIceCream = CatalogRecipe(
  id: 'homemade-cream-ice-cream',
  title: 'Домашнее сливочное мороженое',
  servings: 6,
  detailedSteps: [
    'Охладить 500 мл сливок жирностью 33–35 % и миску.',
    'Взбить сливки 5–7 минут на средней скорости до мягких пиков.',
    'Добавить 200 мл холодного сгущённого молока и аккуратно перемешать снизу вверх.',
    'Переложить массу в контейнер с крышкой.',
    'Заморозить массу на 6 часов до плотной кремовой консистенции.',
  ],
  buildSteps: () => [
    _node('ice-cream-1', CatalogCards.whisk, [
      _ingredient('ice-cream-1-cream', CatalogCards.cream, [
        _volume('ice-cream-1-cream-volume', 500),
        RecipeNode(
          id: 'ice-cream-1-cream-fat',
          card: CatalogCards.fatContent,
          value: 33,
          unit: NumericUnit.percent,
        ),
      ]),
      _time('ice-cream-1-time', 5, 7),
    ]),
    _node('ice-cream-2', CatalogCards.add, [
      _ingredient('ice-cream-2-condensed-milk', CatalogCards.condensedMilk, [
        _volume('ice-cream-2-condensed-milk-volume', 200),
      ]),
    ]),
    _node('ice-cream-3', CatalogCards.mix, [
      RecipeNode(
        id: 'ice-cream-3-mixture',
        card: CatalogCards.freeText,
        text: 'массу',
      ),
    ]),
    _node('ice-cream-4', CatalogCards.transfer, [
      RecipeNode(
        id: 'ice-cream-4-container',
        card: CatalogCards.freeText,
        text: 'массу в контейнер с крышкой',
      ),
    ]),
    _node('ice-cream-5', CatalogCards.freeze, [
      RecipeNode(
        id: 'ice-cream-5-mixture',
        card: CatalogCards.freeText,
        text: 'массу',
      ),
      _time('ice-cream-5-time', 360),
    ]),
  ],
);

/// Шоколад вводится через тёплую часть сливок: так он растворяется без
/// крупинок, а взбитая холодная часть сохраняет воздушную текстуру.
final _homemadeChocolateIceCream = CatalogRecipe(
  id: 'homemade-chocolate-ice-cream',
  title: 'Шоколадное мороженое',
  servings: 4,
  detailedSteps: [
    'Подогреть 100 мл сливок, не доводя до кипения.',
    'Добавить 80 г шоколада, 20 г какао и 1 г ванили; перемешать до однородности.',
    'Остудить шоколадную основу.',
    'Взбить 200 мл холодных сливок жирностью 33–35 % до мягких пиков.',
    'Добавить 100 г сгущённого молока и остывшую шоколадную основу; аккуратно перемешать.',
    'Переложить массу в контейнер с крышкой и заморозить на 6 часов.',
  ],
  buildSteps: () => [
    _node('chocolate-ice-cream-1', CatalogCards.heat, [
      _ingredient('chocolate-ice-cream-1-cream', CatalogCards.cream, [
        _volume('chocolate-ice-cream-1-cream-volume', 100),
      ]),
      _time('chocolate-ice-cream-1-time', 2, 3),
    ]),
    _node('chocolate-ice-cream-2', CatalogCards.add, [
      _ingredient('chocolate-ice-cream-2-chocolate', CatalogCards.chocolate, [
        _mass('chocolate-ice-cream-2-chocolate-mass', 80),
      ]),
      _ingredient('chocolate-ice-cream-2-cocoa', CatalogCards.cocoa, [
        _mass('chocolate-ice-cream-2-cocoa-mass', 20),
      ]),
      _ingredient('chocolate-ice-cream-2-vanilla', CatalogCards.vanilla, [
        _mass('chocolate-ice-cream-2-vanilla-mass', 1),
      ]),
    ]),
    _node('chocolate-ice-cream-3', CatalogCards.stir, [
      _text('chocolate-ice-cream-3-base', 'шоколадную основу'),
    ]),
    _node('chocolate-ice-cream-4', CatalogCards.cool, [
      _text('chocolate-ice-cream-4-base', 'шоколадную основу'),
    ]),
    _node('chocolate-ice-cream-5', CatalogCards.whisk, [
      _ingredient('chocolate-ice-cream-5-cream', CatalogCards.cream, [
        _volume('chocolate-ice-cream-5-cream-volume', 200),
        RecipeNode(
          id: 'chocolate-ice-cream-5-cream-fat',
          card: CatalogCards.fatContent,
          value: 33,
          unit: NumericUnit.percent,
        ),
      ]),
      _time('chocolate-ice-cream-5-time', 5, 7),
    ]),
    _node('chocolate-ice-cream-6', CatalogCards.add, [
      _ingredient(
        'chocolate-ice-cream-6-condensed-milk',
        CatalogCards.condensedMilk,
        [_mass('chocolate-ice-cream-6-condensed-milk-mass', 100)],
      ),
      _text('chocolate-ice-cream-6-base', 'шоколадную основу'),
    ]),
    _node('chocolate-ice-cream-7', CatalogCards.mix, [
      _text('chocolate-ice-cream-7-mixture', 'массу'),
    ]),
    _node('chocolate-ice-cream-8', CatalogCards.transfer, [
      _text('chocolate-ice-cream-8-container', 'массу в контейнер с крышкой'),
    ]),
    _node('chocolate-ice-cream-9', CatalogCards.freeze, [
      _text('chocolate-ice-cream-9-mixture', 'массу'),
      _time('chocolate-ice-cream-9-time', 360),
    ]),
  ],
);

/// Банан сначала замораживается отдельно: блендер сразу превращает его в
/// холодную кремовую основу, а не в жидкое фруктовое пюре.
final _homemadeBananaIceCream = CatalogRecipe(
  id: 'homemade-banana-ice-cream',
  title: 'Банановое мороженое',
  servings: 3,
  detailedSteps: [
    'Очистить 3 банана, нарезать кусочками и заморозить на 1–2 часа.',
    'Измельчить замороженные бананы с 500 мл сливок и 350–400 г сгущённого молока.',
    'Переложить массу в форму или контейнер с крышкой.',
    'Заморозить на 6 часов.',
  ],
  buildSteps: () => [
    _node('banana-ice-cream-1', CatalogCards.cut, [
      _ingredient('banana-ice-cream-1-banana', CatalogCards.banana, [
        RecipeNode(
          id: 'banana-ice-cream-1-banana-count',
          card: CatalogCards.count,
          value: 3,
          unit: NumericUnit.pieces,
        ),
      ]),
    ]),
    _node('banana-ice-cream-2', CatalogCards.freeze, [
      _ingredient('banana-ice-cream-2-banana', CatalogCards.banana),
      _time('banana-ice-cream-2-time', 60, 120),
    ]),
    _node('banana-ice-cream-3', CatalogCards.blend, [
      _ingredient('banana-ice-cream-3-banana', CatalogCards.banana),
      _ingredient('banana-ice-cream-3-cream', CatalogCards.cream, [
        _volume('banana-ice-cream-3-cream-volume', 500),
      ]),
      _ingredient(
        'banana-ice-cream-3-condensed-milk',
        CatalogCards.condensedMilk,
        [_mass('banana-ice-cream-3-condensed-milk-mass', 375)],
      ),
    ]),
    _node('banana-ice-cream-4', CatalogCards.transfer, [
      _text('banana-ice-cream-4-container', 'массу в контейнер с крышкой'),
    ]),
    _node('banana-ice-cream-5', CatalogCards.freeze, [
      _text('banana-ice-cream-5-mixture', 'массу'),
      _time('banana-ice-cream-5-time', 360),
    ]),
  ],
);

/// Карамельная нота получается из варёного сгущённого молока. Его сначала
/// размягчают молоком, а затем вводят во взбитые сливки небольшими порциями.
final _homemadeCremeBruleeIceCream = CatalogRecipe(
  id: 'homemade-creme-brulee-ice-cream',
  title: 'Мороженое крем-брюле',
  servings: 6,
  detailedSteps: [
    'Смешать 200 г варёного сгущённого молока и 200 мл молока; оставить на 30 минут.',
    'Взбить 400 мл охлаждённых сливок жирностью 35 % до устойчивой пены.',
    'Постепенно добавить молочно-карамельную смесь во взбитые сливки и перемешать на низкой скорости.',
    'Переложить воздушную массу в контейнер с крышкой.',
    'Заморозить на 6–8 часов.',
  ],
  buildSteps: () => [
    _node('creme-brulee-1', CatalogCards.mix, [
      _ingredient(
        'creme-brulee-1-boiled-condensed-milk',
        CatalogCards.boiledCondensedMilk,
        [_mass('creme-brulee-1-boiled-condensed-milk-mass', 200)],
      ),
      _ingredient('creme-brulee-1-milk', CatalogCards.milk, [
        _volume('creme-brulee-1-milk-volume', 200),
      ]),
    ]),
    _node('creme-brulee-2', CatalogCards.leave, [
      _text('creme-brulee-2-mixture', 'смесь'),
      _time('creme-brulee-2-time', 30),
    ]),
    _node('creme-brulee-3', CatalogCards.whisk, [
      _ingredient('creme-brulee-3-cream', CatalogCards.cream, [
        _volume('creme-brulee-3-cream-volume', 400),
        RecipeNode(
          id: 'creme-brulee-3-cream-fat',
          card: CatalogCards.fatContent,
          value: 35,
          unit: NumericUnit.percent,
        ),
      ]),
      _time('creme-brulee-3-time', 5, 7),
    ]),
    _node('creme-brulee-4', CatalogCards.add, [
      _text('creme-brulee-4-mixture', 'молочно-карамельную смесь'),
    ]),
    _node('creme-brulee-5', CatalogCards.mix, [
      _text('creme-brulee-5-mixture', 'воздушную массу'),
    ]),
    _node('creme-brulee-6', CatalogCards.transfer, [
      _text('creme-brulee-6-container', 'массу в контейнер с крышкой'),
    ]),
    _node('creme-brulee-7', CatalogCards.freeze, [
      _text('creme-brulee-7-mixture', 'массу'),
      _time('creme-brulee-7-time', 360, 480),
    ]),
  ],
);

/// Короткая декларация шага для встроенных рецептов. Она создаёт только
/// словарные модули и количества: свободный «Текст» здесь не применяется.
RecipeNode _moduleStep(
  String recipeId,
  int order,
  CardDefinition action,
  List<Object> parts, {
  int? minutes,
  int? upperMinutes,
  int? temperature,
}) {
  final children = <RecipeNode>[];
  for (final (index, part) in parts.indexed) {
    final CardDefinition card;
    int? grams;
    int? milliliters;
    int? pieces;
    switch (part) {
      case (card: final CardDefinition value, grams: final int amount):
        card = value;
        grams = amount;
      case (card: final CardDefinition value, milliliters: final int amount):
        card = value;
        milliliters = amount;
      case (card: final CardDefinition value, pieces: final int amount):
        card = value;
        pieces = amount;
      case (card: final CardDefinition value):
        card = value;
      default:
        throw ArgumentError.value(part, 'part', 'Неизвестная часть шага');
    }
    final quantities = <RecipeNode>[];
    if (grams != null) {
      quantities.add(_mass('$recipeId-$order-$index-mass', grams));
    } else if (milliliters != null) {
      quantities.add(_volume('$recipeId-$order-$index-volume', milliliters));
    } else if (pieces != null) {
      quantities.add(
        RecipeNode(
          id: '$recipeId-$order-$index-count',
          card: CatalogCards.count,
          value: pieces,
          unit: NumericUnit.pieces,
        ),
      );
    }
    children.add(_ingredient('$recipeId-$order-$index', card, quantities));
  }
  if (temperature != null) {
    children.add(
      RecipeNode(
        id: '$recipeId-$order-temperature',
        card: CatalogCards.temperature,
        value: temperature,
        unit: NumericUnit.celsius,
      ),
    );
  }
  if (minutes != null)
    children.add(_time('$recipeId-$order-time', minutes, upperMinutes));
  return _node('$recipeId-$order', action, children);
}

final _newClassicRecipes = <CatalogRecipe>[
  CatalogRecipe(
    id: 'okroshka-ham',
    title: 'Окрошка с ветчиной',
    servings: 6,
    buildSteps: () => [
      _moduleStep('okroshka', 1, CatalogCards.boil, [
        (card: CatalogCards.potato, grams: 500),
        (card: CatalogCards.eggs, pieces: 5),
      ], minutes: 20),
      _moduleStep('okroshka', 2, CatalogCards.cut, [
        (card: CatalogCards.ham, grams: 350),
        (card: CatalogCards.cucumber, grams: 350),
        (card: CatalogCards.radishes, grams: 200),
        (card: CatalogCards.potato, grams: 500),
        (card: CatalogCards.eggs, pieces: 5),
      ]),
      _moduleStep('okroshka', 3, CatalogCards.add, [
        (card: CatalogCards.greenOnion, grams: 60),
        (card: CatalogCards.dill, grams: 25),
        (card: CatalogCards.salt, grams: 7),
      ]),
      _moduleStep('okroshka', 4, CatalogCards.mix, [
        (card: CatalogCards.kvass, milliliters: 1500),
        (card: CatalogCards.sourCream, grams: 180),
      ]),
    ],
  ),
  CatalogRecipe(
    id: 'mannik-kefir',
    title: 'Манник на кефире',
    servings: 8,
    buildSteps: () => [
      _moduleStep('mannik', 1, CatalogCards.mix, [
        (card: CatalogCards.semolina, grams: 250),
        (card: CatalogCards.kefir, milliliters: 500),
      ], minutes: 40),
      _moduleStep('mannik', 2, CatalogCards.add, [
        (card: CatalogCards.eggs, pieces: 3),
        (card: CatalogCards.sugar, grams: 180),
        (card: CatalogCards.butter, grams: 80),
      ]),
      _moduleStep('mannik', 3, CatalogCards.mix, [
        (card: CatalogCards.flour, grams: 120),
        (card: CatalogCards.bakingPowder, grams: 10),
      ]),
      _moduleStep(
        'mannik',
        4,
        CatalogCards.bake,
        [(card: CatalogCards.batter)],
        temperature: 180,
        minutes: 40,
        upperMinutes: 45,
      ),
    ],
  ),
  CatalogRecipe(
    id: 'honey-kovrizhka',
    title: 'Коврижка медовая',
    servings: 10,
    buildSteps: () => [
      _moduleStep('kovrizhka', 1, CatalogCards.heat, [
        (card: CatalogCards.honey, grams: 180),
        (card: CatalogCards.butter, grams: 80),
      ], minutes: 3),
      _moduleStep('kovrizhka', 2, CatalogCards.mix, [
        (card: CatalogCards.eggs, pieces: 2),
        (card: CatalogCards.sugar, grams: 100),
        (card: CatalogCards.honey, grams: 180),
      ]),
      _moduleStep('kovrizhka', 3, CatalogCards.add, [
        (card: CatalogCards.flour, grams: 350),
        (card: CatalogCards.bakingPowder, grams: 10),
        (card: CatalogCards.cinnamon, grams: 3),
      ]),
      _moduleStep(
        'kovrizhka',
        4,
        CatalogCards.bake,
        [(card: CatalogCards.batter)],
        temperature: 180,
        minutes: 35,
        upperMinutes: 40,
      ),
    ],
  ),
  CatalogRecipe(
    id: 'olivier-ham',
    title: 'Оливье с ветчиной',
    servings: 8,
    buildSteps: () => [
      _moduleStep('olivier', 1, CatalogCards.boil, [
        (card: CatalogCards.potato, grams: 500),
        (card: CatalogCards.carrot, grams: 250),
        (card: CatalogCards.eggs, pieces: 5),
      ], minutes: 25),
      _moduleStep('olivier', 2, CatalogCards.cut, [
        (card: CatalogCards.ham, grams: 350),
        (card: CatalogCards.potato, grams: 500),
        (card: CatalogCards.carrot, grams: 250),
        (card: CatalogCards.pickledCucumbers, grams: 250),
        (card: CatalogCards.eggs, pieces: 5),
      ]),
      _moduleStep('olivier', 3, CatalogCards.add, [
        (card: CatalogCards.greenPeas, grams: 250),
        (card: CatalogCards.mayonnaise, grams: 220),
      ]),
      _moduleStep('olivier', 4, CatalogCards.mix, [
        (card: CatalogCards.salt, grams: 5),
        (card: CatalogCards.blackPepper, grams: 1),
      ]),
    ],
  ),
  CatalogRecipe(
    id: 'beef-stroganoff',
    title: 'Бефстроганов',
    servings: 6,
    buildSteps: () => [
      _moduleStep('stroganoff', 1, CatalogCards.cut, [
        (card: CatalogCards.beef, grams: 700),
        (card: CatalogCards.onion, grams: 250),
      ]),
      _moduleStep(
        'stroganoff',
        2,
        CatalogCards.fry,
        [
          (card: CatalogCards.beef, grams: 700),
          (card: CatalogCards.butter, grams: 50),
        ],
        minutes: 7,
        upperMinutes: 9,
      ),
      _moduleStep('stroganoff', 3, CatalogCards.saute, [
        (card: CatalogCards.onion, grams: 250),
        (card: CatalogCards.butter, grams: 25),
      ], minutes: 5),
      _moduleStep(
        'stroganoff',
        4,
        CatalogCards.stew,
        [
          (card: CatalogCards.beef, grams: 700),
          (card: CatalogCards.sourCream, grams: 300),
          (card: CatalogCards.flour, grams: 20),
          (card: CatalogCards.salt, grams: 8),
          (card: CatalogCards.blackPepper, grams: 2),
        ],
        minutes: 12,
        upperMinutes: 15,
      ),
    ],
  ),
  CatalogRecipe(
    id: 'herring-under-fur-coat',
    title: 'Селёдка под шубой',
    servings: 8,
    buildSteps: () => [
      _moduleStep('fur', 1, CatalogCards.boil, [
        (card: CatalogCards.beet, grams: 500),
        (card: CatalogCards.potato, grams: 450),
        (card: CatalogCards.carrot, grams: 250),
        (card: CatalogCards.eggs, pieces: 4),
      ], minutes: 35),
      _moduleStep('fur', 2, CatalogCards.cut, [
        (card: CatalogCards.herring, grams: 350),
        (card: CatalogCards.onion, grams: 120),
      ]),
      _moduleStep('fur', 3, CatalogCards.grate, [
        (card: CatalogCards.beet, grams: 500),
        (card: CatalogCards.potato, grams: 450),
        (card: CatalogCards.carrot, grams: 250),
        (card: CatalogCards.eggs, pieces: 4),
      ]),
      _moduleStep('fur', 4, CatalogCards.form, [
        (card: CatalogCards.herring, grams: 350),
        (card: CatalogCards.mayonnaise, grams: 250),
      ]),
    ],
  ),
  CatalogRecipe(
    id: 'pike-ukha',
    title: 'Уха из щуки',
    servings: 6,
    buildSteps: () => [
      _moduleStep('ukha', 1, CatalogCards.cut, [
        (card: CatalogCards.pike, grams: 900),
        (card: CatalogCards.potato, grams: 450),
        (card: CatalogCards.carrot, grams: 150),
        (card: CatalogCards.onion, grams: 150),
      ]),
      _moduleStep('ukha', 2, CatalogCards.boil, [
        (card: CatalogCards.water, milliliters: 2200),
        (card: CatalogCards.pike, grams: 900),
      ], minutes: 20),
      _moduleStep('ukha', 3, CatalogCards.add, [
        (card: CatalogCards.potato, grams: 450),
        (card: CatalogCards.carrot, grams: 150),
        (card: CatalogCards.onion, grams: 150),
        (card: CatalogCards.bayLeaf, grams: 1),
        (card: CatalogCards.salt, grams: 12),
        (card: CatalogCards.blackPepper, grams: 2),
      ]),
      _moduleStep(
        'ukha',
        4,
        CatalogCards.boil,
        [(card: CatalogCards.potato, grams: 450)],
        minutes: 18,
        upperMinutes: 20,
      ),
    ],
  ),
  CatalogRecipe(
    id: 'beetroot-soup',
    title: 'Свекольник',
    servings: 6,
    buildSteps: () => [
      _moduleStep('beetroot-soup', 1, CatalogCards.boil, [
        (card: CatalogCards.beet, grams: 500),
        (card: CatalogCards.potato, grams: 400),
        (card: CatalogCards.eggs, pieces: 4),
      ], minutes: 30),
      _moduleStep('beetroot-soup', 2, CatalogCards.grate, [
        (card: CatalogCards.beet, grams: 500),
        (card: CatalogCards.cucumber, grams: 300),
      ]),
      _moduleStep('beetroot-soup', 3, CatalogCards.cut, [
        (card: CatalogCards.potato, grams: 400),
        (card: CatalogCards.eggs, pieces: 4),
        (card: CatalogCards.dill, grams: 25),
      ]),
      _moduleStep('beetroot-soup', 4, CatalogCards.mix, [
        (card: CatalogCards.water, milliliters: 1500),
        (card: CatalogCards.sourCream, grams: 200),
        (card: CatalogCards.salt, grams: 8),
      ]),
    ],
  ),
  CatalogRecipe(
    id: 'classic-roast',
    title: 'Жаркое классическое',
    servings: 6,
    buildSteps: () => [
      _moduleStep('roast', 1, CatalogCards.cut, [
        (card: CatalogCards.pork, grams: 800),
        (card: CatalogCards.potato, grams: 900),
        (card: CatalogCards.carrot, grams: 200),
        (card: CatalogCards.onion, grams: 200),
      ]),
      _moduleStep('roast', 2, CatalogCards.fry, [
        (card: CatalogCards.pork, grams: 800),
        (card: CatalogCards.vegetableOil, milliliters: 30),
      ], minutes: 10),
      _moduleStep('roast', 3, CatalogCards.add, [
        (card: CatalogCards.onion, grams: 200),
        (card: CatalogCards.carrot, grams: 200),
        (card: CatalogCards.potato, grams: 900),
        (card: CatalogCards.water, milliliters: 350),
        (card: CatalogCards.salt, grams: 12),
        (card: CatalogCards.blackPepper, grams: 2),
      ]),
      _moduleStep(
        'roast',
        4,
        CatalogCards.stew,
        [(card: CatalogCards.pork, grams: 800)],
        minutes: 45,
        upperMinutes: 55,
      ),
    ],
  ),
  CatalogRecipe(
    id: 'classic-borscht',
    title: 'Борщ',
    servings: 8,
    buildSteps: () => [
      _moduleStep('borscht', 1, CatalogCards.boil, [
        (card: CatalogCards.pork, grams: 700),
        (card: CatalogCards.water, milliliters: 2500),
      ], minutes: 60),
      _moduleStep('borscht', 2, CatalogCards.cut, [
        (card: CatalogCards.cabbage, grams: 500),
        (card: CatalogCards.potato, grams: 500),
        (card: CatalogCards.onion, grams: 180),
        (card: CatalogCards.carrot, grams: 180),
        (card: CatalogCards.beet, grams: 400),
      ]),
      _moduleStep('borscht', 3, CatalogCards.saute, [
        (card: CatalogCards.beet, grams: 400),
        (card: CatalogCards.carrot, grams: 180),
        (card: CatalogCards.onion, grams: 180),
        (card: CatalogCards.tomatoPaste, grams: 70),
        (card: CatalogCards.vegetableOil, milliliters: 30),
      ], minutes: 12),
      _moduleStep('borscht', 4, CatalogCards.add, [
        (card: CatalogCards.potato, grams: 500),
        (card: CatalogCards.cabbage, grams: 500),
        (card: CatalogCards.garlic, grams: 12),
        (card: CatalogCards.salt, grams: 15),
      ]),
      _moduleStep('borscht', 5, CatalogCards.boil, [
        (card: CatalogCards.cabbage, grams: 500),
      ], minutes: 18),
    ],
  ),
  CatalogRecipe(
    id: 'bread-kvass',
    title: 'Квас хлебный',
    servings: 8,
    buildSteps: () => [
      _moduleStep(
        'kvass',
        1,
        CatalogCards.bake,
        [(card: CatalogCards.bread, grams: 400)],
        temperature: 180,
        minutes: 18,
        upperMinutes: 20,
      ),
      _moduleStep('kvass', 2, CatalogCards.boil, [
        (card: CatalogCards.water, milliliters: 3000),
      ], minutes: 5),
      _moduleStep('kvass', 3, CatalogCards.add, [
        (card: CatalogCards.bread, grams: 400),
        (card: CatalogCards.sugar, grams: 180),
        (card: CatalogCards.yeast, grams: 7),
      ]),
      _moduleStep('kvass', 4, CatalogCards.leave, [
        (card: CatalogCards.kvass),
      ], minutes: 720),
      _moduleStep('kvass', 5, CatalogCards.cool, [
        (card: CatalogCards.kvass),
      ], minutes: 120),
    ],
  ),
  CatalogRecipe(
    id: 'potato-puree',
    title: 'Картофельное пюре',
    servings: 6,
    buildSteps: () => [
      _moduleStep('puree', 1, CatalogCards.cut, [
        (card: CatalogCards.potato, grams: 1200),
      ]),
      _moduleStep('puree', 2, CatalogCards.boil, [
        (card: CatalogCards.potato, grams: 1200),
        (card: CatalogCards.salt, grams: 12),
      ], minutes: 25),
      _moduleStep('puree', 3, CatalogCards.drain, [
        (card: CatalogCards.potato, grams: 1200),
      ]),
      _moduleStep('puree', 4, CatalogCards.mash, [
        (card: CatalogCards.potato, grams: 1200),
        (card: CatalogCards.milk, milliliters: 250),
        (card: CatalogCards.butter, grams: 70),
      ]),
    ],
  ),
  CatalogRecipe(
    id: 'apple-plum-compote',
    title: 'Компот из яблок и слив',
    servings: 8,
    buildSteps: () => [
      _moduleStep('compote', 1, CatalogCards.cut, [
        (card: CatalogCards.apples, grams: 500),
        (card: CatalogCards.plums, grams: 350),
      ]),
      _moduleStep('compote', 2, CatalogCards.boil, [
        (card: CatalogCards.water, milliliters: 2500),
        (card: CatalogCards.sugar, grams: 180),
      ], minutes: 5),
      _moduleStep('compote', 3, CatalogCards.add, [
        (card: CatalogCards.apples, grams: 500),
        (card: CatalogCards.plums, grams: 350),
      ]),
      _moduleStep(
        'compote',
        4,
        CatalogCards.boil,
        [(card: CatalogCards.apples, grams: 500)],
        minutes: 8,
        upperMinutes: 10,
      ),
      _moduleStep('compote', 5, CatalogCards.cool, [
        (card: CatalogCards.water, milliliters: 2500),
      ], minutes: 60),
    ],
  ),
  CatalogRecipe(
    id: 'baked-apples-honey',
    title: 'Запечённые яблоки с мёдом',
    servings: 6,
    buildSteps: () => [
      _moduleStep('baked-apples', 1, CatalogCards.cut, [
        (card: CatalogCards.apples, grams: 1200),
        (card: CatalogCards.walnuts, grams: 80),
        (card: CatalogCards.raisins, grams: 80),
      ]),
      _moduleStep('baked-apples', 2, CatalogCards.mix, [
        (card: CatalogCards.honey, grams: 120),
        (card: CatalogCards.walnuts, grams: 80),
        (card: CatalogCards.raisins, grams: 80),
        (card: CatalogCards.cinnamon, grams: 3),
      ]),
      _moduleStep('baked-apples', 3, CatalogCards.fill, [
        (card: CatalogCards.apples, grams: 1200),
        (card: CatalogCards.honey, grams: 120),
      ]),
      _moduleStep(
        'baked-apples',
        4,
        CatalogCards.bake,
        [(card: CatalogCards.apples, grams: 1200)],
        temperature: 180,
        minutes: 25,
        upperMinutes: 30,
      ),
    ],
  ),
  CatalogRecipe(
    id: 'vinaigrette',
    title: 'Винегрет',
    servings: 8,
    buildSteps: () => [
      _moduleStep('vinaigrette', 1, CatalogCards.boil, [
        (card: CatalogCards.beet, grams: 500),
        (card: CatalogCards.potato, grams: 500),
        (card: CatalogCards.carrot, grams: 250),
      ], minutes: 35),
      _moduleStep('vinaigrette', 2, CatalogCards.cut, [
        (card: CatalogCards.beet, grams: 500),
        (card: CatalogCards.potato, grams: 500),
        (card: CatalogCards.carrot, grams: 250),
        (card: CatalogCards.pickledCucumbers, grams: 250),
      ]),
      _moduleStep('vinaigrette', 3, CatalogCards.add, [
        (card: CatalogCards.sauerkraut, grams: 250),
        (card: CatalogCards.greenPeas, grams: 200),
        (card: CatalogCards.vegetableOil, milliliters: 50),
      ]),
      _moduleStep('vinaigrette', 4, CatalogCards.mix, [
        (card: CatalogCards.salt, grams: 5),
        (card: CatalogCards.blackPepper, grams: 1),
      ]),
    ],
  ),
  CatalogRecipe(
    id: 'gogol-mogol',
    title: 'Гоголь-моголь',
    servings: 2,
    buildSteps: () => [
      _moduleStep('gogol', 1, CatalogCards.whisk, [
        (card: CatalogCards.eggYolk, pieces: 3),
        (card: CatalogCards.sugar, grams: 45),
        (card: CatalogCards.vanilla, grams: 1),
      ], minutes: 4),
      _moduleStep('gogol', 2, CatalogCards.heat, [
        (card: CatalogCards.milk, milliliters: 250),
      ], minutes: 3),
      _moduleStep('gogol', 3, CatalogCards.mix, [
        (card: CatalogCards.eggYolk, pieces: 3),
        (card: CatalogCards.milk, milliliters: 250),
      ]),
      _moduleStep('gogol', 4, CatalogCards.whisk, [
        (card: CatalogCards.eggWhite, pieces: 3),
        (card: CatalogCards.sugar, grams: 15),
      ], minutes: 3),
      _moduleStep('gogol', 5, CatalogCards.add, [
        (card: CatalogCards.eggWhite, pieces: 3),
      ]),
    ],
  ),
  CatalogRecipe(
    id: 'buckwheat-cabbage-rolls',
    title: 'Голубцы с гречкой',
    servings: 6,
    detailedSteps: [
      'Промыть 180 г гречки, залить 350 мл воды и варить 12–15 минут до почти полной готовности. Остудить.',
      'Снять с кочана капусты 12–14 крупных листьев. Опустить их в кипящую воду на 4–5 минут, затем обсушить.',
      'Мелко нарезать 180 г лука и натереть 120 г моркови.',
      'Обжарить половину лука на 15 мл масла 3–4 минуты до мягкости.',
      'Смешать 500 г фарша, гречку, обжаренный лук, 7 г соли и 1 г чёрного перца.',
      'Разложить начинку по капустным листьям и завернуть плотные голубцы.',
      'Обжарить оставшиеся лук и морковь на 10 мл масла 4–5 минут, добавить 60 г томатной пасты.',
      'Смешать 200 г сметаны с 600 мл воды и добавить к овощам.',
      'Уложить голубцы в соус и тушить под крышкой 40–45 минут.',
    ],
    buildSteps: () => [
      _moduleStep('buckwheat-rolls', 1, CatalogCards.rinse, [
        (card: CatalogCards.buckwheat, grams: 180),
      ]),
      _moduleStep(
        'buckwheat-rolls',
        2,
        CatalogCards.boil,
        [
          (card: CatalogCards.buckwheat, grams: 180),
          (card: CatalogCards.water, milliliters: 350),
        ],
        minutes: 12,
        upperMinutes: 15,
      ),
      _moduleStep(
        'buckwheat-rolls',
        3,
        CatalogCards.boil,
        [
          (card: CatalogCards.cabbage, grams: 1000),
          (card: CatalogCards.water, milliliters: 2000),
        ],
        minutes: 4,
        upperMinutes: 5,
      ),
      _moduleStep('buckwheat-rolls', 4, CatalogCards.cut, [
        (card: CatalogCards.onion, grams: 180),
        (card: CatalogCards.carrot, grams: 120),
      ]),
      _moduleStep(
        'buckwheat-rolls',
        5,
        CatalogCards.saute,
        [
          (card: CatalogCards.onion, grams: 90),
          (card: CatalogCards.vegetableOil, milliliters: 15),
        ],
        minutes: 3,
        upperMinutes: 4,
      ),
      _moduleStep('buckwheat-rolls', 6, CatalogCards.mix, [
        (card: CatalogCards.mincedMeat, grams: 500),
        (card: CatalogCards.buckwheat, grams: 180),
        (card: CatalogCards.onion, grams: 90),
        (card: CatalogCards.salt, grams: 7),
        (card: CatalogCards.blackPepper, grams: 1),
      ]),
      _moduleStep('buckwheat-rolls', 7, CatalogCards.wrap, [
        (card: CatalogCards.cabbage, grams: 1000),
      ]),
      _moduleStep(
        'buckwheat-rolls',
        8,
        CatalogCards.saute,
        [
          (card: CatalogCards.onion, grams: 90),
          (card: CatalogCards.carrot, grams: 120),
          (card: CatalogCards.vegetableOil, milliliters: 10),
          (card: CatalogCards.tomatoPaste, grams: 60),
        ],
        minutes: 4,
        upperMinutes: 5,
      ),
      _moduleStep('buckwheat-rolls', 9, CatalogCards.mix, [
        (card: CatalogCards.sourCream, grams: 200),
        (card: CatalogCards.water, milliliters: 600),
      ]),
      _moduleStep(
        'buckwheat-rolls',
        10,
        CatalogCards.stew,
        [(card: CatalogCards.cabbage, grams: 1000)],
        minutes: 40,
        upperMinutes: 45,
      ),
    ],
  ),
  CatalogRecipe(
    id: 'mimosa-pink-salmon',
    title: 'Салат «Мимоза» с горбушей',
    servings: 6,
    detailedSteps: [
      'Отварить 350 г картошки, 250 г моркови и 5 яиц до готовности, затем остудить.',
      'Открыть банку горбуши в собственном соку (240 г) и размять рыбу вилкой.',
      'Мелко нарезать 80 г лука; картошку, морковь, яйца и 150 г твёрдого сыра натереть отдельно.',
      'Сформировать салат слоями: картошка, горбуша, лук, морковь, яйца и сыр, промазывая слои 220 г майонеза.',
      'Охладить салат не менее 60 минут перед подачей.',
    ],
    buildSteps: () => [
      _moduleStep('mimosa', 1, CatalogCards.boil, [
        (card: CatalogCards.potato, grams: 350),
        (card: CatalogCards.carrot, grams: 250),
        (card: CatalogCards.eggs, pieces: 5),
      ], minutes: 25),
      _node('mimosa-2', CatalogCards.open, [
        _cannedIngredient('mimosa-2-canned', CatalogCards.pinkSalmon, 240),
      ]),
      _node('mimosa-3', CatalogCards.mash, [
        _cannedIngredient('mimosa-3-canned', CatalogCards.pinkSalmon, 240),
      ]),
      _moduleStep('mimosa', 4, CatalogCards.cut, [
        (card: CatalogCards.onion, grams: 80),
      ]),
      _moduleStep('mimosa', 5, CatalogCards.grate, [
        (card: CatalogCards.potato, grams: 350),
        (card: CatalogCards.carrot, grams: 250),
        (card: CatalogCards.eggs, pieces: 5),
        (card: CatalogCards.cheese, grams: 150),
      ]),
      _node('mimosa-6', CatalogCards.form, [
        _ingredient('mimosa-6-potato', CatalogCards.potato, [
          _mass('mimosa-6-potato-mass', 350),
        ]),
        _cannedIngredient('mimosa-6-canned', CatalogCards.pinkSalmon, 240),
        _ingredient('mimosa-6-onion', CatalogCards.onion, [
          _mass('mimosa-6-onion-mass', 80),
        ]),
        _ingredient('mimosa-6-carrot', CatalogCards.carrot, [
          _mass('mimosa-6-carrot-mass', 250),
        ]),
        _ingredient('mimosa-6-eggs', CatalogCards.eggs, [
          RecipeNode(
            id: 'mimosa-6-eggs-count',
            card: CatalogCards.count,
            value: 5,
            unit: NumericUnit.pieces,
          ),
        ]),
        _ingredient('mimosa-6-cheese', CatalogCards.cheese, [
          _mass('mimosa-6-cheese-mass', 150),
        ]),
        _ingredient('mimosa-6-mayonnaise', CatalogCards.mayonnaise, [
          _mass('mimosa-6-mayonnaise-mass', 220),
        ]),
      ]),
    ],
  ),
  CatalogRecipe(
    id: 'cranberry-kissel',
    title: 'Кисель из клюквы',
    servings: 6,
    detailedSteps: [
      'Промыть и измельчить 300 г клюквы, затем процедить ягодную массу через сито.',
      'Залить жмых 1 200 мл воды, довести до кипения и варить 10–15 минут; процедить отвар.',
      'Добавить 120 г сахара и вновь довести отвар до кипения.',
      'Добавить 40 г картофельного крахмала в 100 мл холодной воды и перемешать до однородности.',
      'Добавить крахмальную смесь в отвар тонкой струёй, постоянно перемешивая; довести до загустения и снять с нагрева.',
      'Добавить отжатый клюквенный сок и перемешать.',
    ],
    buildSteps: () => [
      _moduleStep('cranberry-kissel', 1, CatalogCards.rinse, [
        (card: CatalogCards.cranberries, grams: 300),
      ]),
      _moduleStep('cranberry-kissel', 2, CatalogCards.blend, [
        (card: CatalogCards.cranberries, grams: 300),
      ]),
      _moduleStep('cranberry-kissel', 3, CatalogCards.strain, [
        (card: CatalogCards.cranberries, grams: 300),
      ]),
      _moduleStep(
        'cranberry-kissel',
        4,
        CatalogCards.boil,
        [
          (card: CatalogCards.cranberries, grams: 300),
          (card: CatalogCards.water, milliliters: 1200),
        ],
        minutes: 10,
        upperMinutes: 15,
      ),
      _moduleStep('cranberry-kissel', 5, CatalogCards.add, [
        (card: CatalogCards.sugar, grams: 120),
      ]),
      _moduleStep('cranberry-kissel', 6, CatalogCards.add, [
        (card: CatalogCards.potatoStarch, grams: 40),
        (card: CatalogCards.water, milliliters: 100),
      ]),
      _moduleStep('cranberry-kissel', 7, CatalogCards.stir, [
        (card: CatalogCards.cranberries, grams: 300),
      ], minutes: 3),
    ],
  ),
  CatalogRecipe(
    id: 'apple-pastila',
    title: 'Белёвская яблочная пастила',
    servings: 8,
    detailedSteps: [
      'Промыть 2 000 г кислых яблок, очистить их от кожуры и сердцевин.',
      'Запечь яблоки при 180 °C 20–25 минут до мягкости, затем измельчить в однородное пюре.',
      'Взбить яблочное пюре с 2 белками и 300 г сахара до пышной светлой массы.',
      'Сформировать на противне пласт толщиной около 1–1,5 см.',
      'Высушить пастилу при 100 °C 4–5 часов с приоткрытой дверцей духовки.',
      'Разрезать пласт, сложить его слоями и высушить ещё 1,5–2 часа при 70 °C.',
    ],
    buildSteps: () => [
      _moduleStep('apple-pastila', 1, CatalogCards.rinse, [
        (card: CatalogCards.apples, grams: 2000),
      ]),
      _moduleStep('apple-pastila', 2, CatalogCards.clean, [
        (card: CatalogCards.apples, grams: 2000),
      ]),
      _moduleStep(
        'apple-pastila',
        3,
        CatalogCards.bake,
        [(card: CatalogCards.apples, grams: 2000)],
        temperature: 180,
        minutes: 20,
        upperMinutes: 25,
      ),
      _moduleStep('apple-pastila', 4, CatalogCards.blend, [
        (card: CatalogCards.apples, grams: 2000),
      ]),
      _moduleStep('apple-pastila', 5, CatalogCards.whisk, [
        (card: CatalogCards.apples, grams: 2000),
        (card: CatalogCards.eggWhite, pieces: 2),
        (card: CatalogCards.sugar, grams: 300),
      ], minutes: 15),
      _moduleStep('apple-pastila', 6, CatalogCards.form, [
        (card: CatalogCards.apples, grams: 2000),
      ]),
      _moduleStep(
        'apple-pastila',
        7,
        CatalogCards.dry,
        [(card: CatalogCards.apples, grams: 2000)],
        temperature: 100,
        minutes: 240,
        upperMinutes: 300,
      ),
      _moduleStep(
        'apple-pastila',
        8,
        CatalogCards.dry,
        [(card: CatalogCards.apples, grams: 2000)],
        temperature: 70,
        minutes: 90,
        upperMinutes: 120,
      ),
    ],
  ),
  CatalogRecipe(
    id: 'lean-pea-kissel',
    title: 'Кисель гороховый',
    servings: 4,
    detailedSteps: [
      'Промыть 300 г гороха и замочить его в 900 мл воды на 6–8 часов.',
      'Слить воду, влить 1 000 мл свежей воды, добавить соль и варить горох 50–60 минут до полной мягкости.',
      'Измельчить горох до гладкой массы, разлить по тарелкам и охладить до застывания.',
      'Нарезать 120 г лука и обжарить его в 25 мл растительного масла 6–8 минут.',
      'Подать гороховый кисель с жареным луком.',
    ],
    buildSteps: () => [
      _moduleStep('lean-pea-kissel', 1, CatalogCards.rinse, [
        (card: CatalogCards.peas, grams: 300),
      ]),
      _moduleStep(
        'lean-pea-kissel',
        2,
        CatalogCards.soak,
        [
          (card: CatalogCards.peas, grams: 300),
          (card: CatalogCards.water, milliliters: 900),
        ],
        minutes: 360,
        upperMinutes: 480,
      ),
      _moduleStep(
        'lean-pea-kissel',
        3,
        CatalogCards.boil,
        [
          (card: CatalogCards.peas, grams: 300),
          (card: CatalogCards.water, milliliters: 1000),
          (card: CatalogCards.salt, grams: 5),
        ],
        minutes: 50,
        upperMinutes: 60,
      ),
      _moduleStep('lean-pea-kissel', 4, CatalogCards.blend, [
        (card: CatalogCards.peas, grams: 300),
      ]),
      _moduleStep('lean-pea-kissel', 5, CatalogCards.cool, [
        (card: CatalogCards.peas, grams: 300),
      ], minutes: 120),
      _moduleStep('lean-pea-kissel', 6, CatalogCards.cut, [
        (card: CatalogCards.onion, grams: 120),
      ]),
      _moduleStep(
        'lean-pea-kissel',
        7,
        CatalogCards.fry,
        [
          (card: CatalogCards.onion, grams: 120),
          (card: CatalogCards.vegetableOil, milliliters: 25),
        ],
        minutes: 6,
        upperMinutes: 8,
      ),
    ],
  ),
  CatalogRecipe(
    id: 'lean-shchi-grains-mushrooms',
    title: 'Щи с крупой и грибами',
    servings: 6,
    detailedSteps: [
      'Промыть 120 г перловой крупы и замочить её на 2 часа.',
      'Нашинковать 500 г капусты; нарезать 300 г картошки, 150 г моркови, 120 г лука и 300 г грибов.',
      'Обжарить лук, морковь и грибы в 30 мл растительного масла 8–10 минут.',
      'Влить 1 800 мл воды, добавить крупу, картошку, капусту, соль и лавровый лист.',
      'Варить щи 30–35 минут, затем добавить обжаренные овощи с грибами и варить ещё 10 минут.',
    ],
    buildSteps: () => [
      _moduleStep('lean-shchi', 1, CatalogCards.rinse, [
        (card: CatalogCards.pearlBarley, grams: 120),
      ]),
      _moduleStep('lean-shchi', 2, CatalogCards.soak, [
        (card: CatalogCards.pearlBarley, grams: 120),
      ], minutes: 120),
      _moduleStep('lean-shchi', 3, CatalogCards.shred, [
        (card: CatalogCards.cabbage, grams: 500),
      ]),
      _moduleStep('lean-shchi', 4, CatalogCards.cut, [
        (card: CatalogCards.potato, grams: 300),
        (card: CatalogCards.carrot, grams: 150),
        (card: CatalogCards.onion, grams: 120),
        (card: CatalogCards.mushrooms, grams: 300),
      ]),
      _moduleStep(
        'lean-shchi',
        5,
        CatalogCards.fry,
        [
          (card: CatalogCards.onion, grams: 120),
          (card: CatalogCards.carrot, grams: 150),
          (card: CatalogCards.mushrooms, grams: 300),
          (card: CatalogCards.vegetableOil, milliliters: 30),
        ],
        minutes: 8,
        upperMinutes: 10,
      ),
      _moduleStep('lean-shchi', 6, CatalogCards.add, [
        (card: CatalogCards.water, milliliters: 1800),
        (card: CatalogCards.pearlBarley, grams: 120),
        (card: CatalogCards.potato, grams: 300),
        (card: CatalogCards.cabbage, grams: 500),
        (card: CatalogCards.salt, grams: 9),
        (card: CatalogCards.bayLeaf, pieces: 2),
      ]),
      _moduleStep(
        'lean-shchi',
        7,
        CatalogCards.boil,
        [(card: CatalogCards.cabbage, grams: 500)],
        minutes: 30,
        upperMinutes: 35,
      ),
      _moduleStep('lean-shchi', 8, CatalogCards.boil, [
        (card: CatalogCards.mushrooms, grams: 300),
      ], minutes: 10),
    ],
  ),
  CatalogRecipe(
    id: 'lean-stuffed-turnip',
    title: 'Репа чинёная с грибами и рисом',
    servings: 4,
    detailedSteps: [
      'Промыть 120 г риса и варить его в 250 мл воды 15 минут.',
      'Очистить 800 г репы и варить её 15–20 минут до полуготовности.',
      'Нарезать 250 г грибов и 100 г лука; обжарить их в 25 мл растительного масла 8 минут.',
      'Смешать рис, грибы, лук и соль. Начинить репу получившейся смесью.',
      'Запекать репу при 180 °C 25–30 минут.',
    ],
    buildSteps: () => [
      _moduleStep('stuffed-turnip', 1, CatalogCards.rinse, [
        (card: CatalogCards.rice, grams: 120),
      ]),
      _moduleStep('stuffed-turnip', 2, CatalogCards.boil, [
        (card: CatalogCards.rice, grams: 120),
        (card: CatalogCards.water, milliliters: 250),
      ], minutes: 15),
      _moduleStep('stuffed-turnip', 3, CatalogCards.clean, [
        (card: CatalogCards.turnip, grams: 800),
      ]),
      _moduleStep(
        'stuffed-turnip',
        4,
        CatalogCards.boil,
        [(card: CatalogCards.turnip, grams: 800)],
        minutes: 15,
        upperMinutes: 20,
      ),
      _moduleStep('stuffed-turnip', 5, CatalogCards.cut, [
        (card: CatalogCards.mushrooms, grams: 250),
        (card: CatalogCards.onion, grams: 100),
      ]),
      _moduleStep('stuffed-turnip', 6, CatalogCards.fry, [
        (card: CatalogCards.mushrooms, grams: 250),
        (card: CatalogCards.onion, grams: 100),
        (card: CatalogCards.vegetableOil, milliliters: 25),
      ], minutes: 8),
      _moduleStep('stuffed-turnip', 7, CatalogCards.mix, [
        (card: CatalogCards.rice, grams: 120),
        (card: CatalogCards.mushrooms, grams: 250),
        (card: CatalogCards.salt, grams: 5),
      ]),
      _moduleStep('stuffed-turnip', 8, CatalogCards.fill, [
        (card: CatalogCards.turnip, grams: 800),
        (card: CatalogCards.rice, grams: 120),
      ]),
      _moduleStep(
        'stuffed-turnip',
        9,
        CatalogCards.bake,
        [(card: CatalogCards.turnip, grams: 800)],
        temperature: 180,
        minutes: 25,
        upperMinutes: 30,
      ),
    ],
  ),
  CatalogRecipe(
    id: 'lean-kundyubki',
    title: 'Кундюбки с грибами',
    servings: 6,
    detailedSteps: [
      'Смешать 350 г муки, 160 мл воды, 30 мл растительного масла и соль; вымесить тесто.',
      'Промыть 120 г гречки и варить её 15 минут.',
      'Нарезать 300 г грибов и 120 г лука; обжарить в 25 мл масла 8–10 минут.',
      'Смешать гречку с грибами и луком. Раскатать тесто тонко, завернуть начинку и защипнуть края.',
      'Запекать кундюбки при 190 °C 20–25 минут.',
    ],
    buildSteps: () => [
      _moduleStep('kundyubki', 1, CatalogCards.knead, [
        (card: CatalogCards.flour, grams: 350),
        (card: CatalogCards.water, milliliters: 160),
        (card: CatalogCards.vegetableOil, milliliters: 30),
        (card: CatalogCards.salt, grams: 4),
      ]),
      _moduleStep('kundyubki', 2, CatalogCards.rinse, [
        (card: CatalogCards.buckwheat, grams: 120),
      ]),
      _moduleStep('kundyubki', 3, CatalogCards.boil, [
        (card: CatalogCards.buckwheat, grams: 120),
        (card: CatalogCards.water, milliliters: 260),
      ], minutes: 15),
      _moduleStep('kundyubki', 4, CatalogCards.cut, [
        (card: CatalogCards.mushrooms, grams: 300),
        (card: CatalogCards.onion, grams: 120),
      ]),
      _moduleStep(
        'kundyubki',
        5,
        CatalogCards.fry,
        [
          (card: CatalogCards.mushrooms, grams: 300),
          (card: CatalogCards.onion, grams: 120),
          (card: CatalogCards.vegetableOil, milliliters: 25),
        ],
        minutes: 8,
        upperMinutes: 10,
      ),
      _moduleStep('kundyubki', 6, CatalogCards.mix, [
        (card: CatalogCards.buckwheat, grams: 120),
        (card: CatalogCards.mushrooms, grams: 300),
      ]),
      _moduleStep('kundyubki', 7, CatalogCards.rollOut, [
        (card: CatalogCards.flour, grams: 350),
      ]),
      _moduleStep('kundyubki', 8, CatalogCards.wrap, [
        (card: CatalogCards.mushrooms, grams: 300),
      ]),
      _moduleStep('kundyubki', 9, CatalogCards.pinch, [
        (card: CatalogCards.mushrooms, grams: 300),
      ]),
      _moduleStep(
        'kundyubki',
        10,
        CatalogCards.bake,
        [(card: CatalogCards.mushrooms, grams: 300)],
        temperature: 190,
        minutes: 20,
        upperMinutes: 25,
      ),
    ],
  ),
  CatalogRecipe(
    id: 'lean-kulebyaka-cabbage-mushrooms',
    title: 'Кулебяка с капустой и грибами',
    servings: 8,
    detailedSteps: [
      'Смешать 500 г муки, 280 мл воды, 7 г сухих дрожжей, 15 г сахара, 35 мл масла и соль; вымесить тесто.',
      'Нашинковать 700 г капусты, нарезать 300 г грибов и 150 г лука.',
      'Обжарить лук и грибы 8 минут, добавить капусту и тушить ещё 15 минут.',
      'Раскатать тесто, выложить начинку, завернуть и защипнуть края.',
      'Выпекать кулебяку при 190 °C 35–40 минут.',
    ],
    buildSteps: () => [
      _moduleStep('lean-kulebyaka', 1, CatalogCards.knead, [
        (card: CatalogCards.flour, grams: 500),
        (card: CatalogCards.water, milliliters: 280),
        (card: CatalogCards.yeast, grams: 7),
        (card: CatalogCards.sugar, grams: 15),
        (card: CatalogCards.vegetableOil, milliliters: 35),
        (card: CatalogCards.salt, grams: 6),
      ]),
      _moduleStep('lean-kulebyaka', 2, CatalogCards.shred, [
        (card: CatalogCards.cabbage, grams: 700),
      ]),
      _moduleStep('lean-kulebyaka', 3, CatalogCards.cut, [
        (card: CatalogCards.mushrooms, grams: 300),
        (card: CatalogCards.onion, grams: 150),
      ]),
      _moduleStep('lean-kulebyaka', 4, CatalogCards.fry, [
        (card: CatalogCards.mushrooms, grams: 300),
        (card: CatalogCards.onion, grams: 150),
        (card: CatalogCards.vegetableOil, milliliters: 25),
      ], minutes: 8),
      _moduleStep('lean-kulebyaka', 5, CatalogCards.stew, [
        (card: CatalogCards.cabbage, grams: 700),
        (card: CatalogCards.mushrooms, grams: 300),
      ], minutes: 15),
      _moduleStep('lean-kulebyaka', 6, CatalogCards.rollOut, [
        (card: CatalogCards.flour, grams: 500),
      ]),
      _moduleStep('lean-kulebyaka', 7, CatalogCards.wrap, [
        (card: CatalogCards.cabbage, grams: 700),
      ]),
      _moduleStep('lean-kulebyaka', 8, CatalogCards.pinch, [
        (card: CatalogCards.cabbage, grams: 700),
      ]),
      _moduleStep(
        'lean-kulebyaka',
        9,
        CatalogCards.bake,
        [(card: CatalogCards.cabbage, grams: 700)],
        temperature: 190,
        minutes: 35,
        upperMinutes: 40,
      ),
    ],
  ),
  CatalogRecipe(
    id: 'lean-levashniki-apple',
    title: 'Левашники с яблоком',
    servings: 6,
    detailedSteps: [
      'Смешать 350 г муки, 180 мл воды и 20 мл растительного масла; вымесить тесто.',
      'Очистить и измельчить 500 г яблок, смешать их со 100 г сахара.',
      'Раскатать тесто, завернуть в него яблочную начинку и защипнуть края.',
      'Жарить левашники в 250 мл растительного масла по 3–4 минуты с каждой стороны.',
    ],
    buildSteps: () => [
      _moduleStep('lean-levashniki', 1, CatalogCards.knead, [
        (card: CatalogCards.flour, grams: 350),
        (card: CatalogCards.water, milliliters: 180),
        (card: CatalogCards.vegetableOil, milliliters: 20),
      ]),
      _moduleStep('lean-levashniki', 2, CatalogCards.clean, [
        (card: CatalogCards.apples, grams: 500),
      ]),
      _moduleStep('lean-levashniki', 3, CatalogCards.blend, [
        (card: CatalogCards.apples, grams: 500),
        (card: CatalogCards.sugar, grams: 100),
      ]),
      _moduleStep('lean-levashniki', 4, CatalogCards.rollOut, [
        (card: CatalogCards.flour, grams: 350),
      ]),
      _moduleStep('lean-levashniki', 5, CatalogCards.wrap, [
        (card: CatalogCards.apples, grams: 500),
      ]),
      _moduleStep('lean-levashniki', 6, CatalogCards.pinch, [
        (card: CatalogCards.apples, grams: 500),
      ]),
      _moduleStep(
        'lean-levashniki',
        7,
        CatalogCards.fry,
        [
          (card: CatalogCards.apples, grams: 500),
          (card: CatalogCards.vegetableOil, milliliters: 250),
        ],
        minutes: 3,
        upperMinutes: 4,
      ),
    ],
  ),
  CatalogRecipe(
    id: 'fried-mushrooms-sour-cream',
    title: 'Грибы, жаренные в сметане',
    servings: 4,
    detailedSteps: [
      'Нарезать 500 г грибов и 120 г лука.',
      'Обжарить лук в 25 мл растительного масла 3–4 минуты.',
      'Добавить грибы и жарить 8–10 минут, пока лишняя влага почти не испарится.',
      'Смешать 200 г сметаны, 10 г муки и 50 мл воды до однородности.',
      'Добавить сметанный соус, 5 г соли и 1 г чёрного перца.',
      'Тушить грибы на слабом огне 5–7 минут.',
      'Добавить 10 г укропа перед подачей.',
    ],
    buildSteps: () => [
      _moduleStep('fried-mushrooms-sour-cream', 1, CatalogCards.cut, [
        (card: CatalogCards.mushrooms, grams: 500),
        (card: CatalogCards.onion, grams: 120),
      ]),
      _moduleStep(
        'fried-mushrooms-sour-cream',
        2,
        CatalogCards.fry,
        [
          (card: CatalogCards.onion, grams: 120),
          (card: CatalogCards.vegetableOil, milliliters: 25),
        ],
        minutes: 3,
        upperMinutes: 4,
      ),
      _moduleStep(
        'fried-mushrooms-sour-cream',
        3,
        CatalogCards.fry,
        [(card: CatalogCards.mushrooms, grams: 500)],
        minutes: 8,
        upperMinutes: 10,
      ),
      _moduleStep('fried-mushrooms-sour-cream', 4, CatalogCards.mix, [
        (card: CatalogCards.sourCream, grams: 200),
        (card: CatalogCards.flour, grams: 10),
        (card: CatalogCards.water, milliliters: 50),
      ]),
      _moduleStep('fried-mushrooms-sour-cream', 5, CatalogCards.add, [
        (card: CatalogCards.sourCream, grams: 200),
        (card: CatalogCards.salt, grams: 5),
        (card: CatalogCards.blackPepper, grams: 1),
      ]),
      _moduleStep(
        'fried-mushrooms-sour-cream',
        6,
        CatalogCards.stew,
        [(card: CatalogCards.mushrooms, grams: 500)],
        minutes: 5,
        upperMinutes: 7,
      ),
      _moduleStep('fried-mushrooms-sour-cream', 7, CatalogCards.add, [
        (card: CatalogCards.dill, grams: 10),
      ]),
    ],
  ),
];

final catalogRecipes = <CatalogRecipe>[
  ..._newClassicRecipes,
  _homemadeCreamIceCream,
  _homemadeChocolateIceCream,
  _homemadeBananaIceCream,
  _homemadeCremeBruleeIceCream,
  _traditionalMushroomSoup,
  _traditionalMilkNoodleSoup,
  _traditionalBuckwheatMushrooms,
  _traditionalOatmeal,
  _traditionalSemolinaPorridge,
  _traditionalSyrniki,
  _traditionalYeastPancakes,
  _traditionalCocoa,
  _traditionalSquashCaviar,
  _traditionalRaspberryJam,
  _traditionalPearlBarley,
  _traditionalCottageCheeseCasserole,
  _traditionalBakedBeet,
  _traditionalCapitalSalad,
  _traditionalSovietGoulash,
  _lazyCabbageRolls,
  ..._traditionalPorridges,
  CatalogRecipe(
    id: 'cabbage-potato-pancakes',
    title: 'Драники из капусты и картошки',
    detailedSteps: [
      'Включить мультиварку Moulinex CE5A0FF2: вынуть чашу, вытереть её насухо и поставить на место.',
      'Тонко нашинковать 1 кг белокочанной капусты, посолить 10 г соли, перемешать и оставить на 10 минут.',
      'Тщательно отжать капусту от выделившегося сока.',
      'Натереть 1 кг картофеля на крупной тёрке и сразу смешать с капустой.',
      'Добавить 3 яйца, 200 г муки и оставшиеся 5 г соли; перемешать до равномерной густой массы.',
      'Выбрать программу «Жарка», налить 30 мл растительного масла и прогреть чашу 2 минуты.',
      'Сформировать плоские драники толщиной около 1 см, выкладывая их в один слой.',
      'Жарить 4–6 минут с каждой стороны до румяной корочки; при необходимости доливать масло небольшими порциями.',
      'Переложить готовые драники на тарелку и подавать горячими.',
    ],
    buildSteps: () => [
      _node('dran-1', CatalogCards.grate, [
        _ingredient('dran-1-cabbage', CatalogCards.cabbage, [
          RecipeNode(
            id: 'dran-1-mass',
            card: CatalogCards.mass,
            value: 1000,
            unit: NumericUnit.grams,
          ),
        ]),
      ]),
      _node('dran-2', CatalogCards.add, [
        _ingredient('dran-2-salt', CatalogCards.salt, [
          RecipeNode(
            id: 'dran-2-salt-mass',
            card: CatalogCards.mass,
            value: 10,
            unit: NumericUnit.grams,
          ),
        ]),
      ]),
      _node('dran-3', CatalogCards.leave, [
        _ingredient('dran-3-cabbage', CatalogCards.cabbage),
        RecipeNode(
          id: 'dran-3-time',
          card: CatalogCards.time,
          value: 10,
          unit: NumericUnit.minutes,
        ),
      ]),
      _node('dran-4', CatalogCards.drain, [
        _ingredient('dran-4-cabbage', CatalogCards.cabbage),
        RecipeNode(
          id: 'dran-4-text',
          card: CatalogCards.freeText,
          text: 'от лишнего сока',
        ),
      ]),
      _node('dran-5', CatalogCards.grate, [
        _ingredient('dran-2-potato', CatalogCards.potato, [
          RecipeNode(
            id: 'dran-2-mass',
            card: CatalogCards.mass,
            value: 1000,
            unit: NumericUnit.grams,
          ),
        ]),
      ]),
      _node('dran-6', CatalogCards.add, [
        _ingredient('dran-6-eggs', CatalogCards.eggs, [
          RecipeNode(
            id: 'dran-6-eggs-count',
            card: CatalogCards.count,
            value: 3,
            unit: NumericUnit.pieces,
          ),
        ]),
        _ingredient('dran-6-flour', CatalogCards.flour, [
          RecipeNode(
            id: 'dran-6-flour-mass',
            card: CatalogCards.mass,
            value: 200,
            unit: NumericUnit.grams,
          ),
        ]),
        _ingredient('dran-6-salt', CatalogCards.salt, [
          RecipeNode(
            id: 'dran-6-salt-mass',
            card: CatalogCards.mass,
            value: 15,
            unit: NumericUnit.grams,
          ),
        ]),
      ]),
      _node('dran-7', CatalogCards.mix, [
        _ingredient('dran-7-cabbage', CatalogCards.cabbage),
        _ingredient('dran-7-potato', CatalogCards.potato),
        _ingredient('dran-7-eggs', CatalogCards.eggs),
        _ingredient('dran-7-flour', CatalogCards.flour),
      ]),
      _multicookerStep('dran-8', 'Жарка'),
      _node('dran-9', CatalogCards.add, [
        _ingredient('dran-9-oil', CatalogCards.vegetableOil, [
          RecipeNode(
            id: 'dran-9-oil-volume',
            card: CatalogCards.volume,
            value: 30,
            unit: NumericUnit.milliliters,
          ),
        ]),
      ]),
      _node('dran-10', CatalogCards.form, [
        RecipeNode(
          id: 'dran-10-text',
          card: CatalogCards.freeText,
          text: 'драники толщиной около 1 см',
        ),
      ]),
      _node('dran-11', CatalogCards.fry, [
        RecipeNode(
          id: 'dran-11-text',
          card: CatalogCards.freeText,
          text: 'драники с каждой стороны',
        ),
        RecipeNode(
          id: 'dran-11-time',
          card: CatalogCards.time,
          value: 4,
          upperValue: 6,
          unit: NumericUnit.minutes,
        ),
      ]),
      _node('dran-12', CatalogCards.plate, [
        RecipeNode(
          id: 'dran-12-text',
          card: CatalogCards.freeText,
          text: 'драники',
        ),
        RecipeNode(
          id: 'dran-12-plate',
          card: CatalogCards.servingPlate,
          caseFromParent: GrammarCase.accusative,
        ),
      ]),
    ],
  ),
  CatalogRecipe(
    id: 'curd-casserole-apples',
    title: 'Творожная запеканка с яблоками',
    detailedSteps: [
      'Включить мультиварку Moulinex CE5A0FF2: вынуть чашу и проверить, что она сухая.',
      'Очистить 2 яблока, удалить сердцевину, нарезать кубиками 8–10 мм; прогреть на сухой сковороде 4–5 минут и полностью остудить.',
      'Смешать 600 г творога, 3 яйца, 60–70 г сахара, щепотку соли и 70 г сметаны.',
      'Добавить 60 г пшеничной муки и 1 ч. л. разрыхлителя; перемешать до однородности.',
      'Добавить остывшие яблоки и аккуратно перемешать.',
      'Смазать чашу сливочным маслом, выложить массу и разровнять.',
      'Выпекать на программе «Выпечка» 50 минут; при жидком центре добавить 10 минут.',
      'Выключить подогрев, оставить в чаше 15 минут, затем открыть крышку и остудить ещё 10–15 минут.',
    ],
    buildSteps: () => [
      _node('zap-1', CatalogCards.cut, [
        _ingredient('zap-1-a', CatalogCards.apples, [
          RecipeNode(
            id: 'zap-1-text',
            card: CatalogCards.shape,
            text: 'кубиками',
          ),
          RecipeNode(
            id: 'zap-1-mass',
            card: CatalogCards.mass,
            value: 230,
            unit: NumericUnit.grams,
          ),
        ]),
      ]),
      _node('zap-2', CatalogCards.fry, [
        _ingredient('zap-2-apples', CatalogCards.apples),
        RecipeNode(
          id: 'zap-2-time',
          card: CatalogCards.time,
          value: 4,
          upperValue: 5,
          unit: NumericUnit.minutes,
        ),
      ]),
      _node('zap-3', CatalogCards.mix, [
        _ingredient('zap-3-a', CatalogCards.cottageCheese, [
          RecipeNode(
            id: 'zap-3-q',
            card: CatalogCards.mass,
            value: 600,
            unit: NumericUnit.grams,
          ),
        ]),
        _ingredient('zap-3-e', CatalogCards.eggs),
        _ingredient('zap-3-sugar', CatalogCards.sugar, [
          RecipeNode(
            id: 'zap-3-sugar-mass',
            card: CatalogCards.mass,
            value: 70,
            unit: NumericUnit.grams,
          ),
        ]),
        _ingredient('zap-3-salt', CatalogCards.salt, [
          RecipeNode(
            id: 'zap-3-salt-mass',
            card: CatalogCards.mass,
            value: 1,
            unit: NumericUnit.grams,
          ),
        ]),
        _ingredient('zap-3-cream', CatalogCards.sourCream, [
          RecipeNode(
            id: 'zap-3-cream-mass',
            card: CatalogCards.mass,
            value: 70,
            unit: NumericUnit.grams,
          ),
        ]),
      ]),
      _node('zap-4', CatalogCards.add, [
        _ingredient('zap-4-f', CatalogCards.flour, [
          RecipeNode(
            id: 'zap-4-flour-mass',
            card: CatalogCards.mass,
            value: 60,
            unit: NumericUnit.grams,
          ),
        ]),
        _ingredient('zap-4-powder', CatalogCards.bakingPowder, [
          RecipeNode(
            id: 'zap-4-powder-mass',
            card: CatalogCards.mass,
            value: 5,
            unit: NumericUnit.grams,
          ),
        ]),
      ]),
      _node('zap-5', CatalogCards.add, [
        _ingredient('zap-5-apples', CatalogCards.apples),
      ]),
      _node('zap-6', CatalogCards.grease, [
        _ingredient('zap-6-butter', CatalogCards.butter, [
          RecipeNode(
            id: 'zap-6-butter-mass',
            card: CatalogCards.mass,
            value: 15,
            unit: NumericUnit.grams,
          ),
        ]),
      ]),
      _multicookerStep('zap-7', 'Выпечка', 50),
      _node('zap-8', CatalogCards.leave, [
        _ingredient('zap-8-casserole', CatalogCards.cottageCheese),
        RecipeNode(
          id: 'zap-8-time',
          card: CatalogCards.time,
          value: 15,
          unit: NumericUnit.minutes,
        ),
      ]),
    ],
  ),
  CatalogRecipe(
    id: 'buckwheat-pudding-apples',
    title: 'Крупник с яблоками',
    detailedSteps: [
      'Включить мультиварку Moulinex CE5A0FF2.',
      'Очистить 1–2 яблока, нарезать кубиками, прогреть 4–5 минут и остудить.',
      'Смешать 400 г готовой остывшей гречки, 400 г творога, 3 яйца, 70 г сметаны, 50–60 г сахара, щепотку соли и 30–35 г муки.',
      'Добавить яблоки и по желанию ½ ч. л. корицы.',
      'Смазать чашу сливочным маслом, выложить массу и разровнять.',
      'Выпекать на «Выпечке» 50 минут; при жидком центре добавить 10 минут.',
      'Выключить подогрев, оставить в чаше 15–20 минут, затем остудить полностью.',
    ],
    buildSteps: () => [
      _node('kr-1', CatalogCards.mix, [
        _ingredient('kr-1-b', CatalogCards.buckwheat, [
          RecipeNode(
            id: 'kr-1-q',
            card: CatalogCards.mass,
            value: 400,
            unit: NumericUnit.grams,
          ),
        ]),
        _ingredient('kr-1-c', CatalogCards.cottageCheese, [
          RecipeNode(
            id: 'kr-1-cq',
            card: CatalogCards.mass,
            value: 400,
            unit: NumericUnit.grams,
          ),
        ]),
        _ingredient('kr-1-eggs', CatalogCards.eggs),
        _ingredient('kr-1-cream', CatalogCards.sourCream, [
          RecipeNode(
            id: 'kr-1-cream-mass',
            card: CatalogCards.mass,
            value: 70,
            unit: NumericUnit.grams,
          ),
        ]),
        _ingredient('kr-1-sugar', CatalogCards.sugar, [
          RecipeNode(
            id: 'kr-1-sugar-mass',
            card: CatalogCards.mass,
            value: 55,
            unit: NumericUnit.grams,
          ),
        ]),
        _ingredient('kr-1-salt', CatalogCards.salt, [
          RecipeNode(
            id: 'kr-1-salt-mass',
            card: CatalogCards.mass,
            value: 1,
            unit: NumericUnit.grams,
          ),
        ]),
        _ingredient('kr-1-flour', CatalogCards.flour, [
          RecipeNode(
            id: 'kr-1-flour-mass',
            card: CatalogCards.mass,
            value: 35,
            unit: NumericUnit.grams,
          ),
        ]),
      ]),
      _node('kr-2', CatalogCards.cut, [
        _ingredient('kr-2-a', CatalogCards.apples, [
          RecipeNode(
            id: 'kr-2-text',
            card: CatalogCards.shape,
            text: 'кубиками',
          ),
          RecipeNode(
            id: 'kr-2-mass',
            card: CatalogCards.mass,
            value: 200,
            unit: NumericUnit.grams,
          ),
        ]),
      ]),
      _node('kr-3', CatalogCards.fry, [
        _ingredient('kr-3-apples', CatalogCards.apples),
        RecipeNode(
          id: 'kr-3-time',
          card: CatalogCards.time,
          value: 4,
          upperValue: 5,
          unit: NumericUnit.minutes,
        ),
      ]),
      _node('kr-4', CatalogCards.add, [
        _ingredient('kr-4-apples', CatalogCards.apples),
      ]),
      _node('kr-5', CatalogCards.grease, [
        _ingredient('kr-5-butter', CatalogCards.butter, [
          RecipeNode(
            id: 'kr-5-butter-mass',
            card: CatalogCards.mass,
            value: 15,
            unit: NumericUnit.grams,
          ),
        ]),
      ]),
      _multicookerStep('kr-6', 'Выпечка', 50),
      _node('kr-7', CatalogCards.leave, [
        _ingredient('kr-7-pudding', CatalogCards.buckwheat),
        RecipeNode(
          id: 'kr-7-time',
          card: CatalogCards.time,
          value: 15,
          upperValue: 20,
          unit: NumericUnit.minutes,
        ),
      ]),
    ],
  ),
  CatalogRecipe(
    id: 'pork-escalope-cream',
    title: 'Свиные отбивные в яично-сливочном льезоне',
    detailedSteps: [
      'Включить мультиварку Moulinex CE5A0FF2, включить «Жарку» и прогреть чашу 2–3 минуты.',
      'Эскалопы 1,25 кг при толщине более 1 см слегка отбить до 7–10 мм.',
      'Посолить 12–14 г соли, поперчить и оставить на 10 минут.',
      'Смешать 5 яиц С2, 100 мл сливок жирностью 33%; в отдельную тарелку насыпать 100–120 г муки.',
      'Каждый кусок тонко обвалять в муке, стряхнуть излишек и окунуть в яично-сливочную смесь.',
      'Жарить партиями в один слой: 2,5–3 минуты с первой стороны и 2–3 минуты со второй.',
      'Между партиями удалить подгоревшие остатки смеси и при необходимости добавить немного масла.',
    ],
    buildSteps: () => [
      _node('pork-1', CatalogCards.beat, [
        _ingredient('pork-1-meat', CatalogCards.pork, [
          RecipeNode(
            id: 'pork-1-mass',
            card: CatalogCards.mass,
            value: 1250,
            unit: NumericUnit.grams,
          ),
        ]),
      ]),
      _node('pork-2', CatalogCards.add, [
        _ingredient('pork-2-salt', CatalogCards.salt, [
          RecipeNode(
            id: 'pork-2-salt-mass',
            card: CatalogCards.mass,
            value: 13,
            unit: NumericUnit.grams,
          ),
        ]),
        _ingredient('pork-2-pepper', CatalogCards.blackPepper),
      ]),
      _node('pork-3', CatalogCards.leave, [
        _ingredient('pork-3-meat', CatalogCards.pork),
        RecipeNode(
          id: 'pork-3-time',
          card: CatalogCards.time,
          value: 10,
          unit: NumericUnit.minutes,
        ),
      ]),
      _node('pork-4', CatalogCards.mix, [
        _ingredient('pork-4-eggs', CatalogCards.eggs),
        _ingredient('pork-4-cream', CatalogCards.cream, [
          RecipeNode(
            id: 'pork-4-cream-volume',
            card: CatalogCards.volume,
            value: 100,
            unit: NumericUnit.milliliters,
          ),
          RecipeNode(
            id: 'pork-4-cream-fat',
            card: CatalogCards.fatContent,
            value: 33,
            unit: NumericUnit.percent,
          ),
        ]),
      ]),
      _node('pork-5', CatalogCards.add, [
        _ingredient('pork-5-flour', CatalogCards.flour, [
          RecipeNode(
            id: 'pork-5-flour-mass',
            card: CatalogCards.mass,
            value: 110,
            unit: NumericUnit.grams,
          ),
        ]),
      ]),
      _multicookerStep('pork-6', 'Жарка'),
      _node('pork-7', CatalogCards.add, [
        _ingredient('pork-7-oil', CatalogCards.vegetableOil, [
          RecipeNode(
            id: 'pork-7-oil-volume',
            card: CatalogCards.volume,
            value: 30,
            unit: NumericUnit.milliliters,
          ),
        ]),
      ]),
      _node('pork-8', CatalogCards.dip, [
        _ingredient('pork-8-meat', CatalogCards.pork),
        _ingredient('pork-8-eggs', CatalogCards.eggs),
      ]),
      _node('pork-9', CatalogCards.fry, [
        _ingredient('pork-9-meat', CatalogCards.pork),
        RecipeNode(
          id: 'pork-9-time',
          card: CatalogCards.time,
          value: 2,
          upperValue: 3,
          unit: NumericUnit.minutes,
        ),
      ]),
    ],
  ),
  CatalogRecipe(
    id: 'fresh-cabbage-soup',
    title: 'Щи из свежей капусты со свининой',
    detailedSteps: [
      'Включить мультиварку Moulinex CE5A0FF2.',
      'Нарезать 700 г свиной лопатки кусками 3–4 см; обжарить на «Жарке» в 1 ст. л. масла 6–8 минут.',
      'Добавить половину лука, 1,5 л горячей воды и ½ ч. л. соли; готовить на «Супе» под давлением 25 минут.',
      'Подождать 10 минут, сбросить остаточное давление.',
      'Нарезать 400–500 г картофеля, нашинковать 500–600 г свежей капусты, подготовить морковь и оставшийся лук.',
      'Добавить картофель, овощи, капусту, лавровый лист и долить воду до 1,8–2 л.',
      'Варить на «Супе» под давлением 5 минут; подождать 5 минут и сбросить давление.',
      'Посолить, поперчить и оставить под крышкой без давления на 15–20 минут.',
    ],
    buildSteps: () => [
      _node('soup-1', CatalogCards.cut, [
        _ingredient('soup-1-p', CatalogCards.pork, [
          RecipeNode(
            id: 'soup-1-mass',
            card: CatalogCards.mass,
            value: 700,
            unit: NumericUnit.grams,
          ),
        ]),
      ]),
      _multicookerStep('soup-2', 'Жарка'),
      _node('soup-3', CatalogCards.add, [
        _ingredient('soup-3-oil', CatalogCards.vegetableOil, [
          RecipeNode(
            id: 'soup-3-oil-volume',
            card: CatalogCards.volume,
            value: 15,
            unit: NumericUnit.milliliters,
          ),
        ]),
      ]),
      _node('soup-4', CatalogCards.saute, [
        _ingredient('soup-4-pork', CatalogCards.pork),
        RecipeNode(
          id: 'soup-4-time',
          card: CatalogCards.time,
          value: 6,
          upperValue: 8,
          unit: NumericUnit.minutes,
        ),
      ]),
      _node('soup-5', CatalogCards.add, [
        _ingredient('soup-5-onion', CatalogCards.onion, [
          RecipeNode(
            id: 'soup-5-onion-mass',
            card: CatalogCards.mass,
            value: 75,
            unit: NumericUnit.grams,
          ),
        ]),
        _ingredient('soup-5-water', CatalogCards.water, [
          RecipeNode(
            id: 'soup-5-water-volume',
            card: CatalogCards.volume,
            value: 1500,
            unit: NumericUnit.milliliters,
          ),
        ]),
        _ingredient('soup-5-salt', CatalogCards.salt, [
          RecipeNode(
            id: 'soup-5-salt-mass',
            card: CatalogCards.mass,
            value: 3,
            unit: NumericUnit.grams,
          ),
        ]),
      ]),
      _multicookerStep('soup-6', 'Суп', 25),
      _node('soup-7', CatalogCards.cut, [
        _ingredient('soup-7-potato', CatalogCards.potato, [
          RecipeNode(
            id: 'soup-7-potato-mass',
            card: CatalogCards.mass,
            value: 450,
            unit: NumericUnit.grams,
          ),
        ]),
      ]),
      _node('soup-8', CatalogCards.shred, [
        _ingredient('soup-8-cabbage', CatalogCards.cabbage, [
          RecipeNode(
            id: 'soup-8-cabbage-mass',
            card: CatalogCards.mass,
            value: 550,
            unit: NumericUnit.grams,
          ),
        ]),
      ]),
      _node('soup-9', CatalogCards.add, [
        _ingredient('soup-9-potato', CatalogCards.potato),
        _ingredient('soup-9-cabbage', CatalogCards.cabbage),
        _ingredient('soup-9-carrot', CatalogCards.carrot, [
          RecipeNode(
            id: 'soup-9-carrot-mass',
            card: CatalogCards.mass,
            value: 150,
            unit: NumericUnit.grams,
          ),
        ]),
        _ingredient('soup-9-onion', CatalogCards.onion, [
          RecipeNode(
            id: 'soup-9-onion-mass',
            card: CatalogCards.mass,
            value: 75,
            unit: NumericUnit.grams,
          ),
        ]),
        _ingredient('soup-9-bay', CatalogCards.bayLeaf),
      ]),
      _multicookerStep('soup-10', 'Суп', 5),
      _node('soup-11', CatalogCards.add, [
        _ingredient('soup-11-salt', CatalogCards.salt, [
          RecipeNode(
            id: 'soup-11-salt-mass',
            card: CatalogCards.mass,
            value: 6,
            unit: NumericUnit.grams,
          ),
        ]),
        _ingredient('soup-11-pepper', CatalogCards.blackPepper),
        _ingredient('soup-11-garlic', CatalogCards.garlic),
      ]),
      _node('soup-12', CatalogCards.leave, [
        _ingredient('soup-12-soup', CatalogCards.cabbage),
        RecipeNode(
          id: 'soup-12-time',
          card: CatalogCards.time,
          value: 15,
          upperValue: 20,
          unit: NumericUnit.minutes,
        ),
      ]),
    ],
  ),
  CatalogRecipe(
    id: 'milk-buckwheat',
    title: 'Гречка на молоке',
    detailedSteps: [
      'Включить мультиварку Moulinex CE5A0FF2.',
      'Промыть 200 г гречки 2–3 раза и тщательно слить воду.',
      'Переложить гречку в чашу.',
      'Влить 200 мл молока и 200 мл воды, добавить ½ ч. л. соли.',
      'Перемешать, закрыть и заблокировать крышку.',
      'Выбрать программу «Молочная каша» и установить 10 минут.',
      'После завершения подождать 10 минут, затем аккуратно сбросить остаточное давление и открыть крышку.',
    ],
    buildSteps: () => [
      _node('milk-1', CatalogCards.rinse, [
        _ingredient('milk-1-b', CatalogCards.buckwheat, [
          RecipeNode(
            id: 'milk-1-q',
            card: CatalogCards.mass,
            value: 200,
            unit: NumericUnit.grams,
          ),
        ]),
      ]),
      _node('milk-2', CatalogCards.transfer, [
        _ingredient('milk-8-b', CatalogCards.buckwheat),
      ]),
      _node('milk-3', CatalogCards.pour, [
        _ingredient('milk-3-m', CatalogCards.milk, [
          RecipeNode(
            id: 'milk-3-mq',
            card: CatalogCards.volume,
            value: 200,
            unit: NumericUnit.milliliters,
          ),
        ]),
        _ingredient('milk-3-w', CatalogCards.water, [
          RecipeNode(
            id: 'milk-3-wq',
            card: CatalogCards.volume,
            value: 200,
            unit: NumericUnit.milliliters,
          ),
        ]),
        _ingredient('milk-3-s', CatalogCards.salt, [
          RecipeNode(
            id: 'milk-3-sq',
            card: CatalogCards.mass,
            value: 3,
            unit: NumericUnit.grams,
          ),
        ]),
      ]),
      _node('milk-4', CatalogCards.stir, [
        _ingredient('milk-4-b', CatalogCards.buckwheat),
      ]),
      _node('milk-5', CatalogCards.close, [
        _ingredient('milk-5-l', CatalogCards.lid),
      ]),
      _multicookerStep('milk-6', 'Молочная каша', 10),
      _node('milk-7', CatalogCards.leave, [
        _ingredient('milk-7-porridge', CatalogCards.buckwheat),
        RecipeNode(
          id: 'milk-7-time',
          card: CatalogCards.time,
          value: 10,
          unit: NumericUnit.minutes,
        ),
      ]),
      _node('milk-8', CatalogCards.open, [
        RecipeNode(
          id: 'milk-8-lid',
          card: CatalogCards.lid,
          caseFromParent: GrammarCase.accusative,
        ),
      ]),
      _node('milk-9', CatalogCards.stir, [
        _ingredient('milk-9-buckwheat', CatalogCards.buckwheat),
      ]),
    ],
  ),
  CatalogRecipe(
    id: 'merchant-buckwheat-chicken',
    title: 'Гречка по-купечески с куриным филе',
    detailedSteps: [
      'Включить мультиварку Moulinex CE5A0FF2. Нарезать 750 г куриного филе кубиками по 2–3 см, 150 г лука — небольшими кубиками, натереть 150 г моркови и промыть 350 г гречки 2–3 раза.',
      'На программе «Жарка» с открытой крышкой нагреть 25 мл растительного масла. Обжарить курицу 6–8 минут до лёгкой корочки, не дожидаясь полной готовности.',
      'Добавить лук и обжаривать 3–4 минуты, затем добавить морковь и готовить ещё 3 минуты, перемешивая.',
      'Добавить 20 г томатной пасты, чёрный перец и сладкую паприку; обжаривать 1–2 минуты.',
      'Отключить «Жарку». Распределить гречку среди мяса и овощей, добавить 11–12 г соли, 1–2 лавровых листа и 650 мл горячей воды; перемешать.',
      'Закрыть крышку, готовить на «Тушении» под давлением 7 минут. После завершения выдержать 10 минут для естественного снижения давления, затем открыть крышку.',
      'Добавить 8–10 г измельчённого чеснока и, по желанию, 20–30 г сливочного масла. Осторожно перемешать и оставить под закрытой крышкой без нагрева ещё на 10 минут.',
      'Если крупа получилась слегка твёрдой, влить 30–50 мл горячей воды и довести до готовности с открытой крышкой.',
    ],
    buildSteps: () => [
      _node('merchant-1', CatalogCards.cut, [
        _ingredient('merchant-1-chicken', CatalogCards.chickenFillet, [
          RecipeNode(
            id: 'merchant-1-chicken-mass',
            card: CatalogCards.mass,
            value: 750,
            unit: NumericUnit.grams,
          ),
        ]),
      ]),
      _node('merchant-2', CatalogCards.cut, [
        _ingredient('merchant-2-onion', CatalogCards.onion, [
          RecipeNode(
            id: 'merchant-2-onion-mass',
            card: CatalogCards.mass,
            value: 150,
            unit: NumericUnit.grams,
          ),
        ]),
      ]),
      _node('merchant-3', CatalogCards.grate, [
        _ingredient('merchant-3-carrot', CatalogCards.carrot, [
          RecipeNode(
            id: 'merchant-3-carrot-mass',
            card: CatalogCards.mass,
            value: 150,
            unit: NumericUnit.grams,
          ),
        ]),
      ]),
      _node('merchant-4', CatalogCards.rinse, [
        _ingredient('merchant-4-buckwheat', CatalogCards.buckwheat, [
          RecipeNode(
            id: 'merchant-4-buckwheat-mass',
            card: CatalogCards.mass,
            value: 350,
            unit: NumericUnit.grams,
          ),
        ]),
      ]),
      _multicookerStep('merchant-5', 'Жарка'),
      _node('merchant-6', CatalogCards.add, [
        _ingredient('merchant-6-oil', CatalogCards.vegetableOil, [
          RecipeNode(
            id: 'merchant-6-oil-volume',
            card: CatalogCards.volume,
            value: 25,
            unit: NumericUnit.milliliters,
          ),
        ]),
      ]),
      _node('merchant-7', CatalogCards.fry, [
        _ingredient('merchant-7-chicken', CatalogCards.chickenFillet),
        RecipeNode(
          id: 'merchant-7-time',
          card: CatalogCards.time,
          value: 6,
          upperValue: 8,
          unit: NumericUnit.minutes,
        ),
      ]),
      _node('merchant-8', CatalogCards.add, [
        _ingredient('merchant-8-onion', CatalogCards.onion),
      ]),
      _node('merchant-9', CatalogCards.saute, [
        _ingredient('merchant-9-onion', CatalogCards.onion),
        RecipeNode(
          id: 'merchant-9-time',
          card: CatalogCards.time,
          value: 3,
          upperValue: 4,
          unit: NumericUnit.minutes,
        ),
      ]),
      _node('merchant-10', CatalogCards.add, [
        _ingredient('merchant-10-carrot', CatalogCards.carrot),
      ]),
      _node('merchant-11', CatalogCards.saute, [
        _ingredient('merchant-11-carrot', CatalogCards.carrot),
        RecipeNode(
          id: 'merchant-11-time',
          card: CatalogCards.time,
          value: 3,
          unit: NumericUnit.minutes,
        ),
      ]),
      _node('merchant-12', CatalogCards.add, [
        _ingredient('merchant-12-paste', CatalogCards.tomatoPaste, [
          RecipeNode(
            id: 'merchant-12-paste-mass',
            card: CatalogCards.mass,
            value: 20,
            unit: NumericUnit.grams,
          ),
        ]),
        _ingredient('merchant-12-pepper', CatalogCards.blackPepper),
        _ingredient('merchant-12-paprika', CatalogCards.sweetPaprika),
      ]),
      _node('merchant-13', CatalogCards.fry, [
        _ingredient('merchant-13-paste', CatalogCards.tomatoPaste),
        RecipeNode(
          id: 'merchant-13-time',
          card: CatalogCards.time,
          value: 1,
          upperValue: 2,
          unit: NumericUnit.minutes,
        ),
      ]),
      _node('merchant-14', CatalogCards.turnOff, [
        _multicookerProgram('merchant-14-mode', 'Жарка'),
      ]),
      _node('merchant-15', CatalogCards.add, [
        _ingredient('merchant-15-buckwheat', CatalogCards.buckwheat),
        _ingredient('merchant-15-bay-leaf', CatalogCards.bayLeaf, [
          RecipeNode(
            id: 'merchant-15-bay-leaf-count',
            card: CatalogCards.count,
            value: 1,
            unit: NumericUnit.pieces,
          ),
        ]),
        _ingredient('merchant-15-salt', CatalogCards.salt, [
          RecipeNode(
            id: 'merchant-15-salt-mass',
            card: CatalogCards.mass,
            value: 11,
            unit: NumericUnit.grams,
          ),
        ]),
        _ingredient('merchant-15-water', CatalogCards.water, [
          RecipeNode(
            id: 'merchant-15-water-volume',
            card: CatalogCards.volume,
            value: 650,
            unit: NumericUnit.milliliters,
          ),
        ]),
      ]),
      _node('merchant-16', CatalogCards.stir, [
        _ingredient('merchant-16-buckwheat', CatalogCards.buckwheat),
      ]),
      _node('merchant-17', CatalogCards.close, [
        RecipeNode(
          id: 'merchant-17-lid',
          card: CatalogCards.lid,
          caseFromParent: GrammarCase.accusative,
        ),
      ]),
      _multicookerStep('merchant-18', 'Тушение', 7),
      _node('merchant-19', CatalogCards.leave, [
        _ingredient('merchant-19-buckwheat', CatalogCards.buckwheat),
        RecipeNode(
          id: 'merchant-19-time',
          card: CatalogCards.time,
          value: 10,
          unit: NumericUnit.minutes,
        ),
      ]),
      _node('merchant-20', CatalogCards.open, [
        RecipeNode(
          id: 'merchant-20-lid',
          card: CatalogCards.lid,
          caseFromParent: GrammarCase.accusative,
        ),
      ]),
      _node('merchant-21', CatalogCards.add, [
        _ingredient('merchant-21-garlic', CatalogCards.garlic, [
          RecipeNode(
            id: 'merchant-21-garlic-mass',
            card: CatalogCards.mass,
            value: 10,
            unit: NumericUnit.grams,
          ),
        ]),
        _ingredient('merchant-21-butter', CatalogCards.butter, [
          RecipeNode(
            id: 'merchant-21-butter-mass',
            card: CatalogCards.mass,
            value: 20,
            unit: NumericUnit.grams,
          ),
        ]),
      ]),
      _node('merchant-22', CatalogCards.stir, [
        _ingredient('merchant-22-buckwheat', CatalogCards.buckwheat),
      ]),
      _node('merchant-23', CatalogCards.leave, [
        _ingredient('merchant-23-buckwheat', CatalogCards.buckwheat),
        RecipeNode(
          id: 'merchant-23-time',
          card: CatalogCards.time,
          value: 10,
          unit: NumericUnit.minutes,
        ),
      ]),
    ],
  ),
  CatalogRecipe(
    id: 'apple-plum-jam',
    title: 'Яблочно-сливовый джем',
    detailedSteps: [
      'Включить мультиварку Moulinex CE5A0FF2.',
      'Вымыть 900 г яблок и 480 г слив без косточек; у яблок удалить сердцевины и нарезать фрукты.',
      'Смешать яблоки, сливы и 400 г сахара прямо в чаше.',
      'Выбрать программу «Джем/Десерт» и готовить без давления 90 минут, перемешивая 1–2 раза в последние 10 минут.',
      'Если нужны более мелкие кусочки, после выключения слегка размять размягчённые яблоки лопаткой или толкушкой; не нужно обязательно превращать массу в пюре.',
      'Остудить джем до комнатной температуры и разложить в ёмкости, оставив свободное место для заморозки.',
    ],
    buildSteps: () => [
      _node('jam-1', CatalogCards.rinse, [
        _ingredient('jam-1-apples', CatalogCards.apples),
        _ingredient('jam-1-plums', CatalogCards.plums),
      ]),
      _node('jam-2', CatalogCards.cut, [
        _ingredient('jam-2-apples', CatalogCards.apples, [
          RecipeNode(
            id: 'jam-2-apples-mass',
            card: CatalogCards.mass,
            value: 900,
            unit: NumericUnit.grams,
          ),
        ]),
        _ingredient('jam-2-plums', CatalogCards.plums, [
          RecipeNode(
            id: 'jam-2-plums-mass',
            card: CatalogCards.mass,
            value: 480,
            unit: NumericUnit.grams,
          ),
        ]),
      ]),
      _node('jam-3', CatalogCards.mix, [
        _ingredient('jam-3-apples', CatalogCards.apples),
        _ingredient('jam-3-plums', CatalogCards.plums),
        _ingredient('jam-3-sugar', CatalogCards.sugar, [
          RecipeNode(
            id: 'jam-3-sugar-mass',
            card: CatalogCards.mass,
            value: 400,
            unit: NumericUnit.grams,
          ),
        ]),
      ]),
      _multicookerStep('jam-4', 'Джем/Десерт'),
      _node('jam-5', CatalogCards.boil, [
        _ingredient('jam-5-apples', CatalogCards.apples),
        _ingredient('jam-5-plums', CatalogCards.plums),
        RecipeNode(
          id: 'jam-5-time',
          card: CatalogCards.time,
          value: 90,
          unit: NumericUnit.minutes,
        ),
      ]),
      _node('jam-6', CatalogCards.stir, [
        _ingredient('jam-6-apples', CatalogCards.apples),
        _ingredient('jam-6-plums', CatalogCards.plums),
      ]),
      _node('jam-7', CatalogCards.blend, [
        _ingredient('jam-7-apples', CatalogCards.apples),
        _ingredient('jam-7-plums', CatalogCards.plums),
      ]),
      _node('jam-8', CatalogCards.cool, [
        _ingredient('jam-8-apples', CatalogCards.apples),
        _ingredient('jam-8-plums', CatalogCards.plums),
      ]),
    ],
  ),
  CatalogRecipe(
    id: 'zucchini-sour-cream',
    title: 'Кабачки, тушённые в сметане',
    buildSteps: () => [
      _node('zuc-1', CatalogCards.cut, [
        _ingredient('zuc-1-c', CatalogCards.zucchini, [
          RecipeNode(
            id: 'zuc-1-mass',
            card: CatalogCards.mass,
            value: 800,
            unit: NumericUnit.grams,
          ),
        ]),
      ]),
      _node('zuc-2', CatalogCards.cut, [
        _ingredient('zuc-2-onion', CatalogCards.onion, [
          RecipeNode(
            id: 'zuc-2-mass',
            card: CatalogCards.mass,
            value: 120,
            unit: NumericUnit.grams,
          ),
        ]),
      ]),
      _node('zuc-3', CatalogCards.cut, [
        _ingredient('zuc-3-garlic', CatalogCards.garlic, [
          RecipeNode(
            id: 'zuc-3-mass',
            card: CatalogCards.mass,
            value: 10,
            unit: NumericUnit.grams,
          ),
        ]),
      ]),
      _node('zuc-4', CatalogCards.cut, [
        _ingredient('zuc-4-dill', CatalogCards.dill, [
          RecipeNode(
            id: 'zuc-4-mass',
            card: CatalogCards.mass,
            value: 15,
            unit: NumericUnit.grams,
          ),
        ]),
      ]),
      _node('zuc-5', CatalogCards.mix, [
        _ingredient('zuc-5-s', CatalogCards.sourCream, [
          RecipeNode(
            id: 'zuc-5-mass',
            card: CatalogCards.mass,
            value: 200,
            unit: NumericUnit.grams,
          ),
        ]),
        _ingredient('zuc-5-flour', CatalogCards.flour, [
          RecipeNode(
            id: 'zuc-5-flour-mass',
            card: CatalogCards.mass,
            value: 10,
            unit: NumericUnit.grams,
          ),
        ]),
      ]),
      _multicookerStep('zuc-6', 'Жарка'),
      _node('zuc-7', CatalogCards.add, [
        _ingredient('zuc-7-oil', CatalogCards.vegetableOil, [
          RecipeNode(
            id: 'zuc-7-oil-volume',
            card: CatalogCards.volume,
            value: 20,
            unit: NumericUnit.milliliters,
          ),
        ]),
      ]),
      _node('zuc-8', CatalogCards.saute, [
        _ingredient('zuc-8-onion', CatalogCards.onion),
        RecipeNode(
          id: 'zuc-8-time',
          card: CatalogCards.time,
          value: 4,
          upperValue: 5,
          unit: NumericUnit.minutes,
        ),
      ]),
      _node('zuc-9', CatalogCards.add, [
        _ingredient('zuc-9-zucchini', CatalogCards.zucchini),
        _ingredient('zuc-9-salt', CatalogCards.salt, [
          RecipeNode(
            id: 'zuc-9-salt-mass',
            card: CatalogCards.mass,
            value: 3,
            unit: NumericUnit.grams,
          ),
        ]),
      ]),
      _node('zuc-10', CatalogCards.fry, [
        _ingredient('zuc-10-zucchini', CatalogCards.zucchini),
        RecipeNode(
          id: 'zuc-10-time',
          card: CatalogCards.time,
          value: 10,
          upperValue: 12,
          unit: NumericUnit.minutes,
        ),
      ]),
      _node('zuc-11', CatalogCards.add, [
        _ingredient('zuc-11-water', CatalogCards.water, [
          RecipeNode(
            id: 'zuc-11-water-volume',
            card: CatalogCards.volume,
            value: 30,
            unit: NumericUnit.milliliters,
          ),
        ]),
      ]),
      _node('zuc-12', CatalogCards.turnOff, [
        _multicookerProgram('zuc-12-mode', 'Жарка'),
      ]),
      _node('zuc-13', CatalogCards.add, [
        _ingredient('zuc-13-sour-cream', CatalogCards.sourCream),
        _ingredient('zuc-13-flour', CatalogCards.flour),
        _ingredient('zuc-13-salt', CatalogCards.salt, [
          RecipeNode(
            id: 'zuc-13-salt-mass',
            card: CatalogCards.mass,
            value: 4,
            unit: NumericUnit.grams,
          ),
        ]),
        _ingredient('zuc-13-pepper', CatalogCards.blackPepper),
      ]),
      _node('zuc-14', CatalogCards.fry, [
        _ingredient('zuc-14-zucchini', CatalogCards.zucchini),
        RecipeNode(
          id: 'zuc-14-time',
          card: CatalogCards.time,
          value: 5,
          upperValue: 8,
          unit: NumericUnit.minutes,
        ),
      ]),
      _node('zuc-15', CatalogCards.turnOff, [
        _multicookerProgram('zuc-15-mode', 'Жарка'),
      ]),
      _node('zuc-16', CatalogCards.add, [
        _ingredient('zuc-16-garlic', CatalogCards.garlic),
        _ingredient('zuc-16-dill', CatalogCards.dill),
      ]),
      _node('zuc-17', CatalogCards.leave, [
        _ingredient('zuc-17-zucchini', CatalogCards.zucchini),
        RecipeNode(
          id: 'zuc-17-time',
          card: CatalogCards.time,
          value: 2,
          upperValue: 3,
          unit: NumericUnit.minutes,
        ),
      ]),
    ],
  ),
  CatalogRecipe(
    id: 'potato-baba-meat',
    title: 'Картофельная баба с мясом',
    detailedSteps: [
      'Включить мультиварку Moulinex CE5A0FF2.',
      'Нарезать 850 г филе цыплёнка-бройлера кубиками 1–1,5 см и мелко нарезать 200 г лука.',
      'На «Жарке» обжарить лук 3–4 минуты, добавить курицу и готовить ещё 5–7 минут, пока кусочки не побелеют снаружи. Полностью зажаривать мясо не нужно.',
      'Переложить курицу с луком и весь выделившийся сок в миску.',
      'Натереть 900 г очищенного картофеля. Если на дне много свободной жидкости, слить только лишнюю воду, не отжимая массу досуха.',
      'Смешать картофель с 2 яйцами С2, 80 г сметаны, 30–35 г муки, солью и перцем; затем вмешать курицу с луком и соком.',
      'Смазать чашу маслом, выложить массу и разровнять. Выпекать 60 минут; если центр всё ещё слишком влажный, добавить 10 минут.',
      'Оставить блюдо под закрытой крышкой 15 минут, затем с открытой крышкой ещё 10–15 минут. Полностью остывшую бабу можно нарезать и заморозить.',
    ],
    buildSteps: () => [
      _node('baba-1', CatalogCards.cut, [
        _ingredient('baba-1-chicken', CatalogCards.chickenFillet, [
          RecipeNode(
            id: 'baba-1-chicken-mass',
            card: CatalogCards.mass,
            value: 850,
            unit: NumericUnit.grams,
          ),
        ]),
      ]),
      _node('baba-2', CatalogCards.cut, [
        _ingredient('baba-2-onion', CatalogCards.onion, [
          RecipeNode(
            id: 'baba-2-onion-mass',
            card: CatalogCards.mass,
            value: 200,
            unit: NumericUnit.grams,
          ),
        ]),
      ]),
      _multicookerStep('baba-3', 'Жарка'),
      _node('baba-4', CatalogCards.saute, [
        _ingredient('baba-4-onion', CatalogCards.onion),
        RecipeNode(
          id: 'baba-4-time',
          card: CatalogCards.time,
          value: 3,
          upperValue: 4,
          unit: NumericUnit.minutes,
        ),
      ]),
      _node('baba-5', CatalogCards.fry, [
        _ingredient('baba-5-chicken', CatalogCards.chickenFillet),
        RecipeNode(
          id: 'baba-5-time',
          card: CatalogCards.time,
          value: 5,
          upperValue: 7,
          unit: NumericUnit.minutes,
        ),
      ]),
      _node('baba-6', CatalogCards.transfer, [
        _ingredient('baba-6-chicken', CatalogCards.chickenFillet),
        _ingredient('baba-6-onion', CatalogCards.onion),
      ]),
      _node('baba-7', CatalogCards.grate, [
        _ingredient('baba-7-potato', CatalogCards.potato, [
          RecipeNode(
            id: 'baba-7-potato-mass',
            card: CatalogCards.mass,
            value: 900,
            unit: NumericUnit.grams,
          ),
        ]),
      ]),
      _node('baba-8', CatalogCards.mix, [
        _ingredient('baba-8-potato', CatalogCards.potato),
        _ingredient('baba-8-eggs', CatalogCards.eggs, [
          RecipeNode(
            id: 'baba-8-eggs-count',
            card: CatalogCards.count,
            value: 2,
            unit: NumericUnit.pieces,
          ),
        ]),
        _ingredient('baba-8-sour-cream', CatalogCards.sourCream, [
          RecipeNode(
            id: 'baba-8-sour-cream-mass',
            card: CatalogCards.mass,
            value: 80,
            unit: NumericUnit.grams,
          ),
        ]),
        _ingredient('baba-8-flour', CatalogCards.flour, [
          RecipeNode(
            id: 'baba-8-flour-mass',
            card: CatalogCards.mass,
            value: 30,
            unit: NumericUnit.grams,
          ),
        ]),
        _ingredient('baba-8-salt', CatalogCards.salt),
        _ingredient('baba-8-pepper', CatalogCards.blackPepper),
      ]),
      _node('baba-9', CatalogCards.add, [
        _ingredient('baba-9-chicken', CatalogCards.chickenFillet),
        _ingredient('baba-9-onion', CatalogCards.onion),
      ]),
      _node('baba-10', CatalogCards.grease, [
        _ingredient('baba-10-oil', CatalogCards.vegetableOil),
      ]),
      _multicookerStep('baba-11', 'Выпечка', 60),
      _node('baba-12', CatalogCards.leave, [
        _ingredient('baba-12-baba', CatalogCards.potato),
        RecipeNode(
          id: 'baba-12-time',
          card: CatalogCards.time,
          value: 15,
          unit: NumericUnit.minutes,
        ),
      ]),
      _node('baba-13', CatalogCards.open, [
        RecipeNode(
          id: 'baba-13-lid',
          card: CatalogCards.lid,
          caseFromParent: GrammarCase.accusative,
        ),
      ]),
      _node('baba-14', CatalogCards.leave, [
        _ingredient('baba-14-baba', CatalogCards.potato),
        RecipeNode(
          id: 'baba-14-time',
          card: CatalogCards.time,
          value: 10,
          upperValue: 15,
          unit: NumericUnit.minutes,
        ),
      ]),
    ],
  ),
  CatalogRecipe(
    id: 'meat-egg-casserole',
    title: 'Яичная запеканка с мясом',
    detailedSteps: [
      'Включить мультиварку Moulinex CE5A0FF2.',
      'Нарезать 1 500 г свинины кубиками 1,5–2 см, 200 г лука — мелкими кубиками; натереть 150 г твёрдого сыра.',
      'На «Жарке» обжарить свинину в 3–4 захода по 4–5 минут, затем обжарить лук 4–5 минут. Вернуть мясо, добавить 8 г соли, чёрный перец и 1 ч. л. сладкой паприки.',
      'Влить 250 мл воды, готовить на «Тушении» под давлением 25 минут, оставить давление снижаться 10 минут, затем слить жидкость и остудить мясо.',
      'Запеканка готовится двумя одинаковыми партиями: на каждую смешать 12 яиц, 150 г сметаны, 15 г кукурузного крахмала и 5 г соли; добавить 75 г сыра, 750 г мяса и 100 г лука.',
      'Смазать чашу растительным маслом. Выпекать каждую партию 55 минут, затем оставить в чаше на 15–20 минут перед извлечением.',
    ],
    buildSteps: () => [
      _node('egg-1', CatalogCards.cut, [
        _ingredient('egg-1-meat', CatalogCards.pork, [
          RecipeNode(
            id: 'egg-1-meat-mass',
            card: CatalogCards.mass,
            value: 1500,
            unit: NumericUnit.grams,
          ),
        ]),
      ]),
      _node('egg-2', CatalogCards.cut, [
        _ingredient('egg-2-onion', CatalogCards.onion, [
          RecipeNode(
            id: 'egg-2-onion-mass',
            card: CatalogCards.mass,
            value: 200,
            unit: NumericUnit.grams,
          ),
        ]),
      ]),
      _node('egg-3', CatalogCards.grate, [
        _ingredient('egg-3-cheese', CatalogCards.cheese, [
          RecipeNode(
            id: 'egg-3-cheese-mass',
            card: CatalogCards.mass,
            value: 150,
            unit: NumericUnit.grams,
          ),
        ]),
      ]),
      _multicookerStep('egg-4', 'Жарка'),
      _node('egg-5', CatalogCards.fry, [
        _ingredient('egg-5-meat', CatalogCards.pork),
        RecipeNode(
          id: 'egg-5-time',
          card: CatalogCards.time,
          value: 4,
          upperValue: 5,
          unit: NumericUnit.minutes,
        ),
      ]),
      _node('egg-6', CatalogCards.saute, [
        _ingredient('egg-6-onion', CatalogCards.onion),
        RecipeNode(
          id: 'egg-6-time',
          card: CatalogCards.time,
          value: 4,
          upperValue: 5,
          unit: NumericUnit.minutes,
        ),
      ]),
      _node('egg-7', CatalogCards.add, [
        _ingredient('egg-7-meat', CatalogCards.pork),
        _ingredient('egg-7-paprika', CatalogCards.sweetPaprika),
        _ingredient('egg-7-pepper', CatalogCards.blackPepper),
        _ingredient('egg-7-salt', CatalogCards.salt, [
          RecipeNode(
            id: 'egg-7-salt-mass',
            card: CatalogCards.mass,
            value: 8,
            unit: NumericUnit.grams,
          ),
        ]),
      ]),
      _node('egg-8', CatalogCards.add, [
        _ingredient('egg-8-water', CatalogCards.water, [
          RecipeNode(
            id: 'egg-8-water-volume',
            card: CatalogCards.volume,
            value: 250,
            unit: NumericUnit.milliliters,
          ),
        ]),
      ]),
      _multicookerStep('egg-9', 'Тушение', 25),
      _node('egg-10', CatalogCards.leave, [
        _ingredient('egg-10-meat', CatalogCards.pork),
        RecipeNode(
          id: 'egg-10-time',
          card: CatalogCards.time,
          value: 10,
          unit: NumericUnit.minutes,
        ),
      ]),
      _node('egg-11', CatalogCards.drain, [
        RecipeNode(
          id: 'egg-11-detail',
          card: CatalogCards.freeText,
          text: 'жидкость из чаши',
        ),
      ]),
      _node('egg-12', CatalogCards.cool, [
        _ingredient('egg-12-meat', CatalogCards.pork),
      ]),
      ..._eggCasseroleBatch('egg-first'),
      ..._eggCasseroleBatch('egg-second'),
    ],
  ),
  CatalogRecipe(
    id: 'milk-pancakes',
    title: 'Оладьи на молоке',
    detailedSteps: [
      'Включить мультиварку Moulinex CE5A0FF2; оладьи готовятся на программе «Жарка».',
      'Подогреть 900 г молока до 30–35 °C.',
      'Смешать 4 яйца С2, 65 г сахара и 7 г соли. Влить тёплое молоко и 30 мл растительного масла.',
      'Отдельно смешать 850 г муки и 25 г разрыхлителя; постепенно ввести сухую смесь в жидкую. При необходимости добавить ещё 50–100 г муки.',
      'Оставить густое тесто на 5–10 минут. Оно должно медленно сползать с ложки широкой лентой и не растекаться на поверхности.',
      'На «Жарке» налить масло тонким слоем; выкладывать тесто по 1 столовой ложке с горкой и жарить оладьи по 2–3 минуты с каждой стороны.',
    ],
    buildSteps: () => [
      _node('pan-1', CatalogCards.heat, [
        _ingredient('pan-1-milk', CatalogCards.milk, [
          RecipeNode(
            id: 'pan-1-milk-mass',
            card: CatalogCards.mass,
            value: 900,
            unit: NumericUnit.grams,
          ),
        ]),
      ]),
      _node('pan-2', CatalogCards.mix, [
        _ingredient('pan-2-eggs', CatalogCards.eggs, [
          RecipeNode(
            id: 'pan-2-eggs-count',
            card: CatalogCards.count,
            value: 4,
            unit: NumericUnit.pieces,
          ),
        ]),
        _ingredient('pan-2-sugar', CatalogCards.sugar, [
          RecipeNode(
            id: 'pan-2-sugar-mass',
            card: CatalogCards.mass,
            value: 65,
            unit: NumericUnit.grams,
          ),
        ]),
        _ingredient('pan-2-salt', CatalogCards.salt, [
          RecipeNode(
            id: 'pan-2-salt-mass',
            card: CatalogCards.mass,
            value: 7,
            unit: NumericUnit.grams,
          ),
        ]),
      ]),
      _node('pan-3', CatalogCards.pour, [
        _ingredient('pan-3-milk', CatalogCards.milk),
        _ingredient('pan-3-oil', CatalogCards.vegetableOil, [
          RecipeNode(
            id: 'pan-3-oil-volume',
            card: CatalogCards.volume,
            value: 30,
            unit: NumericUnit.milliliters,
          ),
        ]),
      ]),
      _node('pan-4', CatalogCards.mix, [
        _ingredient('pan-4-flour', CatalogCards.flour, [
          RecipeNode(
            id: 'pan-4-flour-mass',
            card: CatalogCards.mass,
            value: 850,
            unit: NumericUnit.grams,
          ),
        ]),
        _ingredient('pan-4-powder', CatalogCards.bakingPowder, [
          RecipeNode(
            id: 'pan-4-powder-mass',
            card: CatalogCards.mass,
            value: 25,
            unit: NumericUnit.grams,
          ),
        ]),
      ]),
      _node('pan-5', CatalogCards.leave, [
        _ingredient('pan-5-batter', CatalogCards.batter),
        RecipeNode(
          id: 'pan-5-time',
          card: CatalogCards.time,
          value: 5,
          upperValue: 10,
          unit: NumericUnit.minutes,
        ),
      ]),
      _multicookerStep('pan-6', 'Жарка'),
      _node('pan-7', CatalogCards.add, [
        _ingredient('pan-7-oil', CatalogCards.vegetableOil, [
          RecipeNode(
            id: 'pan-7-oil-volume',
            card: CatalogCards.volume,
            value: 50,
            unit: NumericUnit.milliliters,
          ),
        ]),
      ]),
      _node('pan-8', CatalogCards.fry, [
        _ingredient('pan-8-batter', CatalogCards.batter),
        RecipeNode(
          id: 'pan-8-time',
          card: CatalogCards.time,
          value: 2,
          upperValue: 3,
          unit: NumericUnit.minutes,
        ),
      ]),
    ],
  ),
  CatalogRecipe(
    id: 'rassolnik-chicken-fillet',
    title: 'Рассольник с куриным филе и перловкой',
    detailedSteps: [
      'Промыть 100 г перловой крупы, залить 600 мл воды и готовить на «Тушении» под давлением 20 минут; дать давлению снизиться 10 минут.',
      'Обжарить на 20 мл масла 150 г лука 3–4 минуты, добавить 120 г моркови и готовить ещё 3 минуты.',
      'Добавить 20 г томатной пасты и обжаривать 1–2 минуты.',
      'Добавить 900 г куриного филе, 400 г картофеля, перловку, 2 лавровых листа, перец и 1,2 л воды; готовить под давлением 3–4 минуты.',
      'Добавить 300 г солёных огурцов и 500 мл воды; готовить при открытой крышке 8–10 минут.',
      'Добавить 70 мл огуречного рассола, чеснок, соль и укроп; прогреть 2–3 минуты и оставить на 15–20 минут с выключенным нагревом.',
    ],
    buildSteps: () => [
      _node('ras-1', CatalogCards.rinse, [
        _ingredient('ras-1-barley', CatalogCards.pearlBarley, [
          RecipeNode(
            id: 'ras-1-barley-mass',
            card: CatalogCards.mass,
            value: 100,
            unit: NumericUnit.grams,
          ),
        ]),
      ]),
      _node('ras-2', CatalogCards.add, [
        _ingredient('ras-2-barley', CatalogCards.pearlBarley),
        _ingredient('ras-2-water', CatalogCards.water, [
          RecipeNode(
            id: 'ras-2-water-volume',
            card: CatalogCards.volume,
            value: 600,
            unit: NumericUnit.milliliters,
          ),
        ]),
      ]),
      _multicookerStep('ras-3', 'Тушение'),
      _node('ras-4', CatalogCards.stew, [
        _ingredient('ras-4-barley', CatalogCards.pearlBarley),
        RecipeNode(
          id: 'ras-4-time',
          card: CatalogCards.time,
          value: 20,
          unit: NumericUnit.minutes,
        ),
      ]),
      _node('ras-5', CatalogCards.leave, [
        _ingredient('ras-5-barley', CatalogCards.pearlBarley),
        RecipeNode(
          id: 'ras-5-time',
          card: CatalogCards.time,
          value: 10,
          unit: NumericUnit.minutes,
        ),
      ]),
      _node('ras-6', CatalogCards.add, [
        _ingredient('ras-6-oil', CatalogCards.vegetableOil, [
          RecipeNode(
            id: 'ras-6-oil-volume',
            card: CatalogCards.volume,
            value: 20,
            unit: NumericUnit.milliliters,
          ),
        ]),
      ]),
      _node('ras-7', CatalogCards.saute, [
        _ingredient('ras-7-onion', CatalogCards.onion, [
          RecipeNode(
            id: 'ras-7-onion-mass',
            card: CatalogCards.mass,
            value: 150,
            unit: NumericUnit.grams,
          ),
        ]),
        RecipeNode(
          id: 'ras-7-time',
          card: CatalogCards.time,
          value: 3,
          upperValue: 4,
          unit: NumericUnit.minutes,
        ),
      ]),
      _node('ras-8', CatalogCards.add, [
        _ingredient('ras-8-carrot', CatalogCards.carrot, [
          RecipeNode(
            id: 'ras-8-carrot-mass',
            card: CatalogCards.mass,
            value: 120,
            unit: NumericUnit.grams,
          ),
        ]),
      ]),
      _node('ras-9', CatalogCards.saute, [
        _ingredient('ras-9-carrot', CatalogCards.carrot),
        RecipeNode(
          id: 'ras-9-time',
          card: CatalogCards.time,
          value: 3,
          unit: NumericUnit.minutes,
        ),
      ]),
      _node('ras-10', CatalogCards.add, [
        _ingredient('ras-10-paste', CatalogCards.tomatoPaste, [
          RecipeNode(
            id: 'ras-10-paste-mass',
            card: CatalogCards.mass,
            value: 20,
            unit: NumericUnit.grams,
          ),
        ]),
      ]),
      _node('ras-11', CatalogCards.fry, [
        _ingredient('ras-11-paste', CatalogCards.tomatoPaste),
        RecipeNode(
          id: 'ras-11-time',
          card: CatalogCards.time,
          value: 1,
          upperValue: 2,
          unit: NumericUnit.minutes,
        ),
      ]),
      _node('ras-12', CatalogCards.add, [
        _ingredient('ras-12-chicken', CatalogCards.chickenFillet, [
          RecipeNode(
            id: 'ras-12-chicken-mass',
            card: CatalogCards.mass,
            value: 900,
            unit: NumericUnit.grams,
          ),
        ]),
        _ingredient('ras-12-potato', CatalogCards.potato, [
          RecipeNode(
            id: 'ras-12-potato-mass',
            card: CatalogCards.mass,
            value: 400,
            unit: NumericUnit.grams,
          ),
        ]),
        _ingredient('ras-12-barley', CatalogCards.pearlBarley),
        _ingredient('ras-12-bay', CatalogCards.bayLeaf),
        _ingredient('ras-12-pepper', CatalogCards.blackPepper),
        _ingredient('ras-12-water', CatalogCards.water, [
          RecipeNode(
            id: 'ras-12-water-volume',
            card: CatalogCards.volume,
            value: 1200,
            unit: NumericUnit.milliliters,
          ),
        ]),
      ]),
      _multicookerStep('ras-13', 'Тушение'),
      _node('ras-14', CatalogCards.stew, [
        _ingredient('ras-14-chicken', CatalogCards.chickenFillet),
        _ingredient('ras-14-potato', CatalogCards.potato),
        RecipeNode(
          id: 'ras-14-time',
          card: CatalogCards.time,
          value: 3,
          upperValue: 4,
          unit: NumericUnit.minutes,
        ),
      ]),
      _node('ras-15', CatalogCards.add, [
        _ingredient('ras-15-cucumbers', CatalogCards.pickledCucumbers, [
          RecipeNode(
            id: 'ras-15-cucumbers-mass',
            card: CatalogCards.mass,
            value: 300,
            unit: NumericUnit.grams,
          ),
        ]),
        _ingredient('ras-15-water', CatalogCards.water, [
          RecipeNode(
            id: 'ras-15-water-volume',
            card: CatalogCards.volume,
            value: 500,
            unit: NumericUnit.milliliters,
          ),
        ]),
      ]),
      _node('ras-16', CatalogCards.boil, [
        _ingredient('ras-16-cucumbers', CatalogCards.pickledCucumbers),
        RecipeNode(
          id: 'ras-16-time',
          card: CatalogCards.time,
          value: 8,
          upperValue: 10,
          unit: NumericUnit.minutes,
        ),
      ]),
      _node('ras-17', CatalogCards.add, [
        _ingredient('ras-17-brine', CatalogCards.cucumberBrine, [
          RecipeNode(
            id: 'ras-17-brine-volume',
            card: CatalogCards.volume,
            value: 70,
            unit: NumericUnit.milliliters,
          ),
        ]),
        _ingredient('ras-17-garlic', CatalogCards.garlic),
        _ingredient('ras-17-salt', CatalogCards.salt),
        _ingredient('ras-17-dill', CatalogCards.dill),
      ]),
      _node('ras-18', CatalogCards.heat, [
        _ingredient('ras-18-brine', CatalogCards.cucumberBrine),
        RecipeNode(
          id: 'ras-18-time',
          card: CatalogCards.time,
          value: 2,
          upperValue: 3,
          unit: NumericUnit.minutes,
        ),
      ]),
      _node('ras-19', CatalogCards.leave, [
        _ingredient('ras-19-soup', CatalogCards.chickenFillet),
        RecipeNode(
          id: 'ras-19-time',
          card: CatalogCards.time,
          value: 15,
          upperValue: 20,
          unit: NumericUnit.minutes,
        ),
      ]),
    ],
  ),
  CatalogRecipe(
    id: 'milk-bread-oven',
    title: 'Домашний пшеничный хлеб на молоке',
    detailedSteps: [
      'Подогреть 700 мл молока до 30–35 °C.',
      'Смешать молоко с 40 г сахара.',
      'Смешать 1 150 г муки, 11 г сухих быстродействующих дрожжей и 20 г соли; постепенно соединить с молоком.',
      'Добавить 60 г размягчённого сливочного масла и вымесить тесто 12–15 минут.',
      'Оставить тесто для первого подъёма на 60–90 минут, затем сформировать две буханки.',
      'Оставить заготовки на расстойку на 35–60 минут; разогреть духовку до 190 °C.',
      'Выпекать две крупные буханки при верхнем и нижнем нагреве 190 °C 40–50 минут.',
      'Остудить хлеб на решётке не менее 60 минут.',
    ],
    buildSteps: () => [
      _node('bread-1', CatalogCards.heat, [
        _ingredient('bread-1-milk', CatalogCards.milk, [
          RecipeNode(
            id: 'bread-1-milk-volume',
            card: CatalogCards.volume,
            value: 700,
            unit: NumericUnit.milliliters,
          ),
        ]),
        RecipeNode(
          id: 'bread-1-time',
          card: CatalogCards.time,
          value: 2,
          upperValue: 3,
          unit: NumericUnit.minutes,
        ),
      ]),
      _node('bread-2', CatalogCards.mix, [
        _ingredient('bread-2-milk', CatalogCards.milk),
        _ingredient('bread-2-sugar', CatalogCards.sugar, [
          RecipeNode(
            id: 'bread-2-sugar-mass',
            card: CatalogCards.mass,
            value: 40,
            unit: NumericUnit.grams,
          ),
        ]),
      ]),
      _node('bread-3', CatalogCards.mix, [
        _ingredient('bread-3-flour', CatalogCards.flour, [
          RecipeNode(
            id: 'bread-3-flour-mass',
            card: CatalogCards.mass,
            value: 1150,
            unit: NumericUnit.grams,
          ),
        ]),
        _ingredient('bread-3-yeast', CatalogCards.yeast, [
          RecipeNode(
            id: 'bread-3-yeast-mass',
            card: CatalogCards.mass,
            value: 11,
            unit: NumericUnit.grams,
          ),
        ]),
        _ingredient('bread-3-salt', CatalogCards.salt, [
          RecipeNode(
            id: 'bread-3-salt-mass',
            card: CatalogCards.mass,
            value: 20,
            unit: NumericUnit.grams,
          ),
        ]),
      ]),
      _node('bread-4', CatalogCards.add, [
        _ingredient('bread-4-butter', CatalogCards.butter, [
          RecipeNode(
            id: 'bread-4-butter-mass',
            card: CatalogCards.mass,
            value: 60,
            unit: NumericUnit.grams,
          ),
        ]),
      ]),
      _node('bread-5', CatalogCards.knead, [
        _ingredient('bread-5-dough', CatalogCards.batter),
        RecipeNode(
          id: 'bread-5-time',
          card: CatalogCards.time,
          value: 12,
          upperValue: 15,
          unit: NumericUnit.minutes,
        ),
      ]),
      _node('bread-6', CatalogCards.leave, [
        _ingredient('bread-6-dough', CatalogCards.batter),
        RecipeNode(
          id: 'bread-6-time',
          card: CatalogCards.time,
          value: 60,
          upperValue: 90,
          unit: NumericUnit.minutes,
        ),
      ]),
      _node('bread-7', CatalogCards.form, [
        _ingredient('bread-7-dough', CatalogCards.batter),
      ]),
      _node('bread-8', CatalogCards.leave, [
        _ingredient('bread-8-dough', CatalogCards.batter),
        RecipeNode(
          id: 'bread-8-time',
          card: CatalogCards.time,
          value: 35,
          upperValue: 60,
          unit: NumericUnit.minutes,
        ),
      ]),
      _node('bread-9', CatalogCards.preheat, [
        RecipeNode(
          id: 'bread-9-oven',
          card: CatalogCards.oven,
          caseFromParent: GrammarCase.accusative,
        ),
      ]),
      _node('bread-10', CatalogCards.select, [
        RecipeNode(
          id: 'bread-10-mode',
          card: CatalogCards.ovenTopBottomHeat,
          caseFromParent: GrammarCase.accusative,
        ),
        RecipeNode(
          id: 'bread-10-temperature',
          card: CatalogCards.temperature,
          value: 190,
          unit: NumericUnit.celsius,
        ),
      ]),
      _node('bread-11', CatalogCards.bake, [
        _ingredient('bread-11-bread', CatalogCards.bread),
        RecipeNode(
          id: 'bread-11-time',
          card: CatalogCards.time,
          value: 40,
          upperValue: 50,
          unit: NumericUnit.minutes,
        ),
      ]),
      _node('bread-12', CatalogCards.cool, [
        _ingredient('bread-12-bread', CatalogCards.bread),
        RecipeNode(
          id: 'bread-12-time',
          card: CatalogCards.time,
          value: 60,
          unit: NumericUnit.minutes,
        ),
      ]),
    ],
  ),
];
