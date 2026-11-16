import 'recipe_node.dart';

/// Пищевая ценность на 100 г съедобной части продукта.
///
/// Значения округлены до десятых по таблицам химического состава продуктов
/// Роспотребнадзора и USDA FoodData Central. Калории намеренно вычисляются из
/// Б/Ж/У (4/9/4), поэтому итог согласован с отображаемыми макронутриентами.
class NutritionProfile {
  const NutritionProfile(this.protein, this.fat, this.carbohydrates);

  final double protein;
  final double fat;
  final double carbohydrates;
}

class NutritionTotals {
  const NutritionTotals({
    required this.protein,
    required this.fat,
    required this.carbohydrates,
  });

  const NutritionTotals.zero() : protein = 0, fat = 0, carbohydrates = 0;

  final double protein;
  final double fat;
  final double carbohydrates;

  double get kilocalories => protein * 4 + fat * 9 + carbohydrates * 4;

  NutritionTotals operator +(NutritionTotals other) => NutritionTotals(
    protein: protein + other.protein,
    fat: fat + other.fat,
    carbohydrates: carbohydrates + other.carbohydrates,
  );

  NutritionTotals dividedBy(int divisor) => divisor <= 0
      ? this
      : NutritionTotals(
          protein: protein / divisor,
          fat: fat / divisor,
          carbohydrates: carbohydrates / divisor,
        );
}

