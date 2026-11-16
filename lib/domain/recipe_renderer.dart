import 'recipe_node.dart';

/// Видимый фрагмент строки рецепта. [nodeId] связывает текст конкретного
/// модуля с его карточкой в редакторе при координатном переходе.
class RecipeRenderPart {
  const RecipeRenderPart(this.text, {this.nodeId});
  final String text;
  final String? nodeId;
}

/// Утварь, которая в шаге с ингредиентом описывает место действия, а не
/// второй прямой объект. Например, «Подогреть тарелку» остаётся корректным,
/// но «Подогреть курицу в тарелке» требует предложного падежа и предлога.
const _locationUtensilIds = <String>{
  'utensil.plate',
  'utensil.pot',
  'utensil.frying-pan',
  'utensil.baking-sheet',
  'utensil.moulinex-ce5a0ff2',
  'utensil.oven',
};

bool _actionHasIngredientObject(RecipeNode action) =>
    action.children.any((child) => child.card.kind == CardKind.ingredient);

/// Прибор получает форму инструмента только тогда, когда ингредиент уже
/// является главным объектом действия. Без ингредиента остаётся прямой
/// объект: «Взбить венчик», а не «Взбить венчиком».
bool _usesToolWithIngredient(RecipeNode parent, RecipeNode child) =>
    parent.card.kind == CardKind.action &&
    _actionHasIngredientObject(parent) &&
    {
      'utensil.grater',
      'utensil.sieve',
      'utensil.colander',
      'utensil.meat-grinder',
      'utensil.whisk',
      'utensil.rolling-pin',
    }.contains(child.card.id);

/// У операций переливания и перекладывания утварь — направление перемещения:
/// «влить в кастрюлю», а не место происходящего действия «в кастрюле».
/// Их собственные правила имеют приоритет над общим правилом места.
bool _hasExplicitUtensilRelation(RecipeNode parent, RecipeNode child) {
  final parentId = parent.card.id;
  final childId = child.card.id;
  return (parentId == 'action.pour' || parentId == 'action.transfer') &&
          {
            'utensil.baking-sheet',
            'utensil.frying-pan',
            'utensil.pot',
            'utensil.moulinex-ce5a0ff2',
          }.contains(childId) ||
      (parentId == 'action.plate' && childId == 'utensil.plate') ||
      (parentId == 'action.drain' && childId == 'utensil.colander') ||
      (parentId == 'action.strain' && childId == 'utensil.sieve') ||
      (parentId == 'action.grate' && childId == 'utensil.grater');
}

bool _usesUtensilAsLocation(RecipeNode parent, RecipeNode child) =>
    parent.card.kind == CardKind.action &&
    _locationUtensilIds.contains(child.card.id) &&
    _actionHasIngredientObject(parent) &&
    !_hasExplicitUtensilRelation(parent, child);

/// Падеж дочернего модуля в конкретной связи. Не полагается только на
/// сохранённый код узла: старые деревья могли быть записаны до появления
/// предлогов у утвари.
GrammarCase grammarCaseForChild(RecipeNode parent, RecipeNode child) {
  if (parent.card.id == 'ingredient.canned') return GrammarCase.nominative;
  if (parent.card.id == 'action.season') return GrammarCase.instrumental;
  if (parent.card.id == 'action.grate' &&
      child.card.id == 'utensil.grater' &&
      _usesToolWithIngredient(parent, child)) {
    return GrammarCase.prepositional;
  }
  if ((parent.card.id == 'action.whisk' || parent.card.id == 'action.stir') &&
      child.card.id == 'utensil.whisk' &&
      _usesToolWithIngredient(parent, child)) {
    return GrammarCase.instrumental;
  }
  if (parent.card.id == 'action.roll-out' &&
      child.card.id == 'utensil.rolling-pin' &&
      _usesToolWithIngredient(parent, child)) {
    return GrammarCase.instrumental;
  }
  if (_usesUtensilAsLocation(parent, child)) {
    return GrammarCase.prepositional;
  }
  return parent.card.kind == CardKind.action
      ? GrammarCase.accusative
      : child.caseFromParent;
}

