import 'dart:math' as math;

import '../data/recipe_database.dart';
import '../domain/catalog.dart';
import '../domain/recipe_node.dart';
import '../domain/recipe_renderer.dart';
import 'speech_personalization.dart';

typedef SpeechCalibrationTextSet = ({
  List<String> modules,
  List<String> trainingSteps,
  List<String> validationSteps,
});

typedef SpeechCalibrationStep = ({
  String recipeId,
  String primaryCardId,
  String text,
});

/// Builds the exercise from the existing module catalog and rendered recipe
/// steps. The random choice is constrained by module-kind quotas, usage in
/// recipes, one-step-per-recipe preference, action limits, and pronunciation
/// distance.
SpeechCalibrationTextSet selectSpeechCalibrationTexts({
  required Iterable<CardDefinition> modules,
  required Iterable<SpeechCalibrationStep> steps,
  Map<String, int> moduleUsage = const <String, int>{},
  math.Random? random,
}) {
  const moduleCount = 24;
  const trainingStepCount = 14;
  const validationStepCount = 10;
  final generator = random ?? math.Random();
  final selectedModules = _selectModules(
    modules,
    moduleUsage,
    moduleCount,
    generator,
  );
  if (selectedModules.length < moduleCount) {
    throw StateError('Недостаточно различных модулей для настройки речи');
  }

  final selectedSteps = _selectSteps(
    steps,
    trainingStepCount + validationStepCount,
    generator,
  );
  if (selectedSteps.length < trainingStepCount + validationStepCount) {
    throw StateError('Недостаточно различных шагов рецептов для настройки');
  }
  selectedSteps.shuffle(generator);
  return (
    modules: selectedModules.map((module) => module.nominative).toList(),
    trainingSteps: selectedSteps
        .take(trainingStepCount)
        .map((step) => step.text)
        .toList(),
    validationSteps: selectedSteps
        .skip(trainingStepCount)
        .map((step) => step.text)
        .toList(),
  );
}

Future<SpeechCalibrationTextSet> createSpeechCalibrationTexts({
  math.Random? random,
}) async {
  final steps = <SpeechCalibrationStep>[];
  final moduleUsage = <String, int>{};
  final knownTexts = <String>{};
  final database = RecipeDatabase();
  try {
    final titles = await database.loadRecipeTitles();
    for (final recipeId in titles.keys) {
      _addRecipeSteps(
        recipeId: recipeId,
        roots: await database.loadRecipeSteps(recipeId),
        destination: steps,
        moduleUsage: moduleUsage,
        knownTexts: knownTexts,
      );
    }
  } catch (_) {
    // The bundled catalog below remains available if the local DB is damaged.
  }

  void addBundledCatalog() {
    for (final recipe in catalogRecipes) {
      _addRecipeSteps(
        recipeId: 'catalog:${recipe.id}',
        roots: recipe.buildSteps(),
        destination: steps,
        moduleUsage: moduleUsage,
        knownTexts: knownTexts,
      );
    }
  }

  if (steps.length < 24) addBundledCatalog();
  try {
    return selectSpeechCalibrationTexts(
      modules: CatalogCards.all,
      steps: steps,
      moduleUsage: moduleUsage,
      random: random,
    );
  } on StateError {
    addBundledCatalog();
    return selectSpeechCalibrationTexts(
      modules: CatalogCards.all,
      steps: steps,
      moduleUsage: moduleUsage,
      random: random,
    );
  }
}

void _addRecipeSteps({
  required String recipeId,
  required Iterable<RecipeNode> roots,
  required List<SpeechCalibrationStep> destination,
  required Map<String, int> moduleUsage,
  required Set<String> knownTexts,
}) {
  const renderer = RecipeRenderer();
  for (final root in roots) {
    final moduleIds = <String>[];
    var containsFreeText = false;

    void visit(RecipeNode node) {
      if (node.card.kind == CardKind.text) containsFreeText = true;
      moduleIds.add(node.card.id);
      for (final child in node.children) {
        visit(child);
      }
    }

    visit(root);
    if (containsFreeText || root.card.kind != CardKind.action) continue;
    for (final moduleId in moduleIds) {
      moduleUsage[moduleId] = (moduleUsage[moduleId] ?? 0) + 1;
    }
    final rendered = renderer.renderParts(root).map((part) => part.text).join();
    final normalized = normalizeSpeechText(rendered);
    if (normalized.isEmpty ||
        normalized.contains(RegExp(r'\d')) ||
        !knownTexts.add(normalized)) {
      continue;
    }
    destination.add((
      recipeId: recipeId,
      primaryCardId: root.card.id,
      text: normalized,
    ));
  }
}