/// Единый справочник КБЖУ для словарных модулей ингредиентов.
/// Все числа отнесены к 100 г; для воды, соли и специй, не дающих заметной
/// энергии в рецептурных количествах, также сохранены их фактические нули.
class NutritionCatalog {
  static const _profiles = <String, NutritionProfile>{
    'ingredient.apples': NutritionProfile(0.4, 0.4, 11.3),
    'ingredient.baking-powder': NutritionProfile(0, 0, 27.0),
    'ingredient.batter': NutritionProfile(6.0, 5.0, 35.0),
    'ingredient.bay-leaf': NutritionProfile(7.6, 8.4, 48.7),
    'ingredient.beans': NutritionProfile(21.0, 1.6, 47.0),
    'ingredient.beef': NutritionProfile(18.9, 12.4, 0),
    'ingredient.beet': NutritionProfile(1.6, 0.2, 9.6),
    'ingredient.bell-pepper': NutritionProfile(1.3, 0.1, 5.7),
    'ingredient.black-pepper': NutritionProfile(10.4, 3.3, 38.7),
    'ingredient.bones': NutritionProfile(17.0, 10.0, 0),
    'ingredient.bread': NutritionProfile(8.1, 1.0, 48.3),
    'ingredient.breadcrumbs': NutritionProfile(11.2, 1.4, 72.2),
    'ingredient.banana': NutritionProfile(1.1, 0.3, 22.8),
    'ingredient.buckwheat': NutritionProfile(12.6, 3.3, 57.1),
    'ingredient.butter': NutritionProfile(0.5, 82.5, 0.8),
    'ingredient.cabbage': NutritionProfile(1.8, 0.1, 4.7),
    'ingredient.carrot': NutritionProfile(1.3, 0.1, 6.9),
    'ingredient.celery': NutritionProfile(0.9, 0.1, 2.1),
    'ingredient.chanterelles': NutritionProfile(1.5, 1.1, 1.0),
    'ingredient.cheese': NutritionProfile(23.4, 30.0, 0.0),
    'ingredient.chicken-fillet': NutritionProfile(23.1, 1.2, 0),
    'ingredient.cinnamon': NutritionProfile(4.0, 1.2, 27.5),
    'ingredient.cloves': NutritionProfile(6.0, 20.1, 27.0),
    'ingredient.cocoa': NutritionProfile(24.2, 17.5, 27.9),
    'ingredient.chocolate': NutritionProfile(7.8, 42.6, 45.9),
    'ingredient.cod': NutritionProfile(17.9, 0.6, 0),
    'ingredient.condensed-milk': NutritionProfile(7.2, 8.5, 56.0),
    // Варёная сгущёнка отличается вкусом и текстурой, а для оценочного КБЖУ
    // использует тот же базовый состав, что и сгущённое молоко.
    'ingredient.boiled-condensed-milk': NutritionProfile(7.2, 8.5, 56.0),
    'ingredient.coriander': NutritionProfile(12.4, 17.8, 13.1),
    'ingredient.corn-starch': NutritionProfile(0.3, 0.1, 85.9),
    'ingredient.potato-starch': NutritionProfile(0.1, 0.0, 83.1),
    'ingredient.cottage-cheese': NutritionProfile(16.7, 9.0, 2.0),
    'ingredient.cranberries': NutritionProfile(0.5, 0.0, 3.7),
    'ingredient.cream': NutritionProfile(2.5, 20.0, 3.4),
    'ingredient.cucumber': NutritionProfile(0.8, 0.1, 2.8),
    'ingredient.cucumber-brine': NutritionProfile(0.0, 0.0, 1.0),
    'ingredient.cumin': NutritionProfile(19.8, 14.6, 11.9),
    'ingredient.dill': NutritionProfile(2.5, 0.5, 6.3),
    'ingredient.eggplant': NutritionProfile(1.2, 0.1, 4.5),
    'ingredient.eggs': NutritionProfile(12.7, 11.5, 0.7),
    'ingredient.egg-yolk': NutritionProfile(15.9, 31.9, 1.8),
    'ingredient.egg-white': NutritionProfile(10.9, 0.2, 0.7),
    'ingredient.flour': NutritionProfile(10.3, 1.1, 70.6),
    'ingredient.garlic': NutritionProfile(6.5, 0.5, 29.9),
    'ingredient.gelatin': NutritionProfile(87.2, 0.4, 0.7),
    'ingredient.green-onion': NutritionProfile(1.3, 0.0, 4.6),
    'ingredient.green-peas': NutritionProfile(5.0, 0.2, 8.3),
    'ingredient.ham': NutritionProfile(14.0, 24.0, 0),
    'ingredient.herring': NutritionProfile(17.7, 19.5, 0),
    'ingredient.honey': NutritionProfile(0.8, 0, 80.3),
    'ingredient.honey-mushrooms': NutritionProfile(2.2, 1.2, 0.5),
    'ingredient.horseradish': NutritionProfile(3.2, 0.4, 10.5),
    'ingredient.kefir': NutritionProfile(3.0, 2.5, 4.0),
    'ingredient.kvass': NutritionProfile(0.2, 0, 5.2),
    'ingredient.lard': NutritionProfile(1.4, 92.8, 0),
    'ingredient.lemon': NutritionProfile(0.9, 0.1, 3.0),
    'ingredient.mayonnaise': NutritionProfile(2.4, 67.0, 3.9),
    'ingredient.milk': NutritionProfile(3.0, 3.2, 4.7),
    'ingredient.millet': NutritionProfile(11.5, 3.3, 66.5),
    'ingredient.minced-meat': NutritionProfile(17.0, 20.0, 0),
    'ingredient.mushrooms': NutritionProfile(3.1, 0.3, 3.3),
    'ingredient.mustard': NutritionProfile(5.7, 6.4, 22.0),
    'ingredient.noodles': NutritionProfile(10.4, 1.1, 69.7),
    'ingredient.oats': NutritionProfile(12.3, 6.1, 59.5),
    'ingredient.olives': NutritionProfile(0.8, 10.7, 6.3),
    'ingredient.onion': NutritionProfile(1.4, 0.0, 10.4),
    'ingredient.parsley': NutritionProfile(3.7, 0.4, 7.6),
    'ingredient.pasta': NutritionProfile(10.4, 1.1, 69.7),
    'ingredient.pearl-barley': NutritionProfile(9.3, 1.1, 66.9),
    'ingredient.peas': NutritionProfile(20.5, 2.0, 49.5),
    'ingredient.perch': NutritionProfile(18.5, 0.9, 0),
    'ingredient.pickled-cucumbers': NutritionProfile(0.8, 0.1, 1.7),
    'ingredient.pike': NutritionProfile(18.4, 0.8, 0),
    'ingredient.pink-salmon': NutritionProfile(20.5, 6.5, 0),
    'ingredient.plums': NutritionProfile(0.8, 0.3, 9.6),
    'ingredient.pollock': NutritionProfile(15.9, 0.9, 0),
    'ingredient.porcini': NutritionProfile(3.7, 1.7, 1.1),
    'ingredient.pork': NutritionProfile(16.0, 21.6, 0),
    'ingredient.potato': NutritionProfile(2.0, 0.4, 16.3),
    'ingredient.processed-cheese': NutritionProfile(20.5, 25.0, 2.5),
    'ingredient.prunes': NutritionProfile(2.3, 0.7, 57.5),
    'ingredient.radish': NutritionProfile(1.2, 0.1, 3.4),
    'ingredient.radishes': NutritionProfile(1.2, 0.1, 3.4),
    'ingredient.raisins': NutritionProfile(2.9, 0.6, 65.8),
    'ingredient.raspberries': NutritionProfile(0.8, 0.5, 8.3),
    'ingredient.rice': NutritionProfile(7.0, 0.7, 74.0),
    'ingredient.rye-flour': NutritionProfile(6.9, 1.4, 66.3),
    'ingredient.salmon': NutritionProfile(20.8, 15.1, 0),
    'ingredient.salt': NutritionProfile(0, 0, 0),
    'ingredient.sauerkraut': NutritionProfile(1.8, 0.1, 4.4),
    'ingredient.semolina': NutritionProfile(10.3, 1.0, 67.4),
    'ingredient.sorrel': NutritionProfile(1.5, 0.3, 2.9),
    'ingredient.sour-cream': NutritionProfile(2.8, 20.0, 3.2),
    'ingredient.strawberries': NutritionProfile(0.8, 0.4, 7.5),
    'ingredient.sugar': NutritionProfile(0, 0, 99.8),
    'ingredient.sweet-paprika': NutritionProfile(14.1, 13.0, 54.0),
    'ingredient.tomato-paste': NutritionProfile(5.6, 0.0, 19.0),
    'ingredient.trout': NutritionProfile(19.2, 2.1, 0),
    'ingredient.turnip': NutritionProfile(1.5, 0.1, 6.2),
    'ingredient.vanilla': NutritionProfile(1.2, 0.1, 12.7),
    'ingredient.vegetable-oil': NutritionProfile(0, 99.9, 0),
    'ingredient.vinegar': NutritionProfile(0, 0, 5.0),
    'ingredient.walnuts': NutritionProfile(15.2, 65.2, 7.0),
    'ingredient.water': NutritionProfile(0, 0, 0),
    'ingredient.yeast': NutritionProfile(16.0, 3.0, 36.0),
    'ingredient.zucchini': NutritionProfile(0.6, 0.3, 4.6),
  };