/// Предлог перед дочерней карточкой. Пустая строка означает обычное
/// соединение модулей пробелом или запятой.
String? joinTextForChild(RecipeNode parent, RecipeNode child) {
  final parentId = parent.card.id;
  final childId = child.card.id;
  if (parentId == 'ingredient.canned' &&
      child.card.kind == CardKind.ingredient) {
    return ' — ';
  }
  if (parentId == 'action.pour') {
    return switch (childId) {
      'utensil.baking-sheet' => ' на ',
      'utensil.pot' ||
      'utensil.moulinex-ce5a0ff2' ||
      'utensil.frying-pan' => ' в ',
      _ => null,
    };
  }
  if (parentId == 'action.transfer') {
    return switch (childId) {
      'utensil.baking-sheet' || 'utensil.frying-pan' => ' на ',
      'utensil.pot' || 'utensil.moulinex-ce5a0ff2' => ' в ',
      _ => null,
    };
  }
  if (parentId == 'action.plate' && childId == 'utensil.plate') {
    return ' на ';
  }
  if (parentId == 'action.drain' &&
      childId == 'utensil.colander' &&
      _usesToolWithIngredient(parent, child)) {
    return ' через ';
  }
  if (parentId == 'action.strain' &&
      childId == 'utensil.sieve' &&
      _usesToolWithIngredient(parent, child)) {
    return ' через ';
  }
  if (parentId == 'action.grate' &&
      childId == 'utensil.grater' &&
      _usesToolWithIngredient(parent, child)) {
    return ' на ';
  }
  if (parentId == 'action.blend' &&
      childId == 'utensil.meat-grinder' &&
      _usesToolWithIngredient(parent, child)) {
    return ' через ';
  }
  if (_usesUtensilAsLocation(parent, child)) return ' в ';
  return null;
}

/// Преобразует редактируемое дерево в видимые фрагменты предложения.
class RecipeRenderer {
  const RecipeRenderer();

  /// Возвращает видимые подписи всех модулей и разделители между ними.
  /// Не сливает их в одну строку, чтобы интерфейс мог измерить и анимировать
  /// каждый узел дерева отдельно. [servings] и [recipeMultiplier] масштабируют
  /// пищевые количества, не меняя исходные значения узлов в БД.
  List<RecipeRenderPart> renderParts(
    RecipeNode node, {
    int servings = 1,
    int recipeMultiplier = 1,
    GrammarCase? caseOverride,
  }) {
    final isParameter =
        node.card.id == 'quantity.mass' ||
        node.card.id == 'quantity.volume' ||
        node.card.id == 'quantity.time' ||
        node.card.id == 'quantity.temperature' ||
        node.card.id == 'quantity.count' ||
        node.card.id == 'quantity.fat-content';
    if (node.card.id == 'text.free') {
      return [RecipeRenderPart(node.text?.trim() ?? '', nodeId: node.id)];
    }
    if (node.card.id == 'characteristic.shape') {
      return [
        RecipeRenderPart(node.text?.trim() ?? 'кубиками', nodeId: node.id),
      ];
    }
    if (node.card.id == 'quantity.spoon') {
      final value = node.text?.trim();
      return [
        RecipeRenderPart(
          _formatSpoon(
            value?.isNotEmpty == true ? value! : '1 ч. л.',
            servings: servings,
            recipeMultiplier: recipeMultiplier,
          ),
          nodeId: node.id,
        ),
      ];
    }
    if (node.card.id == 'ingredient.minced-meat') {
      final specification = node.text?.trim() ?? '';
      final label = node.card.formFor(caseOverride ?? node.caseFromParent);
      return [
        RecipeRenderPart(
          specification.isEmpty ? label : '$label $specification',
          nodeId: node.id,
        ),
      ];
    }
    if (node.card.id == 'utensil.multicooker-program') {
      final program = node.text?.trim() ?? '';
      final label = node.card.formFor(caseOverride ?? node.caseFromParent);
      return [
        RecipeRenderPart(
          program.isEmpty ? label : '$label «$program»',
          nodeId: node.id,
        ),
      ];
    }

    final eggCategory = node.card.id == 'ingredient.eggs'
        ? node.text?.trim() ?? ''
        : '';
    final ownText = StringBuffer(
      isParameter
          ? ''
          : '${node.card.formFor(caseOverride ?? node.caseFromParent)}${eggCategory.isEmpty ? '' : ' $eggCategory'}',
    );
    if (node.value != null && node.unit != null) {
      final suffix = switch (node.unit!) {
        NumericUnit.grams => ' г',
        NumericUnit.milliliters => ' мл',
        NumericUnit.minutes => ' минут',
        NumericUnit.celsius => ' °C',
        NumericUnit.pieces => ' шт.',
        NumericUnit.percent => '%',
      };
      final lower = _formatValue(
        node.value!,
        node.unit!,
        servings: servings,
        recipeMultiplier: recipeMultiplier,
      );
      final upper = node.upperValue == null
          ? ''
          : '–${_formatValue(node.upperValue!, node.unit!, servings: servings, recipeMultiplier: recipeMultiplier)}';
      ownText.write('${isParameter ? '' : ' '}$lower$upper$suffix');
    }

    final parts = <RecipeRenderPart>[
      RecipeRenderPart(ownText.toString(), nodeId: node.id),
    ];
    RecipeNode? previous;
    for (final child in node.children) {
      final childParts = renderParts(
        child,
        servings: servings,
        recipeMultiplier: recipeMultiplier,
        caseOverride: grammarCaseForChild(node, child),
      );
      if (childParts.every((part) => part.text.isEmpty)) continue;
      final separator =
          joinTextForChild(node, child) ??
          (node.card.id == 'action.leave' && child.card.id == 'quantity.time'
              ? ' на '
              : node.card.kind == CardKind.ingredient &&
                    child.card.kind == CardKind.quantity
              ? ' '
              : previous != null &&
                    previous.card.kind == child.card.kind &&
                    child.joinWithPrevious == ' '
              ? ', '
              : child.joinWithPrevious);
      parts.add(RecipeRenderPart(separator));
      parts.addAll(childParts);
      previous = child;
    }
    return parts;
  }