List<CardDefinition> _selectModules(
  Iterable<CardDefinition> source,
  Map<String, int> usage,
  int wanted,
  math.Random random,
) {
  final unique = <String, CardDefinition>{};
  for (final module in source) {
    final normalized = normalizeSpeechText(module.nominative);
    if (module.kind == CardKind.text ||
        normalized.length < 3 ||
        normalized.contains(RegExp(r'[^а-я ]')) ||
        normalized.split(' ').length > 4) {
      continue;
    }
    unique.putIfAbsent(normalized, () => module);
  }
  final ordered = unique.values.map((module) {
    final weight = 1 + math.log(1 + (usage[module.id] ?? 0));
    final draw = math.max(random.nextDouble(), 1e-9);
    return (module: module, key: math.pow(draw, 1 / weight).toDouble());
  }).toList()..sort((left, right) => right.key.compareTo(left.key));

  final quotas = <CardKind, int>{
    CardKind.ingredient: (wanted * .5).round(),
    CardKind.action: (wanted * .29).round(),
    CardKind.utensil: (wanted * .13).round(),
  };
  quotas[CardKind.quantity] = wanted - quotas.values.reduce((a, b) => a + b);

  final selected = <CardDefinition>[];
  for (final entry in quotas.entries) {
    _appendDiverseModules(
      selected,
      ordered
          .where((candidate) => candidate.module.kind == entry.key)
          .map((candidate) => candidate.module),
      entry.value,
      .72,
    );
  }
  for (final limit in const [.72, .82, .92, 1.01]) {
    _appendDiverseModules(
      selected,
      ordered.map((candidate) => candidate.module),
      wanted - selected.length,
      limit,
    );
    if (selected.length >= wanted) break;
  }
  return selected.take(wanted).toList();
}

void _appendDiverseModules(
  List<CardDefinition> selected,
  Iterable<CardDefinition> candidates,
  int wanted,
  double similarityLimit,
) {
  if (wanted <= 0) return;
  var added = 0;
  for (final candidate in candidates) {
    if (selected.contains(candidate) ||
        selected.any(
          (item) =>
              speechPhoneticSimilarity(item.nominative, candidate.nominative) >=
              similarityLimit,
        )) {
      continue;
    }
    selected.add(candidate);
    added++;
    if (added >= wanted) return;
  }
}

List<SpeechCalibrationStep> _selectSteps(
  Iterable<SpeechCalibrationStep> source,
  int wanted,
  math.Random random,
) {
  final unique = <String, SpeechCalibrationStep>{};
  for (final step in source) {
    final normalized = normalizeSpeechText(step.text);
    final wordCount = normalized.split(' ').length;
    if (wordCount < 2 || wordCount > 12 || normalized.contains(RegExp(r'\d'))) {
      continue;
    }
    unique.putIfAbsent(normalized, () => step);
  }
  final ordered = unique.values.map((step) {
    final wordCount = normalizeSpeechText(step.text).split(' ').length;
    final preferredLength = wordCount >= 5 && wordCount <= 9 ? .25 : 0;
    return (step: step, key: random.nextDouble() + preferredLength);
  }).toList()..sort((left, right) => right.key.compareTo(left.key));

  final selected = <SpeechCalibrationStep>[];
  for (final pass in const [
    (similarity: .73, recipeLimit: 1, actionLimit: 2),
    (similarity: .82, recipeLimit: 1, actionLimit: 3),
    (similarity: .9, recipeLimit: 2, actionLimit: 4),
    (similarity: 1.01, recipeLimit: 1000, actionLimit: 1000),
  ]) {
    final recipeCounts = <String, int>{};
    final actionCounts = <String, int>{};
    for (final item in selected) {
      recipeCounts[item.recipeId] = (recipeCounts[item.recipeId] ?? 0) + 1;
      actionCounts[item.primaryCardId] =
          (actionCounts[item.primaryCardId] ?? 0) + 1;
    }
    for (final candidate in ordered.map((entry) => entry.step)) {
      if (selected.contains(candidate) ||
          (recipeCounts[candidate.recipeId] ?? 0) >= pass.recipeLimit ||
          (actionCounts[candidate.primaryCardId] ?? 0) >= pass.actionLimit ||
          selected.any(
            (item) =>
                speechPhoneticSimilarity(item.text, candidate.text) >=
                pass.similarity,
          )) {
        continue;
      }
      selected.add(candidate);
      recipeCounts[candidate.recipeId] =
          (recipeCounts[candidate.recipeId] ?? 0) + 1;
      actionCounts[candidate.primaryCardId] =
          (actionCounts[candidate.primaryCardId] ?? 0) + 1;
      if (selected.length >= wanted) return selected;
    }
  }
  return selected;
}

/// Russian-oriented sound comparison used only to keep a random exercise
/// varied. Voiced/devoiced consonants and close vowels share a code.
double speechPhoneticSimilarity(String left, String right) {
  final leftKey = _phoneticKey(left);
  final rightKey = _phoneticKey(right);
  if (leftKey.isEmpty || rightKey.isEmpty) return 0;
  final distance = speechCharacterDistance(leftKey, rightKey);
  return 1 - distance / math.max(leftKey.length, rightKey.length);
}

String _phoneticKey(String source) {
  final result = StringBuffer();
  String? previous;
  for (final rune in normalizeSpeechText(source).runes) {
    final character = String.fromCharCode(rune);
    final code = switch (character) {
      'а' || 'о' || 'я' => 'а',
      'е' || 'э' || 'и' || 'ы' => 'и',
      'у' || 'ю' => 'у',
      'б' || 'п' => 'п',
      'в' || 'ф' => 'ф',
      'г' || 'к' || 'х' => 'к',
      'д' || 'т' => 'т',
      'ж' || 'ш' || 'щ' || 'ч' => 'ш',
      'з' || 'с' || 'ц' => 'с',
      'ь' || 'ъ' => '',
      _ => character,
    };
    if (code.isEmpty || code == previous) continue;
    result.write(code);
    previous = code;
  }
  return result.toString().trim();
}