  static NutritionProfile? forNode(RecipeNode node) {
    if (node.card.id != 'ingredient.minced-meat') {
      return _profiles[node.card.id];
    }
    return switch (node.text?.trim()) {
      'Куриный' => _profiles['ingredient.chicken-fillet'],
      'Говяжий' => _profiles['ingredient.beef'],
      'Свиной' => _profiles['ingredient.pork'],
      _ => _profiles['ingredient.minced-meat'],
    };
  }

  static NutritionTotals perServing(
    Iterable<RecipeNode> steps, {
    required int recipeMultiplier,
  }) {
    NutritionTotals collect(RecipeNode node) {
      var total = const NutritionTotals.zero();
      final profile = forNode(node);
      if (profile != null) {
        final grams = _gramsFor(node);
        if (grams > 0) {
          total += NutritionTotals(
            protein: profile.protein * grams / 100,
            fat: profile.fat * grams / 100,
            carbohydrates: profile.carbohydrates * grams / 100,
          );
        }
      }
      for (final child in node.children) {
        total += collect(child);
      }
      return total;
    }

    var total = const NutritionTotals.zero();
    for (final step in steps) {
      total += collect(step);
    }
    return total.dividedBy(recipeMultiplier);
  }

  static double _gramsFor(RecipeNode ingredient) {
    final quantity = ingredient.children.cast<RecipeNode?>().firstWhere(
      (node) =>
          node?.card.id == 'quantity.mass' ||
          node?.card.id == 'quantity.volume' ||
          node?.card.id == 'quantity.count',
      orElse: () => null,
    );
    if (quantity == null || quantity.value == null) return 0;
    if (quantity.unit == NumericUnit.grams) return quantity.value!.toDouble();
    if (quantity.unit == NumericUnit.milliliters) {
      return quantity.value! * _densityFor(ingredient.card.id);
    }
    if (quantity.unit == NumericUnit.pieces &&
        (ingredient.card.id == 'ingredient.eggs' ||
            ingredient.card.id == 'ingredient.egg-yolk' ||
            ingredient.card.id == 'ingredient.egg-white')) {
      return quantity.value! * _eggWeight(ingredient.card.id, ingredient.text);
    }
    return 0;
  }

  static double _densityFor(String ingredientId) => switch (ingredientId) {
    'ingredient.milk' || 'ingredient.kefir' || 'ingredient.cream' => 1.03,
    'ingredient.sour-cream' => 1.05,
    'ingredient.vegetable-oil' => 0.92,
    'ingredient.honey' => 1.42,
    _ => 1.0,
  };

  static double _eggWeight(String ingredientId, String? category) {
    if (ingredientId == 'ingredient.egg-yolk') return 18;
    if (ingredientId == 'ingredient.egg-white') return 35;
    return switch (category?.trim()) {
      'СВ' => 75,
      'С0' => 65,
      'С1' => 55,
      _ => 45,
    };
  }
}
