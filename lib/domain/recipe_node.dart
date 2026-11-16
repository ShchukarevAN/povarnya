/// Категория повторно используемой карточки.
enum CardKind { action, ingredient, quantity, utensil, text }

/// Параметр карточки массы или времени. Числа хранятся как компактные
/// положительные целые; второй интервал разрешён только для времени.
enum NumericUnit { grams, milliliters, minutes, celsius, pieces, percent }

/// Свободный текст хранится как короткая строка с однобайтной длиной.
/// Лимит 255 символов достаточен для уточнения шага, но не превращает
/// карточку в неограниченный текстовый редактор.
const freeTextMaxLength = 255;

/// Падеж, который родитель ожидает от вложенной карточки.
enum GrammarCase {
  unspecified,
  nominative,
  genitive,
  dative,
  accusative,
  instrumental,
  prepositional,
}

extension GrammarCaseLabel on GrammarCase {
  String get shortLabel => switch (this) {
    GrammarCase.unspecified => '—',
    GrammarCase.nominative => 'им. пад.',
    GrammarCase.genitive => 'род. пад.',
    GrammarCase.dative => 'дат. пад.',
    GrammarCase.accusative => 'вин. пад.',
    GrammarCase.instrumental => 'тв. пад.',
    GrammarCase.prepositional => 'предл. пад.',
  };
}

/// Словарная карточка. Она хранится в основной (именительной) форме.
class CardDefinition {
  const CardDefinition({
    required this.id,
    required this.kind,
    required this.nominative,
    this.forms = const {},
  });
  final String id;
  final CardKind kind;
  final String nominative;
  final Map<GrammarCase, String> forms;
  String formFor(GrammarCase grammarCase) => forms[grammarCase] ?? nominative;
}

/// Экземпляр карточки в конкретном рецепте или шаблоне.
/// Дочерние элементы не ограничены по количеству и образуют дерево любой глубины.
class RecipeNode {
  RecipeNode({
    required this.id,
    required this.card,
    this.caseFromParent = GrammarCase.unspecified,
    this.joinWithPrevious = ' ',
    this.value,
    this.upperValue,
    this.unit,
    this.text,
    List<RecipeNode>? children,
  }) : children = children ?? [];
  final String id;
  final CardDefinition card;
  final GrammarCase caseFromParent;
  final String joinWithPrevious;
  int? value;
  int? upperValue;
  final NumericUnit? unit;
  String? text;
  final List<RecipeNode> children;
}

/// Возвращает id первого фактического узла каждого ингредиента из [labels].
///
/// Связь строится по данным карточки, а не по тексту, который пользователь
/// видит после склонения. Это позволяет интерфейсу надёжно найти конкретное
/// место ингредиента в дереве рецепта.
Map<String, String> firstIngredientNodeIds(
  Iterable<RecipeNode> steps,
  Iterable<String> labels,
) {
  final pending = labels.toSet();
  final ids = <String, String>{};

  void visit(RecipeNode node) {
    if (node.card.kind == CardKind.ingredient &&
        pending.remove(node.card.nominative)) {
      ids[node.card.nominative] = node.id;
    }
    for (final child in node.children) {
      visit(child);
    }
  }

  for (final step in steps) {
    visit(step);
    if (pending.isEmpty) break;
  }
  return ids;
}