  /// Числовые количества масштабируются на отношение выбранных и базовых
  /// порций. Результат округляется до ближайшего целого, не меняя значение
  /// в модуле.
  String _formatValue(
    int value,
    NumericUnit unit, {
    required int servings,
    required int recipeMultiplier,
  }) {
    if ((unit != NumericUnit.grams &&
            unit != NumericUnit.milliliters &&
            unit != NumericUnit.pieces) ||
        recipeMultiplier <= 0) {
      return '$value';
    }
    return '${(value * servings / recipeMultiplier).round()}';
  }

  /// Ложки сохраняют вид меры, но их число масштабируется так же, как масса.
  /// Округление до четверти ложки даёт привычные кухонные доли (¼, ½, ¾), а
  /// не длинные десятичные дроби.
  String _formatSpoon(
    String source, {
    required int servings,
    required int recipeMultiplier,
  }) {
    if (recipeMultiplier <= 0) return source;
    final match = RegExp(r'^(?:(\d+))?([¼½¾])?\s*(ч\. л\.|дес\. л\.|ст\. л\.)$')
        .firstMatch(source);
    if (match == null) return source;
    final whole = int.tryParse(match.group(1) ?? '') ?? 0;
    final fraction = switch (match.group(2)) {
      '¼' => .25,
      '½' => .5,
      '¾' => .75,
      _ => 0.0,
    };
    final quarters = ((whole + fraction) * servings / recipeMultiplier * 4)
        .round();
    final resultWhole = quarters ~/ 4;
    final resultFraction = switch (quarters % 4) {
      1 => '¼',
      2 => '½',
      3 => '¾',
      _ => '',
    };
    final amount = resultWhole == 0 && resultFraction.isNotEmpty
        ? resultFraction
        : '$resultWhole$resultFraction';
    return '$amount ${match.group(3)}';
  }

  /// Стабильный ключ для изображения: порядок вложений на него не влияет.
  String visualKey(RecipeNode node) {
    if (node.children.isEmpty) return node.card.id;
    final visualChildren = node.children
        .where((child) => child.card.id != 'text.free')
        .toList();
    if (visualChildren.isEmpty) return node.card.id;
    final primaryChild = visualChildren
        .map((child) => child.card.id)
        .reduce((left, right) => left.compareTo(right) <= 0 ? left : right);
    return '${node.card.id}:$primaryChild';
  }
}
